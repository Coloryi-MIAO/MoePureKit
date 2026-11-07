#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"


namespace {
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\ColoryiMIAO.MoePureKit.SingleInstance";
constexpr wchar_t kRunnerWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kRunnerWindowTitle[] = L"MoePureKit";

// A second launch should focus the existing Flutter window instead of
// silently exiting. The short wait covers the first instance's startup race.
void ActivateExistingInstance() {
  HWND window = nullptr;
  for (int attempt = 0; attempt < 30 && window == nullptr; ++attempt) {
    window = ::FindWindowW(kRunnerWindowClass, kRunnerWindowTitle);
    if (window == nullptr) {
      ::Sleep(100);
    }
  }

  if (window == nullptr || !::IsWindow(window)) {
    return;
  }

  if (::IsIconic(window) || !::IsWindowVisible(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    ::ShowWindow(window, SW_SHOW);
  }

  const HWND foreground = ::GetForegroundWindow();
  const DWORD current_thread = ::GetCurrentThreadId();
  const DWORD target_thread = ::GetWindowThreadProcessId(window, nullptr);
  const DWORD foreground_thread = foreground == nullptr
      ? 0
      : ::GetWindowThreadProcessId(foreground, nullptr);

  const bool attached_foreground = foreground_thread != 0 &&
      foreground_thread != current_thread &&
      ::AttachThreadInput(current_thread, foreground_thread, TRUE);
  const bool attached_target = target_thread != 0 &&
      target_thread != current_thread && target_thread != foreground_thread &&
      ::AttachThreadInput(current_thread, target_thread, TRUE);

  ::BringWindowToTop(window);
  ::SetActiveWindow(window);
  ::SetForegroundWindow(window);
  ::SetFocus(window);

  if (attached_target) {
    ::AttachThreadInput(current_thread, target_thread, FALSE);
  }
  if (attached_foreground) {
    ::AttachThreadInput(current_thread, foreground_thread, FALSE);
  }

  // If Windows foreground-lock rules prevent activation, flash the taskbar
  // button so the already-running instance is still clearly discoverable.
  if (::GetForegroundWindow() != window) {
    FLASHWINFO flash{};
    flash.cbSize = sizeof(FLASHWINFO);
    flash.hwnd = window;
    flash.dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG;
    flash.uCount = 3;
    flash.dwTimeout = 0;
    ::FlashWindowEx(&flash);
  }
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex == nullptr) {
    ::MessageBoxW(nullptr, L"MoePureKit could not verify single-instance status.",
                  L"MoePureKit", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ::CloseHandle(single_instance_mutex);
    ActivateExistingInstance();
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Match the Dart WindowOptions initial geometry. The window remains
  // resizable; responsive breakpoints are handled by the Flutter layout.
  Win32Window::Size size(1180, 760);
  if (!window.Create(L"MoePureKit", origin, size)) {
    ::CloseHandle(single_instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
