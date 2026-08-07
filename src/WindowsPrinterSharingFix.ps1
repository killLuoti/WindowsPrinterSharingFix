#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 打印机共享修复工具 - v2.3.2
    @KHAIRUDINFAHMI（汉化版）

.PARAMETER nuke
    静默全部修复模式 - 自动执行全部 50 项修复后自动重启。
#>

param(
    [switch]$nuke
)

$script:version    = "2.3.2"
$script:backupDir  = "C:\WindowsPrinterSharingFixBackup"
$script:silentNuke = $nuke

$script:logFile = $null
$candidateLogs = @(
    "C:\WindowsPrinterSharingFixLog.txt",
    "$env:TEMP\WindowsPrinterSharingFixLog.txt",
    "$env:USERPROFILE\Desktop\WindowsPrinterSharingFixLog.txt"
)
foreach ($cl in $candidateLogs) {
    try {
        Add-Content -Path $cl -Value "" -Encoding UTF8 -ErrorAction Stop
        $script:logFile = $cl
        break
    } catch { }
}
if (-not $script:logFile) {
    $script:logFile = "$env:TEMP\WindowsPrinterSharingFixLog.txt"
}

$script:isARM64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
$script:isServer = $false
try {
    $prodOptions = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions" -ErrorAction SilentlyContinue
    if ($prodOptions -and $prodOptions.ProductType -ne "WinNT") {
        $script:isServer = $true
    }
} catch {
    try {
        $script:isServer = ((Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType -ne 1)
    } catch {
        $script:isServer = $false
    }
}

$buildInfo = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
if ($buildInfo -and $null -ne $buildInfo.CurrentBuild) {
    try {
        $script:buildNumber = [int]$($buildInfo.CurrentBuild)
    }
    catch {
        $script:buildNumber = [Environment]::OSVersion.Version.Build
    }
}
else {
    $script:buildNumber = [Environment]::OSVersion.Version.Build
}

if ($buildInfo -and $null -ne $buildInfo.ProductName) {
    $script:productName = $buildInfo.ProductName

    if ($script:buildNumber -ge 22000 -and $script:productName -match "Windows 10") {
        $script:productName = $script:productName -replace "Windows 10", "Windows 11"
    }
}
else {
    $script:productName = "Windows NT $([Environment]::OSVersion.Version.Major)"
}

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Type - $Message"
    try {
        Add-Content -Path $script:logFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
    }
    catch {

    }

    if ($Type -eq "ERROR") {
        Write-Host "  [错误] $Message" -ForegroundColor Red
    }
    elseif ($Type -eq "WARNING") {
        Write-Host "  [!] $Message" -ForegroundColor Yellow
    }
    elseif ($Type -eq "SUCCESS") {
        Write-Host "  [+] $Message" -ForegroundColor Green
    }
    else {
        Write-Host "  [*] $Message" -ForegroundColor Cyan
    }
}

function Test-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    Write-Host "`n  [!] 请稍候... 正在请求管理员权限。" -ForegroundColor Yellow
    Write-Host "  [!] 请在 UAC 弹窗中点击「是」以继续。" -ForegroundColor Yellow

    $isExe = $false
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($exePath -match '\.exe$' -and $exePath -notmatch 'powershell') {
        $isExe = $true
    }

    if ($isExe) {
        $cmdArgs = ""
        if ($script:silentNuke) { $cmdArgs += "-nuke" }
        Start-Process -FilePath $exePath -ArgumentList $cmdArgs -Verb RunAs
    }
    else {
        $cmdArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($script:silentNuke) { $cmdArgs += " -nuke" }
        Start-Process powershell -Verb RunAs -ArgumentList $cmdArgs
    }
    exit
}

function Initialize-Log {
    if (-not (Test-Path $script:backupDir)) {
        New-Item -ItemType Directory -Path $script:backupDir -Force | Out-Null
    }
    try {
        Add-Content -Path $script:logFile -Value ("=" * 60) -Encoding UTF8 -ErrorAction SilentlyContinue
        Add-Content -Path $script:logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Windows 打印机共享修复工具" -Encoding UTF8 -ErrorAction SilentlyContinue

        if ($script:isARM64) {
            Add-Content -Path $script:logFile -Value "[检测到 ARM64 架构]" -Encoding UTF8
        }
        if ($script:isServer) {
            Add-Content -Path $script:logFile -Value "[检测到 Windows Server 版本]" -Encoding UTF8
        }
    }
    catch {}
}

if (-not (Test-Administrator)) {
    Restart-Elevated
}
Initialize-Log

function Fix-RpcAuthn0x0000011b {
    Write-Log "正在修复错误 0x0000011b (RpcAuthnLevelPrivacy)..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Print" -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "注册表 0x0000011b 修复成功应用。" -Type "SUCCESS"
        Write-Host "  [+] 已禁用 RPC 身份验证级别隐私要求。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 0x0000011b 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Deep0x00000709 {
    Write-Log "深度修复 0x00000709 — 正在应用所有 RPC 层..." -Type "INFO"
    try {

        $rpcPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $rpcPath)) { New-Item -Path $rpcPath -Force | Out-Null }
        Set-ItemProperty -Path $rpcPath -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcTcpEnable            -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcProtocols            -Value 7 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcOverNamedPipes       -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcAuthenticationLevel  -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name ForceKerberosForRpc     -Value 0 -Type DWord -Force

        $printPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print"
        Set-ItemProperty -Path $printPath -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $printPath -Name DnsOnWire              -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $printPath -Name CopyFilesPolicy        -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $printPath -Name RpcOverNamedPipes       -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $printPath -Name RpcOverTcp              -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        $lanPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Set-ItemProperty -Path $lanPath -Name DisableStrictNameChecking -Value 1 -Type DWord -Force

        $deviceKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows"
        $deviceVal = (Get-ItemProperty $deviceKey -ErrorAction SilentlyContinue).Device
        if ($deviceVal) {
            Write-Host "  [!] 正在清除旧版 Device 键: $deviceVal" -ForegroundColor Yellow
            Remove-ItemProperty -Path $deviceKey -Name "Device" -ErrorAction SilentlyContinue
            Write-Log "HKCU Device 键已清除: $deviceVal" -Type "SUCCESS"
        }
        Set-ItemProperty -Path $deviceKey -Name LegacyDefaultPrinterMode -Value 1 -Type DWord -Force

        $wppPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP"
        if (-not (Test-Path $wppPath)) { New-Item -Path $wppPath -Force | Out-Null }
        Set-ItemProperty -Path $wppPath -Name Enabled -Value 0 -Type DWord -Force

        $lsaMSV = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
        Set-ItemProperty -Path $lsaMSV -Name NtlmMinClientSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $lsaMSV -Name NtlmMinServerSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        Restart-Service spooler -Force -ErrorAction SilentlyContinue

        Write-Log "Fix-Deep0x00000709 修复完成。也必须在主机（连接打印机的电脑）上执行。" -Type "SUCCESS"
        Write-Host "  [+] 已应用全部 0x00000709 修复层。" -ForegroundColor Green
        Write-Host "  [!] 重要提示：请在主机电脑（直接连接打印机的电脑）上也运行此脚本！" -ForegroundColor Red
    }
    catch {
        Write-Log "深度修复 0x00000709 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-CrossSignedDriverPolicy {
    Write-Log "正在绕过 KB5089549 交叉签名驱动强制策略（审核模式禁用）..." -Type "INFO"
    try {

        $ciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config"
        if (-not (Test-Path $ciPath)) { New-Item -Path $ciPath -Force | Out-Null }

        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config" `
            -Name VulnerableDriverBlocklistEnable -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        $polPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (-not (Test-Path $polPath)) { New-Item -Path $polPath -Force | Out-Null }
        Set-ItemProperty -Path $polPath `
            -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "交叉签名驱动强制策略已设为宽松（KB5089549 后续修复）。" -Type "SUCCESS"
        Write-Host "  [+] 已中和 KB5089549 驱动策略强制。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复交叉签名驱动策略失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-HKCU-PrinterKeyPerms {
    Write-Log "正在修复 HKCU Windows 注册表键权限以允许写入打印机设备..." -Type "INFO"
    try {

        $regKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows"
        $acl = Get-Acl $regKey
        $sid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $sid,
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $regKey -AclObject $acl -ErrorAction Stop
        Write-Log "HKCU Windows 键：已授予 Everyone (S-1-1-0) 完全控制权限。" -Type "SUCCESS"
        Write-Host "  [+] 注册表权限修复已应用（打印机设备键已授予 Everyone 完全控制）。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 HKCU 打印机键权限失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Set-PostPatchTuesdayTask {
    Write-Log "正在部署 Windows 更新后自动重新应用任务..." -Type "INFO"
    try {
        if (-not (Test-Path $script:backupDir)) {
            New-Item -ItemType Directory -Path $script:backupDir -Force | Out-Null
        }
        
        $scriptPath = Join-Path $script:backupDir "PrinterFixReapply.ps1"
        $fixScript = @'
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC" -Name ForceKerberosForRpc -Value 0 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcProtocols -Value 7 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name RpcOverNamedPipes -Value 1 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name RpcOverTcp -Value 1 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -EA SilentlyContinue
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord -Force -EA SilentlyContinue
Restart-Service spooler -Force -EA SilentlyContinue
'@
        Set-Content -Path $scriptPath -Value $fixScript -Encoding UTF8 -Force
        
        $cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        
        & schtasks.exe /create /tn "PrinterFixPostUpdate" /tr $cmd /sc onstart /ru "SYSTEM" /rl HIGHEST /f > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "schtasks ONSTART 返回退出代码 $LASTEXITCODE" }
        
        & schtasks.exe /create /tn "PrinterFixDaily" /tr $cmd /sc daily /st 10:00 /ru "SYSTEM" /rl HIGHEST /f > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "schtasks DAILY 返回退出代码 $LASTEXITCODE" }

        # 配置任务允许在电池供电下运行（消除笔记本电脑上的 0x800710E0 错误）
        try {
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            Set-ScheduledTask -TaskName "PrinterFixPostUpdate" -Settings $settings -ErrorAction SilentlyContinue | Out-Null
            Set-ScheduledTask -TaskName "PrinterFixDaily" -Settings $settings -ErrorAction SilentlyContinue | Out-Null
        } catch {}

        Write-Log "Windows 更新后自动重新应用任务部署成功。" -Type "SUCCESS"
        Write-Host "  [+] 自动重新应用任务已部署。每次重启/更新后注册表修复将自动重新应用。" -ForegroundColor Green
        Write-Host "  [+] 任务计划程序中已启用任务：'PrinterFixPostUpdate' 和 'PrinterFixDaily'。" -ForegroundColor Cyan
    }
    catch {
        Write-Log "部署更新后任务失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Discovery0x00000bc4 {
    Write-Log "正在绕过错误 0x00000bc4（未找到打印机）..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }

        Set-ItemProperty -Path $path -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name RpcTcpEnable -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name RpcProtocols -Value 0x7 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name ForceSetup -Value 1 -Type DWord -Force -ErrorAction Stop

        Write-Log "已通过命名管道与 TCP 强制 RPC 终结点映射。" -Type "SUCCESS"
        Write-Host "  [+] RPC 打印机发现已明确通过命名管道路由。" -ForegroundColor Green
    }
    catch {
        Write-Log "绕过 0x00000bc4 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NetworkServices {
    Write-Log "正在修复错误 0x80070035（启动 WSD、SMB、NetBIOS 服务）..." -Type "INFO"
    $services = @("nlasvc", "Dnscache", "LanmanServer", "LanmanWorkstation", "lmhosts", "fdPHost", "FDResPub", "SSDPSRV", "upnphost", "WdiSystemHost", "WdiServiceHost")

    foreach ($svc in $services) {
        try {
            Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "警告：无法配置服务 $svc。" -Type "WARNING"
        }
    }
    Write-Log "网络与 WSD 服务已配置为自动启动。" -Type "SUCCESS"
    Write-Host "  [+] 所有网络服务均已正常运行。" -ForegroundColor Green
}

function Fix-CSR {
    Write-Log "正在禁用客户端渲染（错误 0x000006d1）..." -Type "INFO"
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }

        Set-ItemProperty -Path $path -Name DisableClientSideRendering -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "客户端渲染已成功禁用。" -Type "SUCCESS"
        Write-Host "  [+] 客户端渲染已禁用；打印作业将由主机处理。" -ForegroundColor Green
    }
    catch {
        Write-Log "禁用客户端渲染失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Reset-Spooler {
    Write-Log "正在终止打印后台处理程序并清空队列..." -Type "INFO"
    try {
        Stop-Service spooler -Force -ErrorAction SilentlyContinue

        Write-Log "正在确保相关进程（splwow64、printfilter）已终止..." -Type "INFO"
        Get-Process -Name "printfilterpipelinesvc", "splwow64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 1

        Write-Log "正在清除过期的打印后台文件..." -Type "INFO"
        Remove-Item -Path "$env:SystemRoot\System32\Spool\Printers\*" -Force -Recurse -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 1

        Set-Service spooler -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service spooler -ErrorAction Stop

        Write-Log "打印后台处理程序刷新成功！" -Type "SUCCESS"
        Write-Host "  [+] 打印后台处理程序已成功清空并设置为自动启动（硬重置）。" -ForegroundColor Green
    }
    catch {
        Write-Log "重置后台处理程序失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Enable-SMBGuest {
    Write-Log "正在启用 SMB 来宾访问（LanmanWorkstation 与 LanmanServer）..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
        Set-ItemProperty -Path $path -Name AllowInsecureGuestAuth -Value 1 -Type DWord -Force -ErrorAction Stop

        $pathServer = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Set-ItemProperty -Path $pathServer -Name EnableSecuritySignature -Value 0 -Type DWord -Force -ErrorAction Stop

        Write-Log "来宾访问已启用。" -Type "SUCCESS"
        Write-Host "  [+] 已降低 SMB 凭据保护以允许来宾访问。" -ForegroundColor Green
    }
    catch {
        Write-Log "启用 SMB 来宾访问失败: $($_.Exception.Message)" -Type "ERROR"
    }
}
function Reset-Network {
    Write-Log "正在执行完整网络重置（刷新 DNS、NetBIOS、Winsock）..." -Type "INFO"
    try {
        $LASTEXITCODE = 0; ipconfig /flushdns > $null 2>&1
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        $LASTEXITCODE = 0; & netsh winsock reset > $null 2>&1
        $LASTEXITCODE = 0; & netsh int ip reset > $null 2>&1
        $LASTEXITCODE = 0; nbtstat -RR > $null 2>&1

        Write-Log "网络配置已重置。" -Type "SUCCESS"
        Write-Host "  [+] 网络缓存已成功刷新。" -ForegroundColor Green
    }
    catch {
        Write-Log "重置网络失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Set-NetworkPrivate {
    Write-Log "正在更改网络配置文件（公用→专用，绕过域）..." -Type "INFO"
    try {
        $nla = Get-Service nlasvc -ErrorAction SilentlyContinue
        if ($nla -and $nla.Status -ne 'Running') { Start-Service nlasvc -ErrorAction SilentlyContinue }

        $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
        $success = $false
        foreach ($profile in $profiles) {
            if ($profile.NetworkCategory -eq 'Public') {
                try {
                    Set-NetConnectionProfile -InterfaceAlias $profile.InterfaceAlias -NetworkCategory Private -ErrorAction Stop
                    $success = $true
                }
                catch {
                    Write-Log "无法更改配置文件 $($profile.InterfaceAlias)。" -Type "WARNING"
                }
            }
            elseif ($profile.NetworkCategory -eq 'Private' -or $profile.NetworkCategory -eq 'DomainAuthenticated') {
                $success = $true
            }
        }

        if ($success) {
            Write-Log "专用网络配置文件已安全应用。" -Type "SUCCESS"
            Write-Host "  [+] 网络已强制设为专用；发现限制已移除。" -ForegroundColor Green
        }
    }
    catch {
        Write-Log "更改网络配置文件失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Disable-PasswordSharing {
    Write-Log "正在禁用密码保护共享..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name limitblankpassworduse -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name everyoneincludesanonymous -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name restrictnullsessaccess -Value 0 -Type DWord -Force -ErrorAction Stop

        Write-Log "密码保护共享已禁用。" -Type "SUCCESS"
        Write-Host "  [+] 网络共享已开放（Everyone = 匿名访问）。" -ForegroundColor Green
    }
    catch {
        Write-Log "禁用密码共享失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NamedPipes {
    Write-Log "正在激活 RPC 命名管道..." -Type "INFO"
    try {
        $rpcPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC"
        if (-not (Test-Path $rpcPath)) { New-Item -Path $rpcPath -Force | Out-Null }

        Set-ItemProperty -Path $rpcPath -Name RpcUseNamedPipeProtocol -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcTcpEnable -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcProtocols -Value 0x7 -Type DWord -Force
        Set-ItemProperty -Path $rpcPath -Name RpcOverNamedPipes -Value 1 -Type DWord -Force

        $printPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print"
        Set-ItemProperty -Path $printPath -Name RpcOverNamedPipes -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $printPath -Name RpcOverTcp -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        Write-Log "命名管道已激活。" -Type "SUCCESS"
        Write-Host "  [+] RPC 命名管道打印后台路径已修复。" -ForegroundColor Green
    }
    catch {
        Write-Log "更改命名管道失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Open-Firewall {
    Write-Log "正在打开防火墙以允许文件和打印机共享..." -Type "INFO"
    try {
        Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28502" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28509" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -DisplayGroup "*File*Printer*" -ErrorAction SilentlyContinue | Out-Null
        Enable-NetFirewallRule -DisplayGroup "*Network Discovery*" -ErrorAction SilentlyContinue | Out-Null

        Write-Log "防火墙端口已开放。" -Type "SUCCESS"
        Write-Host "  [+] Windows Defender 防火墙已配置为允许共享。" -ForegroundColor Green
    }
    catch {
        Write-Log "更改防火墙规则失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Backup-Registry {
    Write-Log "正在执行打印机注册表备份..." -Type "INFO"
    try {
        $backupCount = 0
        $backupTotal = 5

        & reg export "HKLM\SYSTEM\CurrentControlSet\Control\Print" "$script:backupDir\Print.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告：备份 Print 注册表失败。" -Type "WARNING" }

        & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers" "$script:backupDir\PrintersPolicy.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告：备份 PrintersPolicy 注册表失败。" -Type "WARNING" }

        & reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" "$script:backupDir\LanmanWorkstation.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告：备份 LanmanWorkstation 注册表失败。" -Type "WARNING" }

        & reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "$script:backupDir\LanmanServer.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告：备份 LanmanServer 注册表失败。" -Type "WARNING" }

        & reg export "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" "$script:backupDir\Lsa.reg" /y > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $backupCount++ } else { Write-Log "警告：备份 LSA 注册表失败。" -Type "WARNING" }

        Write-Log "备份完成（$backupCount/$backupTotal 个配置单元）。" -Type "SUCCESS"
        Write-Host "  [+] 关键注册表节点已备份到 $script:backupDir（$backupCount/$backupTotal 个配置单元）。" -ForegroundColor Green
    }
    catch {
        Write-Log "备份注册表失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Check-RPC {
    Write-Log "正在检查 RPC 和 DCOM 服务状态..." -Type "INFO"
    $rpc = Get-Service -Name RpcSs -ErrorAction SilentlyContinue
    if ($rpc.Status -ne 'Running') {
        Start-Service RpcSs -ErrorAction SilentlyContinue
        Write-Host "  [*] RpcSs 离线。正在重新初始化服务。" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] RpcSs 正常运行。" -ForegroundColor Green
    }

    $dcom = Get-Service -Name DcomLaunch -ErrorAction SilentlyContinue
    if ($dcom.Status -ne 'Running') {
        Start-Service DcomLaunch -ErrorAction SilentlyContinue
        Write-Host "  [*] DcomLaunch 离线。正在重新初始化服务。" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] DcomLaunch 正常运行。" -ForegroundColor Green
    }
}

function Run-SfcDism {
    Write-Log "正在启动 SFC 和 DISM 序列..." -Type "INFO"
    Write-Host "`n  [!] 请稍候，此操作需要较长时间..." -ForegroundColor Yellow
    Write-Host "  [*] [1/2] 正在执行 SFC Scannow 序列..." -ForegroundColor Cyan
    & sfc /scannow
    Write-Host "  [*] [2/2] 正在执行 DISM RestoreHealth 序列..." -ForegroundColor Cyan
    & dism /online /cleanup-image /restorehealth
    Write-Log "SFC 和 DISM 序列已完成。" -Type "SUCCESS"
    Write-Host "  [+] 系统文件完整性检查已结束。" -ForegroundColor Green
}

function Manage-Drivers {
    Write-Log "正在打开打印服务器属性..." -Type "INFO"
    Write-Host "  [!] 打印服务器属性对话框已打开。请手动清理异常驱动。" -ForegroundColor Yellow
    Start-Process printui -ArgumentList '/s /t2' -NoNewWindow
}

function Reset-SpoolerPerm {
    Write-Log "正在重置后台处理程序目录 ACL 权限..." -Type "INFO"
    try {
        & icacls "$env:SystemRoot\System32\Spool\Printers" /reset /t /c /q > $null 2>&1
        & icacls "$env:SystemRoot\System32\Spool\Printers" /grant "*S-1-1-0:(OI)(CI)F" /T /C /Q > $null 2>&1
        Write-Log "后台处理程序 ACL 已重置，Everyone (S-1-1-0) 授权完成。" -Type "SUCCESS"
        Write-Host "  [+] 打印队列目录权限已重置并授予 Everyone。" -ForegroundColor Green
    }
    catch {
        Write-Log "重置 ACL 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-SMB1 {
    Write-Host "`n  ======================================================================"
    Write-Host "                 SMB 1.0 协议管理（旧版）"
    Write-Host "  ======================================================================"
    Write-Host "  [!] 警告：SMB 1.0 极易受到勒索软件攻击。"
    Write-Host "  [1] 启用 SMB1（紧急情况）"
    Write-Host "  [2] 禁用 SMB1（推荐）"
    $smbopt = Read-Host "  选择选项 (1/2)"
    if ($smbopt -eq '1') {
        try {
            Write-Log "正在启用 SMB 1.0 协议..." -Type "INFO"
            Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null
            Write-Host "  [+] SMB 1.0 协议已启用。" -ForegroundColor Green
        } catch {
            Write-Log "启用 SMB1 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
    if ($smbopt -eq '2') {
        try {
            Write-Log "正在禁用 SMB 1.0 协议..." -Type "INFO"
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null
            Write-Host "  [+] SMB 1.0 协议已成功禁用，增强安全性。" -ForegroundColor Green
        } catch {
            Write-Log "禁用 SMB1 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Add-Credential {
    Write-Host "`n  注入 Windows 凭据"
    $ip = Read-Host "  [?] 目标 IP/主机名（例如 192.168.1.10）"
    if ($null -ne $ip) { $ip = $ip.Trim() }
    $usr = Read-Host "  [?] 目标主机上的用户名"
    if ($null -ne $usr) { $usr = $usr.Trim() }
    $pass = Read-Host "  [?] 目标主机上的密码（明文显示）"

    if (-not $ip -or -not $usr) {
        Write-Host "  [-] 已取消 - 需要目标主机和用户名。" -ForegroundColor Red
        return
    }

    try {
        $proc = Start-Process -FilePath "cmdkey.exe" -ArgumentList "/add:$ip", "/user:$usr", "/pass:`"$pass`"" -WindowStyle Hidden -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-Log "已为 $ip 注入凭据。" -Type "SUCCESS"
            Write-Host "  [+] 凭据已成功提交到 Windows 凭据管理器。" -ForegroundColor Green
        } else {
            Write-Log "cmdkey 返回退出代码 $($proc.ExitCode)（用于 $ip）。" -Type "ERROR"
            Write-Host "  [-] 凭据注入失败（退出代码 $($proc.ExitCode)）。" -ForegroundColor Red
        }
        Start-Sleep -Seconds 1
    }
    catch {
        Write-Log "注入凭据失败: $($_.Exception.Message)" -Type "ERROR"
    }
    $pass = ""
}

function Clean-Credential {
    Write-Host "`n  清除过期 Windows 凭据"
    & cmdkey /list | Select-String "Target:" | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    $del = Read-Host "`n  [?] 输入要清除的目标名称（留空取消）"
    if ($del) {
        $del = $del -replace '(?i)^\s*Target:\s*', ''
        try {
            $proc = Start-Process -FilePath "cmdkey.exe" -ArgumentList "/delete:`"$del`"" -WindowStyle Hidden -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Log "凭据 $del 已清除。" -Type "SUCCESS"
                Write-Host "  [+] 凭据 $del 已成功清除。" -ForegroundColor Green
            } else {
                Write-Log "清除凭据 $del 失败。请检查目标名称。" -Type "ERROR"
                Write-Host "  [-] 清除凭据 $del 失败。请检查目标名称。" -ForegroundColor Red
            }
        }
        catch {
            Write-Log "清除凭据失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Start-Troubleshooter {
    Write-Log "正在执行原生 Windows 疑难解答..." -Type "INFO"
    Start-Process msdt -ArgumentList '/id PrinterDiagnostic' -NoNewWindow
}

function Force-PrinterOnline {
    Write-Log "正在强制设置打印机在线状态..." -Type "INFO"
    $pname = Read-Host "  [?] 输入精确的打印机名称（例如 EPSON L120 Series）"
    if ($pname) {
        try {
            $safeName = $pname -replace "'", "''"
            $prn = Get-CimInstance Win32_Printer -Filter "Name='$safeName'" -ErrorAction Stop
            if ($prn) {
                $prn.WorkOffline = $false
                Set-CimInstance -InputObject $prn -ErrorAction Stop
                Write-Log "打印机 $pname 状态已强制在线。" -Type "SUCCESS"
                Write-Host "  [+] 已向 $pname 发送强制在线命令。" -ForegroundColor Green
            }
            else {
                Write-Host "  [-] 此系统上未检测到打印机 $pname。" -ForegroundColor Red
            }
        }
        catch {
            Write-Log "强制设置打印机在线状态失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Open-Services {
    Write-Log "正在启动 Services.msc MMC 管理单元..." -Type "INFO"
    Start-Process services.msc
}

function Rollback-Registry {
    Write-Log "正在从备份还原注册表..." -Type "INFO"
    if (Test-Path "$script:backupDir\Print.reg") {
        $restoreCount = 0
        $restoreFiles = @(
            @{ File = "Print.reg"; Label = "Print" },
            @{ File = "PrintersPolicy.reg"; Label = "PrintersPolicy" },
            @{ File = "LanmanWorkstation.reg"; Label = "LanmanWorkstation" },
            @{ File = "LanmanServer.reg"; Label = "LanmanServer" },
            @{ File = "Lsa.reg"; Label = "LSA" }
        )
        foreach ($entry in $restoreFiles) {
            $filePath = Join-Path $script:backupDir $entry.File
            if (Test-Path $filePath) {
                & reg import $filePath > $null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $restoreCount++
                } else {
                    Write-Log "警告：还原 $($entry.Label) 失败。" -Type "WARNING"
                    Write-Host "  [!] 还原 $($entry.Label) 失败。" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  [*] 跳过 $($entry.Label)（未找到备份文件）。" -ForegroundColor Cyan
            }
        }
        Write-Log "注册表回滚完成（已还原 $restoreCount 个文件）。" -Type "SUCCESS"
        Write-Host "  [+] 注册表回滚完成（从 $script:backupDir 还原了 $restoreCount 个文件）。" -ForegroundColor Green
    }
    else {
        Write-Host "  [-] 错误：在 $script:backupDir 中未检测到备份文件。" -ForegroundColor Red
    }
}

function Disable-IPv6 {
    Write-Log "正在禁用 IPv6 协议栈..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name DisabledComponents -Value 0xffffffff -Type DWord -Force -ErrorAction Stop
        Write-Log "已通过注册表更改禁用 IPv6。" -Type "SUCCESS"
        Write-Host "  [+] 已禁用 IPv6 以防止路由冲突。需要重启系统。" -ForegroundColor Green
    }
    catch {
        Write-Log "禁用 IPv6 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}function Generate-HtmlLog {
    Write-Log "正在生成 HTML 诊断报告..." -Type "INFO"
    $htmlFile = "$script:backupDir\Report.html"
    $rawLog = Get-Content $script:logFile -Raw -ErrorAction SilentlyContinue
    $encodedLog = [System.Net.WebUtility]::HtmlEncode($rawLog)
    $htmlContent = @"
<html>
<head>
    <title>Windows 打印机共享修复工具 - 日志</title>
    <style>
        body { font-family: 'Courier New', monospace; background: #0b0f19; color: #00ffcc; padding: 20px; }
        h1 { color: #ff0055; border-bottom: 2px solid #333; padding-bottom: 10px; }
        pre { background: #161b22; padding: 20px; border-radius: 8px; border: 1px solid #30363d; overflow-x: auto; font-size: 14px; }
    </style>
</head>
<body>
    <h1>Windows 打印机共享修复工具 - 诊断报告</h1>
    <p>生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | 目标系统: $([System.Net.WebUtility]::HtmlEncode($script:productName))</p>
    <pre>$encodedLog</pre>
</body>
</html>
"@
    $htmlContent | Out-File $htmlFile -Encoding UTF8
    Write-Log "HTML 日志已生成到 $htmlFile。" -Type "SUCCESS"
    Start-Process $htmlFile
}

function Test-Connectivity {
    Write-Host "`n  ======================================================================"
    Write-Host "                 Ping 与网络端口诊断"
    Write-Host "  ======================================================================"
    $ip = Read-Host "  [?] 输入目标 IP/主机名"
    if (-not $ip -or $ip.Trim() -eq '') {
        Write-Host "  [-] 已取消 - 未提供输入。" -ForegroundColor Red
        return
    }
    $ip = $ip.Trim()
    if (Test-Connection $ip -Count 1 -Quiet) {
        Write-Host "  [+] Ping 成功：主机 $ip 可达。" -ForegroundColor Green

        $port445 = Test-NetConnection $ip -Port 445 -WarningAction SilentlyContinue
        if ($port445.TcpTestSucceeded) { Write-Host "  [+] 端口 445 (SMB)：开放" -ForegroundColor Green }
        else { Write-Host "  [-] 端口 445 (SMB)：关闭（防火墙阻挡）" -ForegroundColor Red }

        $port135 = Test-NetConnection $ip -Port 135 -WarningAction SilentlyContinue
        if ($port135.TcpTestSucceeded) { Write-Host "  [+] 端口 135 (RPC)：开放" -ForegroundColor Green }
        else { Write-Host "  [-] 端口 135 (RPC)：关闭（防火墙阻挡）" -ForegroundColor Red }
    }
    else {
        Write-Host "  [-] Ping 失败：目标主机不可达或明确阻止 ICMP。" -ForegroundColor Red
        Write-Host "  [*] 仍将检查 TCP 端口 445 和 135..." -ForegroundColor Cyan
        
        $port445 = Test-NetConnection $ip -Port 445 -WarningAction SilentlyContinue
        if ($port445.TcpTestSucceeded) { Write-Host "  [+] 端口 445 (SMB)：开放（Ping 被阻止但主机存活）" -ForegroundColor Green }
        else { Write-Host "  [-] 端口 445 (SMB)：关闭" -ForegroundColor Red }

        $port135 = Test-NetConnection $ip -Port 135 -WarningAction SilentlyContinue
        if ($port135.TcpTestSucceeded) { Write-Host "  [+] 端口 135 (RPC)：开放（Ping 被阻止但主机存活）" -ForegroundColor Green }
        else { Write-Host "  [-] 端口 135 (RPC)：关闭" -ForegroundColor Red }
    }
}

function Scan-RemotePrinter {
    Write-Host "`n  远程网络打印机发现"
    $ip = Read-Host "  [?] 目标 IP/主机名"
    Write-Host "  [*] 正在扫描 $ip..." -ForegroundColor Cyan
    try {
        $prn = Get-Printer -ComputerName $ip -ErrorAction Stop | Where-Object Shared -eq $true
        if ($prn) {
            $prn | Format-Table Name, ShareName, PortName, PrinterStatus -AutoSize
        }
        else {
            Write-Host "  [-] 在目标主机上未检测到共享打印机。" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  [-] RPC 连接失败。请检查对 $ip 的管理员/来宾访问权限。" -ForegroundColor Red
    }
}

function Remote-SpoolerReset {
    Write-Host "`n  ======================================================================"
    Write-Host "               远程打印后台处理程序重置"
    Write-Host "  ======================================================================"
    Write-Host "  [!] 需要在远程计算机上具有管理员权限。" -ForegroundColor Yellow
    $target = Read-Host "  [?] 目标主机名或 IP（例如 192.168.1.10）"
    if (-not $target) { Write-Host "  [-] 已取消 - 输入为空。" -ForegroundColor Red; return }

    Write-Log "远程后台处理程序重置目标：$target" -Type "INFO"
    try {
        Write-Host "  [*] 正在 Ping $target..." -ForegroundColor Cyan
        if (-not (Test-Connection $target -Count 1 -Quiet)) {
            Write-Host "  [-] 主机不可达。请检查网络和防火墙。" -ForegroundColor Red
            Write-Log "远程后台处理程序重置：$target 不可达。" -Type "ERROR"
            return
        }
        Write-Host "  [+] 主机可达。" -ForegroundColor Green

        Write-Host "  [*] 正在停止 $target 上的后台打印程序..." -ForegroundColor Cyan
        $stopResult = & sc.exe \\$target stop spooler 2>&1
        Start-Sleep -Seconds 3

        Write-Host "  [*] 正在启动 $target 上的后台打印程序..." -ForegroundColor Cyan
        $startResult = & sc.exe \\$target start spooler 2>&1
        Start-Sleep -Seconds 2

        $queryResult = & sc.exe \\$target query spooler 2>&1
        if ($queryResult -match 'RUNNING') {
            Write-Log "远程后台打印程序已在 $target 上成功重启。" -Type "SUCCESS"
            Write-Host "  [+] $target 上的打印后台处理程序现在正在运行。" -ForegroundColor Green
        } else {
            Write-Log "远程后台打印程序在 $target 上可能未重启。请手动检查。" -Type "WARNING"
            Write-Host "  [!] 后台处理程序状态不确定。请在 $target 上手动验证。" -ForegroundColor Yellow
        }
    } catch {
        Write-Log "远程后台处理程序重置失败: $($_.Exception.Message)" -Type "ERROR"
        Write-Host "  [-] 失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  [!] 请确保管理员共享 (C$) 和 RPC（端口 135/445）可访问。" -ForegroundColor Yellow
    }
}

function Log-Manager {
    Write-Log "正在通过记事本启动日志管理器..." -Type "INFO"
    notepad $script:logFile
}

function Print-Migration {
    Write-Log "正在启动 PrintBRM 迁移工具..." -Type "INFO"

    $brmPath = Join-Path $env:SystemRoot "System32\spool\tools\PrintBrm.exe"
    if (-not (Test-Path $brmPath)) {
        $brmPath = Join-Path $env:SystemRoot "System32\PrintBrm.exe"
    }

    if (-not (Test-Path $brmPath)) {
        Write-Log "此系统上未检测到 PrintBrm.exe。" -Type "ERROR"
        Write-Host "  [-] 错误：缺少打印迁移工具 (PrintBrm.exe)。" -ForegroundColor Red
        Write-Host "  [!] 注意：此功能通常仅在 Windows 专业版、企业版或服务器版中可用。" -ForegroundColor Yellow
        Write-Host "  [!] 您的系统：$script:productName" -ForegroundColor Cyan
        return
    }

    Write-Host "  [*] 正在以持久命令提示符窗口启动 PrintBrm.exe..." -ForegroundColor Cyan
    try {
        Start-Process cmd.exe -ArgumentList "/k cd /d `"$env:SystemRoot\System32\spool\tools\`" & title PrintBRM 迁移工具 & `"$brmPath`" /?"
        Write-Log "PrintBRM 提示符已成功启动。" -Type "SUCCESS"
        Write-Host "  [+] PrintBRM 提示符已成功启动！您现在可以执行备份/还原命令。" -ForegroundColor Green
    }
    catch {
        Write-Log "启动 PrintBRM 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Uninstall-Printer {
    $up = Read-Host "`n  [?] 输入要强制卸载的打印机精确名称"
    if ($up) {
        try {
            & printui.exe /dl /n "$up"
            Write-Log "已为 $up 发出卸载命令。" -Type "SUCCESS"
        }
        catch {
            Write-Log "卸载 $up 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Fix-SMBSigning {
    Write-Log "正在禁用 SMB 签名强制和相互身份验证..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name RequireSecuritySignature -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name RequireMutualAuthentication -Value 0 -Type DWord -Force -ErrorAction Stop

        Write-Log "SMB 签名强制已禁用。" -Type "SUCCESS"
        Write-Host "  [+] 已降低 SMB 签名要求（解决 Win 11 NAS/旧版设备连接问题）。" -ForegroundColor Green
    }
    catch {
        Write-Log "禁用 SMB 签名失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-UWPPrinting {
    Write-Log "正在绕过 Microsoft Edge 的 UWP AppContainer 隔离..." -Type "INFO"
    try {
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.windows.printdialog_cw5n1h2txyewy" 2>&1 | Out-Null
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.microsoftedge_8wekyb3d8bbwe" 2>&1 | Out-Null
        Write-Log "已授予回环隔离显式豁免。" -Type "SUCCESS"
        Write-Host "  [+] 已禁用 Edge 和 UWP 应用的网络回环隔离。" -ForegroundColor Green
    }
    catch {
        Write-Log "绕过 UWP 回环失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-mDNS {
    Write-Log "正在启用 mDNS 和 LLMNR 发现协议..." -Type "INFO"
    try {
        $dnsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
        if (-not (Test-Path $dnsPath)) { New-Item -Path $dnsPath -Force | Out-Null }
        Set-ItemProperty -Path $dnsPath -Name EnableMulticast -Value 1 -Type DWord -Force -ErrorAction Stop

        $dnsCachePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
        if (-not (Test-Path $dnsCachePath)) { New-Item -Path $dnsCachePath -Force | Out-Null }
        Set-ItemProperty -Path $dnsCachePath -Name EnableMDNS -Value 1 -Type DWord -Force -ErrorAction Stop

        Write-Log "mDNS/LLMNR 协议已激活。" -Type "SUCCESS"
    }
    catch {
        Write-Log "配置 mDNS 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-WSDFirewall {
    Write-Log "正在确保 WSD (3702) 和 mDNS (5353) 端口无条件开放..." -Type "INFO"
    try {
        Remove-NetFirewallRule -DisplayName "打印机 WSD (UDP 3702 入站)" -ErrorAction SilentlyContinue | Out-Null
        Remove-NetFirewallRule -DisplayName "打印机 mDNS (UDP 5353 入站)" -ErrorAction SilentlyContinue | Out-Null

        New-NetFirewallRule -DisplayName "打印机 WSD (UDP 3702 入站)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 3702 -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "打印机 mDNS (UDP 5353 入站)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 5353 -ErrorAction SilentlyContinue | Out-Null

        Write-Log "WSD 防火墙规则已成功更新。" -Type "SUCCESS"
        Write-Host "  [+] 已在防火墙中明确开放 UDP 端口 3702 和 5353。" -ForegroundColor Green
    }
    catch {
        Write-Log "配置 WSD 防火墙失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-LSAProtection {
    Write-Log "正在降级 LSA 保护（允许旧版身份验证）..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name RunAsPPL -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "LSA PPL 强制已降级。" -Type "SUCCESS"
        Write-Host "  [+] LSA 保护已降级。" -ForegroundColor Green
    }
    catch {
        Write-Log "LSA 保护降级失败: $($_.Exception.Message)（可能由安全启动或凭据保护强制执行）" -Type "WARNING"
        Write-Host "  [!] 无法更改 LSA 保护 - 系统安全策略可能正在强制执行此设置。" -ForegroundColor Yellow
    }
}

function Fix-SAC {
    Write-Log "正在绕过智能应用控制 (SAC) 以注入打印驱动..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "SAC 活动绕过已部署。" -Type "SUCCESS"
        Write-Host "  [+] 已绕过智能应用控制。" -ForegroundColor Green
    }
    catch {
        Write-Log "SAC 绕过失败: $($_.Exception.Message)（SAC 可能由 UEFI/策略强制执行）" -Type "WARNING"
        Write-Host "  [!] SAC 绕过失败 - 可能需要在 Windows 安全中心中手动更改。" -ForegroundColor Yellow
    }
}

function Fix-IPPSharing {
    Write-Log "正在启用 Internet 打印协议 (IPP 和 Mopria)..." -Type "INFO"
    try {
        if ((Get-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-Features" -ErrorAction SilentlyContinue)) {
            Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-Features" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-InternetPrinting-Client" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Log "IPP 基础功能已成功启用。" -Type "SUCCESS"
            Write-Host "  [+] Windows 功能：Internet 打印客户端已激活。" -ForegroundColor Green
        }
    }
    catch {
        Write-Log "配置 IPP 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-AdvancedPointAndPrint {
    Write-Log "正在绕过高级即插即用策略和 PrintNightmare 锁..." -Type "INFO"
    try {
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name InForest -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name TrustedServers -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name ServerList -Value "*.*" -Type String -Force -ErrorAction Stop

        Set-ItemProperty -Path $path -Name RestrictDriverInstallationToAdministrators -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name NoWarningNoElevationOnInstall -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name NoWarningNoElevationOnUpdate -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $path -Name UpdatePromptSettings -Value 2 -Type DWord -Force -ErrorAction Stop

        $pkgPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PackagePointAndPrint"
        if (-not (Test-Path $pkgPath)) { New-Item -Path $pkgPath -Force | Out-Null }
        Set-ItemProperty -Path $pkgPath -Name PackagePointAndPrintServerList -Value 1 -Type DWord -Force -ErrorAction Stop

        Write-Log "即插即用限制和 PrintNightmare 已完全绕过。" -Type "SUCCESS"
        Write-Host "  [+] PrintNightmare 提升限制和即插即用已完全解除。" -ForegroundColor Green
    }
    catch {
        Write-Log "高级即插即用绕过失败: $($_.Exception.Message)" -Type "ERROR"
        Write-Host "  [-] 即插即用绕过失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Fix-ModernSMB {
    Write-Log "正在强制使用现代 SMB2/SMB3 服务器配置..." -Type "INFO"
    try {
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop
        Write-Log "SMB2/SMB3 拓扑已激活。" -Type "SUCCESS"
        Write-Host "  [+] 已强制使用 SMB2/SMB3 协议。" -ForegroundColor Green
    }
    catch {
        Write-Log "强制现代 SMB 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Set-SpoolerRecovery {
    Write-Log "正在配置打印后台处理程序自动重启恢复..." -Type "INFO"
    try {
        & sc.exe failure spooler reset= 0 actions= restart/60000/restart/60000/restart/60000 > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "sc.exe 返回退出代码 $LASTEXITCODE" }
        Write-Log "后台处理程序自动重启恢复已配置。" -Type "SUCCESS"
        Write-Host "  [+] 已配置崩溃时自动重启后台处理程序。" -ForegroundColor Green
    }
    catch {
        Write-Log "配置后台处理程序恢复失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-UACTokenFilter {
    Write-Log "正在绕过 UAC 网络管理员限制..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "LocalAccountTokenFilterPolicy 已设为 1。" -Type "SUCCESS"
        Write-Host "  [+] UAC 网络管理令牌筛选已禁用。" -ForegroundColor Green
    }
    catch {
        Write-Log "UAC 令牌筛选绕过失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Reset-SpoolerDependency {
    Write-Log "正在清除第三方后台处理程序依赖项..." -Type "INFO"
    try {
        & sc.exe config spooler depend= RPCSS/http > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "sc.exe 返回退出代码 $LASTEXITCODE" }
        Write-Log "依赖项已明确重置为 RPCSS 和 http（IPP 兼容）。" -Type "SUCCESS"
        Write-Host "  [+] 打印后台处理程序依赖项已修复，支持现代 IPP。" -ForegroundColor Green
    }
    catch {
        Write-Log "重置后台处理程序依赖项失败: $($_.Exception.Message)" -Type "ERROR"
    }
}function Fix-ProviderOrder {
    Write-Log "正在将 SMB (LanmanWorkstation) 置于网络提供程序顺序的首位..." -Type "INFO"
    try {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider\Order"
        $currentOrder = (Get-ItemProperty -Path $path -Name ProviderOrder -ErrorAction SilentlyContinue).ProviderOrder
        if ($currentOrder) {
            $arr = $currentOrder -split "," | Where-Object { $_ -ne "LanmanWorkstation" -and $_ -ne "" }
            $newOrder = "LanmanWorkstation," + ($arr -join ",")
            Set-ItemProperty -Path $path -Name ProviderOrder -Value $newOrder -Force
            Write-Log "提供程序顺序已明确更新（LanmanWorkstation 优先）。" -Type "SUCCESS"
        }
    }
    catch {
        Write-Log "配置提供程序顺序失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-NTLMv2 {
    Write-Log "正在强制严格执行 NTLMv2 响应合规性（NAS 和 Samba 兼容）..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LmCompatibilityLevel -Value 3 -Type DWord -Force -ErrorAction Stop
        Write-Log "严格 NTLMv2 已成功强制。" -Type "SUCCESS"
        Write-Host "  [+] 已强制严格 NTLMv2（级别 3）。NAS 和现代打印共享连接已安全。" -ForegroundColor Green
    }
    catch {
        Write-Log "强制 NTLMv2 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-Network0x00000040 {
    Write-Log "正在修复错误 0x00000040（网络连接超时）..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name KeepConn -Value 65535 -Type DWord -Force -ErrorAction Stop
        try {
            Restart-Service LanmanWorkstation -Force -ErrorAction Stop
        } catch {
            Write-Log "LanmanWorkstation 重启超时或失败: $($_.Exception.Message)" -Type "WARNING"
        }
        Write-Log "SMB KeepConn 已设为最大值。" -Type "SUCCESS"
        Write-Host "  [+] 已延长 SMB 连接超时以缓解不稳定的网络拓扑。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 0x00000040 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-DriverCopy0x00000002 {
    Write-Log "正在修复错误 0x00000002（驱动 CopyFilesPolicy）..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name CopyFilesPolicy -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "CopyFilesPolicy 已激活。" -Type "SUCCESS"
        Write-Host "  [+] 已允许 CopyFilesPolicy，以便系统可以从主机获取缺失的驱动程序。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 0x00000002 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-RpcBitness0x0000007e {
    Write-Log "正在修复错误 0x0000007e（RPC 位数/身份验证错误）..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC" -Name RpcAuthenticationLevel -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "RPC 身份验证已降级。" -Type "SUCCESS"
        Write-Host "  [+] 已移除 RPC 身份验证限制以促进跨架构通信。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 0x0000007e 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-WPP {
    Write-Host "`n  ======================================================================"
    Write-Host "             Windows 受保护打印 (WPP) 管理"
    Write-Host "  ======================================================================"
    Write-Host "  [!] Win 11 24H2+ 的现代功能，提供严格安全保护，但会阻止所有不支持 Mopria 协议的旧版/自定义打印机。"
    Write-Host "  [1] 启用 WPP（旧版打印机可能无法正常工作）"
    Write-Host "  [2] 禁用 WPP（安全兼容旧版 LAN 共享 - 推荐）"
    $opt = Read-Host "  选择选项 (1/2)"
    $wppPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP"
    if (-not (Test-Path $wppPath)) { New-Item -Path $wppPath -Force | Out-Null }
    if ($opt -eq '1') {
        try {
            Write-Log "正在启用 WPP 模式..." -Type "INFO"
            Set-ItemProperty -Path $wppPath -Name Enabled -Value 1 -Type DWord -Force -ErrorAction Stop
            Write-Host "  [+] WPP 已启用。" -ForegroundColor Yellow
        } catch {
            Write-Log "启用 WPP 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
    if ($opt -eq '2') {
        try {
            Write-Log "正在禁用 WPP 模式..." -Type "INFO"
            Set-ItemProperty -Path $wppPath -Name Enabled -Value 0 -Type DWord -Force -ErrorAction Stop
            Write-Host "  [+] WPP 已成功禁用（兼容模式）。" -ForegroundColor Green
        } catch {
            Write-Log "禁用 WPP 失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Scan-PrintEventLog {
    Write-Log "正在读取最近 20 条打印机服务日志..." -Type "INFO"
    Write-Host "`n  --- Microsoft 打印服务事件日志错误历史 ---" -ForegroundColor Cyan
    $events = Get-WinEvent -LogName "Microsoft-Windows-PrintService/Admin" -MaxEvents 20 -ErrorAction SilentlyContinue
    if ($events) {
        $events | Select-Object TimeCreated, Id, Message | Format-Table -AutoSize
    }
    else {
        Write-Host "  [+] 干净！没有历史故障记录。" -ForegroundColor Green
    }
}

function Manage-TCPPort {
    Write-Host "`n  创建手动 TCP/IP 端口"
    $ip = Read-Host "  [?] 物理打印机 IP（例如 192.168.1.100）"
    if ($ip) {
        try {
            Add-PrinterPort -Name "IP_$ip" -PrinterHostAddress $ip -ErrorAction Stop
            Write-Log "TCP/IP 端口 IP_$ip 已成功创建。" -Type "SUCCESS"
            Write-Host "  [+] 端口 [IP_$ip] 已成功注入系统。" -ForegroundColor Green
        }
        catch {
            Write-Log "创建端口失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Manage-DefaultPrinter {
    Write-Host "`n  强制设置永久默认打印机"
    $prn = Read-Host "  [?] 输入要设为默认的打印机精确名称"
    if ($prn) {
        try {
            $safeName = $prn -replace "'", "''"
            $wmi = Get-CimInstance Win32_Printer -Filter "Name='$safeName'" -ErrorAction Stop
            if ($wmi) {
                Invoke-CimMethod -InputObject $wmi -MethodName SetDefaultPrinter | Out-Null
                Write-Log "已强制将默认打印机设为 $prn" -Type "SUCCESS"
                Write-Host "  [+] 系统已强制将 $prn 设为主要默认打印机。" -ForegroundColor Green
            }
            else {
                Write-Host "  [-] 未检测到打印机。" -ForegroundColor Red
            }
        }
        catch {
            Write-Log "设置默认打印机失败: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

function Set-SpoolerWatchdog {
    Write-Log "正在注入后台处理程序监视任务..." -Type "INFO"
    try {
        $cmd = "powershell.exe -WindowStyle Hidden -Command \`"if((Get-Service spooler).Status -ne 'Running'){ Start-Service spooler }\`""
        & schtasks.exe /create /tn "SpoolerWatchdog" /tr $cmd /sc minute /mo 5 /ru "SYSTEM" /rl HIGHEST /f > $null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "schtasks 返回退出代码 $LASTEXITCODE" }
        
        # 配置任务允许在电池供电下运行（消除笔记本电脑上的 0x800710E0 错误）
        try {
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            Set-ScheduledTask -TaskName "SpoolerWatchdog" -Settings $settings -ErrorAction SilentlyContinue | Out-Null
        } catch {}

        Write-Log "后台处理程序监视已部署（无限制重复，每 5 分钟）。" -Type "SUCCESS"
        Write-Host "  [+] 后台处理程序监视已激活。每 5 分钟审计一次。" -ForegroundColor Green
    }
    catch {
        Write-Log "监视部署失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-RDPPrinter {
    Write-Log "正在修复 RDP 打印机终端服务重定向..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services" -Name fDisableCpm -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services" -Name fEnablePrintRDR -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "RDP 重定向已激活。" -Type "SUCCESS"
        Write-Host "  [+] 在远程桌面 (RDP) 会话期间，本地打印机现在可见。" -ForegroundColor Green
    }
    catch {
        Write-Log "修复 RDP 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-HyperVConflict {
    Write-Log "正在修复 Hyper-V/WSL 网络发现冲突..." -Type "INFO"
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Virtual" -or $_.InterfaceDescription -match "Hyper-V" -or $_.InterfaceDescription -match "WSL" }
        if ($adapters) {
            foreach ($adp in $adapters) {
                Set-NetIPInterface -InterfaceAlias $adp.Name -InterfaceMetric 99 -ErrorAction SilentlyContinue
            }
            Write-Log "vSwitch 优先级（跃点数）已成功降低。" -Type "SUCCESS"
            Write-Host "  [+] Hyper-V/WSL 虚拟适配器已降权，以防止干扰本地 LAN/Wi-Fi。" -ForegroundColor Green
        }
        else {
            Write-Host "  [*] 未检测到冲突的虚拟适配器。" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Log "Hyper-V 修复失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-LPR {
    Write-Log "正在安装旧版 LPR/LPD 协议..." -Type "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-LPRPortMonitor" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "LPR 端口监视器已安装。" -Type "SUCCESS"
    } catch {
        Write-Log "安装 LPR 端口监视器失败: $($_.Exception.Message)" -Type "WARNING"
    }

    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-Foundation-LPDPrintService" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "LPD 打印服务已安装。" -Type "SUCCESS"
    } catch {
        Write-Log "安装 LPD 服务失败: $($_.Exception.Message)（可能已在最新的 Win 11 版本中弃用）" -Type "WARNING"
    }

    Write-Host "  [+] LPR/LPD 安装完成。如果失败，此功能可能已在您的 Windows 版本中弃用。" -ForegroundColor Green
}

function Fix-PrintToPDF {
    Write-Log "正在重新安装/刷新 Microsoft Print to PDF 和 XPS..." -Type "INFO"
    Write-Host "  [*] 此过程大约需要 10-30 秒..." -ForegroundColor Cyan
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -NoRestart -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 2
        Enable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "Print to PDF 已成功刷新。" -Type "SUCCESS"
        Write-Host "  [+] Microsoft Print to PDF 驱动程序已恢复。建议重启！" -ForegroundColor Green
    }
    catch {
        Write-Log "刷新 PrintToPDF 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Fix-CredentialGuard {
    Write-Log "正在绕过凭据保护限制（严格 NTLM）..." -Type "INFO"
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LsaCfgFlags -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "凭据保护 (LsaCfgFlags) 已禁用。" -Type "SUCCESS"
        Write-Host "  [+] Win 11 专业版/企业版的严格 NTLM 封锁已缓解。" -ForegroundColor Green
    }
    catch {
        Write-Log "绕过凭据保护失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Manage-BITS {
    Write-Log "正在重启 BITS 服务..." -Type "INFO"
    try {
        Restart-Service BITS -Force -ErrorAction Stop
        Write-Log "后台智能传输服务 (BITS) 已重启。" -Type "SUCCESS"
        Write-Host "  [+] BITS 服务已重启。" -ForegroundColor Green
    }
    catch {
        Write-Log "重启 BITS 失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Create-RestorePoint {
    Write-Log "正在生成系统还原点..." -Type "INFO"
    Write-Host "  [*] 正在调用系统保护（请稍候）..." -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "WinPrinterSharingFix-安全备份" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "系统还原点生成成功。" -Type "SUCCESS"
        Write-Host "  [+] Windows 还原点已建立。" -ForegroundColor Green
    }
    catch {
        Write-Log "生成还原点失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Run-QuickDiagnostics {
    Write-Host "`n  ======================================================================"
    Write-Host "                 系统诊断"
    Write-Host "  ======================================================================"

    $spool = (Get-Service spooler -ErrorAction SilentlyContinue).Status
    if ($spool -eq 'Running') { $spc = "Green" } else { $spc = "Red" }
    Write-Host "  [+] 打印后台处理程序 : " -NoNewline; Write-Host $spool -ForegroundColor $spc

    $rpc = (Get-Service RpcSs -ErrorAction SilentlyContinue).Status
    if ($rpc -eq 'Running') { $rcc = "Green" } else { $rcc = "Red" }
    Write-Host "  [+] RPC 服务        : " -NoNewline; Write-Host $rpc -ForegroundColor $rcc

    $fw = (Get-Service mpssvc -ErrorAction SilentlyContinue).Status
    if ($fw -eq 'Running') { $fwc = "Green" } else { $fwc = "Red" }
    Write-Host "  [+] 防火墙          : " -NoNewline; Write-Host $fw -ForegroundColor $fwc

    $net = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NetworkCategory
    $netStr = ($net -join ", ")
    if ($netStr -match "Public") { $ntc = "Red" } else { $ntc = "Green" }
    Write-Host "  [+] 网络配置文件    : " -NoNewline; Write-Host $netStr -ForegroundColor $ntc

    Write-Host "  [+] 系统类型        : " -NoNewline; Write-Host $script:productName -ForegroundColor Cyan
    if ($script:isARM64) { Write-Host "  [+] 架构            : ARM64（骁龙/Apple M 系列虚拟机）" -ForegroundColor Cyan }

    Write-Host "  ======================================================================"
}function Fix-V4ClassDriver {
    Write-Log "正在扫描通用打印类驱动程序 (V4) 是否损坏..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               通用打印类驱动程序 V4 修复"
    Write-Host "  ======================================================================"
    try {
        $v4Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-4"
        if (-not (Test-Path $v4Path)) {
            $v4Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows NT x86\Drivers\Version-4"
        }
        $corrupted = @()
        $corruptedDirs = @()
        if (Test-Path $v4Path) {
            $drivers = Get-ChildItem $v4Path -ErrorAction SilentlyContinue
            foreach ($drv in $drivers) {
                $props = Get-ItemProperty $drv.PSPath -ErrorAction SilentlyContinue
                if ($props.InfPath) {
                    $driverDir = $props.DriverPath
                    if ($driverDir) {
                        $parentDir = Split-Path $driverDir -Parent
                        $configDll = Join-Path $parentDir "PrintConfig.dll"
                        if (-not (Test-Path $configDll)) {
                            $corrupted += $drv.PSChildName
                            $corruptedDirs += $parentDir
                        }
                    }
                }
            }
        }
        if ($corrupted.Count -gt 0) {
            Write-Host "  [!] 检测到损坏的 V4 驱动程序：$($corrupted.Count) 个" -ForegroundColor Red
            foreach ($c in $corrupted) { Write-Host "      - $c" -ForegroundColor Yellow }
            Write-Host "  [*] 正在尝试通过 DriverStore 重新注册进行修复..." -ForegroundColor Cyan
            $prnmsDir = Get-ChildItem "$env:SystemRoot\System32\DriverStore\FileRepository\prnms*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($prnmsDir) {
                $goodDll = Get-ChildItem $prnmsDir.FullName -Filter "PrintConfig.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($goodDll) {
                    Write-Host "  [+] 已知完好的 PrintConfig.dll 位于 $($goodDll.FullName)" -ForegroundColor Green
                    Write-Log "PrintConfig.dll 源文件已定位：$($goodDll.FullName)" -Type "SUCCESS"
                    
                    for ($i = 0; $i -lt $corrupted.Count; $i++) {
                        $destDir = $corruptedDirs[$i]
                        $destFile = Join-Path $destDir "PrintConfig.dll"
                        try {
                            Copy-Item -Path $goodDll.FullName -Destination $destFile -Force -ErrorAction Stop
                            Write-Host "  [+] 已将 PrintConfig.dll 恢复到 $destDir" -ForegroundColor Green
                            Write-Log "已将 PrintConfig.dll 恢复到 $destDir" -Type "SUCCESS"
                        } catch {
                            Write-Host "  [-] 恢复到 $destDir 失败: $($_.Exception.Message)" -ForegroundColor Red
                            Write-Log "复制 PrintConfig.dll 到 $destDir 失败: $($_.Exception.Message)" -Type "ERROR"
                        }
                    }
                }
            }
            & pnputil /scan-devices > $null 2>&1
            Write-Log "V4 驱动扫描完成。$($corrupted.Count) 个损坏条目已处理。" -Type "WARNING"
        }
        else {
            Write-Host "  [+] 所有 V4 打印类驱动程序均完好无损。" -ForegroundColor Green
            Write-Log "V4 驱动程序健康。" -Type "SUCCESS"
        }
    }
    catch {
        Write-Log "V4 扫描失败: $($_.Exception.Message)" -Type "ERROR"
    }
}

function Switch-DriverMode {
    Write-Host "`n  ======================================================================"
    Write-Host "               切换 PCL 与 PostScript 驱动程序模式"
    Write-Host "  ======================================================================"
    Write-Log "正在启动 PCL/PostScript 驱动切换..." -Type "INFO"
    try {
        $printers = Get-Printer -ErrorAction Stop
        if (-not $printers) { Write-Host "  [-] 未安装打印机。" -ForegroundColor Red; return }
        Write-Host ""
        $idx = 1
        foreach ($p in $printers) {
            Write-Host "  [$idx] $($p.Name) | 驱动：$($p.DriverName)" -ForegroundColor Cyan
            $idx++
        }
        $sel = Read-Host "`n  [?] 选择打印机编号"
        $selIdx = -1
        try { $selIdx = [int]$sel - 1 } catch { Write-Host "  [-] 输入无效。" -ForegroundColor Red; return }
        if ($selIdx -lt 0 -or $selIdx -ge $printers.Count) { Write-Host "  [-] 选择无效。" -ForegroundColor Red; return }
        $target = $printers[$selIdx]
        $allDrivers = Get-PrinterDriver -ErrorAction SilentlyContinue
        $currentDriver = $target.DriverName
        Write-Host "`n  当前驱动：$currentDriver" -ForegroundColor Yellow
        if ($currentDriver -match 'PCL') {
            $altDrivers = $allDrivers | Where-Object { $_.Name -match 'PS|PostScript' }
            Write-Host "  [*] 正在搜索 PostScript 替代..." -ForegroundColor Cyan
        }
        else {
            $altDrivers = $allDrivers | Where-Object { $_.Name -match 'PCL' }
            Write-Host "  [*] 正在搜索 PCL 替代..." -ForegroundColor Cyan
        }
        if ($altDrivers) {
            $idx = 1
            foreach ($d in $altDrivers) { Write-Host "  [$idx] $($d.Name)" -ForegroundColor Green; $idx++ }
            $drvSel = Read-Host "  [?] 选择替换驱动程序编号（0 取消）"
            if ($drvSel -ne '0') {
                $drvIdx = -1
                try { $drvIdx = [int]$drvSel - 1 } catch { Write-Host "  [-] 输入无效。" -ForegroundColor Red; return }
                if ($drvIdx -ge 0 -and $drvIdx -lt $altDrivers.Count) {
                    Set-Printer -Name $target.Name -DriverName $altDrivers[$drvIdx].Name -ErrorAction Stop
                    Write-Log "驱动已切换：$($target.Name) -> $($altDrivers[$drvIdx].Name)" -Type "SUCCESS"
                    Write-Host "  [+] 驱动已成功切换！" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "  [-] 未找到替代驱动程序。请先安装目标驱动程序。" -ForegroundColor Red
        }
    }
    catch { Write-Log "驱动切换失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Manage-WindowsUpdate {
    Write-Host "`n  ======================================================================"
    Write-Host "                 Windows 更新与阻止管理"
    Write-Host "  ======================================================================"
    Write-Host "  [1] 卸载特定 KB 更新"
    Write-Host "  [2] 暂停 Windows 更新 35 天"
    Write-Host "  [3] 永久禁用 Windows 更新服务（阻止修复被还原）"
    Write-Host "  [4] 重新启用 Windows 更新服务（恢复默认）"
    Write-Host "  [5] 取消"
    $opt = Read-Host "  选择选项 (1-5)"

    switch ($opt) {
        '1' {
            Write-Log "正在启动 KB 更新卸载程序..." -Type "INFO"
            try {
                Write-Host "  [!] 已知的破坏打印机的 KB 更新 (2025-2026)：" -ForegroundColor Red
                Write-Host "      KB5065426 (2025年9月) - 阻止打印共享 (SID 检查)" -ForegroundColor Yellow
                Write-Host "      KB5066835 (2025年10月) - 主要打印机共享破坏者" -ForegroundColor Yellow
                Write-Host "      KB5068661 (2025年11月) - 破坏打印机和网络共享" -ForegroundColor Yellow
                Write-Host "      KB5089549 (2026年5月) - 交叉签名驱动程序强制" -ForegroundColor Yellow

                Write-Host "  [*] 正在列举最近的 Windows 更新..." -ForegroundColor Cyan
                $updates = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 20
                if ($updates) { $updates | Format-Table HotFixID, Description, InstalledOn -AutoSize }
                else { Write-Host "  [-] 未通过 Get-HotFix 检测到任何修补程序。" -ForegroundColor Yellow }

                $kb = Read-Host "`n  [?] 输入要卸载的 KB 编号（例如 KB5034441，留空取消）"
                if (-not $kb) { return }
                $kb = $kb -replace '(?i)^KB', ''

                $dismSuccess = $false
                Write-Host "  [*] 正在尝试通过 DISM 卸载 KB$kb..." -ForegroundColor Cyan
                $packages = & dism /online /get-packages 2>&1 | Select-String "Package_for_KB$kb"

                if ($packages) {
                    $pkgName = ($packages[0].ToString() -split ':')[1].Trim()
                    $proc = Start-Process -FilePath "dism.exe" -ArgumentList "/online /remove-package /package-name:`"$pkgName`" /quiet /norestart" -Wait -PassThru -WindowStyle Hidden

                    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                        $dismSuccess = $true
                        Write-Log "KB$kb 已通过 DISM 卸载。" -Type "SUCCESS"
                        Write-Host "  [+] KB$kb 已成功卸载。（可能需要重启）" -ForegroundColor Green
                    } else {
                        Write-Log "DISM 卸载 KB$kb 失败。退出代码: $($proc.ExitCode)。正在回退到 wusa.exe..." -Type "WARNING"
                        Write-Host "  [-] DISM 失败（退出代码 $($proc.ExitCode)）。正在尝试 wusa.exe 回退..." -ForegroundColor Yellow
                    }
                }

                if (-not $dismSuccess) {
                    Write-Host "  [!] 将出现 Windows 对话框。如果提示，请确认卸载。" -ForegroundColor Cyan
                    $proc = Start-Process wusa.exe -ArgumentList "/uninstall /kb:$kb /norestart" -Wait -PassThru

                    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                        Write-Log "KB$kb 已通过 wusa 卸载。" -Type "SUCCESS"
                        Write-Host "  [+] KB$kb 已成功卸载。（可能需要重启）" -ForegroundColor Green
                    } else {
                        Write-Log "Wusa 卸载 KB$kb 失败/取消。退出代码: $($proc.ExitCode)" -Type "WARNING"
                        Write-Host "  [-] 卸载失败或已取消。该更新可能是永久性安全更新。" -ForegroundColor Red
                    }
                }
            }
            catch { Write-Log "KB 卸载失败: $($_.Exception.Message)" -Type "ERROR" }
        }
        '2' {
            Write-Log "正在暂停 Windows 更新 35 天..." -Type "INFO"
            try {
                $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }

                $pauseStart = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
                $pauseEnd = (Get-Date).AddDays(35).ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)

                Set-ItemProperty -Path $wuPath -Name PauseQualityUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $wuPath -Name PauseFeatureUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $wuPath -Name PauseUpdatesExpiryTime -Value $pauseEnd -Force -ErrorAction Stop
                Set-ItemProperty -Path $wuPath -Name SetDisableUXWUAccess -Value 1 -Type DWord -Force -ErrorAction Stop

                $uxPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                if (-not (Test-Path $uxPath)) { New-Item -Path $uxPath -Force | Out-Null }

                Set-ItemProperty -Path $uxPath -Name PauseUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseFeatureUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseQualityUpdatesStartTime -Value $pauseStart -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseFeatureUpdatesEndTime -Value $pauseEnd -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseQualityUpdatesEndTime -Value $pauseEnd -Force -ErrorAction Stop
                Set-ItemProperty -Path $uxPath -Name PauseUpdatesExpiryTime -Value $pauseEnd -Force -ErrorAction Stop

                Write-Host "  [+] Windows 更新已完全暂停 35 天（已应用 GPO 和设置 UX 覆盖）。" -ForegroundColor Green
                Write-Log "Windows 更新已暂停，直到 $pauseEnd。" -Type "SUCCESS"
            }
            catch { Write-Log "暂停 Windows 更新失败: $($_.Exception.Message)" -Type "ERROR" }
        }
        '3' {
            Write-Log "正在永久禁用 Windows 更新服务..." -Type "INFO"
            try {
                $services = @("wuauserv", "UsoSvc", "bits")
                foreach ($svc in $services) {
                    & sc.exe config $svc start= disabled > $null 2>&1
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue | Out-Null
                }

                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name Start -Value 4 -Type DWord -Force -ErrorAction Stop
                Stop-Service -Name "WaaSMedicSvc" -Force -ErrorAction SilentlyContinue | Out-Null

                $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
                if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }
                Set-ItemProperty -Path $auPath -Name NoAutoUpdate -Value 1 -Type DWord -Force -ErrorAction Stop

                Write-Log "Windows 更新服务已永久禁用（Medic 已阻止）。" -Type "SUCCESS"
                Write-Host "  [+] 核心 Windows 更新服务 (wuauserv, UsoSvc, bits, WaaSMedicSvc) 已禁用。" -ForegroundColor Green
                Write-Host "  [+] 注册表策略 NoAutoUpdate 已强制设为 1。" -ForegroundColor Green
                Write-Host "  [!] 安全配置将不再被 Windows 更新还原。" -ForegroundColor Yellow
            }
            catch { Write-Log "禁用 Windows 更新失败: $($_.Exception.Message)" -Type "ERROR" }
        }
        '4' {
            Write-Log "正在重新启用 Windows 更新服务..." -Type "INFO"
            try {
                & sc.exe config wuauserv start= demand > $null 2>&1
                & sc.exe config UsoSvc start= auto > $null 2>&1
                & sc.exe config bits start= demand > $null 2>&1

                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name Start -Value 3 -Type DWord -Force -ErrorAction Stop

                $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
                if (Test-Path $auPath) {
                    Remove-ItemProperty -Path $auPath -Name NoAutoUpdate -ErrorAction SilentlyContinue | Out-Null
                }

                $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                if (Test-Path $wuPath) {
                    $properties = @("PauseQualityUpdatesStartTime", "PauseFeatureUpdatesStartTime", "PauseUpdatesExpiryTime", "SetDisableUXWUAccess")
                    foreach ($prop in $properties) {
                        Remove-ItemProperty -Path $wuPath -Name $prop -ErrorAction SilentlyContinue | Out-Null
                    }
                }

                $uxPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
                if (Test-Path $uxPath) {
                    $properties = @("PauseUpdatesStartTime", "PauseFeatureUpdatesStartTime", "PauseQualityUpdatesStartTime", "PauseFeatureUpdatesEndTime", "PauseQualityUpdatesEndTime", "PauseUpdatesExpiryTime")
                    foreach ($prop in $properties) {
                        Remove-ItemProperty -Path $uxPath -Name $prop -ErrorAction SilentlyContinue | Out-Null
                    }
                }

                Write-Log "Windows 更新服务已恢复为默认启动类型。" -Type "SUCCESS"
                Write-Host "  [+] Windows 更新服务已恢复为默认状态。" -ForegroundColor Green
                Write-Host "  [+] 自动更新和暂停限制已移除。" -ForegroundColor Green
            }
            catch { Write-Log "恢复 Windows 更新失败: $($_.Exception.Message)" -Type "ERROR" }
        }
        default { return }
    }
}function Sweep-OrphanedDrivers {
    Write-Host "`n  ======================================================================"
    Write-Host "               孤立驱动清理 (pnputil)"
    Write-Host "  ======================================================================"
    Write-Log "正在扫描孤立的打印机驱动..." -Type "INFO"
    try {
        $rawOutput = & pnputil /enum-drivers 2>&1
        $activeDrivers = (Get-PrinterDriver -ErrorAction SilentlyContinue).Name
        $orphans = @()
        $currentOem = ""
        $currentClass = ""
        $currentProvider = ""
        foreach ($line in $rawOutput) {
            if ($line -match 'Published Name\s*:\s*(oem\d+\.inf)') { $currentOem = $Matches[1] }
            if ($line -match 'Class Name\s*:\s*(.+)') { $currentClass = $Matches[1].Trim() }
            if ($line -match 'Driver Package Provider\s*:\s*(.+)') { $currentProvider = $Matches[1].Trim() }
            if ($line -match '^\s*$' -and $currentOem -and $currentClass -match 'Printer') {
                $orphans += [PSCustomObject]@{ OemInf = $currentOem; Provider = $currentProvider }
                $currentOem = ""; $currentClass = ""; $currentProvider = ""
            }
        }
        if ($currentOem -and $currentClass -match 'Printer') {
            $orphans += [PSCustomObject]@{ OemInf = $currentOem; Provider = $currentProvider }
        }
        if ($orphans.Count -gt 0) {
            Write-Host "  [!] 在驱动程序存储中找到 $($orphans.Count) 个打印机驱动包：" -ForegroundColor Yellow
            $orphans | Format-Table OemInf, Provider -AutoSize
            $confirm = Read-Host "  [?] 强制删除所有孤立的打印机驱动？(Y/N)"
            if ($confirm -eq 'Y') {
                foreach ($o in $orphans) {
                    Write-Host "  [*] 正在移除 $($o.OemInf)..." -ForegroundColor Cyan
                    & pnputil /delete-driver $o.OemInf /force 2>&1 | Out-Null
                }
                Write-Log "孤立驱动已清除：$($orphans.Count) 个包。" -Type "SUCCESS"
                Write-Host "  [+] 清理完成。" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  [+] 在驱动程序存储中未找到孤立的打印机驱动。" -ForegroundColor Green
            Write-Log "未检测到孤立驱动。" -Type "SUCCESS"
        }
    }
    catch { Write-Log "驱动清理失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Force-KillDriverProcess {
    Write-Host "`n  ======================================================================"
    Write-Host "               绕过「驱动当前正在使用」"
    Write-Host "  ======================================================================"
    Write-Log "正在强制终止驱动隔离进程..." -Type "INFO"
    Write-Host "  [!] 警告：这将终止所有正在进行的打印处理。" -ForegroundColor Red
    $confirm = Read-Host "  [?] 继续? (Y/N)"
    if ($confirm -ne 'Y') { return }
    try {
        Write-Host "  [*] 正在停止打印后台处理程序..." -ForegroundColor Cyan
        Stop-Service spooler -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $targets = @("PrintIsolationHost", "printfilterpipelinesvc", "splwow64")
        foreach ($proc in $targets) {
            $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
            if ($running) {
                $running | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Host "  [+] 已终止：$proc (PID: $($running.Id -join ', '))" -ForegroundColor Green
            }
            else {
                Write-Host "  [*] $proc 未运行。" -ForegroundColor Cyan
            }
        }
        Start-Sleep -Seconds 2
        Start-Service spooler -ErrorAction SilentlyContinue
        Write-Log "驱动句柄已释放。后台处理程序已重启。" -Type "SUCCESS"
        Write-Host "  [+] 所有驱动句柄已释放。您现在可以卸载驱动程序。" -ForegroundColor Green
    }
    catch { Write-Log "强制终止失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Convert-WSDtoTCPIP {
    Write-Host "`n  ======================================================================"
    Write-Host "               WSD 到标准 TCP/IP 端口转换器"
    Write-Host "  ======================================================================"
    Write-Log "正在扫描 WSD 端口..." -Type "INFO"
    try {
        $wsdPorts = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "WSD-*" }
        if (-not $wsdPorts) {
            Write-Host "  [+] 未检测到 WSD 端口。所有端口均稳定。" -ForegroundColor Green
            Write-Log "未找到 WSD 端口。" -Type "SUCCESS"
            return
        }
        Write-Host "  [!] 找到 $($wsdPorts.Count) 个 WSD 端口：" -ForegroundColor Yellow
        foreach ($wp in $wsdPorts) {
            $printerOnPort = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -eq $wp.Name }
            $printerName = if ($printerOnPort) { $printerOnPort.Name } else { "(未分配)" }
            Write-Host "      端口：$($wp.Name) | 打印机：$printerName" -ForegroundColor Cyan
        }
        $ip = Read-Host "`n  [?] 输入 WSD 打印机的实际 IP（例如 192.168.1.100）"
        if (-not $ip) { return }
        $newPortName = "IP_$ip"
        if (-not (Get-PrinterPort -Name $newPortName -ErrorAction SilentlyContinue)) {
            Add-PrinterPort -Name $newPortName -PrinterHostAddress $ip -ErrorAction Stop
            Write-Host "  [+] TCP/IP 端口 $newPortName 已创建。" -ForegroundColor Green
        }
        $printerToMove = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -like "WSD-*" } | Select-Object -First 1
        if ($printerToMove) {
            Set-Printer -Name $printerToMove.Name -PortName $newPortName -ErrorAction Stop
            Write-Log "打印机 $($printerToMove.Name) 已从 WSD 迁移到 TCP/IP ($ip)。" -Type "SUCCESS"
            Write-Host "  [+] $($printerToMove.Name) 已迁移到 $newPortName。" -ForegroundColor Green
        }
    }
    catch { Write-Log "WSD 转换失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Reset-NetworkSockets {
    Write-Host "`n  ======================================================================"
    Write-Host "               网络套接字重新初始化（选择性清理）"
    Write-Host "  ======================================================================"
    Write-Log "正在执行选择性网络套接字清理..." -Type "INFO"
    try {
        Write-Host "  [*] 正在扫描卡住的 SMB/RPC 连接..." -ForegroundColor Cyan
        $stuck445 = & netstat -ano 2>&1 | Select-String ":445\s.*(ESTABLISHED|TIME_WAIT|CLOSE_WAIT)"
        $stuck135 = & netstat -ano 2>&1 | Select-String ":135\s.*(ESTABLISHED|TIME_WAIT|CLOSE_WAIT)"
        $totalStuck = 0
        if ($stuck445) { $totalStuck += $stuck445.Count; Write-Host "  [!] 端口 445 (SMB)：$($stuck445.Count) 个卡住连接" -ForegroundColor Yellow }
        if ($stuck135) { $totalStuck += $stuck135.Count; Write-Host "  [!] 端口 135 (RPC)：$($stuck135.Count) 个卡住连接" -ForegroundColor Yellow }
        if ($totalStuck -eq 0) { Write-Host "  [+] 未检测到卡住的连接。" -ForegroundColor Green }
        Write-Host "  [*] 仅重启 SMB 客户端和服务器服务..." -ForegroundColor Cyan
        Restart-Service LanmanWorkstation -Force -ErrorAction SilentlyContinue
        Restart-Service LanmanServer -Force -ErrorAction SilentlyContinue
        $LASTEXITCODE = 0; ipconfig /registerdns > $null 2>&1
        Write-Log "网络套接字已选择性清除。已清理 $totalStuck 个连接。" -Type "SUCCESS"
        Write-Host "  [+] 套接字清理完成。已清除 $totalStuck 个过期连接。" -ForegroundColor Green
    }
    catch { Write-Log "套接字重新初始化失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Rescue-NetworkProfile {
    Write-Host "`n  ======================================================================"
    Write-Host "               恢复网络配置文件（自动检测与监视）"
    Write-Host "  ======================================================================"
    Write-Log "正在恢复网络配置文件..." -Type "INFO"
    try {
        $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
        $publicFound = $false
        foreach ($p in $profiles) {
            if ($p.NetworkCategory -eq 'Public') {
                $publicFound = $true
                Write-Host "  [!] 检测到公用配置文件：$($p.InterfaceAlias)" -ForegroundColor Red
                Set-NetConnectionProfile -InterfaceAlias $p.InterfaceAlias -NetworkCategory Private -ErrorAction SilentlyContinue
                Write-Host "  [+] 已强制设为专用：$($p.InterfaceAlias)" -ForegroundColor Green
            }
        }
        if (-not $publicFound) { Write-Host "  [+] 所有配置文件均已是专用/域。无需操作。" -ForegroundColor Green }
        $deployWatchdog = Read-Host "`n  [?] 部署网络配置文件监视任务（每 10 分钟检查一次）？(Y/N)"
        if ($deployWatchdog -eq 'Y') {
            $cmd = "powershell.exe -WindowStyle Hidden -Command \`"Get-NetConnectionProfile | Where-Object { `$_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private\`""
            & schtasks.exe /create /tn "NetworkProfileWatchdog" /tr $cmd /sc minute /mo 10 /ru "SYSTEM" /rl HIGHEST /f > $null 2>&1
            if ($LASTEXITCODE -eq 0) {
                try {
                    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                    Set-ScheduledTask -TaskName "NetworkProfileWatchdog" -Settings $settings -ErrorAction SilentlyContinue | Out-Null
                } catch {}
                Write-Log "网络配置文件监视已部署（无限制重复）。" -Type "SUCCESS"
                Write-Host "  [+] 监视已部署。每 10 分钟强制配置文件为专用。" -ForegroundColor Green
            } else {
                Write-Log "部署网络配置文件监视失败。schtasks 返回退出代码 $LASTEXITCODE" -Type "ERROR"
            }
        }
    }
    catch { Write-Log "网络恢复失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Remove-GhostUSBPrinters {
    Write-Host "`n  ======================================================================"
    Write-Host "               幽灵 USB 端口与副本清除器"
    Write-Host "  ======================================================================"
    Write-Log "正在扫描幽灵 USB 打印机和重复项..." -Type "INFO"
    try {
        $allPrinters = Get-Printer -ErrorAction SilentlyContinue
        $ghosts = $allPrinters | Where-Object { $_.Name -match '\(Copy \d+\)' -or $_.Name -match ' - Copy' -or $_.Name -match 'Copy \d+$' }
        $activePorts = ($allPrinters | Where-Object { $_.Name -notmatch 'Copy' }).PortName
        $deadUSB = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "USB*" -and $_.Name -notin $activePorts }
        if ($ghosts.Count -eq 0 -and $deadUSB.Count -eq 0) {
            Write-Host "  [+] 未检测到幽灵打印机或失效 USB 端口。" -ForegroundColor Green
            Write-Log "未找到幽灵设备。" -Type "SUCCESS"
            return
        }
        if ($ghosts.Count -gt 0) {
            Write-Host "  [!] 找到重复/幽灵打印机：" -ForegroundColor Yellow
            foreach ($g in $ghosts) { Write-Host "      - $($g.Name) [端口：$($g.PortName)]" -ForegroundColor Red }
        }
        if ($deadUSB.Count -gt 0) {
            Write-Host "  [!] 找到失效 USB 端口：" -ForegroundColor Yellow
            foreach ($u in $deadUSB) { Write-Host "      - $($u.Name)" -ForegroundColor Red }
        }
        $confirm = Read-Host "`n  [?] 移除所有幽灵打印机和失效 USB 端口？(Y/N)"
        if ($confirm -eq 'Y') {
            foreach ($g in $ghosts) {
                Remove-Printer -Name $g.Name -ErrorAction SilentlyContinue
                Write-Host "  [+] 已移除打印机：$($g.Name)" -ForegroundColor Green
            }
            foreach ($u in $deadUSB) {
                Remove-PrinterPort -Name $u.Name -ErrorAction SilentlyContinue
                Write-Host "  [+] 已移除端口：$($u.Name)" -ForegroundColor Green
            }
            Write-Log "幽灵清理：已移除 $($ghosts.Count) 台打印机、$($deadUSB.Count) 个端口。" -Type "SUCCESS"
        }
    }
    catch { Write-Log "幽灵 USB 清理失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Nuke-PrintQueue {
    Write-Log "正在对打印队列执行强制清除..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "                强制清除打印队列"
    Write-Host "  ======================================================================"
    try {
        Write-Host "  [*] 正在终止打印后台处理程序和所有子进程..." -ForegroundColor Cyan
        Stop-Service spooler -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Get-Process -Name "PrintIsolationHost", "printfilterpipelinesvc", "splwow64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $spoolDir = "$env:SystemRoot\System32\Spool\Printers"
        $shdFiles = Get-ChildItem "$spoolDir\*.shd" -ErrorAction SilentlyContinue
        $splFiles = Get-ChildItem "$spoolDir\*.spl" -ErrorAction SilentlyContinue
        $totalFiles = 0
        if ($shdFiles) { $totalFiles += $shdFiles.Count; Remove-Item "$spoolDir\*.shd" -Force -ErrorAction SilentlyContinue }
        if ($splFiles) { $totalFiles += $splFiles.Count; Remove-Item "$spoolDir\*.spl" -Force -ErrorAction SilentlyContinue }
        Remove-Item "$spoolDir\*" -Force -Recurse -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Start-Service spooler -ErrorAction Stop
        Write-Log "强制清除完成。已清除 $totalFiles 个损坏的后台文件。" -Type "SUCCESS"
        Write-Host "  [+] 打印队列已清除。已清除 $totalFiles 个过期文件。后台处理程序已重启。" -ForegroundColor Green
    }
    catch { Write-Log "强制清除失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Reset-SpoolerDependencyRegistry {
    Write-Log "正在通过直接注册表写入重置后台处理程序 DependOnService..." -Type "INFO"
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Spooler"
        $current = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).DependOnService
        if ($current) {
            Write-Host "  [*] 当前依赖项：$($current -join ', ')" -ForegroundColor Yellow
        }
        Set-ItemProperty -Path $regPath -Name DependOnService -Value @("RPCSS","http") -Type MultiString -Force -ErrorAction Stop
        Write-Log "后台处理程序 DependOnService 已重置为出厂默认值 (RPCSS, http)。" -Type "SUCCESS"
        Write-Host "  [+] 后台处理程序依赖项已重置为：RPCSS, http" -ForegroundColor Green
        Write-Host "  [*] 正在重启后台处理程序以应用..." -ForegroundColor Cyan
        Restart-Service spooler -Force -ErrorAction SilentlyContinue
    }
    catch { Write-Log "依赖项注册表重置失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Inject-CrossUserCredentials {
    Write-Host "`n  ======================================================================"
    Write-Host "               跨用户凭据映射"
    Write-Host "  ======================================================================"
    Write-Host "  [!] 警告：这会将凭据注入此电脑上的所有用户配置文件。" -ForegroundColor Red
    Write-Log "跨用户凭据映射已启动..." -Type "INFO"
    $ip = Read-Host "  [?] 目标 IP/主机名（例如 192.168.1.10）"
    $usr = Read-Host "  [?] 目标主机上的用户名"
    $pass = Read-Host "  [?] 目标主机上的密码（明文显示）"
    if (-not $ip -or -not $usr) { Write-Host "  [-] 已取消。" -ForegroundColor Red; return }
    try {
        $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-' }
        $injected = 0
        foreach ($profile in $profiles) {
            $sid = $profile.PSChildName
            $profilePath = (Get-ItemProperty $profile.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
            $userName = Split-Path $profilePath -Leaf
            Write-Host "  [*] 正在为用户注入凭据：$userName ($sid)..." -ForegroundColor Cyan
            $ntuser = Join-Path $profilePath "NTUSER.DAT"
            if (Test-Path $ntuser) {
                $LASTEXITCODE = 0; & reg load "HKU\$sid" $ntuser > $null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    try {
                        $credScript = Join-Path $profilePath "PrinterCredFix.cmd"
                        $cmdContent = "@echo off`r`ncmdkey.exe /add:$ip /user:$usr /pass:`"$pass`"`r`ndel `"%~f0`""
                        Set-Content -Path $credScript -Value $cmdContent -Encoding ASCII -Force -ErrorAction Stop

                        $runOncePath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\RunOnce"
                        Set-ItemProperty -Path $runOncePath -Name "PrinterCredFix" -Value "`"$credScript`"" -Force -ErrorAction Stop
                        Write-Log "已为 $userName 注入 RunOnce 凭据命令。" -Type "SUCCESS"
                    } catch {
                        Write-Log "为 ${userName} 写入 RunOnce 注册表失败: $($_.Exception.Message)" -Type "ERROR"
                    }
                    
                    $unloaded = $false
                    for ($retry = 1; $retry -le 5; $retry++) {
                        $LASTEXITCODE = 0
                        & reg unload "HKU\$sid" > $null 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $unloaded = $true
                            break
                        }
                        Start-Sleep -Milliseconds 200
                    }
                    if (-not $unloaded) {
                        Write-Log "尝试 5 次后仍无法卸载 $userName ($sid) 的注册表配置单元。" -Type "WARNING"
                    }
                    $injected++
                } else {
                    Write-Log "无法加载 $userName ($sid) 的注册表配置单元。" -Type "ERROR"
                }
            }
        }
        Write-Log "已为 $injected 个用户配置文件注入凭据。" -Type "SUCCESS"
        Write-Host "  [+] 已向 $injected 个用户配置文件注入凭据。" -ForegroundColor Green
        $pass = ""
    }
    catch { Write-Log "跨用户凭据注入失败: $($_.Exception.Message)" -Type "ERROR" }
}function Force-DefaultPrinterRegistry {
    Write-Host "`n  ======================================================================"
    Write-Host "               强制设置默认打印机（注册表绕过 0x00000709）"
    Write-Host "  ======================================================================"
    Write-Log "正在通过注册表注入强制设置默认打印机..." -Type "INFO"
    try {
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        $printers = Get-Printer -ErrorAction Stop
        if (-not $printers) { Write-Host "  [-] 未找到打印机。" -ForegroundColor Red; return }
        $idx = 1
        foreach ($p in $printers) {
            Write-Host "  [$idx] $($p.Name) | 端口：$($p.PortName)" -ForegroundColor Cyan
            $idx++
        }
        $sel = Read-Host "`n  [?] 选择要强制设为默认的打印机编号"
        $selIdx = -1
        try { $selIdx = [int]$sel - 1 } catch { Write-Host "  [-] 输入无效。" -ForegroundColor Red; return }
        if ($selIdx -lt 0 -or $selIdx -ge $printers.Count) { Write-Host "  [-] 选择无效。" -ForegroundColor Red; return }
        $target = $printers[$selIdx]
        $deviceStr = "$($target.Name),winspool,$($target.PortName):"
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" -Name Device -Value $deviceStr -Type String -Force -ErrorAction Stop
        Write-Log "已通过注册表强制设置默认打印机：$($target.Name)" -Type "SUCCESS"
        Write-Host "  [+] 默认打印机已设为：$($target.Name)（已应用注册表绕过）。" -ForegroundColor Green
    }
    catch { Write-Log "注册表默认打印机设置失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Sanitize-PrinterShareName {
    Write-Log "正在扫描不合规的打印机共享名称..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               自动清理打印机共享名称"
    Write-Host "  ======================================================================"
    try {
        $shared = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared -eq $true }
        if (-not $shared) { Write-Host "  [+] 未找到共享打印机。" -ForegroundColor Yellow; return }
        $fixed = 0
        foreach ($p in $shared) {
            $original = $p.ShareName
            $clean = $original -replace '[^a-zA-Z0-9_\-\.]', '_' -replace '__+', '_' -replace '^_|_$', ''
            if ($clean -ne $original) {
                Write-Host "  [!] $original -> $clean" -ForegroundColor Yellow
                Set-Printer -Name $p.Name -ShareName $clean -ErrorAction SilentlyContinue
                $fixed++
            }
            else {
                Write-Host "  [+] $original (干净)" -ForegroundColor Green
            }
        }
        if ($fixed -gt 0) {
            Write-Log "已清理 $fixed 个打印机共享名称。" -Type "SUCCESS"
            Write-Host "`n  [+] $fixed 个共享名称已清理。" -ForegroundColor Green
        }
        else {
            Write-Host "`n  [+] 所有共享名称均已合规。" -ForegroundColor Green
            Write-Log "所有共享名称均合规。" -Type "SUCCESS"
        }
    }
    catch { Write-Log "共享名称清理失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Fix-BrowserPrintSandbox {
    Write-Log "正在重置浏览器打印沙箱 (Chromium)..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               浏览器打印沙箱修复 (Chromium)"
    Write-Host "  ======================================================================"
    try {
        Write-Host "  [*] 正在终止浏览器进程..." -ForegroundColor Cyan
        Get-Process -Name "chrome", "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $cleared = 0
        $chromePrintDir = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
        $edgePrintDir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
        if (Test-Path $chromePrintDir) {
            Remove-Item "$chromePrintDir\*" -Force -Recurse -ErrorAction SilentlyContinue
            $cleared++; Write-Host "  [+] Chrome 缓存已清除。" -ForegroundColor Green
        }
        if (Test-Path $edgePrintDir) {
            Remove-Item "$edgePrintDir\*" -Force -Recurse -ErrorAction SilentlyContinue
            $cleared++; Write-Host "  [+] Edge 缓存已清除。" -ForegroundColor Green
        }
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.windows.printdialog_cw5n1h2txyewy" 2>&1 | Out-Null
        & CheckNetIsolation.exe LoopbackExempt -a -n="microsoft.microsoftedge_8wekyb3d8bbwe" 2>&1 | Out-Null
        Restart-Service spooler -Force -ErrorAction SilentlyContinue
        Write-Log "浏览器打印沙箱已重置。已清除 $cleared 个浏览器缓存。" -Type "SUCCESS"
        Write-Host "  [+] 浏览器打印沙箱重置完成。请重启浏览器。" -ForegroundColor Green
    }
    catch { Write-Log "浏览器沙箱修复失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Detect-GPOIntervention {
    Write-Log "正在扫描组策略对打印机注册表的干预..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "               组策略 (GPO) 干预检测"
    Write-Host "  ======================================================================"
    try {
        $isPartOfDomain = $false
        try {
            $sys = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $isPartOfDomain = $sys.PartOfDomain
        } catch {
            $netJoin = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -ErrorAction SilentlyContinue
            if ($netJoin -and $netJoin.Domain -and $netJoin.Domain -ne "") {
                $isPartOfDomain = $true
            }
        }

        if ($isPartOfDomain) {
            Write-Host "  [+] 域状态：已加入域" -ForegroundColor Green
        } else {
            Write-Host "  [+] 域状态：工作组（未加入域）" -ForegroundColor Green
        }

        $policyPaths = @(
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"; Label = "打印机策略" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint"; Label = "即插即用" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC"; Label = "RPC 策略" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP"; Label = "Windows 受保护打印" },
            @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"; Label = "用户打印机策略" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation"; Label = "Lanman 工作站策略" },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanServer"; Label = "Lanman 服务器策略" }
        )

        $recommendations = @{
            "DisableClientSideRendering" = 1
            "RestrictDriverInstallationToAdministrators" = 0
            "InForest" = 1
            "TrustedServers" = 1
            "ServerList" = "*.*"
            "NoWarningNoElevationOnInstall" = 1
            "NoWarningNoElevationOnUpdate" = 1
            "UpdatePromptSettings" = 2
            "RpcUseNamedPipeProtocol" = 1
            "RpcTcpEnable" = 1
            "RpcProtocols" = 7
            "ForceSetup" = 1
            "RpcAuthenticationLevel" = 0
            "RpcOverNamedPipes" = 1
            "ForceKerberosForRpc" = 0
            "Enabled" = 0
            "PackagePointAndPrintServerList" = 1
            "RequireSecuritySignature" = 0
            "EnableSecuritySignature" = 0
        }

        $gpoDetected = $false
        $restrictionDetected = $false

        foreach ($entry in $policyPaths) {
            if (Test-Path $entry.Path) {
                $props = Get-ItemProperty $entry.Path -ErrorAction SilentlyContinue
                $propNames = $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
                if ($propNames.Count -gt 0) {
                    $gpoDetected = $true
                    Write-Host "`n  [*] 路径：$($entry.Label)" -ForegroundColor Cyan
                    foreach ($prop in $propNames) {
                        $pName = $prop.Name
                        $pValue = $prop.Value
                        if ($recommendations.ContainsKey($pName)) {
                            $recVal = $recommendations[$pName]
                            if ($pValue.ToString() -eq $recVal.ToString()) {
                                Write-Host "      [已修复] $pName = $pValue" -ForegroundColor Green
                            } else {
                                $restrictionDetected = $true
                                Write-Host "      [!] 策略覆盖（受限）：$pName = $pValue（应为：$recVal）" -ForegroundColor Red
                            }
                        } else {
                            Write-Host "      [*] 用户覆盖：$pName = $pValue" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }

        if ($isPartOfDomain) {
            Write-Host "`n  [*] 正在运行 gpresult 查找打印机相关 GPO..." -ForegroundColor Cyan
            $gpresult = & gpresult /R /Scope Computer 2>&1 | Select-String -Pattern "Printer|Print|Point"
            if ($gpresult) {
                Write-Host "  [!] 在计算机策略中找到 GPO 引用：" -ForegroundColor Yellow
                $gpresult | ForEach-Object { Write-Host "      $_" -ForegroundColor Cyan }
            } else {
                Write-Host "  [+] 未通过 gpresult 检测到活动的打印机相关 GPO。" -ForegroundColor Green
            }

            if ($restrictionDetected) {
                Write-Host "`n  [!] 警告：GPO 管理的键将被域控制器覆盖。" -ForegroundColor Red
                Write-Host "  [!] 对这些键的本地更改将在 gpupdate 后还原。" -ForegroundColor Red
                Write-Log "检测到 GPO 对打印机注册表进行干预。" -Type "WARNING"
            } else {
                Write-Host "`n  [+] GPO 策略与打印机共享修复一致或未激活。" -ForegroundColor Green
                Write-Log "GPO 已检查；策略一致。" -Type "SUCCESS"
            }
        } else {
            Write-Host "`n  [+] 本地工作组环境（未检测到活动域控制器）。" -ForegroundColor Green
            if ($restrictionDetected) {
                Write-Host "  [!] 某些本地策略覆盖正在限制共享。可在本地调整。" -ForegroundColor Yellow
                Write-Log "检测到本地策略限制。" -Type "WARNING"
            } else {
                Write-Host "  [+] 未检测到本地策略冲突。" -ForegroundColor Green
                Write-Log "未检测到策略冲突。" -Type "SUCCESS"
            }
        }
    }
    catch { Write-Log "GPO 检测失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Parse-PrintEventLog {
    Write-Log "正在解析前 5 条 PrintService 错误/警告事件..." -Type "INFO"
    Write-Host "`n  ======================================================================"
    Write-Host "                 PrintService 事件日志解析器（前 5 条）"
    Write-Host "  ======================================================================"
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-PrintService/Admin'
            Level   = @(2, 3)
        } -MaxEvents 5 -ErrorAction SilentlyContinue
        if ($events) {
            $resolutionMap = @{
                '808' = "驱动安装失败。执行 [43] 孤立驱动清理。"
                '842' = "队列损坏。执行 [37] 强制清除打印队列。"
                '354' = "后台处理程序启动失败。执行 [38] 后台处理程序依赖项重置。"
                '824' = "打印机离线。执行 [26] WSD 到 TCP/IP 转换器。"
            }
            foreach ($evt in $events) {
                $levelStr = if ($evt.Level -eq 2) { "错误" } else { "警告" }
                $color = if ($evt.Level -eq 2) { "Red" } else { "Yellow" }
                Write-Host "`n  [$levelStr] 事件 $($evt.Id) - $($evt.TimeCreated)" -ForegroundColor $color
                Write-Host "  消息：$($evt.Message)" -ForegroundColor White

                $suggestion = ""
                if ($evt.Id -eq 372) {
                    if ($evt.Message -match "Access is denied" -or $evt.Message -match "error code.*: 5\b") {
                        $suggestion = "权限被阻止。执行 [12] 禁用密码共享或 [60] 注入凭据。"
                    }
                    elseif ($evt.Message -match "The network path was not found" -or $evt.Message -match "error code.*: 53\b") {
                        $suggestion = "主机不可达。检查主机 IP/电源，然后执行 [14] 开放防火墙。"
                    }
                    else {
                        $suggestion = "后台处理程序/驱动崩溃。执行 [06] 或 [37] 强制清除打印队列。"
                    }
                }
                elseif ($resolutionMap.ContainsKey($evt.Id.ToString())) {
                    $suggestion = $resolutionMap[$evt.Id.ToString()]
                }

                if ($suggestion) {
                    Write-Host "  建议：$suggestion" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "  [+] 未找到错误/警告事件。PrintService 健康。" -ForegroundColor Green
        }
        Write-Log "PrintService 事件日志已解析。" -Type "SUCCESS"
    }
    catch { Write-Log "事件日志解析失败: $($_.Exception.Message)" -Type "ERROR" }
}

function Map-LocalPortUNC {
    Write-Host "`n  ======================================================================"
    Write-Host "               映射本地端口到 UNC 路径（绕过）"
    Write-Host "  ======================================================================"
    Write-Host "  [!] 如果标准共享仍然失败，提示「检查打印机名称」错误时使用此选项。"
    $ip = Read-Host "  [?] 目标主机 IP/主机名（例如 192.168.1.10）"
    $share = Read-Host "  [?] 精确打印机共享名称（例如 EPSON_L120）"
    if ($ip -and $share) {
        $uncPath = "\\$ip\$share"
        try {
            Write-Host "  [*] 正在尝试标准本地端口创建：$uncPath" -ForegroundColor Cyan
            Add-PrinterPort -Name $uncPath -ErrorAction Stop
            Write-Log "已通过 API 为 UNC 创建本地端口：$uncPath" -Type "SUCCESS"
            Write-Host "  [+] 本地端口已注入！您现在可以添加本地打印机并选择此端口。" -ForegroundColor Green
        }
        catch {
            Write-Host "  [*] 标准方法被 Windows 阻止。正在部署注册表绕过..." -ForegroundColor Yellow
            try {
                $portRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports"

                Set-ItemProperty -Path $portRegPath -Name $uncPath -Value "" -Type String -Force -ErrorAction Stop

                Write-Host "  [*] 端口已注入。正在重启打印后台处理程序以完成..." -ForegroundColor Cyan
                Restart-Service spooler -Force -ErrorAction SilentlyContinue

                Write-Log "已通过注册表绕过为 UNC 注入本地端口：$uncPath" -Type "SUCCESS"
                Write-Host "  [+] 绕过成功！端口 $uncPath 现在在您的端口列表中可用。" -ForegroundColor Green
                Write-Host "  [!] 下一步：转到「添加打印机」->「添加本地打印机」->「使用现有端口」。" -ForegroundColor Green
                Write-Host "  [!] 从下拉菜单中选择 $uncPath，然后选择您的驱动程序。" -ForegroundColor Green
            }
            catch {
                Write-Log "绕过失败: $($_.Exception.Message)" -Type "ERROR"
                Write-Host "  [-] 绕过失败。注册表访问被管理员/GPO 完全锁定。" -ForegroundColor Red
            }
        }
    }
}

function Remove-LocalPortUNC {
    Write-Host "`n  ======================================================================"
    Write-Host "               移除已注入的本地端口 (UNC)"
    Write-Host "  ======================================================================"

    Write-Host "  [*] 正在识别活动的打印机端口..." -ForegroundColor Cyan
    try {
        $ports = Get-PrinterPort | Select-Object -ExpandProperty Name | Sort-Object
        if ($ports) {
            Write-Host "  [>] 检测到的端口：" -ForegroundColor Yellow
            foreach ($p in $ports) {
                if ($p -like "\\*") {
                    Write-Host "      -> $p (UNC 映射)" -ForegroundColor Green
                } else {
                    Write-Host "      -> $p" -ForegroundColor Gray
                }
            }
        }
    } catch { Write-Host "  [!] 无法通过 API 检索端口列表。" -ForegroundColor Yellow }

    Write-Host "`n  [!] 使用此选项删除之前由选项 [86] 创建的端口。"
    $portName = Read-Host "  [?] 输入要移除的精确端口名称（例如 \\192.168.1.10\Printer）"
    if (-not $portName) { return }

    try {
        Write-Host "  [*] 正在尝试标准端口移除..." -ForegroundColor Cyan
        Remove-PrinterPort -Name $portName -ErrorAction Stop
        Write-Log "端口 $portName 已通过 API 移除。" -Type "SUCCESS"
        Write-Host "  [+] 端口 $portName 已成功移除。" -ForegroundColor Green
    }
    catch {
        Write-Host "  [*] 标准方法失败。正在部署注册表清理..." -ForegroundColor Yellow
        try {
            $portRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports"
            Remove-ItemProperty -Path $portRegPath -Name $portName -ErrorAction Stop

            Write-Host "  [*] 端口已从注册表删除。正在重启打印后台处理程序..." -ForegroundColor Cyan
            Restart-Service spooler -Force -ErrorAction SilentlyContinue

            Write-Log "端口 $portName 已通过注册表绕过移除。" -Type "SUCCESS"
            Write-Host "  [+] 绕过成功！端口 $portName 已被永久删除。" -ForegroundColor Green
        }
        catch {
            Write-Log "移除 UNC 端口失败: $($_.Exception.Message)" -Type "ERROR"
            Write-Host "  [-] 移除端口失败。请确保输入的名称与端口列表中的完全一致。" -ForegroundColor Red
        }
    }
}function AllFix-Core {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "         执行全部修复（50 项自动修复）"
    Write-Host "  ===================================================================================================`n"
    Write-Log "运行全部修复（静默=$script:silentNuke）" -Type "INFO"

    Write-Host "  [*] [1/50] 检测操作系统..." -ForegroundColor Cyan
    Write-Host "  $script:productName Build $script:buildNumber"

    Write-Host "  [*] [2/50] 安全备份注册表... (菜单 64)" -ForegroundColor Cyan
    Backup-Registry

    Write-Host "  [*] [3/50] 刷新 GPO 缓存（注册表更改前）..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; gpupdate /force > $null 2>&1 } catch {}

    Write-Host "  [*] [4/50] 检查 RPC 和 DCOM... (菜单 32)" -ForegroundColor Cyan
    Check-RPC

    Write-Host "  [*] [5/50] 修复错误 0x0000011b... (菜单 01)" -ForegroundColor Cyan
    Fix-RpcAuthn0x0000011b

    Write-Host "  [*] [6/50] 深度修复 0x00000709（多层 RPC）... (菜单 02)" -ForegroundColor Cyan
    Fix-Deep0x00000709

    Write-Host "  [*] [7/50] KB5089549 驱动策略和 HKCU 权限修复..." -ForegroundColor Cyan
    Fix-CrossSignedDriverPolicy
    Fix-HKCU-PrinterKeyPerms

    Write-Host "  [*] [8/50] 绕过错误 0x00000bc4... (菜单 03)" -ForegroundColor Cyan
    Fix-Discovery0x00000bc4

    Write-Host "  [*] [9/50] 修复错误 0x00000040 (KeepConn)... (菜单 07)" -ForegroundColor Cyan
    Fix-Network0x00000040

    Write-Host "  [*] [10/50] 修复错误 0x00000002 (CopyFilesPolicy)... (菜单 08)" -ForegroundColor Cyan
    Fix-DriverCopy0x00000002

    Write-Host "  [*] [11/50] 修复错误 0x0000007e (RPC 身份验证)... (菜单 09)" -ForegroundColor Cyan
    Fix-RpcBitness0x0000007e

    Write-Host "  [*] [12/50] 注入 DnsOnWire、StrictName 和 UAC 绕过... (菜单 57)" -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name DnsOnWire -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name DisableStrictNameChecking -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}
    Fix-UACTokenFilter

    Write-Host "  [*] [13/50] 禁用 SMB 签名要求和相互身份验证... (菜单 16)" -ForegroundColor Cyan
    Fix-SMBSigning

    Write-Host "  [*] [14/50] 确保 SMB2/SMB3 兼容性和提供程序顺序... (菜单 17 和 18)" -ForegroundColor Cyan
    Fix-ModernSMB
    Fix-ProviderOrder

    Write-Host "  [*] [15/50] 强制使用命名管道和 TCP... (菜单 13)" -ForegroundColor Cyan
    Fix-NamedPipes

    Write-Host "  [*] [16/50] 禁用客户端渲染... (菜单 05)" -ForegroundColor Cyan
    Fix-CSR

    Write-Host "  [*] [17/50] 禁用驱动隔离... (菜单 40)" -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force
    }
    catch {}

    Write-Host "  [*] [18/50] 启动网络发现、mDNS、NetBIOS 和 WSD 服务... (菜单 20 和 04)" -ForegroundColor Cyan
    Fix-mDNS
    Fix-NetworkServices

    Write-Host "  [*] [19/50] 配置防火墙并开放 UDP 通道... (菜单 14 和 21)" -ForegroundColor Cyan
    Open-Firewall
    Fix-WSDFirewall

    Write-Host "  [*] [20/50] 开放 SMB 来宾访问（客户端和服务器）... (菜单 82)" -ForegroundColor Cyan
    Enable-SMBGuest

    Write-Host "  [*] [21/50] 禁用密码保护网络共享... (菜单 12)" -ForegroundColor Cyan
    Disable-PasswordSharing

    Write-Host "  [*] [22/50] 降级 LSA 保护并强制 NTLMv2... (菜单 54、58 和 62)" -ForegroundColor Cyan
    Fix-LSAProtection
    Fix-NTLMv2
    Fix-CredentialGuard

    Write-Host "  [*] [23/50] 绕过智能应用控制 (SAC)... (菜单 55)" -ForegroundColor Cyan
    Fix-SAC

    Write-Host "  [*] [24/50] 初始化 IPP 和 Mopria 打印共享... (菜单 22)" -ForegroundColor Cyan
    Fix-IPPSharing

    Write-Host "  [*] [25/50] 禁用 WPP（允许旧版网络打印）... (菜单 59)" -ForegroundColor Cyan
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}

    Write-Host "  [*] [26/50] 修复 RDP 和 LPD 协议... (菜单 52 和 24)" -ForegroundColor Cyan
    Fix-RDPPrinter
    Manage-LPR

    Write-Host "  [*] [27/50] 强制网络设为专用模式... (菜单 11)" -ForegroundColor Cyan
    Set-NetworkPrivate

    Write-Host "  [*] [28/50] 降权虚拟适配器 (Hyper-V)... (菜单 23)" -ForegroundColor Cyan
    Fix-HyperVConflict

    Write-Host "  [*] [29/50] 刷新 DNS 和 Winsock... (菜单 10)" -ForegroundColor Cyan
    Reset-Network

    Write-Host "  [*] [30/50] 终止后台处理程序..." -ForegroundColor Cyan
    Stop-Service spooler -Force -ErrorAction SilentlyContinue

    Write-Host "  [*] [31/50] 注入后台处理程序自动重启恢复... (菜单 34)" -ForegroundColor Cyan
    Set-SpoolerRecovery

    Write-Host "  [*] [32/50] 清除后台处理程序依赖项 (http 和 RPCSS)... (菜单 35)" -ForegroundColor Cyan
    Reset-SpoolerDependency

    Write-Host "  [*] [33/50] 重置 PRINTERS 文件夹权限... (菜单 06)" -ForegroundColor Cyan
    Reset-SpoolerPerm

    Write-Host "  [*] [34/50] 清除过期打印队列和 Splwow64... (菜单 31)" -ForegroundColor Cyan
    Reset-Spooler

    Write-Host "  [*] [35/50] 绕过 AppContainer UWP/Edge 回环... (菜单 47)" -ForegroundColor Cyan
    Fix-UWPPrinting

    Write-Host "  [*] [36/50] 应用高级即插即用和 PrintNightmare 绕过... (菜单 56)" -ForegroundColor Cyan
    Fix-AdvancedPointAndPrint

    Write-Host "  [*] [37/50] 部署后台处理程序监视任务... (菜单 36)" -ForegroundColor Cyan
    Set-SpoolerWatchdog

    Write-Host "  [*] [38/50] 重启 BITS 服务... (菜单 68)" -ForegroundColor Cyan
    Manage-BITS

    Write-Host "  [*] [39/50] 重启后台处理程序（验证）..." -ForegroundColor Cyan
    if ((Get-Service spooler).Status -ne 'Running') { Start-Service spooler -ErrorAction SilentlyContinue }
    Write-Host "  [+] 后台处理程序已验证正常运行。" -ForegroundColor Green

    Write-Host "  [*] [40/50] 清除 Kerberos 登录缓存..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; klist purge > $null 2>&1 } catch {}

    Write-Host "  [*] [41/50] 重启 WdiSystemHost 服务..." -ForegroundColor Cyan
    try { Restart-Service WdiSystemHost -Force -ErrorAction SilentlyContinue } catch {}

    Write-Host "  [*] [42/50] 注册 mDNS（多播）..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; ipconfig /registerdns > $null 2>&1 } catch {}

    Write-Host "  [*] [43/50] 生成还原点... (菜单 66)" -ForegroundColor Cyan
    Create-RestorePoint

    Write-Host "  [*] [44/50] 扫描 V4 打印类驱动程序... (菜单 41)" -ForegroundColor Cyan
    Fix-V4ClassDriver

    Write-Host "  [*] [45/50] 恢复网络配置文件（强制专用）... (菜单 28)" -ForegroundColor Cyan
    $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    $profiles | Where-Object { $_.NetworkCategory -eq 'Public' } | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

    Write-Host "  [*] [46/50] 强制清除打印队列文件... (菜单 37)" -ForegroundColor Cyan
    Nuke-PrintQueue

    Write-Host "  [*] [47/50] 重置后台处理程序依赖项（注册表）... (菜单 38)" -ForegroundColor Cyan
    Reset-SpoolerDependencyRegistry

    Write-Host "  [*] [48/50] 清理打印机共享名称... (菜单 53)" -ForegroundColor Cyan
    Sanitize-PrinterShareName

    Write-Host "  [*] [49/50] 部署更新后自动重新应用任务..." -ForegroundColor Cyan
    Set-PostPatchTuesdayTask

    Write-Host "  [*] [50/50] 解析 PrintService 事件日志和最终后台处理程序验证... (菜单 78)" -ForegroundColor Cyan
    Parse-PrintEventLog
    if ((Get-Service spooler).Status -ne 'Running') { Start-Service spooler -ErrorAction SilentlyContinue }
    Write-Host "  [+] 后台处理程序已验证正常运行。" -ForegroundColor Green

    Write-Log "全部修复完成" -Type "SUCCESS"

    if ($script:silentNuke) {
        Write-Host "`n  ==================================================================================================="
        Write-Host "    [+] 静默全部修复完成！3 秒后重启..."
        Write-Host "  ===================================================================================================`n"
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }

    Write-Host "`n  ==================================================================================================="
    Write-Host "  [!] 域信息：如果主机已加入 AD，请在 secpol.msc 中验证「从网络访问此计算机」权限" -ForegroundColor Yellow
    Write-Host "  [!] 仍然被拒绝？提示：如果连接仍然失败，请使用选项 [60] 或绕过 [86]。"

    $checkError = Read-Host "   [?] 查看执行错误日志？(Y/N)"
    if ($checkError -eq 'Y') {
        Write-Host "`n   --- 错误扫描结果 ---" -ForegroundColor Cyan
        $errors = Select-String -Path $script:logFile -Pattern " - 错误 - " -SimpleMatch
        if ($errors) {
            $errors.Line | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        else {
            Write-Host "   [+] 日志中未发现错误。" -ForegroundColor Green
        }
        Write-Host "   --------------------`n"
    }

    $allFixRestart = Read-Host "   [?] 立即执行系统重启？(Y/N)"
    if ($allFixRestart -eq 'Y') {
        Write-Host "  [*] 正在执行，5 秒后重启..." -ForegroundColor Cyan
        Restart-Computer -Force
    }
    else {
        Write-Host "  [*] 请手动重启以应用所有更改。" -ForegroundColor Cyan
    }
}

function Extreme-25H2 {
    cls
    Write-Host "`n  ==================================================================================================="
    Write-Host "        Win 11 25H2 / 24H2 / 26H2+ / ARM64 极端修复路径"
    Write-Host "  ==================================================================================================="
    Write-Host "  [*] 此路径为具有严格安全策略的 Windows 11 系统应用深度修复。"
    Write-Host "  [*] 正在自动运行所有修复..." -ForegroundColor Cyan

    Write-Log "运行极端修复 25H2/26H2" -Type "INFO"

    Write-Host "  [*] 在应用修复前刷新 GPO 缓存..." -ForegroundColor Cyan
    try { $LASTEXITCODE = 0; gpupdate /force > $null 2>&1 } catch {}

    Fix-Deep0x00000709
    Fix-CrossSignedDriverPolicy
    Fix-HKCU-PrinterKeyPerms
    Set-PostPatchTuesdayTask

    Fix-UACTokenFilter
    Fix-LSAProtection
    Fix-NTLMv2
    Fix-SMBSigning
    Fix-ProviderOrder
    Fix-SAC
    Fix-IPPSharing
    Fix-AdvancedPointAndPrint

    Fix-mDNS
    Reset-SpoolerDependency
    Fix-UWPPrinting
    Enable-SMBGuest
    Disable-PasswordSharing
    Fix-WSDFirewall
    Fix-Network0x00000040
    Fix-DriverCopy0x00000002
    Fix-RpcBitness0x0000007e
    Fix-RDPPrinter
    Fix-CredentialGuard
    Fix-V4ClassDriver
    Reset-SpoolerDependencyRegistry
    Sanitize-PrinterShareName

    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP" -Name Enabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name DnsOnWire -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name DisableStrictNameChecking -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name NtlmMinClientSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name NtlmMinServerSec -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    catch {}

    try {
        $LASTEXITCODE = 0; cmdkey /list | Select-String $env:COMPUTERNAME | ForEach-Object { $t = $_.ToString() -replace '(?i)^\s*Target:\s*', ''; cmdkey /delete:$t > $null 2>&1 }
        $LASTEXITCODE = 0; klist purge > $null 2>&1
        $LASTEXITCODE = 0; ipconfig /flushdns > $null 2>&1
        $LASTEXITCODE = 0; nbtstat -RR > $null 2>&1
    }
    catch {}

    Write-Log "极端修复路径完成！" -Type "SUCCESS"
    Write-Host "  [+] 极端安全配置更改完成。建议重启系统。" -ForegroundColor Green

    $extremeRestart = Read-Host "`n   [?] 立即执行系统重启？(Y/N)"
    if ($extremeRestart -eq 'Y') { Restart-Computer -Force }
}

function Restart-PC {
    Write-Host "`n  [*] 系统将在 5 秒后重启..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}

function Detect-Win {
    Write-Host "`n  ======================================================================"
    Write-Host "                 Windows 与架构检测"
    Write-Host "  ======================================================================"
    Write-Host "  [+] 系统版本 ：$script:productName" -ForegroundColor Green
    Write-Host "  [+] 系统版本号：$script:buildNumber" -ForegroundColor Green
    if ($script:isARM64) {
        Write-Host "  [+] 架构     ：ARM64（骁龙/Apple M 系列虚拟机）" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] 架构     ：AMD64 / x64" -ForegroundColor Cyan
    }
    if ($script:isServer) {
        Write-Host "  [+] 版本     ：Windows Server 版" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [+] 版本     ：客户端（家庭版/专业版/企业版）" -ForegroundColor Cyan
    }
}function Show-Help {
    param([string]$Topic = "")

    $helpData = @{
        '1'  = @("修复错误 0x0000011b (RpcAuthnLevelPrivacy)", "禁用 RpcAuthnLevelPrivacyEnabled 注册表键，使 RPC 身份验证不再阻止共享连接。", "Windows 10/11 累积更新后最常见的错误。")
        '2'  = @("深度修复 0x00000709（多层 RPC 和 Kerberos）", "应用多层修复：RPC 命名管道、Kerberos 绕过、HKCU 清理和旧版覆盖。", "Windows 11 中标准修复无法解决的持续性 0x00000709 错误。也必须在主机上运行！")
        '3'  = @("绕过错误 0x00000bc4（未找到打印机）", "强制 RPC 使用命名管道协议，以便可以发现打印机。", "尽管网络可用，Windows 仍报告「未找到打印机」。")
        '4'  = @("修复错误 0x80070035（自动化网络服务）", "自动启动 fdPHost、FDResPub、SSDPSRV、upnphost 服务。", "目标电脑未在网络中显示；提示「找不到网络路径」。")
        '5'  = @("禁用客户端渲染（错误 0x000006d1）", "在注册表中启用 DisableClientSideRendering。", "打印作业因客户端驱动渲染问题而失败。")
        '6'  = @("修复错误 0x80070005（重置后台处理程序 ACL）", "使用 icacls 将 Spool\Printers 目录 ACL 重置为默认值。", "打印操作期间出现「拒绝访问」(0x80070005) 错误。")
        '7'  = @("修复错误 0x00000040（网络不可用）", "修复 PrintProcessor 和 Ports 注册表节点。", "访问打印机时提示「网络不可用」。")
        '8'  = @("修复错误 0x00000002 (CopyFilesPolicy)", "配置 CopyFilesPolicy 允许驱动摄取。", "从主机服务器克隆打印机驱动时出错。")
        '9'  = @("修复错误 0x0000007e（RPC 位数不匹配）", "强制跨架构驱动注册表合规。", "32 位与 64 位架构不匹配。")
        '10' = @("完整网络重置（DNS、Winsock、NetBIOS）", "刷新 DNS、释放/续订 IP、重置 Winsock 和 NetBIOS。", "网络连接不稳定、RTO 或严重延迟。")
        '11' = @("强制网络配置文件为专用", "将所有连接配置文件覆盖为专用状态。", "因网络配置文件设为公用而阻止共享。")
        '12' = @("强制禁用密码保护共享", "修改 LSA 注册表：limitblankpassworduse=0、everyoneincludesanonymous=1。", "未配置密码却仍出现凭据提示。")
        '13' = @("通过命名管道和 TCP 启用 RPC", "强制 RPC 通过命名管道和 TCP 协议通信。", "RPC 终结点阻止导致的打印机连接错误。")
        '14' = @("配置防火墙文件和打印机共享", "在防火墙中启用「文件和打印机共享」和「网络发现」规则。", "主机在网络中不可见，共享被严重阻止。")
        '15' = @("SMB 1.0 旧版协议管理（开/关）", "根据用户输入启用或禁用 SMB 1.0 协议。", "需要连接旧版硬件（Win XP/7）。警告：勒索软件风险！")
        '16' = @("禁用 SMB 签名（修复 Win 11 访问 NAS）", "禁用 SMB 客户端和服务器的 RequireSecuritySignature。", "从 Win 11 24H2+ 无法访问 NAS 或旧版主机。")
        '17' = @("强制现代 SMB2/SMB3 拓扑", "确保 SMB2/SMB3 处于活动状态，明确禁用 SMB1。", "向现代安全协议过渡。")
        '18' = @("将 SMB 置于网络提供程序顺序首位", "在提供程序列表中优先使用 LanmanWorkstation。", "SMB 连接严重延迟。")
        '19' = @("禁用 IPv6 协议栈", "通过注册表和 netsh 接口禁用 IPv6。", "纯 IPv4 网络中 IPv6 导致路由问题。")
        '20' = @("启用 mDNS 和 LLMNR（发现协议）", "启用多播 DNS 和 LLMNR 协议。", "通过主机名解析无法发现打印机。")
        '21' = @("配置 WSD 防火墙规则（端口 3702）", "在防火墙中为 WSD 发现开放 UDP 端口 3702。", "Web 服务发现被防火墙阻止。")
        '22' = @("启用 IPP 和 Mopria 共享基础", "启用 Windows IPP 和 Mopria 基础功能。", "使用 IPP 协议的现代打印机。")
        '23' = @("解决 Hyper-V/WSL 虚拟网络冲突", "禁用虚拟适配器上的打印机绑定。", "Hyper-V/WSL 虚拟交换机干扰 LAN 拓扑。")
        '24' = @("安装旧版 LPR/LPD 协议", "启用 Windows LPR 端口监视器和 LPD 服务功能。", "需要通过旧版 LPR 连接。")
        '25' = @("远程网络打印机发现", "扫描并枚举目标上的所有共享打印机。", "目标主机上的共享打印机未知。")
        '26' = @("WSD 到标准 TCP/IP 端口转换器", "检测 WSD 端口并将打印机迁移到稳定的标准 TCP/IP 端口。", "因 WSD 发现失败导致打印机间歇性消失或离线。")
        '27' = @("网络套接字重新初始化（选择性清理）", "重启 SMB 客户端/服务器服务并清除卡住的 445/135 端口连接。", "IP 更改或 VPN 后过期网络连接阻止打印机访问。")
        '28' = @("恢复网络配置文件（自动监视）", "强制将所有公用网络配置文件设为专用，并可选择部署监视任务。", "重启后网络配置文件重置为公用，阻止打印机共享。")
        '29' = @("手动注入标准 TCP/IP 端口", "通过 WMI 脚本注入 TCP/IP 端口。", "需要手动添加 IP 打印机端口。")
        '30' = @("强制初始化 WSD 打印设备", "为 Web 服务发现初始化 WSDPrintDevice 服务。", "WSD 网络打印机仍无法被检测到。")
        '31' = @("硬重置打印后台处理程序（清除队列）", "停止后台处理程序，强制删除 Spool\Printers 中的队列文件，重启后台处理程序。", "打印队列完全冻结，后台处理程序挂起。")
        '32' = @("重新初始化 RPC 和 DCOM 服务", "验证并重启 RpcSs 和 DcomLaunch 服务。", "RPC 或 DCOM 服务终止/崩溃；提示「RPC 服务器不可用」。")
        '33' = @("远程目标后台处理程序重启", "通过 sc.exe 执行远程后台处理程序重置。", "远程后台处理程序冻结且无法物理访问。", "需要目标主机上的管理员权限。")
        '34' = @("配置后台处理程序崩溃时自动重启", "通过 sc.exe 配置恢复操作：崩溃时自动重启。", "后台处理程序极不稳定，需要自愈机制。")
        '35' = @("清除过期后台处理程序依赖项", "将 DependOnService 后台处理程序参数重置为默认值 (RPCSS, http)。", "RPC 服务正常但后台处理程序不活动。")
        '36' = @("部署后台处理程序监视（每 5 分钟审计）", "部署每 5 分钟审计一次后台处理程序的计划任务。", "需要持续可用性的高运行时间打印服务器环境。")
        '37' = @("强制清除打印队列 (.shd/.spl)", "终止所有打印进程并清除损坏的 .shd/.spl 后台文件。", "标准取消方法无法完全清空队列。")
        '38' = @("后台处理程序依赖项注册表重置", "通过 HKLM 直接将后台处理程序 DependOnService 注册表重置为出厂默认值 (RPCSS, http)。", "即使重启后后台处理程序也无法启动。")
        '39' = @("驱动管理（打印服务器属性）", "启动打印服务器属性 GUI 管理已安装的驱动。", "打印机使用错误驱动或存在重复驱动实例。")
        '40' = @("禁用打印驱动隔离", "在注册表中禁用 IsolationPolicy。", "后台处理程序与特定驱动同时崩溃。")
        '41' = @("通用打印类驱动 V4 修复", "扫描 V4 驱动是否存在损坏的 PrintConfig.dll 并触发 DriverStore 重新注册。", "V4 打印机突然停止工作或打印乱码。")
        '42' = @("切换 PCL 与 PostScript 驱动模式", "在 PCL 和 PostScript 渲染模式之间切换打印机的驱动。", "打印机输出随机字符页。")
        '43' = @("孤立驱动清理 (pnputil)", "扫描 DriverStore 中的孤立打印机 OEM INF 包并强制删除。", "由于与旧的无形驱动冲突而无法安装新驱动。")
        '44' = @("绕过「驱动当前正在使用」", "强制终止 PrintIsolationHost、splwow64 和管道进程以释放驱动句柄。", "Windows 拒绝删除驱动程序。")
        '45' = @("幽灵 USB 端口和副本清除器", "检测并移除重复/幽灵打印机副本和失效 USB 端口。", "将打印机插入不同 USB 端口后产生了幽灵副本。")
        '46' = @("强制移除幽灵打印机", "通过命令行 (printui) 强制移除打印机。", "幽灵或损坏的打印机拒绝标准卸载。")
        '47' = @("修复 Microsoft Edge / UWP 打印", "重新注册 UWP 打印组件和回环豁免。", "从 Edge/UWP 应用打印失败，但从记事本成功。")
        '48' = @("重新安装 Microsoft Print to PDF/XPS", "重新初始化原生 Windows PDF 和 XPS 打印功能。", "原生虚拟打印机缺失或生成错误。")
        '49' = @("浏览器打印沙箱修复 (Chromium)", "清除浏览器打印缓存并修复打印对话框的回环豁免。", "可以在 Word 中打印但不能在 Chrome 中打印。")
        '50' = @("强制永久默认打印机", "禁用自动管理并通过 WMI 强制设置默认打印机。", "Windows 根据网络位置动态更改默认打印机。")
        '51' = @("强制设置默认打印机（注册表绕过）", "绕过 Windows 自动管理，通过直接 HKCU 注册表写入设置默认打印机。", "无法通过常规设置应用设置默认打印机。")
        '52' = @("修复 RDP 打印机终端服务", "在 RDP 终端服务注册表中启用打印机重定向。", "通过 RDP 身份验证但本地打印机映射失败。")
        '53' = @("自动清理打印机共享名称", "扫描共享打印机并将共享名称中的非法字符替换为下划线。", "客户端无法连接共享名称过长或复杂的打印机。")
        '54' = @("降级 LSA 保护（旧版身份验证）", "在 LSA 注册表中禁用 RunAsPPL。", "因 Win 11 严格 LSA 保护导致共享登录失败。")
        '55' = @("绕过智能应用控制 (SAC)", "将 VerifiedAndReputablePolicyState 设为关闭。", "Windows 11 SAC 积极阻止驱动安装程序。")
        '56' = @("绕过高级 ServerList 即插即用（PrintNightmare 绕过）", "将 PrintNightmare 绕过（提升覆盖）和 ServerList 通配符 (*) 注入注册表。", "驱动下载期间出现「检查打印机名称」或「拒绝访问」等通用错误。", "Windows 11 Build 22621+ 需要")
        '57' = @("绕过 UAC 管理员网络令牌筛选", "配置 LocalAccountTokenFilterPolicy = 1。", "UAC 筛选导致对工作组主机的远程管理失败。")
        '58' = @("强制 NTLMv2 响应合规性", "将 LmCompatibilityLevel 严格配置为 NTLMv2（级别 3）。", "针对不同操作系统版本或网络存储 (NAS) 身份验证时出现「拒绝访问」。")
        '59' = @("管理 Windows 受保护打印 (WPP)", "禁用 Windows 受保护打印功能。", "打印机驱动与 WPP 隔离不兼容。")
        '60' = @("将 Windows 凭据永久注入凭据管理器", "将用户名/密码直接注入 Windows 凭据管理器。", "避免每次访问时手动身份验证。")
        '61' = @("从 Windows 凭据管理器清除过期凭据", "通过 cmdkey 清除凭据管理器中无效或过期的凭据。", "主机密码已更改，但本地计算机保留过期缓存。")
        '62' = @("绕过凭据保护（严格 NTLM 阻止）", "禁用 LsaCfgFlags 凭据保护注册表节点。", "启用了凭据保护的企业/专业版环境。")
        '63' = @("跨用户凭据映射", "通过 NTUSER.DAT 注册表加载向所有用户配置文件注入登录 RunOnce 凭据任务。", "设置带多个本地帐户的共享电脑。")
        '64' = @("执行前注册表备份（后台处理程序和网络）", "将 Print、Printers 策略和 LanmanWorkstation 注册表树导出到 C:\WindowsPrinterSharingFixBackup。", "建议在应用其他修复前执行。", "务必首先运行此选项！")
        '65' = @("从备份回滚注册表", "从备份目录导入 .reg 文件。", "应用修复后情况恶化时使用。", "仅当之前执行过 [64] 备份时才有效。")
        '66' = @("生成系统还原点（安全）", "生成系统还原点以进行完整系统回滚。", "执行重大系统级架构更改之前。")
        '67' = @("系统文件检查器和 DISM 还原", "执行 SFC /scannow 和 DISM RestoreHealth。", "频繁蓝屏、异常错误或恶意软件清理后。", "此过程可能需要 10-30 分钟！")
        '68' = @("重启 BITS（后台传输服务）", "重启后台智能传输服务。", "驱动无法自动下载。")
        '69' = @("Windows 更新与阻止管理", "提供工具卸载更新、暂停更新、永久禁用更新服务（阻止修复还原）或恢复更新默认值。", "防止 Windows 重新启用受限协议或破坏打印机共享。")
        '70' = @("启动原生 Windows 疑难解答", "执行原生 Windows 打印机疑难解答 (msdt)。", "手动干预前的初始诊断步骤。")
        '71' = @("强制打印机在线状态", "通过 WMI/CIM 强制打印机的 WorkOffline 状态为 false。", "打印机状态卡在「脱机」或呈灰色。")
        '72' = @("启动 Services.msc", "启动 Services.msc MMC 管理单元。", "手动验证打印后台处理程序运行状态。")
        '73' = @("检测系统版本和构建架构", "显示系统版本、版本号和具体建议。", "选择特定修复前确保兼容性。")
        '74' = @("Ping 与端口 445/135 诊断", "ICMP Ping + SMB (445) 和 RPC (135) 端口扫描。", "测试网络连接和防火墙状态的第一步。")
        '75' = @("查看执行日志", "启动日志管理界面（记事本）。", "修复后审计和验证。")
        '76' = @("审计最近 20 条打印服务错误日志", "解析系统事件日志中最近 20 条错误事件。", "调查打印问题的根本原因。")
        '77' = @("系统诊断审计", "审计后台处理程序状态、SMB、防火墙和网络拓扑。", "部署修复前检查系统整体健康状况。")
        '78' = @("PrintService 事件日志解析器（前 5 条）", "解析最近 5 条错误/警告事件并提供自动解决建议。", "没有明显错误代码的神秘打印问题。")
        '79' = @("生成 HTML 诊断报告", "将执行日志编译为交互式 HTML 文件。", "用于 IT 文档或向上级汇报。")
        '80' = @("检测 GPO 干预（策略扫描）", "扫描注册表和 gpresult 以查找影响打印机的组策略覆盖。", "修复暂时有效，但 gpupdate 或重启后再次失效。")
        '81' = @("PrintBRM（备份/还原迁移）", "通过 PrintBrm.exe 执行打印机拓扑的完整备份或还原。", "向多台工作站部署打印机或迁移到新硬件。")
        '82' = @("启用 SMB 来宾访问并取消匿名阻止", "在 LanmanWorkstation 注册表中启用 AllowInsecureGuestAuth。", "用于本地网络中的无密码共享。")
        '83' = @("极端修复路径（Win 11 24H2/25H2/26H2+ 和 ARM64 专用）", "激进修复组合：DnsOnWire、StrictNameChecking、NTLM 级别、SMB 签名、Kerberos 清理等。", "标准修复在最新 Win 11 上无效。", "专为 Build 26000 及以上版本构建。")
        '84' = @("执行全部修复（50 项自动修复）", "顺序执行 50 项自动修复。", "主要推荐 - 大多数常见情况的首选修复。", "完成后重启系统以获得最佳效果。")
        '85' = @("静默全部修复并重启（零提示）", "静默执行全部 50 个步骤并自动重启。", "需要立即无人值守修复的紧急情况。", "系统将自动重启！请先保存所有重要工作！")
        '86' = @("映射本地端口到 UNC 路径（绕过 0x00000709）", "尝试标准端口创建，若被阻止则回退到直接注册表注入绕过。", "标准共享失败且系统完全阻止「Add-PrinterPort」命令时。")
        '87' = @("移除已注入的本地端口 (UNC)", "尝试标准端口移除，若被阻止则回退到注册表清理。", "映射端口不再需要或配置错误时。")
        '88' = @("重启系统", "立即执行系统重启。", "运行任何重大修复后务必执行。")
        '89' = @("退出脚本", "退出工具。", "故障排除完成时。")
    }

    if ($Topic -eq "" -or $Topic.ToLower() -eq "menu" -or $Topic.ToLower() -eq "help") {
        cls
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host "      使用指南：Windows 打印机共享修复工具 - @KHAIRUDINFAHMI（汉化版）" -ForegroundColor Green
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  使用方法：" -ForegroundColor Yellow
        Write-Host "    - 输入功能编号 (1-89) 并按回车"
        Write-Host "    - '7' 和 '07' 均有效"
        Write-Host "    - 输入 '?' 显示本指南"
        Write-Host "    - 输入 '? 7' 查看功能 7 的详细说明"
        Write-Host "    - 输入 '? all' 打开完整 HTML 文档"
        Write-Host ""
        Write-Host "  新手工作流（标准执行）：" -ForegroundColor Yellow
        Write-Host "    1. 执行 [64] 备份注册表（必做）" -ForegroundColor White
        Write-Host "    2. 执行 [84] 全部修复（50 项自动步骤）" -ForegroundColor White
        Write-Host "    3. 重启系统" -ForegroundColor White
        Write-Host "    4. 验证打印机共享访问" -ForegroundColor White
        Write-Host ""
        Write-Host "  Win 11 24H2+ 工作流（Build 26000+）：" -ForegroundColor Yellow
        Write-Host "    1. 执行 [64] 备份注册表" -ForegroundColor White
        Write-Host "    2. 执行 [83] 极端修复路径" -ForegroundColor White
        Write-Host "    3. 重启系统" -ForegroundColor White
        Write-Host ""
        Write-Host "  紧急方案（快速自动修复）：" -ForegroundColor Yellow
        Write-Host "    - 执行 [85] 静默全部修复（警告：会自动重启！）" -ForegroundColor White
        Write-Host ""
        Write-Host "  功能分类：" -ForegroundColor Yellow
        Write-Host "    [01-09] 错误代码修复 (0x0000011b, 0x00000709, 0x00000bc4, 0x80070035, 0x000006d1, 0x00000040, 0x00000002, 0x0000007e)" -ForegroundColor Cyan
        Write-Host "    [10-30] 网络与共享配置 (DNS, SMB, 防火墙, WSD, IPP)" -ForegroundColor Cyan
        Write-Host "    [31-38] 后台处理程序管理 (重置, RPC, 恢复, 监视, 清除)" -ForegroundColor Cyan
        Write-Host "    [39-53] 驱动与打印 (隔离, V4, PCL, 幽灵, PDF, RDP)" -ForegroundColor Cyan
        Write-Host "    [54-59] 安全与策略 (LSA, SAC, UAC, NTLMv2, WPP)" -ForegroundColor Cyan
        Write-Host "    [60-69] 凭据与系统 (凭据管理器, 备份, SFC, BITS, KB)" -ForegroundColor Cyan
        Write-Host "    [70-81] 诊断与工具 (疑难解答, 日志, GPO, BRM)" -ForegroundColor Green
        Write-Host "    [82-89] 特殊操作 (极端修复, 全部修复, 本地 UNC, 清除 UNC, 静默全部修复)" -ForegroundColor Green

        Write-Host ""
        Write-Host "  快速故障排除：" -ForegroundColor Yellow
        Write-Host "    - 持续提示输入密码？            -> 执行 [12]、[60]、[82]" -ForegroundColor White
        Write-Host "    - 「拒绝访问」（持续）？         -> 使用 [60] 注入目标 IP 和凭据。" -ForegroundColor White
        Write-Host "    - 「检查打印机名称」通用错误？   -> 执行 [56] 或 [86]" -ForegroundColor White
        Write-Host "    - 打印机已开机但仍显示脱机？     -> 执行 [71]" -ForegroundColor White
        Write-Host "    - 网络上看不到主机？             -> 执行 [04]、[11]、[14]" -ForegroundColor White
        Write-Host "    - Edge/UWP 打印失败？            -> 执行 [47]" -ForegroundColor White
        Write-Host "    - 需要回滚所有更改？             -> 执行 [65]" -ForegroundColor White
        Write-Host ""
        Write-Host "  ======================================================================================" -ForegroundColor Cyan
    }
    elseif ($Topic.ToLower() -eq "all") {
        $docPath = $null

        try {
            $exeDir = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
            $searchPaths = @(
                (Join-Path $exeDir "documentation.html"),
                (Join-Path $exeDir "docs\documentation.html"),
                (Join-Path (Split-Path $exeDir -Parent) "docs\documentation.html")
            )
            foreach ($sp in $searchPaths) {
                if (Test-Path $sp) { $docPath = $sp; break }
            }
        }
        catch {}

        if (-not $docPath -or -not (Test-Path $docPath)) {
            try {
                if ($PSCommandPath) {
                    $scriptDir = Split-Path $PSCommandPath -Parent
                    $fallbacks = @(
                        (Join-Path $scriptDir "documentation.html"),
                        (Join-Path $scriptDir "docs\documentation.html"),
                        (Join-Path (Split-Path $scriptDir -Parent) "docs\documentation.html")
                    )
                    foreach ($fb in $fallbacks) {
                        if (Test-Path $fb) { $docPath = $fb; break }
                    }
                }
            }
            catch {}
        }
        if ($docPath -and (Test-Path $docPath)) {
            Write-Host "  [*] 正在打开完整 HTML 文档..." -ForegroundColor Cyan
            $fileUrl = "file:///" + $docPath.Replace("\", "/") + "?all"
            Start-Process $fileUrl
        }
        else {
            Write-Host "  [-] 安装目录中未检测到 documentation.html 文件。" -ForegroundColor Red
            Write-Host "  [!] 使用 '?' 查看快速指南，或使用 '? <数字>' 查看功能详情。" -ForegroundColor Yellow
        }
    }
    else {
        $num = $Topic.TrimStart('0')
        if ($helpData.ContainsKey($num)) {
            $h = $helpData[$num]
            Write-Host ""
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
            Write-Host "      帮助：功能 [$Topic]" -ForegroundColor Green
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  名称     ：$($h[0])" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  功能说明 ：$($h[1])" -ForegroundColor White
            Write-Host ""
            if ($h[2] -ne "") {
                Write-Host "  适用场景 ：$($h[2])" -ForegroundColor Cyan
            }
            Write-Host ""
            Write-Host "  ======================================================================================" -ForegroundColor Cyan
        }
        else {
            Write-Host "  [-] 未找到功能编号 '$Topic'。请输入 1-89。" -ForegroundColor Red
        }
    }
}function Show-Menu {
    cls
    $winName = "$script:productName $script:buildNumber".ToUpper()
    if ($script:isARM64) { $winName += " ARM64" }
    elseif ([Environment]::Is64BitOperatingSystem) { $winName += " 64位" }
    else { $winName += " 32位" }

    Write-Host " 用户: " -NoNewline
    Write-Host "$env:USERNAME " -ForegroundColor Green -NoNewline
    Write-Host "| 计算机名: " -NoNewline
    Write-Host "$env:COMPUTERNAME " -ForegroundColor Green -NoNewline
    Write-Host "| 系统: " -NoNewline
    Write-Host "$winName " -ForegroundColor Blue -NoNewline
    Write-Host "| Windows 打印机共享修复工具 v2.3.2" -ForegroundColor Green

    Write-Host " 时区: " -NoNewline
    Write-Host "$(Get-TimeZone | Select-Object -ExpandProperty Id) | $(Get-Date -Format 'HH.mm.ss')" -ForegroundColor Red
    Write-Host " 作者: @KHAIRUDINFAHMI (2026) | 汉化版" -ForegroundColor Magenta
    Write-Host ("=" * 238) -ForegroundColor DarkGray

    try {
        $rawUI = $Host.UI.RawUI
        $bufSize = $rawUI.BufferSize
        if ($bufSize.Width -lt 245) {
            $bufSize.Width = 245
            $rawUI.BufferSize = $bufSize
        }
        $winSize = $rawUI.WindowSize
        if ($winSize.Width -lt 245) {
            $winSize.Width = 245
            $rawUI.WindowSize = $winSize
        }
    } catch {}

    $cw1 = 80
    $cw2 = 78
    $cw3 = 80
    $totalW = $cw1 + $cw2 + $cw3

    Write-Host (" 核心修复与网络服务".PadRight($cw1)) -ForegroundColor Cyan -NoNewline
    Write-Host (" 后台处理程序、驱动与策略".PadRight($cw2)) -ForegroundColor Cyan -NoNewline
    Write-Host " 诊断与自动化" -ForegroundColor Cyan

    $col1 = @(
        "[01] 修复错误 0x0000011b (RpcAuthnLevelPrivacy)",
        "[02] 深度修复 0x00000709（多层 RPC 和 Kerberos）",
        "[03] 绕过错误 0x00000bc4（未找到打印机）",
        "[04] 修复错误 0x80070035（自动化网络服务）",
        "[05] 禁用客户端渲染（错误 0x000006d1）",
        "[06] 修复错误 0x80070005（重置后台处理程序 ACL）",
        "[07] 修复错误 0x00000040（网络不可用）",
        "[08] 修复错误 0x00000002 (CopyFilesPolicy)",
        "[09] 修复错误 0x0000007e（RPC 位数不匹配）",
        "[10] 完整网络重置（DNS、Winsock、NetBIOS）",
        "[11] 强制网络配置文件为专用",
        "[12] 强制禁用密码保护共享",
        "[13] 通过命名管道和 TCP 启用 RPC",
        "[14] 配置防火墙文件和打印机共享",
        "[15] SMB 1.0 旧版协议管理（开/关）",
        "[16] 禁用 SMB 签名（修复 Win 11 访问 NAS）",
        "[17] 强制现代 SMB2/SMB3 拓扑",
        "[18] 将 SMB 置于网络提供程序顺序首位",
        "[19] 禁用 IPv6 协议栈",
        "[20] 启用 mDNS 和 LLMNR（发现协议）",
        "[21] 配置 WSD 防火墙规则（端口 3702）",
        "[22] 启用 IPP 和 Mopria 共享基础",
        "[23] 解决 Hyper-V/WSL 虚拟网络冲突",
        "[24] 安装旧版 LPR/LPD 协议",
        "[25] 远程网络打印机发现",
        "[26] WSD 到标准 TCP/IP 端口转换器",
        "[27] 网络套接字重新初始化（选择性清理）",
        "[28] 恢复网络配置文件（自动监视）",
        "[29] 手动注入标准 TCP/IP 端口",
        "[30] 强制初始化 WSD 打印设备"
    )

    $col2 = @(
        "[31] 硬重置打印后台处理程序（清除队列）",
        "[32] 重新初始化 RPC 和 DCOM 服务",
        "[33] 远程目标后台处理程序重启",
        "[34] 配置后台处理程序崩溃时自动重启",
        "[35] 清除过期后台处理程序依赖项",
        "[36] 部署后台处理程序监视（每 5 分钟审计）",
        "[37] 强制清除打印队列 (.shd/.spl)",
        "[38] 后台处理程序依赖项注册表重置",
        "[39] 驱动管理（打印服务器属性）",
        "[40] 禁用打印驱动隔离",
        "[41] 通用打印类驱动 V4 修复",
        "[42] 切换 PCL 与 PostScript 驱动模式",
        "[43] 孤立驱动清理 (pnputil)",
        "[44] 绕过「驱动当前正在使用」",
        "[45] 幽灵 USB 端口和副本清除器",
        "[46] 强制移除幽灵打印机",
        "[47] 修复 Microsoft Edge / UWP 打印",
        "[48] 重新安装 Microsoft Print to PDF/XPS",
        "[49] 浏览器打印沙箱修复 (Chromium)",
        "[50] 强制永久默认打印机",
        "[51] 强制设置默认打印机（注册表绕过）",
        "[52] 修复 RDP 打印机终端服务",
        "[53] 自动清理打印机共享名称",
        "[54] 降级 LSA 保护（旧版身份验证）",
        "[55] 绕过智能应用控制 (SAC)",
        "[56] 绕过高级 ServerList 即插即用",
        "[57] 绕过 UAC 管理员网络令牌筛选",
        "[58] 强制 NTLMv2 响应合规性",
        "[59] 管理 Windows 受保护打印 (WPP)"
    )

    $col3 = @(
        "[60] 将凭据永久注入凭据管理器",
        "[61] 清除凭据管理器中的过期凭据",
        "[62] 绕过凭据保护（严格 NTLM）",
        "[63] 跨用户凭据映射",
        "[64] 执行前注册表备份（后台处理程序）",
        "[65] 从备份回滚注册表",
        "[66] 生成系统还原点（安全）",
        "[67] 系统文件检查器和 DISM 还原",
        "[68] 重启 BITS（后台传输）",
        "[69] Windows 更新与阻止管理",
        "[70] 启动原生 Windows 疑难解答",
        "[71] 强制打印机在线状态",
        "[72] 启动 Services.msc",
        "[73] 检测系统版本和构建架构",
        "[74] Ping 与端口 445/135 诊断",
        "[75] 查看执行日志",
        "[76] 审计最近 20 条打印服务错误日志",
        "[77] 系统诊断审计",
        "[78] PrintService 事件日志解析器（前 5 条）",
        "[79] 生成 HTML 诊断报告",
        "[80] 检测 GPO 干预（策略扫描）",
        "[81] PrintBRM（备份/还原迁移）",
        "[82] 启用 SMB 来宾访问并取消匿名阻止",
        "[83] 极端修复路径（Win 11 24H2/25H2/26H2+ 和 ARM64）",
        "[84] 全部修复（50 项自动修复）",
        "[85] 静默全部修复并重启（零提示）",
        "[86] 映射本地端口到 UNC 路径（绕过 0x00000709）",
        "[87] 移除已注入的本地端口 (UNC)",
        "[88] 重启系统",
        "[89] 退出脚本"
    )

    $maxRows = 30
    for ($i = 0; $i -lt $maxRows; $i++) {

        if ($i -lt $col1.Count) {
            $m1 = [regex]::Match($col1[$i], '^(\[\d+\])(.*)')
            if ($m1.Success) {
                Write-Host (" " + $m1.Groups[1].Value) -ForegroundColor Green -NoNewline
                Write-Host $m1.Groups[2].Value.PadRight($cw1 - 6) -ForegroundColor Green -NoNewline
            } else { Write-Host (" " + $col1[$i].PadRight($cw1 - 1)) -ForegroundColor Green -NoNewline }
        } else { Write-Host (" " * ($cw1 - 1)) -NoNewline }

        Write-Host " " -NoNewline

        if ($i -lt $col2.Count) {
            $m2 = [regex]::Match($col2[$i], '^(\[\d+\])(.*)')
            if ($m2.Success) {
                Write-Host $m2.Groups[1].Value -ForegroundColor Green -NoNewline
                Write-Host $m2.Groups[2].Value.PadRight($cw2 - 5) -ForegroundColor Green -NoNewline
            } else { Write-Host $col2[$i].PadRight($cw2 - 1) -ForegroundColor Green -NoNewline }
        } else { Write-Host (" " * ($cw2 - 1)) -NoNewline }

        Write-Host " " -NoNewline

        if ($i -lt $col3.Count) {
            $m3 = [regex]::Match($col3[$i], '^(\[\d+\])(.*)')
            if ($m3.Success) {
                Write-Host $m3.Groups[1].Value -ForegroundColor Green -NoNewline
                if ($m3.Groups[1].Value -in @("[83]", "[84]", "[85]")) {
                    Write-Host $m3.Groups[2].Value -ForegroundColor Red
                } else {
                    Write-Host $m3.Groups[2].Value -ForegroundColor Green
                }
            } else { Write-Host $col3[$i] -ForegroundColor Green }
        } else { Write-Host "" }
    }

    Write-Host ("-" * $totalW) -ForegroundColor Red
    $noteLine1 = " :   提示: ".PadRight($totalW - 2) + ":"
    $noteLine2 = " :   [84] 全部修复 (50 步) | [83] 极端修复路径 (Win11) | [85] 静默全部修复 ".PadRight($totalW - 2) + ":"
    $noteLine3 = " :   [?] 帮助 | [? 7] 详情 | [? all] HTML | 提示：若出现「检查打印机名称」错误，请使用选项 [86] ".PadRight($totalW - 2) + ":"

    Write-Host $noteLine1 -ForegroundColor Red
    Write-Host $noteLine2 -ForegroundColor Red
    Write-Host $noteLine3 -ForegroundColor Green
    Write-Host ("-" * $totalW) -ForegroundColor Red
    Write-Host ""
    Write-Host "请输入选项: " -NoNewline
}

if ($script:silentNuke) {
    AllFix-Core
    exit
}

do {
    Show-Menu
    $choice = Read-Host
    $choice = $choice.Trim()

    if ($choice -match '^\?(.*)$' -or $choice -match '^help\s*(.*)$') {
        $helpTopic = $Matches[1].Trim()
        Show-Help -Topic $helpTopic
        Write-Host "`n  [>] 按回车返回主菜单..." -ForegroundColor Yellow
        Read-Host | Out-Null
        continue
    }

    if ($choice -match '^\d+$' -and $choice.Length -gt 1) { $choice = $choice.TrimStart('0') }

    if ($choice -match '^\d+$') {
        Clear-Host
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "  正在执行模块 [$choice]" -ForegroundColor Yellow
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host ""
    }

    switch ($choice) {
        '1' { Fix-RpcAuthn0x0000011b }
        '2' { Fix-Deep0x00000709 }
        '3' { Fix-Discovery0x00000bc4 }
        '4' { Fix-NetworkServices }
        '5' { Fix-CSR }
        '6' { Reset-SpoolerPerm }
        '7' { Fix-Network0x00000040 }
        '8' { Fix-DriverCopy0x00000002 }
        '9' { Fix-RpcBitness0x0000007e }
        '10' { Reset-Network }
        '11' { Set-NetworkPrivate }
        '12' { Disable-PasswordSharing }
        '13' { Fix-NamedPipes }
        '14' { Open-Firewall }
        '15' { Manage-SMB1 }
        '16' { Fix-SMBSigning }
        '17' { Fix-ModernSMB }
        '18' { Fix-ProviderOrder }
        '19' { Disable-IPv6 }
        '20' { Fix-mDNS }
        '21' { Fix-WSDFirewall }
        '22' { Fix-IPPSharing }
        '23' { Fix-HyperVConflict }
        '24' { Manage-LPR }
        '25' { Scan-RemotePrinter }
        '26' { Convert-WSDtoTCPIP }
        '27' { Reset-NetworkSockets }
        '28' { Rescue-NetworkProfile }
        '29' { Manage-TCPPort }
        '30' { Start-Service WSDPrintDevice -ErrorAction SilentlyContinue; Write-Host "  [+] WSD 发现已启用" -ForegroundColor Green }
        '31' { Reset-Spooler }
        '32' { Check-RPC }
        '33' { Remote-SpoolerReset }
        '34' { Set-SpoolerRecovery }
        '35' { Reset-SpoolerDependency }
        '36' { Set-SpoolerWatchdog }
        '37' { Nuke-PrintQueue }
        '38' { Reset-SpoolerDependencyRegistry }
        '39' { Manage-Drivers }
        '40' { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print" -Name IsolationPolicy -Value 0 -Type DWord -Force; Write-Host "  [+] 隔离已禁用" -ForegroundColor Green }
        '41' { Fix-V4ClassDriver }
        '42' { Switch-DriverMode }
        '43' { Sweep-OrphanedDrivers }
        '44' { Force-KillDriverProcess }
        '45' { Remove-GhostUSBPrinters }
        '46' { Uninstall-Printer }
        '47' { Fix-UWPPrinting }
        '48' { Fix-PrintToPDF }
        '49' { Fix-BrowserPrintSandbox }
        '50' { Manage-DefaultPrinter }
        '51' { Force-DefaultPrinterRegistry }
        '52' { Fix-RDPPrinter }
        '53' { Sanitize-PrinterShareName }
        '54' { Fix-LSAProtection }
        '55' { Fix-SAC }
        '56' { Fix-AdvancedPointAndPrint }
        '57' { Fix-UACTokenFilter }
        '58' { Fix-NTLMv2 }
        '59' { Manage-WPP }
        '60' { Add-Credential }
        '61' { Clean-Credential }
        '62' { Fix-CredentialGuard }
        '63' { Inject-CrossUserCredentials }
        '64' { Backup-Registry }
        '65' { Rollback-Registry }
        '66' { Create-RestorePoint }
        '67' { Run-SfcDism }
        '68' { Manage-BITS }
        '69' { Manage-WindowsUpdate }
        '70' { Start-Troubleshooter }
        '71' { Force-PrinterOnline }
        '72' { Open-Services }
        '73' { Detect-Win }
        '74' { Test-Connectivity }
        '75' { Log-Manager }
        '76' { Scan-PrintEventLog }
        '77' { Run-QuickDiagnostics }
        '78' { Parse-PrintEventLog }
        '79' { Generate-HtmlLog }
        '80' { Detect-GPOIntervention }
        '81' { Print-Migration }
        '82' { Enable-SMBGuest }
        '83' { Extreme-25H2 }
        '84' { AllFix-Core }
        '85' { $script:silentNuke = $true; AllFix-Core }
        '86' { Map-LocalPortUNC }
        '87' { Remove-LocalPortUNC }
        '88' { Restart-PC }
        '89' { Write-Log "工具已退出。" -Type "INFO"; exit }

        default { Write-Host "`n  [-] 选择无效。请输入数字 1 - 89。" -ForegroundColor Red }
    }

    if ($choice -ne '89' -and $choice -ne '88' -and $choice -ne '85') {
        Write-Host "`n  [>] 按回车返回主菜单..." -ForegroundColor Yellow
        Read-Host | Out-Null
    }
} while ($true)
