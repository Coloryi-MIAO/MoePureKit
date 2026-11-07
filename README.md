# MoePureKit 萌净工具箱

一款面向 Windows 桌面的轻量工具箱，界面以清晰、克制和易用为目标。项目版本为 **0.3.5-beta.22**，作者 **Coloryi-MIAO**，版权 **© 2026 Coloryi-MIAO**。

## 功能一览

- 首页同时展示 CPU、内存、C 盘容量实时状态与原有静态系统摘要，并提供常用功能入口。
- 下载页使用随应用打包的 aria2，支持 HTTP/HTTPS/FTP、磁力、种子及 Metalink，并可设置目录、并发、代理、请求头和登录信息。
- 系统资源从 `assets/iso.json` 读取；软件资源从 `assets/app.json` 读取，两份清单均可在应用内编辑。
- Office 页通过微软官方 Office Deployment Tool（ODT）生成并执行部署配置；Windows 许可页可安装用户持有的正版产品密钥、检查本地 XML 票据结构，并只读诊断现有企业 KMS 客户端配置。
- 快捷工具提供常用 Windows 控制台入口；文件校验流式计算 SHA-256；网络诊断检查 DNS 和微软 HTTPS 连通性。
- 界面语言支持跟随系统、简体中文和 English；浅色/深色外观支持跟随系统或手动选择。
- 关于页面提供 GitHub Release 更新监测、应用内流式下载与便携版/安装版选择。
- 启动遮罩每次启动显示约 3 秒，并按界面语言显示文案。
- 应用使用 Microsoft YaHei（微软雅黑）作为全局字体，不提供字体切换选项。
- Windows 同一用户会话只允许一个 MoePureKit 实例运行。
- 可选的开机自启仅修改当前 Windows 用户的 `Run` 注册表项，不需要管理员权限。
- 关闭窗口时可选择隐藏到托盘或退出；可选择不再询问，也可在设置中恢复询问。

## 获取与构建

需要 Flutter stable、Dart 3.13.5 或兼容版本，以及 Windows 桌面开发所需的 Visual Studio C++ 工具链和 Windows SDK。

```powershell
flutter pub get
flutter run -d windows
flutter analyze
flutter test
flutter build windows --release
```

发布程序为 `build\windows\x64\runner\Release\MoePureKit.exe`。请分发整个 `Release` 文件夹，而不是只复制 EXE；Flutter 运行库、插件、资源和 `data\aria2` 均为运行所需文件。

若发布 EXE 正在运行，Windows 会锁定文件并阻止重新链接。关闭应用后再执行 Release 构建。

## 下载引擎

Windows x64 发布包内置 aria2 1.37.0，并在本机回环地址启动 JSON-RPC；无需安装外部 aria2。RPC 仅监听本机，使用本机生成的密钥。下载任务及 aria2 会话保存在当前 Windows 用户目录，默认下载目录为 `%USERPROFILE%\Downloads\MoePureKit`。

首次启动会询问下载目录；之后可以在“设置”中修改。下载页支持 HTTP/HTTPS/FTP、磁力链接、种子文件和 Metalink。任务可使用 Cookie、额外 Header、User-Agent 和 Referer；并发数、代理和默认请求信息也可在设置中配置。

aria2 官方 Windows x64 1.37.0 发布包的 SHA-256 为：

```text
67D015301EEF0B612191212D564C5BB0A14B5B9C4796B76454276A4D28D9B288
```

上游发布页：[aria2 release 1.37.0](https://github.com/aria2/aria2/releases/tag/release-1.37.0)。随包保留 aria2 与 OpenSSL 的许可、作者和来源说明。aria2 按 GPL-2.0 发布；上游源码：[aria2-1.37.0.tar.xz](https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0.tar.xz)。

Cookie、请求头和 RPC 密钥保存在本机 SharedPreferences 中，当前版本未加密。不要在共享 Windows 账户中保存敏感登录信息。

## 资源清单

`assets/iso.json` 是应用默认的系统镜像清单，`assets/app.json` 是默认软件清单。应用也允许在相应页面导入或编辑本机 JSON 清单。

条目可以使用 `title`/`name`、`url`/`download_url`、`version`、`size`、`sha256`、`category`、`description`、`tags` 和 `source` 字段。`sha256` 若填写，必须为 64 位十六进制字符串。

镜像清单内的 ED2K 和磁力资源来自第三方社区，并非微软官方分发链接。下载前请自行核对发布者、来源和校验值；没有校验值的条目不代表已验证。官方 Windows 下载入口会在系统默认浏览器中打开微软网站。

## Office 部署与 Windows 许可

Office 部署使用用户从微软官方渠道取得的 ODT。应用在运行 ODT 自解压程序或 `setup.exe` 前验证微软 Authenticode 签名，并请求用户确认；随后按页面选择的产品、语言、更新通道及组件生成配置 XML。实际安装内容和授权由微软 ODT 及用户提供的许可决定。

Windows 许可页读取系统许可状态，并可通过 Windows Software Licensing 服务安装用户输入的正版产品密钥。许可诊断会优先显示已授权的 Windows 许可证记录，并展示许可状态、密钥末五位、授权通道及可用的宽限时间信息。提交密钥需要用户确认并通过 UAC；密钥通过临时文件传递，处理后清理。安装密钥不保证激活成功，最终结果应以 Windows“激活”设置页为准。

XML 票据检查只在本机读取所选文件，禁止 DTD 与外部实体解析，检查 XML 语法、根节点、节点数量及 SHA-256；它不会将文件写入 ClipSVC，也不验证票据签名或授权资格。KMS 诊断只读取 Windows 当前批量授权客户端信息、已配置或 DNS 发现的服务器及 TCP 连通性，不会更改 KMS 配置或发起激活。

本项目不包含数字权利伪造、激活绕过、未经授权的票据导入、Office DLL 劫持或伪造授权组件。请仅使用自己有权使用的正版密钥与许可证。



## 系统监控与设备维护（V10）

- 首页同时保留“性能”与“本机系统信息”两块卡片。系统摘要包含设备名、Windows 版本/内部版本、处理器、内存、系统架构、设备厂商/型号、主板/BIOS 和运行时间；可单独刷新静态信息。
- CPU 通过 Windows `GetSystemTimes` 计算，物理内存通过 `GlobalMemoryStatusEx` 读取，系统卷容量通过 `GetDiskFreeSpaceExW` 读取；这些数据由 Windows runner 的 MethodChannel 原生接口直接返回，不启动 PowerShell、不使用 WMI/CIM，也不依赖 Windows Performance Counter。
- 系统卷容量通过 `GetDiskFreeSpaceExW` 读取。当前不伪造磁盘活动率/读写吞吐：如果没有可用且稳定的磁盘活动数据源，面板会显示“C 盘占用”及“磁盘活动数据暂不可用”，CPU、内存和磁盘容量仍正常更新。
- 性能面板使用 Dart 定时器每约 1.5 秒请求一次原生快照；首页可见时采样，切换到其他 TAB 后停止，返回首页后恢复，应用退出时释放句柄。
- 首页磁盘卡始终以 C 盘容量占用作为主指标，并在小字中单独显示磁盘活动率；读写吞吐独立显示。原生采样优先尝试物理磁盘 IOCTL，失败时回退到系统卷设备路径，并在无可用驱动数据时明确显示不可用。
- 驱动页的“重新扫描设备”、INF 安装以及打开设备管理器均先显示应用内确认，再通过 Windows Shell `RunAs` 请求 UAC 管理员授权；不会要求整个 MoePureKit 始终以管理员身份运行。
- 设置页对主题和背景进行即时预览，但不自动持久化。离开设置页、关闭窗口或从托盘退出时，如存在未保存改动，会提示“保存并离开 / 放弃修改 / 继续编辑”；放弃时恢复保存版本的主题与背景。

## 窗口自适应、启动项与关闭行为

- 初始窗口为 1180 × 760 DIP，最小窗口为 760 × 520 DIP；窗口可自由缩放，宽度低于 1020 DIP 时导航自动收缩为图标栏，页头间距同步收紧，增大后恢复完整分组文字。
- 自定义标题栏关闭按钮与 Windows 原生关闭事件共用同一关闭确认流程；Beta 19 使用新的关闭确认偏好键，避免旧版本遗留的“不再询问”状态导致确认框看似消失。

应用使用无原生标题栏窗口、自定义标题栏和 Windows Mica/Acrylic 效果。托盘图标、aria2 引擎和下载任务会随应用进程运行。

开机自启可在“设置”中打开或关闭，只针对当前用户；卸载或更换 EXE 路径后，请在设置中关闭旧启动项并重新启用。

默认关闭窗口时会检查下载及 Office 部署状态，然后询问隐藏到托盘、退出或取消。选择“不再询问关闭确认”后，窗口将按设置中的默认操作执行：隐藏到托盘或直接退出。可在“设置”中重新开启确认。

单实例限制由 Windows 本地会话互斥量实现；重复启动不会再创建第二个窗口。aria2 另有独立的 Windows 本地会话互斥量与 Dart 启动去重 Future，第二个启动请求不会再拉起第二份下载引擎。选择“退出应用”时会等待 aria2 RPC 关闭；超时后仅终止本实例持有的 aria2 子进程。若升级前已有同一配置的本机 aria2 RPC 残留，新版本会先复用并接管该 RPC，再在退出时发送关闭请求。选择“最小化到托盘”则按设计保留 aria2 与下载任务继续运行。

## 目录结构

- `assets`：应用图标、aria2 运行文件和默认 JSON 清单
- `lib/config`：应用常量与中英文文案
- `lib/models`：设置、下载任务和清单数据模型
- `lib/pages`：主窗口、导航与功能页面
- `lib/services`：设置持久化、启动项、SHA-256、系统状态、资源清单及 aria2 服务
- `windows/runner`：Windows 窗口、单实例互斥量及当前用户开机自启注册表接口
- `test`：设置、清单、aria2、文件校验、Bing 缓存和界面测试


## 本轮工具页扩展

- **文本工具**：首尾空白清理、空行处理、行去重/排序、大小写转换、文本反转及字符/行/UTF-8 字节统计。
- **JSON 格式化**：格式化、压缩、语法校验和结果复制。
- **编码转换**：UTF-8 Base64 编码/解码、URL 编码/解码。
- **文件校验 UI**：SHA-256、SHA-512、SHA-384、SHA-1、MD5；流式读取进度、文件大小/修改时间/耗时、结果复制和期望哈希对比。MD5 与 SHA-1 仅用于兼容性比对，安全校验优先使用 SHA-256 或 SHA-512。

以上操作均在本机执行，不会上传输入文本或待校验文件。


## 网络诊断与流畅度优化（V4）

- 网络诊断现在包含默认网关信息与网关 Ping、网络适配器、本机 IPv4、系统 DNS 服务器、5 次目标 ICMP Ping 样本、平均/最小/最大延迟、相邻样本平均抖动、丢包率、DNS 解析耗时、HTTPS 延迟，以及 Cloudflare 公共测速节点的下载/上传吞吐估算。
- 下载测速最多接收 8 MiB；上传测速发送 2 MiB 自动生成数据，不读取或上传本地文件。上传测速可以在页面中关闭。
- 网络测试分阶段异步执行；网卡配置通过 PowerShell 网络配置接口读取，Ping 使用系统 `ping` 进程，HTTP 测速使用 Dart `HttpClient`，不会在 Flutter UI isolate 中等待网络操作。
- 文件 Hash 计算已移动到后台 isolate，进度通知降频到约 400 ms / 16 MiB，避免大文件计算频繁触发 UI rebuild。
- 文本字数、行数和 UTF-8 字节统计，以及 JSON/编码工具输入状态更新增加了轻量 debounce，减少大文本输入时的重复计算和整页重建。
- 已访问页面保留在主工作区中并保持挂载；切换 Tab 不会中断网络诊断、文件 Hash、Windows 许可检查或 Office 部署。相应 Tab 图标右上角显示绿色运行点。网络进度按阶段更新，Ping 结果可分别观察到默认网关与公网目标，方便区分局域网与上游线路问题。

测速结果是本机到 `speed.cloudflare.com` 节点的近似测量值，受 Wi-Fi、VPN、代理、防火墙、节点路由和当前网络负载影响；不等同于 ISP 线路保证值。

### Windows build: MSB3073 while copying aria2 / tray icon

The Windows runner no longer performs a second, duplicate POST_BUILD copy of
`assets/aria2/windows-x64` and `assets/tray_icon.ico`. The top-level Windows
CMake install rules are the single source of truth for bundling these files.
Asset paths are resolved relative to `windows/CMakeLists.txt`, and CMake now
reports a clear configure-time error if either required asset is missing.

After replacing the project files, run `flutter clean`, remove the generated
`build/windows` directory if it remains stale, then run `flutter pub get` and
`flutter build windows --release`.


## 后台任务与 Bing 每日背景（V5）

- 已访问过的页面会保留在主工作区中。网络诊断、文件 Hash、Windows 许可检查和 Office 验证/部署在切换 Tab 后继续执行；任务正在运行时，对应侧边栏图标右上角显示绿色圆点。
- 普通设置变化不再重建 aria2 服务，也不会每次都触发 MaterialApp 全局主题/语言重建。只有真正影响 aria2 RPC/下载配置的设置才重启运行时；请求头、Cookie 等默认值变化只更新服务实例。
- 设置页的语言、主题和背景下拉框不再使用动态 Key 强制卸载重建；移除整页切换动画和背景 AnimatedSwitcher，减少切换时整面闪烁。主题更换采用即时更新。
- Bing 每日壁纸现在下载到本机缓存（Windows `%LOCALAPPDATA%`），保存标题、版权信息和日期；同一天启动优先使用缓存，刷新失败时继续展示最近一次有效壁纸。设置页提供壁纸预览、版权说明和手动刷新按钮。
- Bing 壁纸图片大小限制为 20 MiB，图片地址限定 HTTPS Bing 域名，并设置网络超时；本地图片缓存避免每次绘制时重复请求远程图片。


## 界面持续运行与 Bing 背景完善（V6）

- 访问过的功能页保留在主工作区中；切换侧边栏时不销毁任务所属 Widget，因此网络诊断、Hash、许可诊断、Office 验证/部署和下载列表刷新可以继续执行。
- 运行状态图标改由独立 `ValueNotifier` 更新；任务开始/结束只刷新侧边栏绿点，不会为了一个小圆点重建整个工作区。各已访问页面另有 `RepaintBoundary`，减少无关页面的重复绘制。
- 修复设置保存回调重复执行的问题；主题、语言和 Bing 背景等继承级设置由父级统一更新一次，普通偏好只更新必要状态，降低切换时的闪动。
- Bing 壁纸在内容区域的可见度提高；主内容卡片与侧栏采用半透明底色，让图片不再只出现在窗口边缘。图片仍使用本地缓存并保留失败回退、预览、版权信息和手动刷新。
- 版本更新为 `0.3.5-beta.11`。


## 系统概览与维护工具（0.3.5-beta.11）

- 首页新增 Windows 性能面板，约每 1.5 秒采样 CPU、内存、系统盘空间、磁盘活动与读写速率；历史曲线保留最近 48 个样本。性能采样只在首页可见时运行，切换到其他 Tab 会停止采样。
- 侧边栏按“概览 / 下载与资源 / 系统维护 / 效率工具 / 其他”分组，保留原有浅色、深色和 Bing 背景主题。
- 页面切换使用淡入淡出与轻微位移，导航选中条和图标平滑过渡；卡片和分区标题采用短时淡入。可在设置中关闭动画，并遵循 Windows 减少动态效果偏好。
- 文件管理支持当前目录浏览、过滤搜索、打开、复制/移动、重命名、新建文件夹和二次确认删除；单次目录列表上限为 1,200 项。
- C 盘清理仅扫描系统盘 TEMP/TMP 与 Windows Temp 中超过 24 小时的普通文件，先展示预览并由用户确认；不会自动删除下载、文档或系统组件存储。
- 驱动管理读取最多 100 条已安装签名驱动、触发 Windows 设备重新扫描，并可通过 pnputil 安装用户选择的 INF（显示 UAC，安装前二次确认）。
- 病毒查杀支持本地 SHA-256 特征库导入与后台 Isolate 逐文件计算，并可请求 Microsoft Defender 对所选目录执行自定义扫描。内置特征只有 EICAR 测试指纹用于验证匹配流程，不是完整病毒库；未命中不代表安全。

当前执行环境没有 Flutter/Dart SDK，因此本轮仅完成源码静态检查与打包检查，尚未在 Windows 上运行 `flutter analyze`、单元测试或实际 UAC/Defender 操作。


## 驱动管理权限修复（0.3.5-beta.11）

- “扫描硬件变更”先提示用户，再通过 PowerShell `Start-Process -Verb RunAs` 提升 `pnputil.exe /scan-devices`，不再直接以普通权限调用。
- 驱动管理页的设备管理器入口显式请求 UAC，并以管理员身份启动 `mmc.exe devmgmt.msc`。
- 快捷工具中的设备管理器入口也统一请求管理员权限。
- UAC 被取消或系统拒绝提升时，会显示失败原因，不会误报扫描成功。


## ODT 管理员启动修复（0.3.5-beta.12）

- 选择微软官方 ODT 自解压包并验证签名后，使用 Windows `Start-Process -Verb RunAs` 请求 UAC，再启动自解压程序。
- Office 部署的 `setup.exe /configure` 同样使用 UAC 提权启动；启动器等待子进程退出，并把 ODT 的真实退出码回传到界面。
- UAC 取消与 ODT 自身退出失败分开显示，不再把 Win32 错误 740 误报为普通启动错误。
- 仅提升经过签名验证的 ODT 可执行文件；MoePureKit 本身不要求始终以管理员身份运行。

## V10 Beta 13

- Windows 单实例：重复启动会恢复并激活已运行的 MoePureKit 窗口；若 Windows 前台锁定阻止置前，则闪烁任务栏提示。
- 页面转场升级为 280ms 淡入淡出、轻微位移与缩放；导航选中与标题切换同步优化。
- 通用 FadeIn 组件加入极轻的缩放收束，不使用高成本模糊滤镜，并继续遵循减少动态效果设置。


## 运行时进程与性能采样修复（0.3.5-beta.15）

- aria2 使用独立的 Windows 命名互斥量，Dart 层使用 single-flight 启动保护，避免并发初始化多个下载引擎。
- aria2 子进程启动后立即加入 Windows Job Object（`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`）；正常退出仍先发送 `aria2.shutdown` 并等待退出，异常退出/窗口销毁时由 Job Object 回收子进程。
- 只有确认 aria2 退出后才释放运行锁；进程未确认退出时阻止再次启动，避免遗留进程与新进程重叠。
- 默认关闭窗口会退出应用并等待 aria2 关闭；只有显式启用“关闭时最小化到系统托盘”才会保留 aria2 和下载任务。为避免旧版本默认托盘设置造成误解，Beta 15 使用独立的新设置键，升级后默认改为退出应用。
- CPU、内存、系统卷容量通过 Windows runner 的 Win32 API 直读：`GetSystemTimes`、`GlobalMemoryStatusEx`、`GetDiskFreeSpaceExW`；物理磁盘活动/读写速率通过 `IOCTL_DISK_PERFORMANCE` 获取。采样不再创建 PowerShell/WMI/CIM 进程；无法访问的存储控制器会单独显示不可用，不影响 CPU/内存。
- 性能面板离开首页时关闭磁盘统计引用并释放设备句柄，退出时再做一次兜底清理。


## 编译兼容性修复（0.3.5-beta.16）

- aria2 RPC 探测使用的 `package:http` Client 改为无参数 `close()`，移除不受该 Client API 支持的 `force` 命名参数。
- Windows 原生性能采样服务在空结果分支中移除 `PlatformException` 的 `const` 构造调用，修复 Dart 常量表达式编译错误。


## 后台任务与磁盘活动显示修复（0.3.5-beta.18）

- 所有已访问页面由 `IndexedStack` 常驻保活；切换 TAB 只更改可见索引，不销毁页面 State，不重新初始化扫描器、测试器或部署状态。
- 页面淡出/淡入动画仅作用于可见的 `IndexedStack` 表面。后台页面只有在任务运行时才保持 `TickerMode` 开启；任务空闲时暂停其动画以节省 CPU，运行中的进度动画/依赖 ticker 的任务不会因切换 TAB 而暂停。
- 下载、清理、指纹扫描、网络诊断、Office 部署和驱动操作仍由各自页面/服务持有，并通过导航图标的运行状态点显示后台执行状态。离开页面不会主动取消任务；仅应用退出或对应任务自然完成时结束。
- 首页性能采样在首页可见时运行；切换到其他页面后暂停，回到首页自动恢复。它不会取消其他页面的扫描、测试或部署任务。
- C 盘容量占用作为磁盘卡片的主数值，磁盘活动百分比改为下方小字同时显示；读写吞吐在卡片底部独立展示，不再与容量占用互相替换。
- 磁盘性能采样优先访问 PhysicalDrive 设备；物理盘统计接口不可用时，尝试 Windows 系统卷（例如 `\\.\C:`）计数器；如果没有可访问的数据源，每 10 秒重试一次。


## Beta 18 修复

- 修复 Windows 原生磁盘性能采样中的宽字符空字符字面量：`L'\0'`，避免 MSVC C4066 在 `/WX` 下导致构建失败。


## 更新下载与许可（0.3.5-beta.22）

- 关于页面进入时检查 GitHub 最新 Release，应用运行期间每 6 小时自动检查一次，并支持手动检查。
- 检测到新版本且 Release 含有可识别的 Windows 安装包时，会自动询问下载哪个包；同一 Release 在本次应用运行期间只提示一次，也可随时手动下载。
- 更新源固定为 `Coloryi-MIAO/MoePureKit`；按附件文件名识别便携版或安装版，并排除明确标记为 Linux/macOS 等非 Windows 的附件（以该 Release 实际发布的 Windows 附件为准）。
- 下载直接在应用内进行，采用 HTTP 流式写盘，显示实时进度并支持取消；中断时清理 `.part` 临时文件，不会把整个安装包一次性载入内存。
- 若 GitHub Release API 提供 SHA-256 digest，下载完成后自动校验；若未提供，会在界面提示用户按发布说明自行核对。
- 不会静默运行安装程序。下载完成后，便携包可在资源管理器中定位；安装包需用户再次确认后才启动 Windows 安装程序。
- 项目代码按 GNU GPL v3.0（GPL-3.0-only）发布，完整文本见 `LICENSE` / `COPYING`。第三方依赖、aria2、字体和资源仍遵循各自许可证。
