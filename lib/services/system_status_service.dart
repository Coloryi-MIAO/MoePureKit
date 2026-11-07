import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class PowerShellUnavailableException implements Exception {
  const PowerShellUnavailableException();

  @override
  String toString() => '当前系统策略禁止启动 PowerShell，无法完成状态检测；请联系系统管理员或检查应用执行权限。';
}

class SystemStatusService {
  Future<String> verifyMicrosoftSignedExecutable(String path) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('此签名验证仅支持 Windows');
    }
    final encodedPath = base64Encode(utf8.encode(path));
    final script =
        r"$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" +
        encodedPath +
        r"')); $signature=Get-AuthenticodeSignature -LiteralPath $target; if($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match 'Microsoft Corporation'){'VALID|'+$signature.SignerCertificate.Subject}else{'INVALID|'+$signature.Status+'|'+$signature.SignerCertificate.Subject}";
    final result = await _runPowerShell(script);
    if (result.exitCode != 0) {
      _throwPowerShellResult(result);
    }
    final subject = result.stdout.toString().trim();
    if (subject.startsWith('INVALID|')) {
      throw FormatException('安装程序未通过微软数字签名验证：${subject.substring(8)}');
    }
    if (!subject.startsWith('VALID|') ||
        !subject.contains('Microsoft Corporation')) {
      throw const FormatException('无法确认安装程序的微软数字签名');
    }
    return subject.substring('VALID|'.length);
  }

  Future<String> detectOffice() async {
    if (!Platform.isWindows) return '此检测仅支持 Windows';
    const script =
        r"$paths=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'); $items=Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Microsoft (365|Office)' } | Select-Object -ExpandProperty DisplayName -Unique; if($items){$items -join [Environment]::NewLine}else{'未检测到已安装的 Office'}";
    final result = await _runPowerShell(script);
    if (result.exitCode != 0) {
      _throwPowerShellResult(result);
    }
    return result.stdout.toString().trim();
  }

  Future<String> detectWindowsLicense() async {
    if (!Platform.isWindows) return '此检测仅支持 Windows';
    // Windows may expose several licensing records. Prefer an actually
    // licensed Windows record instead of taking an arbitrary first result.
    const script =
        r"$items=@(Get-CimInstance SoftwareLicensingProduct -ErrorAction Stop | Where-Object { $_.PartialProductKey -and $_.ApplicationID -eq '55c92734-d682-4d71-983e-d6ec3f16059f' } | Sort-Object @{Expression={if($_.LicenseStatus -eq 1){0}else{1}}},Name | Select-Object -First 5 Name,Description,LicenseStatus,GracePeriodRemaining,PartialProductKey,ProductKeyChannel,LicenseStatusReason); if($items.Count -gt 0){ConvertTo-Json -InputObject $items -Compress -Depth 3}else{'未检测到 Windows 许可证信息'}";
    final result = await _runPowerShell(script);
    if (result.exitCode != 0) {
      _throwPowerShellResult(result);
    }

    final raw = result.stdout.toString().trim();
    if (raw.isEmpty || raw == '未检测到 Windows 许可证信息') {
      return raw.isEmpty ? '未收到 Windows 许可证信息' : raw;
    }

    final decoded = jsonDecode(raw);
    final records = switch (decoded) {
      List<dynamic> values => values,
      Map<String, dynamic> value => [value],
      _ => throw const FormatException('Windows 许可证响应格式异常'),
    };
    if (records.isEmpty) return '未检测到 Windows 许可证信息';

    return records.map((record) {
      if (record is! Map<String, dynamic>) {
        throw const FormatException('Windows 许可证记录格式异常');
      }
      final name = record['Name']?.toString().trim();
      final statusCode = int.tryParse('${record['LicenseStatus']}');
      final status = switch (statusCode) {
        0 => '未授权',
        1 => '已授权',
        2 => '初始宽限期',
        3 => '超期宽限期',
        4 => '非正版宽限期',
        5 => '通知状态',
        6 => '扩展宽限期',
        _ => '未知状态',
      };
      final partialKey = record['PartialProductKey']?.toString();
      final channel = _readWindowsProductKeyChannel(record);
      final graceMinutes = int.tryParse(
        '${record['GracePeriodRemaining']}',
      );
      final details = <String>[
        '许可状态：$status${statusCode == null ? '' : '（代码 $statusCode）'}',
        if (partialKey != null && partialKey.isNotEmpty)
          '产品密钥末五位：$partialKey',
        if (channel.isNotEmpty) '授权通道：$channel',
        if (graceMinutes != null && graceMinutes > 0)
          '剩余宽限时间：${_formatGracePeriod(graceMinutes)}',
        if (record['LicenseStatusReason'] != null &&
            '${record['LicenseStatusReason']}' != '0')
          '状态原因代码：${record['LicenseStatusReason']}',
      ];
      return '${name?.isNotEmpty == true ? name : 'Windows 许可证'}\n${details.join('；')}';
    }).join('\n\n');
  }

  String _readWindowsProductKeyChannel(Map<String, dynamic> record) {
    final channel = record['ProductKeyChannel']?.toString().trim();
    if (channel != null && channel.isNotEmpty) return channel;
    final description = record['Description']?.toString() ?? '';
    final knownChannels = [
      'VOLUME_KMSCLIENT',
      'VOLUME_MAK',
      'OEM_DM',
      'OEM_COA',
      'RETAIL',
    ];
    return knownChannels.firstWhere(
      (value) => description.toUpperCase().contains(value),
      orElse: () => '',
    );
  }

  String _formatGracePeriod(int minutes) {
    final days = minutes ~/ (24 * 60);
    final hours = (minutes % (24 * 60)) ~/ 60;
    if (days > 0) return '$days 天 $hours 小时';
    if (hours > 0) return '$hours 小时';
    return '$minutes 分钟';
  }

  Future<Map<String, String>> getSystemOverview() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('系统信息读取仅支持 Windows');
    }
    const script =
        r"$os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $cpu=Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1; $cs=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue; $board=Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue; $bios=Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue; $uptime=(Get-Date)-$os.LastBootUpTime; [ordered]@{computerName=$env:COMPUTERNAME; os=$os.Caption; version=$os.Version; build=$os.BuildNumber; architecture=$os.OSArchitecture; cpu=$cpu.Name; memoryGB=[math]::Round($os.TotalVisibleMemorySize/1MB,1); manufacturer=$cs.Manufacturer; model=$cs.Model; board=($board.Product); bios=($bios.SMBIOSBIOSVersion); uptimeDays=[math]::Floor($uptime.TotalDays); uptimeHours=$uptime.Hours} | ConvertTo-Json -Compress";
    final result = await _runPowerShell(script);
    if (result.exitCode != 0) _throwPowerShellResult(result);
    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Windows 系统信息响应格式异常');
    }
    return decoded.map((key, value) => MapEntry(key, '$value'));
  }

  Future<String> installGenuineWindowsProductKey(String input) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('正版密钥安装仅支持 Windows');
    }
    final key = input.trim().replaceAll('-', '').toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{25}$').hasMatch(key)) {
      throw const FormatException('产品密钥应为 25 位字母数字字符');
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'moepurekit-activation-',
    );
    try {
      final keyPath = '${temporaryDirectory.path}\\product-key.txt';
      final resultPath = '${temporaryDirectory.path}\\result.json';
      final scriptPath = '${temporaryDirectory.path}\\activate.ps1';
      await File(keyPath).writeAsString(key, flush: true);
      final keyPathBase64 = base64Encode(utf8.encode(keyPath));
      final resultPathBase64 = base64Encode(utf8.encode(resultPath));
      final script =
          '''
\$keyPath=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$keyPathBase64'))
\$resultPath=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$resultPathBase64'))
try {
  \$productKey=[IO.File]::ReadAllText(\$keyPath).Trim()
  Remove-Item -LiteralPath \$keyPath -Force
  \$licensingService=Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
  \$installResult=Invoke-CimMethod -InputObject \$licensingService -MethodName InstallProductKey -Arguments @{ProductKey=\$productKey} -ErrorAction Stop
  if ([int]\$installResult.ReturnValue -ne 0) { throw "Windows rejected product key (code \$([int]\$installResult.ReturnValue))" }
  \$activationCode=-1
  \$activationError=''
  try {
    \$activationProcess=Start-Process -FilePath "\$env:WINDIR\\System32\\cscript.exe" -ArgumentList @('//NoLogo', "\$env:WINDIR\\System32\\slmgr.vbs", '/ato') -Wait -PassThru -WindowStyle Hidden
    \$activationCode=[int]\$activationProcess.ExitCode
  } catch {
    \$activationError=\$_.Exception.Message
  }
  \$refreshResult=Invoke-CimMethod -InputObject \$licensingService -MethodName RefreshLicenseStatus -ErrorAction Stop
  \$license=Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop | Where-Object { \$_.PartialProductKey -and \$_.ApplicationID -eq '55c92734-d682-4d71-983e-d6ec3f16059f' } | Select-Object -First 1 Name,LicenseStatus,PartialProductKey
  \$payload=@{success=\$true; installCode=[int]\$installResult.ReturnValue; activationCode=\$activationCode; activationError=\$activationError; refreshCode=[int]\$refreshResult.ReturnValue; name=\$license.Name; licenseStatus=[int]\$license.LicenseStatus; lastFive=\$license.PartialProductKey} | ConvertTo-Json -Compress
  [IO.File]::WriteAllText(\$resultPath,\$payload,[Text.UTF8Encoding]::new(\$false))
} catch {
  \$payload=@{success=\$false; error=\$_.Exception.Message} | ConvertTo-Json -Compress
  [IO.File]::WriteAllText(\$resultPath,\$payload,[Text.UTF8Encoding]::new(\$false))
  exit 1
}
''';
      await File(scriptPath).writeAsString(script, encoding: utf8, flush: true);
      final launchCommand =
          "\$scriptPath=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${base64Encode(utf8.encode(scriptPath))}')); "
          "\$arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `\"' + \$scriptPath + '`\"'; "
          "\$process=Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList \$arguments -Wait -PassThru; "
          "exit \$process.ExitCode";
      final commandBytes = Uint8List(launchCommand.length * 2);
      for (var index = 0; index < launchCommand.length; index++) {
        final codeUnit = launchCommand.codeUnitAt(index);
        commandBytes[index * 2] = codeUnit & 0xFF;
        commandBytes[index * 2 + 1] = codeUnit >> 8;
      }
      final encodedCommand = base64Encode(commandBytes);
      final processResult = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        encodedCommand,
      ], runInShell: false).timeout(const Duration(minutes: 10));
      final resultFile = File(resultPath);
      if (!await resultFile.exists()) {
        final error = processResult.stderr.toString().trim();
        if (processResult.exitCode != 0) {
          throw ProcessException(
            'powershell.exe',
            const ['-Verb', 'RunAs'],
            error.isEmpty ? 'UAC 已取消或提升进程未能启动' : error,
            processResult.exitCode,
          );
        }
        throw const FormatException('未收到 Windows 激活组件的结果');
      }
      final payload = jsonDecode(await resultFile.readAsString());
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Windows 激活结果格式错误');
      }
      if (payload['success'] != true) {
        throw StateError('Windows 未接受该密钥：${payload['error'] ?? '未知错误'}');
      }
      final licenseName = payload['name']?.toString() ?? 'Windows';
      final lastFive = payload['lastFive']?.toString() ?? '';
      final activationCode = int.tryParse('${payload['activationCode']}') ?? -1;
      final activationError = payload['activationError']?.toString() ?? '';
      final activationResult = activationCode == 0
          ? 'Windows 在线激活命令已完成'
          : 'Windows 在线激活未确认（退出码：$activationCode）${activationError.isEmpty ? '' : '：$activationError'}';
      final licenseStatus = payload['licenseStatus']?.toString() ?? '未知';
      return '已安装密钥（末五位：$lastFive）；$activationResult。$licenseName 当前许可状态码：$licenseStatus。请在 Windows 激活设置中确认最终状态。';
    } on TimeoutException {
      throw TimeoutException('Windows 激活流程超时；请检查 UAC 提示和系统激活设置。');
    } finally {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }

  /// Safely inspects a local XML file without importing it into Windows
  /// licensing components. DTDs and external entity resolution are disabled.
  Future<String> inspectLicenseTicketXml(String path) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('XML 票据检查仅支持 Windows');
    }
    final file = File(path);
    if (!await file.exists()) throw const FileSystemException('文件不存在');
    final length = await file.length();
    if (length == 0) throw const FormatException('XML 文件为空');
    if (length > 8 * 1024 * 1024) {
      throw const FormatException('XML 文件超过 8 MiB 安全检查上限');
    }

    final pathBase64 = base64Encode(utf8.encode(file.absolute.path));
    final script = r'''
$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PATH_BASE64__'))
try {
  $settings=[System.Xml.XmlReaderSettings]::new()
  $settings.DtdProcessing=[System.Xml.DtdProcessing]::Prohibit
  $settings.XmlResolver=$null
  $settings.MaxCharactersInDocument=8388608
  $reader=[System.Xml.XmlReader]::Create($target,$settings)
  $root=''
  $rootNamespace=''
  $elements=0
  $attributes=0
  $hasXmlSignature=$false
  try {
    while($reader.Read()) {
      if($reader.NodeType -eq [System.Xml.XmlNodeType]::Element) {
        $elements++
        if($elements -gt 200000) { throw 'XML element count exceeds the safety limit' }
        if($reader.Depth -eq 0) { $root=$reader.LocalName; $rootNamespace=$reader.NamespaceURI }
        if($reader.LocalName -eq 'Signature' -and $reader.NamespaceURI -eq 'http://www.w3.org/2000/09/xmldsig#') { $hasXmlSignature=$true }
        if($reader.HasAttributes) { $attributes += $reader.AttributeCount }
      }
    }
  } finally { $reader.Dispose() }
  if([string]::IsNullOrWhiteSpace($root)) { throw 'XML document has no root element' }
  $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash
  $result=@{success=$true; fileName=[IO.Path]::GetFileName($target); bytes=(Get-Item -LiteralPath $target).Length; root=$root; namespace=$rootNamespace; elements=$elements; attributes=$attributes; hasXmlSignature=$hasXmlSignature; sha256=$hash} | ConvertTo-Json -Compress
  [Console]::Out.WriteLine($result)
} catch {
  @{success=$false; error=$_.Exception.Message} | ConvertTo-Json -Compress | Write-Output
}
'''.replaceAll('__PATH_BASE64__', pathBase64);
    final result = await _runPowerShell(script).timeout(
      const Duration(seconds: 20),
    );
    if (result.exitCode != 0) _throwPowerShellResult(result);
    final raw = result.stdout.toString().trim();
    if (raw.isEmpty) throw const FormatException('未收到 XML 检查结果');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('XML 检查响应格式异常');
    }
    if (decoded['success'] != true) {
      throw FormatException('XML 无法安全解析：${decoded['error'] ?? '未知错误'}');
    }
    final hasSignature = decoded['hasXmlSignature'] == true;
    return [
      'XML 语法：通过',
      '文件：${decoded['fileName']}',
      '大小：${decoded['bytes']} 字节',
      '根节点：${decoded['root']}',
      if ('${decoded['namespace']}'.isNotEmpty)
        '命名空间：${decoded['namespace']}',
      '元素数：${decoded['elements']}；属性数：${decoded['attributes']}',
      'XML-DSig Signature 节点：${hasSignature ? '存在' : '未发现'}',
      'SHA-256：${decoded['sha256']}',
      '注意：此检查只验证 XML 可解析性和结构摘要，不验证签名真实性、票据有效性或 Windows 授权资格；文件未被导入系统。',
    ].join('\n');
  }

  /// Read-only diagnostics for an existing organization's KMS client setup.
  /// It never changes the KMS host, product key, or activation state.
  Future<String> diagnoseKmsClient() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('KMS 诊断仅支持 Windows');
    }
    const script = r'''
try {
  $appId='55c92734-d682-4d71-983e-d6ec3f16059f'
  $service=Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
  $products=@(Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop | Where-Object { $_.ApplicationID -eq $appId -and $_.PartialProductKey -and ($_.Description -match 'VOLUME_KMSCLIENT' -or $_.ProductKeyChannel -eq 'Volume:GVLK') } | Select-Object Name,Description,LicenseStatus,GracePeriodRemaining,KeyManagementServiceMachine,KeyManagementServicePort,DiscoveredKeyManagementServiceMachineName,DiscoveredKeyManagementServiceMachinePort)
  $hostName=[string]$service.KeyManagementServiceMachine
  $port=[int]$service.KeyManagementServicePort
  $source='未发现 KMS 主机'
  if(-not [string]::IsNullOrWhiteSpace($hostName)) { $source='本机显式配置' }
  if([string]::IsNullOrWhiteSpace($hostName)) {
    $product=$products | Select-Object -First 1
    if($product) { $hostName=[string]$product.KeyManagementServiceMachine; if($port -eq 0){$port=[int]$product.KeyManagementServicePort} }
  }
  if([string]::IsNullOrWhiteSpace($hostName)) {
    $discovered=[string]$service.DiscoveredKeyManagementServiceMachineName
    $discoveredPort=[int]$service.DiscoveredKeyManagementServiceMachinePort
    if(-not [string]::IsNullOrWhiteSpace($discovered)) {
      $hostName=$discovered; if($discoveredPort -gt 0){$port=$discoveredPort}; $source='Windows DNS 自动发现缓存'
    }
  }
  if([string]::IsNullOrWhiteSpace($hostName)) {
    try {
      $srvName='_vlmcs._tcp'
      if(-not [string]::IsNullOrWhiteSpace($env:USERDNSDOMAIN)) { $srvName += '.' + $env:USERDNSDOMAIN }
      $srv=Resolve-DnsName -Name $srvName -Type SRV -ErrorAction Stop | Select-Object -First 1
      if($srv) { $hostName=([string]$srv.NameTarget).TrimEnd('.'); $port=[int]$srv.Port; $source='DNS SRV 自动发现' }
    } catch {}
  }
  if($port -le 0) { $port=1688 }
  $tcpStatus='未测试'
  if(-not [string]::IsNullOrWhiteSpace($hostName)) {
    $client=[System.Net.Sockets.TcpClient]::new()
    try {
      $async=$client.BeginConnect($hostName,$port,$null,$null)
      if($async.AsyncWaitHandle.WaitOne(2500) -and $client.Connected) { $client.EndConnect($async); $tcpStatus='可连接' } else { $tcpStatus='连接超时或被拒绝' }
    } catch { $tcpStatus='连接失败：'+$_.Exception.Message }
    finally { $client.Dispose() }
  }
  $primary=$products | Select-Object -First 1
  $productName=''
  $licenseStatus=-1
  $graceMinutes=0
  if($primary) { $productName=[string]$primary.Name; $licenseStatus=[int]$primary.LicenseStatus; $graceMinutes=[int]$primary.GracePeriodRemaining }
  $result=@{success=$true; volumeKmsClientCount=$products.Count; productName=$productName; licenseStatus=$licenseStatus; graceMinutes=$graceMinutes; host=$hostName; port=$port; source=$source; tcpStatus=$tcpStatus; dnsHost=[string]$service.DiscoveredKeyManagementServiceMachineName; dnsPort=[int]$service.DiscoveredKeyManagementServiceMachinePort} | ConvertTo-Json -Compress
  [Console]::Out.WriteLine($result)
} catch {
  @{success=$false; error=$_.Exception.Message} | ConvertTo-Json -Compress | Write-Output
}
''';
    final result = await _runPowerShell(script).timeout(
      const Duration(seconds: 20),
    );
    if (result.exitCode != 0) _throwPowerShellResult(result);
    final raw = result.stdout.toString().trim();
    if (raw.isEmpty) throw const FormatException('未收到 KMS 诊断结果');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('KMS 诊断响应格式异常');
    }
    if (decoded['success'] != true) {
      throw FormatException('KMS 诊断失败：${decoded['error'] ?? '未知错误'}');
    }
    final count = int.tryParse('${decoded['volumeKmsClientCount']}') ?? 0;
    final host = decoded['host']?.toString() ?? '';
    final port = decoded['port']?.toString() ?? '';
    final tcp = decoded['tcpStatus']?.toString() ?? '未知';
    final grace = int.tryParse('${decoded['graceMinutes']}') ?? 0;
    final statusCode = int.tryParse('${decoded['licenseStatus']}') ?? -1;
    final licenseStatus = switch (statusCode) {
      0 => '未授权',
      1 => '已授权',
      2 => '初始宽限期',
      3 => '超期宽限期',
      4 => '非正版宽限期',
      5 => '通知状态',
      6 => '扩展宽限期',
      _ => '未检测到 KMS 客户端许可证',
    };
    return [
      'KMS 客户端许可证数量：$count',
      if ('${decoded['productName']}'.isNotEmpty)
        '产品：${decoded['productName']}',
      '许可状态：$licenseStatus${statusCode >= 0 ? '（代码 $statusCode）' : ''}',
      if (grace > 0) '剩余宽限时间：${_formatGracePeriod(grace)}',
      'KMS 主机：${host.isEmpty ? '未配置/未发现' : host}',
      if (host.isNotEmpty) '端口：$port',
      if (host.isNotEmpty) 'TCP 连通性：$tcp',
      '发现来源：${decoded['source'] ?? '未知'}',
      '说明：只读取当前 KMS 配置并测试网络连通性；本工具不会设置 KMS 主机或发起激活。',
    ].join('\n');
  }

  Future<void> openWindowsActivationSettings() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('此操作仅支持 Windows');
    }
    await Process.start('explorer.exe', [
      'ms-settings:activation',
    ], runInShell: false);
  }

  Future<ProcessResult> _runPowerShell(String script) async {
    try {
      return await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ], runInShell: false);
    } on ProcessException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('access is denied') ||
          message.contains('access denied') ||
          message.contains('blocked') ||
          message.contains('拒绝访问')) {
        throw const PowerShellUnavailableException();
      }
      rethrow;
    }
  }

  Never _throwPowerShellResult(ProcessResult result) {
    final message = result.stderr.toString().toLowerCase();
    if (message.contains('access is denied') ||
        message.contains('access denied') ||
        message.contains('running scripts is disabled') ||
        message.contains('blocked') ||
        message.contains('拒绝访问')) {
      throw const PowerShellUnavailableException();
    }
    throw ProcessException(
      'powershell.exe',
      const [],
      result.stderr.toString(),
      result.exitCode,
    );
  }
}
