import 'package:flutter/material.dart';

class LocalizedText extends StatelessWidget {
  const LocalizedText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textStyle = isDark && style?.color != null
        ? style!.copyWith(color: Color.lerp(style!.color, Colors.white, 0.72))
        : style;
    return Text(
      translateText(context, data),
      style: textStyle,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}



const Map<String, String> _english = {
  '支持 MoePureKit': 'Support MoePureKit',
  '如果 MoePureKit 对你有帮助，欢迎前往 GitHub 点亮 Star。这个提示最多每 30 天显示一次。': 'If MoePureKit is useful to you, consider starring it on GitHub. This reminder appears at most once every 30 days.',
  '以管理员身份打开终端': 'Open terminal as administrator',
  '受保护的系统目录建议跳过；仅在确有需要时通过 UAC 提权访问。': 'Protected system folders should normally be skipped. Use UAC elevation only when access is necessary.',
  '请输入有效的 HTTP 或 HTTPS JSON 模板链接': 'Enter a valid HTTP or HTTPS JSON template URL',
  '模板超过 5 MB 安全限制': 'Template exceeds the 5 MB safety limit',
  '猫娘模式 · 内置壁纸': 'Catgirl mode · built-in wallpapers',
  '选择猫娘壁纸': 'Choose a catgirl wallpaper',
  '壁纸完全内置于应用，无需联网；选择后点击保存即可应用。': 'Wallpapers are bundled with the app and work offline. Select one and save to apply it.',
  '猫娘模式': 'Catgirl mode',
  '发现新版本': 'Update available',
  '读取失败': 'Read failed',
  '读取 CPU、内存与磁盘状态…': 'Reading CPU, memory and disk status…',
  '磁盘活动暂不可用': 'Disk activity is currently unavailable',
  '权限不足': 'Access denied',
  '以管理员身份重新打开': 'Reopen as administrator',
  '跳过无权限的系统目录': 'Skip protected system folders',
  '从网络导入模板': 'Import template from URL',
  '模板链接': 'Template URL',
  '导入': 'Import',
  '正在下载并解析模板…': 'Downloading and parsing template…',
  '网络模板导入成功': 'Network template imported',
  'GitHub Star 提示': 'GitHub Star reminder',
  '如果 MoePureKit 对你有帮助，欢迎前往 GitHub 点亮 Star。': 'If MoePureKit is useful to you, consider starring it on GitHub.',
  '永久关闭此提示': 'Never show this reminder again',
  '稍后再说': 'Maybe later',
  '前往 GitHub 点 Star': 'Star on GitHub',
  '喜欢 MoePureKit？': 'Enjoying MoePureKit?',
  '如果它对你有帮助，欢迎在 GitHub 留下一颗 Star。完全自愿，不会影响使用。': 'If it has been useful, consider leaving the project a star on GitHub. It is entirely optional and never affects the app.',
  '不再提示': 'Don’t show again',
  '我已经点过了': 'I have already starred it',
  '稍后': 'Later',
  '前往 GitHub': 'Visit GitHub',
  '关闭': 'Close',
  '窗口已根据当前屏幕自动调整大小': 'Window size was adjusted to fit the current screen',
  '首页': 'Home',
  '下载': 'Downloads',
  '文件管理': 'File manager',
  'C 盘清理': 'C drive cleanup',
  '病毒查杀': 'Virus scan',
  '驱动管理': 'Driver manager',
  '概览': 'Overview',
  '下载与资源': 'Downloads & resources',
  '系统维护': 'System maintenance',
  '效率工具': 'Productivity tools',
  '系统': 'System',
  '实用软件': 'Utilities',
  '激活': 'Licensing',
  '设置': 'Settings',
  '关于': 'About',
  'MoePureKit 萌净工具箱': 'MoePureKit Utility Toolkit',
  '您下一次的选择，何必再是网络查找呢': 'Your next choice, without another web search.',
  '启用界面轻量动画': 'Enable subtle interface motion',
  '控制页面、卡片与导航的淡入淡出；不会暂停后台任务': 'Controls subtle fades for pages, cards and navigation; background tasks continue.',
  '界面语言': 'Interface language',
  '主题模式': 'Theme',
  '跟随系统': 'Follow system',
  '简体中文': 'Simplified Chinese',
  '浅色模式': 'Light',
  '深色模式': 'Dark',
  '背景模式': 'Background',
  '编辑清单': 'Edit catalog',
  '添加到下载': 'Add to downloads',
  '保存清单': 'Save catalog',
  '编辑系统资源 JSON': 'Edit system resource JSON',
  '编辑软件清单 JSON': 'Edit software catalog JSON',
  '安装组件': 'Components',
  'Windows 11 官方镜像': 'Official Windows 11 media',
  '打开微软官方下载页': 'Open Microsoft download page',
  '需要管理员权限': 'Administrator permission required',
  '此 Windows 系统工具要求提升权限。是否继续并响应 Windows 用户账户控制（UAC）提示？': 'This Windows tool requires elevated permissions. Continue and respond to the Windows User Account Control (UAC) prompt?',
  '继续并请求权限': 'Continue and request permission',
  '不再询问关闭确认（可在设置中重新开启）':
      'Do not ask again when closing (change this in Settings)',
  '开机时自动启动': 'Launch at startup',
  '仅为当前 Windows 用户创建启动项，不需要管理员权限': 'Adds a startup entry for this Windows user only; no administrator access required',
  '关闭时不再询问': 'Do not ask before closing',
  '直接执行上方选择的默认操作；可随时重新开启': 'Performs the default action selected above; you can re-enable the prompt anytime',
  '不再提醒': 'Do not ask again',
  '已启用开机自启': 'Launch at startup enabled',
  '已关闭开机自启': 'Launch at startup disabled',
  '种子文件链接': 'Torrent file URL',
  '语言': 'Language',
  '更新通道': 'Update channel',
  '[{"title":"资源名称","version":"版本","size":"大小","sha256":"校验值","url":"https://...","category":"分类","description":"说明"}]': '[{"title":"Name","version":"Version","size":"Size","sha256":"Checksum","url":"https://...","category":"Category","description":"Description"}]',
  '此检测仅支持 Windows': 'This check is available on Windows only',
  '工具箱': 'Tools',
  '朴素 · 轻便 · 常用': 'Simple · Light · Useful',
  '任务运行中': 'Task running',
  '已就绪': 'Ready',
  '正在加载设置': 'Loading settings',
  'Windows 桌面工具': 'Windows desktop utility',
  'WELCOME': 'WELCOME',
  'OVERVIEW': 'OVERVIEW',
  'QUICK ACCESS': 'QUICK ACCESS',
  '设备状态一览': 'System overview',
  '把常用维护工具和当前系统状态放在一起。': 'System status and everyday maintenance tools, together.',
  '常用入口': 'Quick access',
  '常用功能保持精简，完整工具分类见左侧导航。': 'A short list of essentials; all tools are grouped in the sidebar.',
  '浏览、整理和管理文件': 'Browse and organize files',
  '扫描临时文件并预览空间': 'Scan temporary files and preview space',
  '本地 SHA-256 与 Defender': 'Local SHA-256 and Defender',
  '驱动信息、扫描与 INF 安装': 'Driver details, device scan and INF install',
  '常用工具，简单收好。': 'Everyday tools, kept simple.',
  '下载、系统维护与软件信息，都从这里开始。':
      'Downloads, system tools, and software information in one place.',
  '下载任务': 'Download tasks',
  '查看和管理 aria2 下载': 'Manage aria2 downloads',
  '系统资源': 'System resources',
  '查看已配置的系统资源': 'Browse configured system resources',
  'Office 部署': 'Office deployment',
  '检测安装状态与部署配置': 'Check installation and deployment options',
  '许可状态': 'License status',
  '查看系统许可信息与风险说明': 'Review license status and risk information',
  '下载引擎需要单独运行 aria2，并在设置中填写 JSON-RPC 地址。':
      'Run aria2 separately and enter its JSON-RPC URL in Settings.',
  'ARIA2 JSON-RPC': 'ARIA2 JSON-RPC',
  '添加任务': 'Add task',
  '任务总数': 'Total tasks',
  '正在下载': 'Active',
  '下载目录': 'Download folder',
  '由 aria2 / 设置管理': 'Managed by aria2 / Settings',
  '还没有下载任务': 'No download tasks yet',
  '请先在设置中配置 aria2 JSON-RPC 服务，再添加 HTTP、磁力或种子任务。': 'Configure aria2 JSON-RPC in Settings before adding HTTP, magnet, or torrent tasks.',
  '添加链接后，任务进度和速度会显示在这里。':
      'Task progress and speed will appear here after you add a link.',
  'HTTP / HTTPS / FTP 或磁力链接': 'Enter a valid HTTP, HTTPS, FTP, or magnet link',
  '下载中': 'Downloading',
  '等待中': 'Waiting',
  '已暂停': 'Paused',
  '已完成': 'Complete',
  '失败': 'Failed',
  '已移除': 'Removed',
  '添加下载任务': 'Add download task',
  '种子文件路径': 'Torrent file path',
  'Metalink 文件路径或下载地址': 'Metalink file path or URL',
  'HTTP / HTTPS / 磁力链接': 'HTTP / HTTPS / magnet link',
  '登录信息与请求头': 'Credentials and request headers',
  '收起登录信息': 'Hide request details',
  '额外 Header（每行一个）': 'Extra headers (one per line)',
  '取消': 'Cancel',
  '开始下载': 'Start download',
  '请输入链接或本地种子文件路径': 'Enter a URL or local torrent file path',
  'RESOURCE CATALOG': 'RESOURCE CATALOG',
  '资源清单可由维护者配置；应用不内置来源不明的系统镜像。': 'Resource catalogs are configurable; no unverified system images are bundled.',
  '尚未配置资源': 'No resources configured',
  '配置资源时可填写名称、版本、文件大小、校验值与下载地址；选择后可交由 aria2 下载。': 'Catalog entries can include name, version, size, checksum, and URL, then be sent to aria2.',
  '前往下载': 'Go to downloads',
  '资源接口建议：维护独立 JSON 清单，字段包括 title、version、size、sha256、url。由可信维护者提供链接并验证哈希后再导入。': 'Use a separate JSON catalog with title, version, size, sha256, and url. Import only trusted links with verified hashes.',
  'OFFICE DEPLOYMENT': 'OFFICE DEPLOYMENT',
  '通过官方部署工具和组织授权资源完成安装；本页不内置安装包。': 'Use the official deployment tool and licensed organization resources; no installer is bundled.',
  '安装状态检测': 'Installation status',
  '尚未检测': 'Not checked',
  '正在读取系统安装信息…': 'Reading installed software…',
  '检测已安装 Office': 'Detect installed Office',
  '读取 Office 许可状态': 'Read Office license status',
  'Office 许可状态尚未读取': 'Office license status has not been read',
  '正在读取 Office 许可状态…': 'Reading Office license status…',
  '部署配置': 'Deployment options',
  '等待配置官方 Office Deployment Tool': 'Select the official Office Deployment Tool',
  '微软官方 ODT 下载页': 'Official Microsoft ODT download',
  '选择并运行 ODT 解压包': 'Select and run ODT extractor',
  '解压官方 ODT': 'Extract official ODT',
  '启动解压程序': 'Run extractor',
  '选择官方 ODT 安装包': 'Select official ODT package',
  '选择 ODT setup.exe': 'Select ODT setup.exe',
  '浏览文件夹': 'Browse folders',
  '正在验证微软数字签名…': 'Verifying Microsoft digital signature…',
  '已验证微软签名，等待确认': 'Microsoft signature verified; awaiting confirmation',
  '验证签名中': 'Verifying signature',
  '部署进行中': 'Deployment in progress',
  '验证签名、生成配置并运行 ODT': 'Verify signature, configure, and run ODT',
  '确认部署': 'Confirm deployment',
  '确认并运行': 'Confirm and run',
  '打开 Windows 官方激活设置': 'Open Windows activation settings',
  '已打开 Windows 官方激活设置': 'Opened Windows activation settings',
  'SOFTWARE CATALOG': 'SOFTWARE CATALOG',
  '按分类整理可信软件资源，清单与下载地址应由用户或维护者配置。': 'Browse trusted software by category; catalogs and download URLs must be configured.',
  '搜索软件名称': 'Search software',
  '全部': 'All',
  '办公': 'Office',
  '开发': 'Development',
  '多媒体': 'Multimedia',
  '剩余': 'Remaining',
  '未找到已配置的软件': 'No configured software found',
  '软件数据源为空。配置后可按分类和关键词筛选，并在核对发布者与来源后跳转下载。': 'The catalog is empty. Configure it to filter by category and search term, then verify the publisher and source before downloading.',
  'LICENSE STATUS': 'LICENSE STATUS',
  '许可与授权': 'Licensing',
  '输入你拥有的正版产品密钥，通过 Windows 授权服务安装并尝试激活。': 'Install and activate through Windows licensing with a genuine product key you own.',
  '许可状态尚未读取': 'License status has not been read',
  '正在读取 Windows 许可状态…': 'Reading Windows license status…',
  'Windows 许可状态': 'Windows license status',
  '检查许可状态': 'Check license status',
  'Windows 正版激活': 'Genuine Windows activation',
  'XML 票据安全检查': 'XML ticket safety inspection',
  '选择本地 XML 文件，检查 XML 语法、结构摘要与 SHA-256。此操作不会将票据导入 Windows，也不会判定票据是否真实或具备授权资格。': 'Select a local XML file to check syntax, structure summary, and SHA-256. This does not import the ticket into Windows or determine authenticity or licensing eligibility.',
  '选择并检查 XML 票据': 'Select and inspect XML ticket',
  '正在检查 XML…': 'Inspecting XML…',
  '企业 KMS 客户端诊断': 'Enterprise KMS client diagnostics',
  '只读检查本机现有的批量授权客户端状态、已配置或 DNS 发现的 KMS 主机，以及 TCP 端口连通性。不会修改主机配置或发起激活。': 'Read-only inspection of the existing volume activation client, configured or DNS-discovered KMS host, and TCP reachability. No host configuration is changed and no activation is initiated.',
  '检查 KMS 客户端': 'Inspect KMS client',
  '正在诊断…': 'Diagnosing…',
  'Windows 产品密钥': 'Windows product key',
  '安装正版 Windows 密钥': 'Install genuine Windows key',
  '请输入格式正确的 25 位 Windows 正版产品密钥':
      'Enter a valid 25-character genuine Windows product key',
  '确认并请求管理员权限': 'Confirm and request administrator access',
  '安装密钥并尝试激活': 'Install key and attempt activation',
  '正在安装并激活…': 'Installing key and activating…',
  '正在请求管理员确认并提交正版密钥…':
      'Requesting administrator approval to submit the genuine key…',
  '设置下载目录': 'Set download folder',
  '请选择下载文件的保存位置。之后也可以在“设置”中修改。': 'Choose where downloaded files are saved. You can change this later in Settings.',
  '暂不设置': 'Not now',
  '选择文件夹': 'Choose folder',
  '使用默认目录': 'Use default folder',
  '选择此文件夹': 'Select this folder',
  '关闭 MoePureKit？': 'Close MoePureKit?',
  '选择隐藏到系统托盘继续运行，或退出应用。':
      'Hide to the system tray and keep running, or exit the app.',
  '退出应用': 'Exit app',
  '最小化到托盘': 'Minimize to tray',
  '关闭时优先最小化到系统托盘': 'Prefer minimizing to tray when closing',
  '仍会询问；后台下载和 Office 部署可继续运行': 'You will still be asked; downloads and Office deployment can continue in the background',
  '本机系统信息': 'System information',
  '刷新系统信息': 'Refresh system information',
  '设备': 'Device',
  '处理器': 'Processor',
  '内存': 'Memory',
  '系统架构': 'Architecture',
  'QUICK TOOLS': 'QUICK TOOLS',
  '快捷工具': 'Quick tools',
  '控制面板': 'Control Panel',
  '任务管理器': 'Task Manager',
  '设备管理器': 'Device Manager',
  '磁盘管理': 'Disk Management',
  '程序和功能': 'Programs and Features',
  'Windows 更新': 'Windows Update',
  '网络设置': 'Network settings',
  '声音设置': 'Sound settings',
  '服务管理': 'Services',
  '启动应用': 'Startup apps',
  'FILE INTEGRITY': 'FILE INTEGRITY',
  '文件校验': 'File checksum',
  '选择文件并计算': 'Select file and calculate',
  '计算文件 SHA-256': 'Calculate file SHA-256',
  '流式计算本地文件 SHA-256，避免将大文件整体载入内存。': 'Calculate a local file SHA-256 as a stream without loading the entire file into memory.',
  '正在计算 SHA-256…': 'Calculating SHA-256…',
  'SHA-256 已复制': 'SHA-256 copied',
  '复制校验值': 'Copy checksum',
  'NETWORK DIAGNOSTICS': 'NETWORK DIAGNOSTICS',
  '网络诊断': 'Network diagnostics',
  '检测 Ping、抖动、丢包、DNS、HTTPS 延迟和实际传输速度。': 'Measure ping, jitter, packet loss, DNS, HTTPS latency, and transfer speed.',
  '完整网络检测': 'Full network test',
  'Ping 目标': 'Ping target',
  '同时测试上传速度（发送约 2 MiB 自动生成数据）': 'Also test upload speed (sends about 2 MiB of generated data)',
  '检测中': 'Testing',
  '检测完成': 'Test complete',
  '复制报告': 'Copy report',
  '网络检测报告已复制': 'Network report copied',
  '检测详情': 'Test details',
  '未完成项目': 'Incomplete checks',
  'Ping 平均': 'Average ping',
  '抖动 Jitter': 'Jitter',
  '丢包率': 'Packet loss',
  '下载速度': 'Download speed',
  '上传速度': 'Upload speed',
  'HTTPS 延迟': 'HTTPS latency',
  '网络适配器': 'Network adapter',
  '本机 IPv4': 'Local IPv4',
  '默认网关': 'Default gateway',
  '网关 Ping': 'Gateway ping',
  '网关 Ping 样本': 'Gateway ping samples',
  '系统 DNS 服务器': 'Configured DNS servers',
  '测速域名解析 IP': 'Speed-test hostname IP',
  'DNS 测速节点': 'DNS test endpoint',
  'DNS 查询耗时': 'DNS lookup time',
  'Ping 最低 / 最高': 'Ping min / max',
  'Ping 样本': 'Ping samples',
  '下载数据量': 'Downloaded data',
  '上传数据量': 'Uploaded data',
  '检测节点': 'Test endpoint',
  '测速会连接 Cloudflare 公共测速节点。下载最多接收 8 MiB；上传仅发送自动生成的数据，不会上传本地文件。结果反映本机到该节点的路径，不等同于运营商线路保证值。': 'The test connects to Cloudflare public speed-test endpoints. It downloads up to 8 MiB and uploads generated data only; no local files are uploaded. Results reflect the route to that endpoint and are not an ISP guarantee.',
  '网络适配器、默认网关和系统 DNS 来自 Windows 网络配置。Ping 使用系统 ICMP 命令；部分网络或防火墙会屏蔽 ICMP。此时 HTTPS 延迟仍可反映应用层连通性。抖动按成功样本的相邻延迟差绝对值计算。': 'Adapter, default gateway, and configured DNS values come from Windows network configuration. ICMP ping may be blocked by some networks or firewalls; HTTPS latency can still indicate application connectivity. Jitter is the mean absolute difference between adjacent successful samples.',
  '正在准备检测…': 'Preparing test…',
  '正在读取网络适配器信息…': 'Reading network adapter configuration…',
  '正在测试默认网关 Ping…': 'Pinging the default gateway…',
  '正在解析测速节点 DNS…': 'Resolving the speed-test endpoint…',
  '正在测试 ICMP Ping、抖动和丢包…': 'Testing ICMP ping, jitter, and packet loss…',
  '正在测量 HTTPS 往返延迟…': 'Measuring HTTPS round-trip latency…',
  '正在测试下载速度（最多接收 8 MiB）…': 'Testing download speed (up to 8 MiB)…',
  '正在测试上传速度（发送 2 MiB 自动生成测试数据）…': 'Testing upload speed (sending 2 MiB of generated data)…',
  '未测试': 'Not tested',
  '已关闭上传测试': 'Upload test disabled',
  '未获取': 'Unavailable',
  '解析失败': 'DNS lookup failed',
  '无响应': 'No response',
  '文本工具': 'Text tools',
  'JSON 格式化': 'JSON formatter',
  '编码转换': 'Encoding converter',
  'TEXT UTILITIES': 'TEXT UTILITIES',
  '常用文本清理和批量处理，所有操作均在本机完成。': 'Clean and transform text locally with common batch operations.',
  '输入文本': 'Input text',
  '清空': 'Clear',
  '复制': 'Copy',
  '在此粘贴或输入文本…': 'Paste or type text here…',
  '文本处理': 'Text operations',
  '去除首尾空白': 'Trim whitespace',
  '合并多余空行': 'Collapse blank lines',
  '删除空白行': 'Remove blank lines',
  '行去重': 'Unique lines',
  '按行排序': 'Sort lines',
  '转为大写': 'Uppercase',
  '转为小写': 'Lowercase',
  '反转文本': 'Reverse text',
  '文本已复制': 'Text copied',
  'JSON WORKBENCH': 'JSON WORKBENCH',
  '格式化、压缩并校验 JSON 数据，不会上传输入内容。': 'Format, minify, and validate JSON locally; input is never uploaded.',
  '输入 JSON': 'Input JSON',
  '格式化': 'Format',
  '压缩': 'Minify',
  '校验 JSON': 'Validate JSON',
  'JSON 格式有效。': 'Valid JSON.',
  'JSON 格式有效，已完成格式化。': 'Valid JSON; formatted successfully.',
  'JSON 格式有效，已压缩输出。': 'Valid JSON; minified successfully.',
  '内容已修改，请重新校验。': 'Content changed; validate again.',
  '输出结果': 'Output',
  '复制结果': 'Copy result',
  'JSON 结果已复制': 'JSON result copied',
  'ENCODING CONVERTER': 'ENCODING CONVERTER',
  '支持多种常见哈希算法，流式读取文件并显示实时进度。': 'Multiple common hash algorithms with streamed file reads and live progress.',
  '大小写、去重、排序与文本统计': 'Case conversion, deduplication, sorting, and text statistics',
  '格式化、压缩和校验 JSON': 'Format, minify, and validate JSON',
  'Base64 与 URL 编码/解码': 'Base64 and URL encode/decode',
  '在本机进行 UTF-8、Base64 和 URL 编码转换。': 'Convert UTF-8 text, Base64, and URL encoding locally.',
  '转换模式': 'Conversion mode',
  'Base64 编码': 'Base64 encode',
  'Base64 解码': 'Base64 decode',
  'URL 编码': 'URL encode',
  'URL 解码': 'URL decode',
  '输入内容': 'Input',
  '输入要转换的文本…': 'Enter text to convert…',
  '开始转换': 'Convert',
  '转换结果': 'Result',
  '转换结果已复制': 'Conversion result copied',
  '哈希算法': 'Hash algorithm',
  '选择要校验的文件': 'Choose a file to verify',
  '文件只在本机读取，不会上传。': 'Files are read locally and are never uploaded.',
  '选择文件': 'Choose file',
  '已选择文件': 'File selected',
  '尚未选择文件': 'No file selected',
  '点击右上方按钮浏览本地文件': 'Use the button above to browse local files',
  '重新计算': 'Recalculate',
  '正在计算…': 'Calculating…',
  '计算结果': 'Digest result',
  '可选择并复制完整校验值': 'Select and copy the complete digest',
  '复制哈希': 'Copy digest',
  '对比已有校验值': 'Compare with expected digest',
  '粘贴发布者提供的哈希，自动比较当前计算结果。': 'Paste a publisher-provided digest to compare it with the computed result.',
  '粘贴 MD5 / SHA 哈希值': 'Paste an MD5 / SHA digest',
  '校验值匹配': 'Digest matches',
  '校验值不匹配': 'Digest does not match',
  '提示：MD5 和 SHA-1 仅用于兼容性核对；安全完整性校验建议优先使用 SHA-256 或 SHA-512。': 'Tip: MD5 and SHA-1 are for compatibility checks; prefer SHA-256 or SHA-512 for security-sensitive integrity checks.',
  'SHA-512 已复制': 'SHA-512 copied',
  'SHA-384 已复制': 'SHA-384 copied',
  'SHA-1 已复制': 'SHA-1 copied',
  'MD5 已复制': 'MD5 copied',
  '转换失败：': 'Conversion failed: ',
  '文件哈希计算失败：': 'File hashing failed: ',
  '正在检查 DNS 和 HTTPS 连通性…': 'Checking DNS and HTTPS connectivity…',
  '开始检测': 'Start check',
  '重要风险提示': 'Important risk notice',
  '仅输入你依法获得的 Windows 产品密钥。提交密钥需要通过 Windows UAC 明确确认；本应用不存储该密钥，不含激活绕过或伪造许可证功能。无效、过期或不适用于当前版本的密钥会由 Windows 拒绝。': 'Only enter a Windows product key you are authorized to use. Windows UAC confirmation is required; the app does not store the key or bypass licensing. Windows rejects invalid, expired, or incompatible keys.',
  'PREFERENCES': 'PREFERENCES',
  '偏好信息保存在本机；全局字体固定为微软雅黑。': 'Preferences are stored locally. Microsoft YaHei is the fixed application font.',
  '外观': 'Appearance',
  '纯白背景': 'White background',
  '毛玻璃（Mica / Acrylic）': 'Mica / Acrylic',
  'Bing 每日壁纸 + 毛玻璃': 'Bing daily wallpaper + Mica',
  'Bing 每日壁纸': 'Bing daily wallpaper',
  '刷新 Bing 壁纸': 'Refresh Bing wallpaper',
  '查看图片来源': 'View image source',
  '启用侧边栏轻量过渡': 'Enable lightweight sidebar transitions',
  '控制侧边栏选中状态的轻量过渡；不会暂停后台任务':
      'Controls the sidebar selection transition; background tasks keep running',
  '字体：Microsoft YaHei（固定）': 'Font: Microsoft YaHei (fixed)',
  '下载与 aria2': 'Downloads and aria2',
  'aria2 JSON-RPC 地址': 'aria2 JSON-RPC URL',
  'RPC 密钥': 'RPC secret',
  'Cookie 与 RPC 密钥保存在本机 SharedPreferences 中，当前版本未加密；请勿在共享账户中保存敏感信息。': 'Cookies and the RPC secret are stored in local SharedPreferences without encryption; do not save sensitive data in a shared account.',
  '并发数（1–64）': 'Concurrent downloads (1–64)',
  '代理地址': 'Proxy URL',
  '默认登录信息': 'Default request credentials',
  '启动遮罩按需求每次启动固定显示约 3 秒；当前版本不提供关闭开关。': 'The startup overlay is shown for about 3 seconds on every launch; it cannot be disabled.',
  '保存设置': 'Save settings',
  '设置已保存': 'Settings saved',
  '轻量、朴素的 Windows 常用工具箱。': 'A lightweight, simple toolkit for Windows.',
  '作者': 'Author',
  '版本': 'Version',
  '平台': 'Platform',
  'Windows 桌面': 'Windows desktop',
  '字体': 'Font',
  '版权': 'Copyright',
  '© 2026 Coloryi-MIAO': '© 2026 Coloryi-MIAO',
  '下载资源由用户配置并自行校验。请遵守软件许可、著作权和所在地区法律法规。': 'Download sources are user-configured and should be verified. Follow software licenses, copyright, and applicable laws.',
  '最小化': 'Minimize',
  '最大化 / 还原': 'Maximize / Restore',
  'Microsoft 365 Apps': 'Microsoft 365 Apps',
  'Office LTSC 2024': 'Office LTSC 2024',
  'Office LTSC 2021': 'Office LTSC 2021',
  'zh-CN': 'Chinese (Simplified)',
  'en-US': 'English (US)',
  'ja-JP': 'Japanese',
  'Current': 'Current',
  'MonthlyEnterprise': 'Monthly Enterprise',
  'SemiAnnual': 'Semi-Annual',
  '未检测到已安装的 Office': 'No installed Office product detected',
  '未检测到 Windows 许可证信息': 'No Windows license information detected',
  '性能': 'Performance',
  '重试': 'Retry',
  '选择下载版本': 'Choose download package',
  '请选择要下载的版本。便携版通常解压后运行；安装版会启动 Windows 安装向导。': 'Choose a package to download. Portable packages usually run after extraction; installer packages launch the Windows setup wizard.',
  '运行安装程序？': 'Run the installer?',
  '即将启动你刚下载的安装包。请确认文件来自 MoePureKit 官方 GitHub Release；Windows 可能会显示 UAC 或 SmartScreen 提示。': 'You are about to launch the package you downloaded. Confirm it came from the official MoePureKit GitHub Release. Windows may show a UAC or SmartScreen prompt.',
  '运行安装程序': 'Run installer',
  '更新监测': 'Update monitor',
  '有更新': 'Update available',
  '检查更新': 'Check for updates',
  '下载更新': 'Download update',
  'GitHub 发布页': 'GitHub releases',
  '取消下载': 'Cancel download',
  '复制文件路径': 'Copy file path',
  '进入关于页面时自动检查，应用运行期间每 6 小时检查一次。支持在应用内流式下载 Windows 便携版或安装版；不会自动运行安装程序。': 'Checks automatically when About opens and every 6 hours while the app is running. Stream-download Windows portable or installer packages in the app; installers are never launched automatically.',
  '下载资源由用户配置并自行校验。第三方依赖与资源遵循各自许可。': 'Download sources are user-configured and should be verified. Third-party dependencies and resources remain under their respective licenses.',
  '便携版': 'Portable',
  '安装版': 'Installer',
  '其他格式': 'Other format',
  '正在准备下载…': 'Preparing download…',
  '正在下载…': 'Downloading…',
  '下载完成。该 Release 未提供 API SHA-256，请按发布说明自行核对。': 'Download complete. This release did not provide an API SHA-256 digest; verify it against the release notes.',
  '下载完成，SHA-256 校验通过。': 'Download complete; SHA-256 verified.',
  '下载已取消。': 'Download cancelled.',
  '此 Release 没有可识别的 Windows 安装包或便携包。': 'No recognizable Windows installer or portable package is available in this release.',
  '文件 SHA-256 校验失败，已删除下载文件。': 'The file failed SHA-256 verification and was deleted.',
  '重命名': 'Rename',
  '确定': 'OK',
  '确认删除？': 'Confirm deletion?',
  '删除': 'Delete',
  '新建文件夹': 'New folder',
  '创建': 'Create',
  '上一级': 'Parent folder',
  '选择目录': 'Choose folder',
  '复制到…': 'Copy to…',
  '移动到…': 'Move to…',
  '当前目录项目较多，仅显示前 1,200 项；可使用搜索缩小范围。': 'This folder contains many items. Showing the first 1,200; use search to narrow the results.',
  '此目录为空，或没有匹配的文件。': 'This folder is empty or no files match.',
  '确认清理临时文件？': 'Confirm temporary-file cleanup?',
  '确认清理': 'Confirm cleanup',
  '安全临时文件清理': 'Safe temporary-file cleanup',
  '扫描当前用户 TEMP/TMP 与 Windows Temp 目录，只列出 24 小时以前的普通文件。不会触碰个人文档、下载目录、注册表或系统组件存储。': 'Scans the current user TEMP/TMP and Windows Temp folders and lists ordinary files older than 24 hours. Personal documents, Downloads, the registry, and system component stores are not touched.',
  '扫描临时文件': 'Scan temporary files',
  'Windows 存储设置': 'Windows storage settings',
  '扫描状态': 'Scan status',
  '待清理项目预览': 'Cleanup preview',
  '本地 SHA-256 指纹库': 'Local SHA-256 signature database',
  '导入指纹库': 'Import signature database',
  '选择扫描目录': 'Choose scan folder',
  '本地指纹扫描': 'Local signature scan',
  '通过 Microsoft Defender 官方 PowerShell cmdlet 发起所选目录的自定义扫描。启动时会显示 UAC 提权提示；扫描结果请以 Windows 安全中心的保护历史记录为准。': 'Starts a custom scan of the selected folder using Microsoft Defender official PowerShell cmdlets. UAC appears at launch; consult Windows Security Protection History for results.',
  '重要说明：内置特征目前包含 EICAR 测试指纹，用于验证检测链路，不是完整恶意软件库。指纹未命中不等于文件安全；请以 Defender 等专业引擎结果为准。': 'Important: the built-in signatures currently include the EICAR test signature to verify the detection path; this is not a complete malware database. A clean signature scan does not prove a file is safe. Use Defender or another professional engine.',
  '重新扫描硬件设备需要提升权限。继续后 Windows 将显示 UAC 确认窗口。': 'Rescanning hardware devices requires elevation. Windows will show a UAC confirmation prompt.',
  '安装驱动？': 'Install driver?',
  '以管理员身份打开设备管理器？': 'Open Device Manager as administrator?',
  '继续': 'Continue',
  '刷新驱动清单': 'Refresh driver list',
  '安装 INF 驱动': 'Install INF driver',
  '管理员设备管理器': 'Device Manager (administrator)',
  '尚无驱动清单。点击“刷新驱动清单”读取 Windows 当前已安装的签名驱动。': 'No driver list yet. Select “Refresh driver list” to read the signed drivers currently installed in Windows.',
  '驱动安装会调用 Windows pnputil 并显示 UAC。此页不提供未经验证的第三方驱动包，也不会自动替换当前驱动。': 'Driver installation uses Windows pnputil and displays UAC. This page does not provide unverified third-party driver packages or automatically replace existing drivers.',
  '尚未检查': 'Not checked yet',
  '正在检查更新…': 'Checking for updates…',
  '当前已是最新版本': 'You are up to date',
  '发现新版本：': 'New version found: ',
  '检查失败：': 'Update check failed: ',
  '下载失败：': 'Download failed: ',
  '在文件夹中显示': 'Show in folder',
  '选择保存位置': 'Choose save location',
  'GNU GPL-3.0-only': 'GNU GPL-3.0-only',
  '退出前关闭 aria2 失败：': 'Failed to stop aria2 before exit: ',
  '无法创建系统托盘图标：': 'Could not create the system tray icon: ',
  '系统信息读取失败：': 'Could not read system information: ',
  '已验证发布者：': 'Verified publisher: ',
  '1. 从微软下载并运行 ODT 自解压程序。  2. 选择解压目录中的 setup.exe。  3. 生成官方 configuration.xml 并运行部署。': '1. Download and run the ODT self-extractor from Microsoft.  2. Select setup.exe in the extracted folder.  3. Generate the official configuration.xml and run deployment.',
  '设备管理器将以管理员身份启动，以便执行驱动和设备更改。Windows 将显示 UAC 确认窗口。': 'Device Manager will start as administrator so you can make driver and device changes. Windows will display a UAC confirmation prompt.',
  'UTF-8 字节数：': 'UTF-8 bytes: ',
  '设置尚未保存': 'Settings have not been saved',
  '当前设置有未保存的更改。离开前要如何处理？': 'There are unsaved settings changes. What would you like to do before leaving?',
  '继续编辑': 'Continue editing',
  '放弃修改': 'Discard changes',
  '保存并离开': 'Save and leave',
  'theme': 'theme',
  '主题和背景会立即预览，但不会自动保存；离开本页时会询问保存或放弃。': 'Theme and background changes are previewed immediately but are not saved automatically. You will be asked to save or discard them when leaving this page.',
  '关闭时最小化到系统托盘（保留后台下载）': 'Minimize to the system tray when closing (keep downloads running)',
  '默认关闭窗口会退出应用并关闭 aria2；启用后会隐藏到托盘并继续下载': 'By default, closing the window exits the app and stops aria2. When enabled, the app hides to the tray and downloads continue.',
  '无法打开存储设置：': 'Could not open Storage settings: ',
  '读取失败或无权限：': 'Read failed or access denied: ',
  '另有 ': 'Plus ',
  '已扫描 ': 'Scanned ',
  '将通过 Windows pnputil 安装此 INF，并请求 Windows UAC 管理员授权：': 'Windows pnputil will install this INF and request administrator approval through UAC:',
  '驱动安装、卸载和设备更改通常需要管理员权限。Windows 将显示 UAC 确认窗口。': 'Driver installation, removal, and device changes usually require administrator privileges. Windows will display a UAC confirmation prompt.',
  '已安装驱动 · ': 'Installed drivers · ',
  '无法打开系统工具：': 'Could not open system tool: ',
  '无法打开图片来源：': 'Could not open image source: ',
  '保存失败：': 'Save failed: ',
  '检测完成 · ': 'Test complete · ',
  '版本 ': 'Version ',
  '本地版本高于 GitHub 最新发布版本': 'The local build is newer than the latest GitHub release',
  '下载此发布版': 'Download this release',
  '仅扫描 Windows 临时目录中的旧文件；不会自动清理下载、桌面或文档。': 'Scans old files in Windows temporary folders only. Downloads, Desktop, and Documents are never cleaned automatically.',
  'C 盘临时目录清理仅支持 Windows。': 'C drive temporary-folder cleanup is only available on Windows.',
  '正在扫描临时文件…': 'Scanning temporary files…',
  '正在清理…': 'Cleaning up…',
  '载入本地 SHA-256 指纹库…': 'Loading local SHA-256 signature database…',
  '正在载入…': 'Loading…',
  '正在逐文件计算 SHA-256…': 'Calculating SHA-256 for each file…',
  '正在请求管理员权限并调用 Microsoft Defender…': 'Requesting administrator permission and starting Microsoft Defender…',
  'Microsoft Defender 扫描仅支持 Windows。': 'Microsoft Defender scanning is only available on Windows.',
  'Defender 扫描命令已完成。': 'The Defender scan command completed.',
  '正在请求管理员权限并重新扫描设备…': 'Requesting administrator permission and rescanning devices…',
  'Windows 已完成硬件重新扫描。': 'Windows completed the hardware rescan.',
  'pnputil 已完成驱动安装命令。建议重启后检查设备管理器状态。': 'pnputil completed the driver installation command. Restart and check Device Manager.',
  '驱动清单仅支持 Windows。': 'The driver list is available on Windows only.',
  '已达到 50,000 项安全上限，请分批处理。': 'The 50,000-item safety limit was reached. Process items in batches.',
  '此操作将通过 Windows 用户账户控制请求管理员确认，把你提供的密钥提交给 Windows 授权服务并尝试在线激活。密钥不会保存在本应用设置中。请只使用你有权使用的正版密钥。': 'This action requests administrator approval through Windows User Account Control, submits the key you provide to the Windows licensing service, and attempts online activation. The key is not saved in app settings. Only use a genuine key you are authorized to use.',
  '无效的 SHA-256 指纹': 'Invalid SHA-256 signature',
  '许可': 'License',
};

String translateText(BuildContext context, String value) {
  if (Localizations.localeOf(context).languageCode != 'en') return value;
  final direct = _english[value];
  if (direct != null) return direct;
  final cleanupMatch = RegExp(
    r'^将尝试删除 (.+?) 个超过 24 小时的临时文件，预计释放 (.+?)。被系统占用或权限不足的文件会自动跳过。',
  ).firstMatch(value);
  if (cleanupMatch != null) {
    return 'Attempts to delete ${cleanupMatch[1]} temporary files older than 24 hours, '
        'freeing about ${cleanupMatch[2]}. Files in use or without permission are skipped.';
  }
  if (value.endsWith(' 已复制')) {
    return value.replaceFirst(' 已复制', ' copied');
  }
  if (value.startsWith('发现新版本：')) return value.replaceFirst('发现新版本：', 'Update available: ');
  if (value.startsWith('检查失败：')) return value.replaceFirst('检查失败：', 'Update check failed: ');
  if (value.startsWith('下载失败：')) return value.replaceFirst('下载失败：', 'Download failed: ');
  if (value.startsWith('aria2 已连接 · ')) {
    return value.replaceFirst('aria2 已连接 · ', 'aria2 connected · ');
  }
  if (value.startsWith('aria2 已连接，但设置同步失败：')) {
    return value.replaceFirst(
      'aria2 已连接，但设置同步失败：',
      'aria2 connected, but settings sync failed: ',
    );
  }
  if (value.startsWith('aria2 未连接：')) {
    return value.replaceFirst('aria2 未连接：', 'aria2 disconnected: ');
  }
  if (value.startsWith('Bing 壁纸载入失败：')) {
    return value.replaceFirst('Bing 壁纸载入失败：', 'Bing wallpaper failed: ');
  }
  if (value.startsWith('系统信息读取失败：')) {
    return value.replaceFirst(
      '系统信息读取失败：',
      'Could not read system information: ',
    );
  }
  if (value.startsWith('无法打开系统工具：')) {
    return value.replaceFirst('无法打开系统工具：', 'Could not open system tool: ');
  }
  if (value.startsWith('读取文件失败：')) {
    return value.replaceFirst('读取文件失败：', 'Could not read file: ');
  }
  if (value.startsWith('Windows 未完成密钥安装：')) {
    return value.replaceFirst(
      'Windows 未完成密钥安装：',
      'Windows could not install the key: ',
    );
  }
  if (value.startsWith('Windows 拒绝此密钥：')) {
    return value.replaceFirst('Windows 拒绝此密钥：', 'Windows rejected this key: ');
  }
  if (value.startsWith('密钥格式错误：')) {
    return value.replaceFirst('密钥格式错误：', 'Invalid key format: ');
  }
  if (value.startsWith('激活流程超时：')) {
    return value.replaceFirst('激活流程超时：', 'Activation timed out: ');
  }
  if (value.startsWith('网络连接失败：')) {
    return value.replaceFirst('网络连接失败：', 'Network connection failed: ');
  }
  if (value.startsWith('文件哈希计算失败：')) {
    return value.replaceFirst('文件哈希计算失败：', 'File hashing failed: ');
  }
  if (value.startsWith('转换失败：')) {
    return value.replaceFirst('转换失败：', 'Conversion failed: ');
  }
  if (value.startsWith('处理失败：')) {
    return value.replaceFirst('处理失败：', 'Processing failed: ');
  }
  if (value.startsWith('JSON 格式错误：')) {
    return value.replaceFirst('JSON 格式错误：', 'Invalid JSON: ')
        .replaceAll('（位置 ', ' (offset ')
        .replaceAll('）', ')');
  }
  if (value.startsWith('UTF-8 字节数：')) {
    return value.replaceFirst('UTF-8 字节数：', 'UTF-8 bytes: ');
  }
  if (value.endsWith(' 字符')) {
    return '${value.substring(0, value.length - 3)} characters';
  }
  if (value.endsWith(' 行')) {
    return '${value.substring(0, value.length - 2)} lines';
  }
  if (value.endsWith(' 个词')) {
    return '${value.substring(0, value.length - 3)} words';
  }
  if (value.startsWith('HTTPS 检测失败：')) {
    return value.replaceFirst('HTTPS 检测失败：', 'HTTPS check failed: ');
  }
  if (value.startsWith('无法创建系统托盘图标：')) {
    return value.replaceFirst('无法创建系统托盘图标：', 'Could not create tray icon: ');
  }
  if (value.startsWith('无法启动 ODT：')) {
    return value.replaceFirst('无法启动 ODT：', 'Could not start ODT: ');
  }
  if (value.startsWith('Office 许可检测失败：')) {
    return value.replaceFirst(
      'Office 许可检测失败：',
      'Office license check failed: ',
    );
  }
  if (value.startsWith('无法验证 ODT 签名：')) {
    return value.replaceFirst(
      '无法验证 ODT 签名：',
      'Could not verify the ODT signature: ',
    );
  }
  if (value.startsWith('拒绝运行：')) {
    return value.replaceFirst('拒绝运行：', 'Execution blocked: ');
  }
  if (value.startsWith('无法打开 Windows 激活设置：')) {
    return value.replaceFirst(
      '无法打开 Windows 激活设置：',
      'Could not open Windows activation settings: ',
    );
  }
  if (value.startsWith('设置加载失败：')) {
    return value.replaceFirst('设置加载失败：', 'Could not load settings: ');
  }
  if (value.startsWith('设置保存失败：')) {
    return value.replaceFirst('设置保存失败：', 'Could not save settings: ');
  }
  if (value.startsWith('检测失败：')) {
    return value.replaceFirst('检测失败：', 'Detection failed: ');
  }
  if (value.startsWith('状态读取失败：')) {
    return value.replaceFirst('状态读取失败：', 'Status check failed: ');
  }
  if (value.startsWith('添加失败：')) {
    return value.replaceFirst('添加失败：', 'Could not add task: ');
  }
  if (value.startsWith('操作失败：')) {
    return value.replaceFirst('操作失败：', 'Operation failed: ');
  }
  if (value.startsWith('网络模板导入失败：')) return value.replaceFirst('网络模板导入失败：', 'Could not import network template: ');
  if (value.startsWith('无法启动管理员终端：')) return value.replaceFirst('无法启动管理员终端：', 'Could not start elevated terminal: ');
  if (value.startsWith('资源清单读取失败：')) {
    return value.replaceFirst('资源清单读取失败：', 'Could not load resource catalog: ');
  }
  if (value.startsWith('软件清单读取失败：')) {
    return value.replaceFirst('软件清单读取失败：', 'Could not load software catalog: ');
  }
  if (value.startsWith('保存清单失败：')) {
    return value.replaceFirst('保存清单失败：', 'Could not save catalog: ');
  }
  if (value.startsWith('版本 ')) {
    return value.replaceFirst('版本 ', 'Version ');
  }
  if (value.startsWith('大小 ')) {
    return value.replaceFirst('大小 ', 'Size ');
  }
  if (value.startsWith('版本 ')) return value.replaceFirst('版本 ', 'Version ');
  if (value.startsWith('系统信息读取失败：')) return value.replaceFirst('系统信息读取失败：', 'Could not read system information: ');
  if (value.startsWith('无法打开系统工具：')) return value.replaceFirst('无法打开系统工具：', 'Could not open system tool: ');
  if (value.startsWith('无法打开图片来源：')) return value.replaceFirst('无法打开图片来源：', 'Could not open image source: ');
  if (value.startsWith('无法打开存储设置：')) return value.replaceFirst('无法打开存储设置：', 'Could not open Storage settings: ');
  if (value.startsWith('读取失败或无权限：')) return value.replaceFirst('读取失败或无权限：', 'Read failed or access denied: ');
  if (value.startsWith('已扫描 ')) return value.replaceFirst('已扫描 ', 'Scanned ');
  if (value.startsWith('已安装驱动 · ')) return value.replaceFirst('已安装驱动 · ', 'Installed drivers · ');
  if (value.startsWith('检测完成 · ')) return value.replaceFirst('检测完成 · ', 'Test complete · ');
  if (value.startsWith('UTF-8 字节数：')) return value.replaceFirst('UTF-8 字节数：', 'UTF-8 bytes: ');
  if (value.startsWith('退出前关闭 aria2 失败：')) return value.replaceFirst('退出前关闭 aria2 失败：', 'Failed to stop aria2 before exit: ');
  if (value.startsWith('无法创建系统托盘图标：')) return value.replaceFirst('无法创建系统托盘图标：', 'Could not create the system tray icon: ');
  if (value.startsWith('保存失败：')) return value.replaceFirst('保存失败：', 'Save failed: ');
  if (value.startsWith('无法打开 Windows 激活设置：')) return value.replaceFirst('无法打开 Windows 激活设置：', 'Could not open Windows activation settings: ');
  if (value.startsWith('已验证发布者：')) return value.replaceFirst('已验证发布者：', 'Verified publisher: ');
  if (value.startsWith('文件夹 · ')) return value.replaceFirst('文件夹 · ', 'Folder · ');
  if (value.startsWith('本地版本高于 GitHub 最新发布版本')) return 'The local build is newer than the latest GitHub release';
  if (value.startsWith('无法读取此目录：')) return value.replaceFirst('无法读取此目录：', 'Could not read this folder: ');
  if (value.startsWith('本地指纹库载入失败：')) return value.replaceFirst('本地指纹库载入失败：', 'Could not load local signature database: ');
  if (value.startsWith('本地扫描失败：')) return value.replaceFirst('本地扫描失败：', 'Local scan failed: ');
  if (value.startsWith('设备信息读取失败：')) return value.replaceFirst('设备信息读取失败：', 'Could not read device information: ');
  if (value.startsWith('设备扫描未能完成：')) return value.replaceFirst('设备扫描未能完成：', 'Device scan did not complete: ');
  if (value.startsWith('驱动安装未能确认成功：')) return value.replaceFirst('驱动安装未能确认成功：', 'Could not confirm driver installation: ');
  if (value.startsWith('无法打开系统设置：')) return value.replaceFirst('无法打开系统设置：', 'Could not open System Settings: ');
  if (value.startsWith('Defender 扫描未能确认完成：')) return value.replaceFirst('Defender 扫描未能确认完成：', 'Could not confirm Defender scan completion: ');
  if (value.startsWith('已载入 ') && value.contains(' 条指纹')) return value.replaceAll('已载入 ', 'Loaded ').replaceAll(' 条指纹', ' signatures');
  if (value.startsWith('本地库已载入 ')) return value.replaceFirst('本地库已载入 ', 'Local database loaded: ').replaceAll(' 条指纹。', ' signatures.');
  if (value.startsWith('已导入并保存 ')) return value.replaceFirst('已导入并保存 ', 'Imported and saved ').replaceAll(' 条指纹；当前共 ', ' signatures; ').replaceAll(' 条。', ' total.');
  if (value.startsWith('没有找到有效的 SHA-256 指纹。')) return 'No valid SHA-256 signatures were found. Each row must contain a 64-character hash, a space, and a name.';
  if (value.startsWith('扫描完成：')) return value.replaceFirst('扫描完成：', 'Scan complete: ').replaceAll(' 个超过 24 小时的临时文件，约 ', ' temporary files older than 24 hours, about ').replaceAll('。已达到 50,000 项安全上限，请分批处理。', '. The 50,000-item safety limit was reached; process items in batches.').replaceAll('。', '.');
  if (value.startsWith('已删除 ')) return value.replaceFirst('已删除 ', 'Deleted ').replaceAll(' 个文件，释放 ', ' files, freed ').replaceAll('；跳过 ', '; skipped ').replaceAll(' 个占用或无权限文件。', ' files in use or without permission.');
  if (value.startsWith('读取到 ') && value.contains(' 条设备驱动记录')) return value.replaceFirst('读取到 ', 'Read ').replaceAll(' 条设备驱动记录（最多展示 100 条）。', ' device-driver records (up to 100 shown).');
  if (value.startsWith('已扫描 ') && value.contains(' 个文件 · 跳过 ')) return value.replaceFirst('已扫描 ', 'Scanned ').replaceAll(' 个文件 · 跳过 ', ' files · skipped ').replaceAll(' 个', '');
  if (value.startsWith('另有 ') && value.endsWith(' 项未展开')) return value.replaceFirst('另有 ', '').replaceFirst(' 项未展开', ' more items not shown');
  if (value.startsWith('读取失败或无权限：')) return value.replaceFirst('读取失败或无权限：', 'Read failed or access denied: ').replaceAll(' 项', ' items');
  if (value.startsWith('将通过 Windows pnputil 安装此 INF')) {
    return value.replaceFirst('将通过 Windows pnputil 安装此 INF，并请求 Windows UAC 管理员授权：', 'Windows pnputil will install this INF and request administrator approval through UAC:');
  }
  if (value.startsWith('驱动安装、卸载和设备更改通常需要管理员权限。')) return 'Driver installation, removal, and device changes usually require administrator privileges. Windows will display a UAC confirmation prompt.';
  if (value.endsWith(' 已复制')) return value.replaceFirst(' 已复制', ' copied');
  if (value.startsWith('已验证发布者：')) {
    return value.replaceFirst('已验证发布者：', 'Verified publisher: ')
      .replaceAll('。接下来会请求 Windows UAC 管理员授权并启动微软官方 ODT 自解压程序，请在它的窗口中接受许可并选择解压目录。', '. Windows will next request administrator approval through UAC and launch the official Microsoft ODT self-extractor. Accept its license and choose an extraction folder.')
      .replaceAll('。将请求 Windows UAC 管理员授权，通过 ', '. Windows will request administrator approval through UAC and use ')
      .replaceAll(' 执行 Office 部署；请确认你拥有所选版本的合法许可证。', ' to deploy Office. Confirm you have a valid license for the selected edition.');
  }
  if (value.startsWith('检测完成 · ') && value.endsWith(' 秒')) return value.replaceFirst('检测完成 · ', 'Test complete · ').replaceFirst(' 秒', ' s');
  if (value.startsWith('本地版本高于 GitHub 最新发布版本')) return 'The local build is newer than the latest GitHub release';
  return value;
}
