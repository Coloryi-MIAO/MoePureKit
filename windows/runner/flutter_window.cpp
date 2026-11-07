#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>
#include <algorithm>
#include <cstdint>
#include <limits>
#include <utility>
#include <windows.h>
#include <winioctl.h>

#include "flutter/generated_plugin_registrant.h"


namespace {
constexpr wchar_t kAria2RuntimeMutexName[] =
    L"Local\\ColoryiMIAO.MoePureKit.Aria2Runtime";
HANDLE g_aria2_runtime_mutex = nullptr;
HANDLE g_aria2_job = nullptr;

bool EnsureAria2Job() {
  if (g_aria2_job != nullptr) return true;
  HANDLE job = ::CreateJobObjectW(nullptr, nullptr);
  if (job == nullptr) return false;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!::SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                 &limits, static_cast<DWORD>(sizeof(limits)))) {
    ::CloseHandle(job);
    return false;
  }
  g_aria2_job = job;
  return true;
}

struct CpuTimesSnapshot {
  ULONGLONG idle = 0;
  ULONGLONG kernel = 0;
  ULONGLONG user = 0;
};
bool g_has_cpu_snapshot = false;
CpuTimesSnapshot g_last_cpu_snapshot;

struct DiskCounterEntry {
  HANDLE handle = INVALID_HANDLE_VALUE;
  DISK_PERFORMANCE last{};
  unsigned int active_counter_references = 1;
};
std::vector<DiskCounterEntry> g_disk_counters;
bool g_disk_counters_initialized = false;
ULONGLONG g_next_disk_counter_retry = 0;

void CloseDiskCounters() {
  for (auto& entry : g_disk_counters) {
    if (entry.handle != INVALID_HANDLE_VALUE) {
      while (entry.active_counter_references > 0) {
        DWORD bytes_returned = 0;
        if (!::DeviceIoControl(entry.handle, IOCTL_DISK_PERFORMANCE_OFF,
                               nullptr, 0, nullptr, 0, &bytes_returned,
                               nullptr)) {
          break;
        }
        --entry.active_counter_references;
      }
      ::CloseHandle(entry.handle);
      entry.handle = INVALID_HANDLE_VALUE;
    }
  }
  g_disk_counters.clear();
  g_disk_counters_initialized = false;
  g_next_disk_counter_retry = 0;
}

bool TryAddDiskCounter(const std::wstring& path) {
  HANDLE disk = ::CreateFileW(path.c_str(), 0,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_EXISTING, 0, nullptr);
  if (disk == INVALID_HANDLE_VALUE) return false;

  DISK_PERFORMANCE initial{};
  DWORD bytes_returned = 0;
  const BOOL enabled = ::DeviceIoControl(
      disk, IOCTL_DISK_PERFORMANCE, nullptr, 0, &initial,
      static_cast<DWORD>(sizeof(initial)), &bytes_returned, nullptr);
  if (enabled && bytes_returned >= sizeof(initial)) {
    g_disk_counters.push_back({disk, initial});
    return true;
  }
  if (enabled) {
    DWORD ignored_bytes = 0;
    ::DeviceIoControl(disk, IOCTL_DISK_PERFORMANCE_OFF, nullptr, 0,
                      nullptr, 0, &ignored_bytes, nullptr);
  }
  ::CloseHandle(disk);
  return false;
}

void InitializeDiskCounters() {
  const ULONGLONG now = ::GetTickCount64();
  if (g_disk_counters_initialized &&
      (!g_disk_counters.empty() || now < g_next_disk_counter_retry)) {
    return;
  }
  g_disk_counters_initialized = true;
  // An unsupported controller may become available later (for example after
  // a removable drive is attached), so retry an empty result every 10 seconds.
  g_next_disk_counter_retry = now + 10000;

  // Prefer physical disks. IOCTL_DISK_PERFORMANCE is reference counted by the
  // storage stack; each successful enable is balanced when sampling stops.
  for (DWORD index = 0; index < 16; ++index) {
    const std::wstring path = L"\\\\.\\PhysicalDrive" + std::to_wstring(index);
    TryAddDiskCounter(path);
  }

  // Some NVMe/RAID/virtual controllers do not expose PhysicalDrive counters
  // to desktop processes. The volume stack can expose the system volume stats.
  if (g_disk_counters.empty()) {
    wchar_t windows_directory[MAX_PATH] = {};
    wchar_t volume_root[MAX_PATH] = {};
    if (::GetWindowsDirectoryW(windows_directory, MAX_PATH) > 0 &&
        ::GetVolumePathNameW(windows_directory, volume_root, MAX_PATH) &&
        volume_root[0] != L'\0' && volume_root[1] == L':') {
      const std::wstring volume_path =
          L"\\\\.\\" + std::wstring(volume_root, 0, 2);
      TryAddDiskCounter(volume_path);
    }
  }
}

ULONGLONG CounterDelta(LONGLONG current, LONGLONG previous) {
  if (current < previous) return 0;
  return static_cast<ULONGLONG>(current - previous);
}

void ReadDiskCounters(double* active_percent, int64_t* read_bytes_per_second,
                      int64_t* write_bytes_per_second) {
  InitializeDiskCounters();
  if (g_disk_counters.empty()) return;

  bool has_sample = false;
  double busiest_disk_percent = 0.0;
  long double total_read_rate = 0.0L;
  long double total_write_rate = 0.0L;

  for (auto& entry : g_disk_counters) {
    DISK_PERFORMANCE current{};
    DWORD bytes_returned = 0;
    const BOOL queried = ::DeviceIoControl(
        entry.handle, IOCTL_DISK_PERFORMANCE, nullptr, 0, &current,
        static_cast<DWORD>(sizeof(current)), &bytes_returned, nullptr);
    if (!queried) continue;

    // Each successful IOCTL enables one reference-counted counter. Balance
    // this temporary reference even if a driver returns a short structure.
    ++entry.active_counter_references;
    DWORD ignored_bytes = 0;
    if (::DeviceIoControl(entry.handle, IOCTL_DISK_PERFORMANCE_OFF, nullptr, 0,
                          nullptr, 0, &ignored_bytes, nullptr) &&
        entry.active_counter_references > 0) {
      --entry.active_counter_references;
    }
    if (bytes_returned < sizeof(current)) continue;

    const ULONGLONG elapsed = CounterDelta(
        current.QueryTime.QuadPart, entry.last.QueryTime.QuadPart);
    if (elapsed == 0) {
      entry.last = current;
      continue;
    }

    const ULONGLONG read_delta =
        CounterDelta(current.BytesRead.QuadPart, entry.last.BytesRead.QuadPart);
    const ULONGLONG write_delta = CounterDelta(
        current.BytesWritten.QuadPart, entry.last.BytesWritten.QuadPart);
    const ULONGLONG idle_time_delta =
        CounterDelta(current.IdleTime.QuadPart, entry.last.IdleTime.QuadPart);

    constexpr long double kHundredNanosecondsPerSecond = 10000000.0L;
    total_read_rate +=
        static_cast<long double>(read_delta) * kHundredNanosecondsPerSecond /
        static_cast<long double>(elapsed);
    total_write_rate +=
        static_cast<long double>(write_delta) * kHundredNanosecondsPerSecond /
        static_cast<long double>(elapsed);
    const ULONGLONG bounded_idle = std::min(idle_time_delta, elapsed);
    const double busy =
        static_cast<double>(elapsed - bounded_idle) /
        static_cast<double>(elapsed) * 100.0;
    busiest_disk_percent = std::max(busiest_disk_percent,
                                    std::clamp(busy, 0.0, 100.0));
    has_sample = true;
    entry.last = current;
  }

  if (has_sample) {
    *active_percent = busiest_disk_percent;
    *read_bytes_per_second = static_cast<int64_t>(total_read_rate);
    *write_bytes_per_second = static_cast<int64_t>(total_write_rate);
  }
}

ULONGLONG FileTimeValue(const FILETIME& value) {
  ULARGE_INTEGER combined{};
  combined.LowPart = value.dwLowDateTime;
  combined.HighPart = value.dwHighDateTime;
  return combined.QuadPart;
}

flutter::EncodableValue ReadSystemMetrics() {
  double cpu_percent = -1.0;
  FILETIME idle_time{}, kernel_time{}, user_time{};
  if (::GetSystemTimes(&idle_time, &kernel_time, &user_time)) {
    cpu_percent = 0.0;
    const CpuTimesSnapshot current{
        FileTimeValue(idle_time), FileTimeValue(kernel_time),
        FileTimeValue(user_time)};
    if (g_has_cpu_snapshot) {
      const ULONGLONG idle_delta =
          current.idle >= g_last_cpu_snapshot.idle
              ? current.idle - g_last_cpu_snapshot.idle
              : 0;
      const ULONGLONG kernel_delta =
          current.kernel >= g_last_cpu_snapshot.kernel
              ? current.kernel - g_last_cpu_snapshot.kernel
              : 0;
      const ULONGLONG user_delta =
          current.user >= g_last_cpu_snapshot.user
              ? current.user - g_last_cpu_snapshot.user
              : 0;
      const ULONGLONG total_delta = kernel_delta + user_delta;
      if (total_delta > 0) {
        const ULONGLONG busy_delta =
            total_delta > idle_delta ? total_delta - idle_delta : 0;
        cpu_percent = std::clamp(
            (static_cast<double>(busy_delta) /
             static_cast<double>(total_delta)) * 100.0,
            0.0, 100.0);
      }
    }
    g_last_cpu_snapshot = current;
    g_has_cpu_snapshot = true;
  }

  MEMORYSTATUSEX memory_status{};
  memory_status.dwLength = static_cast<DWORD>(sizeof(memory_status));
  ULONGLONG memory_total = 0;
  ULONGLONG memory_used = 0;
  double memory_percent = -1.0;
  if (::GlobalMemoryStatusEx(&memory_status)) {
    memory_total = memory_status.ullTotalPhys;
    memory_used = memory_total > memory_status.ullAvailPhys
                      ? memory_total - memory_status.ullAvailPhys
                      : 0;
    if (memory_total > 0) {
      memory_percent = std::clamp(
          static_cast<double>(memory_used) /
              static_cast<double>(memory_total) * 100.0,
          0.0, 100.0);
    }
  }

  ULONGLONG drive_total = 0;
  ULONGLONG drive_free = 0;
  wchar_t windows_directory[MAX_PATH] = {};
  wchar_t volume_root[MAX_PATH] = {};
  if (::GetWindowsDirectoryW(windows_directory, MAX_PATH) > 0 &&
      ::GetVolumePathNameW(windows_directory, volume_root, MAX_PATH)) {
    ULARGE_INTEGER available_bytes{}, total_bytes{}, total_free_bytes{};
    if (::GetDiskFreeSpaceExW(volume_root, &available_bytes, &total_bytes,
                              &total_free_bytes)) {
      drive_total = total_bytes.QuadPart;
      drive_free = total_free_bytes.QuadPart;
    }
  }
  const double disk_used_percent =
      drive_total > 0
          ? std::clamp(static_cast<double>(drive_total - drive_free) /
                           static_cast<double>(drive_total) * 100.0,
                       0.0, 100.0)
          : 0.0;

  double disk_active_percent = -1.0;
  int64_t read_rate = -1;
  int64_t write_rate = -1;
  ReadDiskCounters(&disk_active_percent, &read_rate, &write_rate);

  flutter::EncodableMap metrics;
  metrics[flutter::EncodableValue("cpu")] =
      flutter::EncodableValue(cpu_percent);
  metrics[flutter::EncodableValue("memory")] =
      flutter::EncodableValue(memory_percent);
  metrics[flutter::EncodableValue("diskActive")] =
      flutter::EncodableValue(disk_active_percent);
  metrics[flutter::EncodableValue("diskUsed")] =
      flutter::EncodableValue(disk_used_percent);
  metrics[flutter::EncodableValue("memoryUsedBytes")] =
      flutter::EncodableValue(static_cast<int64_t>(memory_used));
  metrics[flutter::EncodableValue("memoryTotalBytes")] =
      flutter::EncodableValue(static_cast<int64_t>(memory_total));
  metrics[flutter::EncodableValue("readBytesPerSec")] =
      flutter::EncodableValue(read_rate);
  metrics[flutter::EncodableValue("writeBytesPerSec")] =
      flutter::EncodableValue(write_rate);
  metrics[flutter::EncodableValue("driveFreeBytes")] =
      flutter::EncodableValue(static_cast<int64_t>(drive_free));
  metrics[flutter::EncodableValue("driveTotalBytes")] =
      flutter::EncodableValue(static_cast<int64_t>(drive_total));
  return flutter::EncodableValue(std::move(metrics));
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  system_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "moepurekit/system",
          &flutter::StandardMethodCodec::GetInstance());
  system_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() == "getSystemMetrics") {
          result->Success(ReadSystemMetrics());
          return;
        }
        if (call.method_name() == "stopSystemMetrics") {
          CloseDiskCounters();
          g_has_cpu_snapshot = false;
          result->Success();
          return;
        }

        if (call.method_name() == "attachAria2Process") {
          int64_t process_id = 0;
          if (const auto* int32_value =
                  std::get_if<int32_t>(call.arguments())) {
            process_id = *int32_value;
          } else if (const auto* int64_value =
                         std::get_if<int64_t>(call.arguments())) {
            process_id = *int64_value;
          }
          if (process_id <= 0 ||
              process_id > static_cast<int64_t>(MAXDWORD)) {
            result->Error("aria2_job_invalid_pid", "Invalid aria2 process ID.");
            return;
          }
          if (!EnsureAria2Job()) {
            result->Error("aria2_job_create_failed",
                          "Windows could not create the aria2 process job.",
                          flutter::EncodableValue(::GetLastError()));
            return;
          }
          HANDLE process = ::OpenProcess(
              PROCESS_SET_QUOTA | PROCESS_TERMINATE |
                  PROCESS_QUERY_LIMITED_INFORMATION,
              FALSE, static_cast<DWORD>(process_id));
          if (process == nullptr) {
            result->Error("aria2_job_open_failed",
                          "Windows could not open the aria2 process.",
                          flutter::EncodableValue(::GetLastError()));
            return;
          }
          const BOOL assigned = ::AssignProcessToJobObject(g_aria2_job, process);
          const DWORD error = assigned ? ERROR_SUCCESS : ::GetLastError();
          ::CloseHandle(process);
          if (!assigned) {
            result->Error("aria2_job_assign_failed",
                          "Windows could not attach aria2 to the app lifetime.",
                          flutter::EncodableValue(error));
            return;
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (call.method_name() == "acquireAria2Mutex") {
          if (g_aria2_runtime_mutex != nullptr) {
            // This process already has an aria2 owner. A second Dart service
            // object in the same app must not mistake that for its own lock.
            result->Success(flutter::EncodableValue(false));
            return;
          }
          HANDLE mutex = ::CreateMutexW(nullptr, FALSE, kAria2RuntimeMutexName);
          if (mutex == nullptr) {
            result->Error("aria2_mutex_error",
                          "Cannot create the aria2 runtime mutex.",
                          flutter::EncodableValue(::GetLastError()));
            return;
          }
          const DWORD wait_result = ::WaitForSingleObject(mutex, 0);
          if (wait_result == WAIT_OBJECT_0 || wait_result == WAIT_ABANDONED) {
            g_aria2_runtime_mutex = mutex;
            result->Success(flutter::EncodableValue(true));
          } else if (wait_result == WAIT_TIMEOUT) {
            ::CloseHandle(mutex);
            result->Success(flutter::EncodableValue(false));
          } else {
            const DWORD error = ::GetLastError();
            ::CloseHandle(mutex);
            result->Error("aria2_mutex_error",
                          "Cannot acquire the aria2 runtime mutex.",
                          flutter::EncodableValue(error));
          }
          return;
        }

        if (call.method_name() == "releaseAria2Mutex") {
          if (g_aria2_runtime_mutex != nullptr) {
            ::ReleaseMutex(g_aria2_runtime_mutex);
            ::CloseHandle(g_aria2_runtime_mutex);
            g_aria2_runtime_mutex = nullptr;
          }
          result->Success();
          return;
        }

        constexpr wchar_t kRunKey[] =
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
        constexpr wchar_t kValueName[] = L"MoePureKit";

        if (call.method_name() == "getAutostart") {
          HKEY key = nullptr;
          const LONG open_status =
              ::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE,
                              &key);
          if (open_status == ERROR_FILE_NOT_FOUND) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          if (open_status != ERROR_SUCCESS) {
            result->Error("autostart_registry_error",
                          "Cannot read the current-user startup registry.",
                          flutter::EncodableValue(open_status));
            return;
          }

          DWORD type = 0;
          DWORD byte_count = 0;
          LONG query_status =
              ::RegQueryValueExW(key, kValueName, nullptr, &type, nullptr,
                                 &byte_count);
          if (query_status == ERROR_FILE_NOT_FOUND) {
            ::RegCloseKey(key);
            result->Success(flutter::EncodableValue(false));
            return;
          }
          if (query_status != ERROR_SUCCESS ||
              (type != REG_SZ && type != REG_EXPAND_SZ)) {
            ::RegCloseKey(key);
            result->Error("autostart_registry_error",
                          "Cannot read the startup application value.",
                          flutter::EncodableValue(
                              query_status == ERROR_SUCCESS
                                  ? ERROR_INVALID_DATATYPE
                                  : query_status));
            return;
          }

          std::vector<wchar_t> command(byte_count / sizeof(wchar_t) + 1, L'\0');
          query_status = ::RegQueryValueExW(
              key, kValueName, nullptr, &type,
              reinterpret_cast<LPBYTE>(command.data()), &byte_count);
          ::RegCloseKey(key);
          if (query_status != ERROR_SUCCESS) {
            result->Error("autostart_registry_error",
                          "Cannot read the startup application command.",
                          flutter::EncodableValue(query_status));
            return;
          }
          std::vector<wchar_t> executable(32768, L'\0');
          const DWORD path_length = ::GetModuleFileNameW(
              nullptr, executable.data(),
              static_cast<DWORD>(executable.size()));
          if (path_length == 0 || path_length >= executable.size()) {
            result->Error("autostart_path_error",
                          "Cannot determine the application executable path.",
                          flutter::EncodableValue(::GetLastError()));
            return;
          }
          const std::wstring expected =
              L"\"" + std::wstring(executable.data(), path_length) + L"\"";
          result->Success(flutter::EncodableValue(
              ::_wcsicmp(command.data(), expected.c_str()) == 0));
          return;
        }

        if (call.method_name() != "setAutostart") {
          result->NotImplemented();
          return;
        }
        const auto* enabled = std::get_if<bool>(call.arguments());
        if (enabled == nullptr) {
          result->Error("invalid_argument", "Expected a boolean value.");
          return;
        }

        if (!*enabled) {
          HKEY key = nullptr;
          LONG status =
              ::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE,
                              &key);
          if (status == ERROR_FILE_NOT_FOUND) {
            result->Success();
            return;
          }
          if (status != ERROR_SUCCESS) {
            result->Error("autostart_registry_error",
                          "Cannot open the current-user startup registry.",
                          flutter::EncodableValue(status));
            return;
          }
          status = ::RegDeleteValueW(key, kValueName);
          ::RegCloseKey(key);
          if (status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND) {
            result->Error("autostart_registry_error",
                          "Cannot remove the startup application value.",
                          flutter::EncodableValue(status));
            return;
          }
          result->Success();
          return;
        }

        std::vector<wchar_t> executable(32768, L'\0');
        const DWORD path_length = ::GetModuleFileNameW(
            nullptr, executable.data(),
            static_cast<DWORD>(executable.size()));
        if (path_length == 0 || path_length >= executable.size()) {
          result->Error("autostart_path_error",
                        "Cannot determine the application executable path.",
                        flutter::EncodableValue(::GetLastError()));
          return;
        }
        const std::wstring command =
            L"\"" + std::wstring(executable.data(), path_length) + L"\"";

        HKEY key = nullptr;
        LONG status = ::RegCreateKeyExW(
            HKEY_CURRENT_USER, kRunKey, 0, nullptr, REG_OPTION_NON_VOLATILE,
            KEY_SET_VALUE, nullptr, &key, nullptr);
        if (status != ERROR_SUCCESS) {
          result->Error("autostart_registry_error",
                        "Cannot create the current-user startup registry key.",
                        flutter::EncodableValue(status));
          return;
        }
        status = ::RegSetValueExW(
            key, kValueName, 0, REG_SZ,
            reinterpret_cast<const BYTE*>(command.c_str()),
            static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
        ::RegCloseKey(key);
        if (status != ERROR_SUCCESS) {
          result->Error("autostart_registry_error",
                        "Cannot enable application startup.",
                        flutter::EncodableValue(status));
          return;
        }
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  if (g_aria2_job != nullptr) {
    ::CloseHandle(g_aria2_job);
    g_aria2_job = nullptr;
  }
  CloseDiskCounters();

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
