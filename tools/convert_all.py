#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WindowsPrinterSharingFix 三语汉化 (ZH/EN/ID) 总脚本
步骤:
1. 语言引擎改造 (三语循环)
2. 内联 if($isEN){EN}else{ID} -> switch 三态 (含中文填充)
3. 变量赋值 if($isEN) -> switch 三态
4. 多行块 if($isEN){...}else{...} -> switch 三态 (含中文填充)
5. helpData 选择逻辑三语化
所有输出行带 \n,避免粘行
"""
import re, sys

SRC = 'src/WindowsPrinterSharingFix.ps1'

with open(SRC, encoding='utf-8') as f:
    content = f.read()

# ========== 1. 语言引擎改造 ==========
old_engine = '''# Windows Printer Sharing Fix - Interactive Engine & Bilingual UI
# Supports Bahasa Indonesia (ID) and English (EN)

$script:lang = "ID"
try {
    $savedLang = (Get-ItemProperty -Path "HKCU:\\Software\\WindowsPrinterSharingFix" -Name "Language" -ErrorAction SilentlyContinue).Language
    if ($savedLang -in @("ID", "EN")) {
        $script:lang = $savedLang
    }
} catch {}

function Set-AppLanguage {
    param([string]$NewLang)
    if ($NewLang -in @("ID", "EN")) {
        $script:lang = $NewLang
        try {
            if (-not (Test-Path "HKCU:\\Software\\WindowsPrinterSharingFix")) {
                New-Item -Path "HKCU:\\Software\\WindowsPrinterSharingFix" -Force | Out-Null
            }
            Set-ItemProperty -Path "HKCU:\\Software\\WindowsPrinterSharingFix" -Name "Language" -Value $script:lang -Force
        } catch {}
    }
}

function Toggle-AppLanguage {
    if ($script:lang -eq "ID") {
        Set-AppLanguage -NewLang "EN"
    } else {
        Set-AppLanguage -NewLang "ID"
    }
}'''

new_engine = '''# Windows Printer Sharing Fix - Interactive Engine & Trilingual UI (ZH / EN / ID)
# Supports Simplified Chinese (ZH, default), English (EN) and Bahasa Indonesia (ID)

$script:lang = "ZH"
try {
    $savedLang = (Get-ItemProperty -Path "HKCU:\\Software\\WindowsPrinterSharingFix" -Name "Language" -ErrorAction SilentlyContinue).Language
    if ($savedLang -in @("ZH", "EN", "ID")) {
        $script:lang = $savedLang
    }
} catch {}

function Set-AppLanguage {
    param([string]$NewLang)
    if ($NewLang -in @("ZH", "EN", "ID")) {
        $script:lang = $NewLang
        try {
            if (-not (Test-Path "HKCU:\\Software\\WindowsPrinterSharingFix")) {
                New-Item -Path "HKCU:\\Software\\WindowsPrinterSharingFix" -Force | Out-Null
            }
            Set-ItemProperty -Path "HKCU:\\Software\\WindowsPrinterSharingFix" -Name "Language" -Value $script:lang -Force
        } catch {}
    }
}

function Toggle-AppLanguage {
    # Cycle ZH -> EN -> ID -> ZH
    if ($script:lang -eq "ZH") {
        Set-AppLanguage -NewLang "EN"
    } elseif ($script:lang -eq "EN") {
        Set-AppLanguage -NewLang "ID"
    } else {
        Set-AppLanguage -NewLang "ZH"
    }
}'''

assert old_engine in content, "语言引擎锚点未找到!"
content = content.replace(old_engine, new_engine)
print("[1/5] 语言引擎已改为三语循环")

# ========== 2 & 3. 内联 + 变量赋值转换 ==========
# 内联: Write-Host $(if ($isEN) { "EN" } else { "ID" })
# 变量: $x = if ($isEN) { "EN" } else { "ID" }
# 统一转成 switch($script:lang){ZH/EN/default} 但ZH需要翻译,先放占位
INLINE_ZH = {
    "OPTIMIZING HOST / PRINT SERVER PC (USB-CONNECTED)": "正在优化主机 / 打印服务器电脑(USB 直连)",
    "  [*] [1/8] Securing Registry Backup...": "  [*] [1/8] 正在安全备份注册表...",
    "  [*] [2/8] Enforcing Spooler Remote RPC Endpoint (Accepting Client Connections)...": "  [*] [2/8] 正在启用后台打印程序远程 RPC 端点(接受客户端连接)...",
    "  [*] [3/8] Enforcing Network Connection Profile to Private...": "  [*] [3/8] 正在将网络配置文件设置为“专用”...",
    "  [*] [4/8] Opening Passwordless Sharing & Guest Access Permissions...": "  [*] [4/8] 正在开启无密码共享与来宾访问权限...",
    "  [*] [5/8] Opening Windows Firewall for File & Printer Sharing and WSD Discovery...": "  [*] [5/8] 正在开放文件和打印机共享的防火墙与 WSD 发现...",
    "  [*] [6/8] Disabling SMB Server Security Signing Enforcement...": "  [*] [6/8] 正在禁用 SMB 服务器安全签名强制...",
    "  [*] [7/8] Sanitizing Printer Share Names (Removing illegal characters & spaces)...": "  [*] [7/8] 正在清理打印机共享名称(移除非法字符与空格)...",
    "  [*] [8/8] Deploying Spooler Watchdog Scheduled Task & Restarting Spooler...": "  [*] [8/8] 正在部署后台打印程序守护计划任务并重启后台打印程序...",
    "  [+] Host / Print Server optimization completed successfully!": "  [+] 主机 / 打印服务器优化成功完成!",
    "  [i] Other PCs on the network can now connect to printers shared by this computer.": "  [i] 网络上的其他电脑现在可以连接这台电脑共享的打印机了。",
    "OPTIMIZING CLIENT PC (CONNECTING TO SHARED PRINTER)": "正在优化客户端电脑(连接共享打印机)",
    "  [*] [1/7] Securing Registry Backup...": "  [*] [1/7] 正在安全备份注册表...",
    "  [*] [2/7] Activating RPC Named Pipes & TCP Protocol Pathways...": "  [*] [2/7] 正在激活 RPC 命名管道与 TCP 协议路径...",
    "  [*] [3/7] Applying Point & Print Driver Elevation Bypass (PrintNightmare Override)...": "  [*] [3/7] 正在应用 Point and Print 驱动提升绕过(PrintNightmare 覆盖)...",
    "  [*] [4/7] Disabling SMB Client Signing Enforcement (Resolving 24H2/25H2 block)...": "  [*] [4/7] 正在禁用 SMB 客户端签名强制(解决 24H2/25H2 阻止)...",
    "  [*] [5/7] Fixing HKCU Printer Registry Key Permissions...": "  [*] [5/7] 正在修复 HKCU 打印机注册表项权限...",
    "  [*] [6/7] Enabling Network Discovery Services (mDNS, LLMNR, SSDP)...": "  [*] [6/7] 正在启用网络发现服务(mDNS、LLMNR、SSDP)...",
    "  [*] [7/7] Opening Firewall Rules & Flushing DNS Cache...": "  [*] [7/7] 正在开放防火墙规则并刷新 DNS 缓存...",
    "  [+] Client Workstation optimization completed successfully!": "  [+] 客户端工作站优化成功完成!",
    "  [i] Try connecting to the shared printer now (e.g. \\\\ComputerName\\PrinterName).": "  [i] 现在尝试连接共享打印机(例如 \\\\电脑名\\打印机名)。",
    "  [i] If still prompted for password, save credentials via Menu 6 -> 1.": "  [i] 如果仍然提示输入密码,请通过菜单 6 -> 1 保存凭据。",
    "  [i] If error 0x709 persists, use Local Port UNC Mapping via Menu 7 -> 1.": "  [i] 如果错误 0x709 仍然存在,请通过菜单 7 -> 1 使用本地端口 UNC 映射。",
    "EXECUTING ALLFIX (50 AUTOMATED FIXES)": "正在执行 ALLFIX(50 项自动修复)",
    "  [*] [1/50] Detecting Operating System...": "  [*] [1/50] 正在检测操作系统...",
    "  [*] [2/50] Securing Registry Backup...": "  [*] [2/50] 正在安全备份注册表...",
    "  [*] [3/50] Refreshing Group Policy cache (gpupdate)...": "  [*] [3/50] 正在刷新组策略缓存 (gpupdate)...",
    "  [*] [4/50] Auditing & Initializing RPC / DCOM Services...": "  [*] [4/50] 正在审计并初始化 RPC / DCOM 服务...",
    "  [*] [5/50] Patching Error 0x0000011b (RpcAuthnLevelPrivacy)...": "  [*] [5/50] 正在修复错误 0x0000011b (RpcAuthnLevelPrivacy)...",
    "  [*] [6/50] Deep Fix Error 0x00000709 (Multi-Layer RPC & Point and Print)...": "  [*] [6/50] 正在深度修复错误 0x00000709(多层 RPC 与 Point and Print)...",
    "  [*] [7/50] Aligning KB5089549 Driver Policy & HKCU Permissions...": "  [*] [7/50] 正在对齐 KB5089549 驱动策略与 HKCU 权限...",
    "  [*] [8/50] Bypassing Error 0x00000bc4 (No Printers Found)...": "  [*] [8/50] 正在绕过错误 0x00000bc4(未找到打印机)...",
    "  [*] [9/50] Fixing Error 0x00000040 (KeepConn & Network Availability)...": "  [*] [9/50] 正在修复错误 0x00000040(KeepConn 与网络可用性)...",
    "  [*] [10/50] Fixing Error 0x00000002 (CopyFilesPolicy Driver Ingestion)...": "  [*] [10/50] 正在修复错误 0x00000002(CopyFilesPolicy 驱动载入)...",
    "  [*] [11/50] Fixing Error 0x0000007e (RPC Bitness Mismatch 32/64-bit)...": "  [*] [11/50] 正在修复错误 0x0000007e(RPC 位数不匹配 32/64 位)...",
    "  [*] [12/50] Enabling DnsOnWire, StrictNameChecking & UAC Token Filter Bypass...": "  [*] [12/50] 正在启用 DnsOnWire、StrictNameChecking 并绕过 UAC 令牌筛选...",
    "  [*] [13/50] Disabling SMB Signing Requirement (Fix Win 11 Access)...": "  [*] [13/50] 正在禁用 SMB 签名要求(修复 Win 11 访问)...",
    "  [*] [14/50] Enforcing Modern SMB2/SMB3 Compatibility & Provider Order...": "  [*] [14/50] 正在强制现代 SMB2/SMB3 兼容性与提供程序顺序...",
    "  [*] [15/50] Enforcing RPC via Named Pipes & TCP Pathways...": "  [*] [15/50] 正在通过命名管道与 TCP 路径强制 RPC...",
    "  [*] [16/50] Disabling Client-Side Rendering (CSR)...": "  [*] [16/50] 正在禁用客户端渲染 (CSR)...",
    "  [*] [17/50] Disabling Print Driver Isolation Policy...": "  [*] [17/50] 正在禁用打印驱动隔离策略...",
    "  [*] [18/50] Starting Discovery Services (mDNS, WSD, NetBIOS)...": "  [*] [18/50] 正在启动发现服务(mDNS、WSD、NetBIOS)...",
    "  [*] [19/50] Configuring Windows Firewall Rules for File & Printer Sharing...": "  [*] [19/50] 正在配置文件和打印机共享的防火墙规则...",
    "  [*] [20/50] Opening SMB Guest Access & Dropping Anonymous Blocks...": "  [*] [20/50] 正在开启 SMB 来宾访问并移除匿名阻止...",
    "  [*] [21/50] Disabling Password Protected Network Sharing...": "  [*] [21/50] 正在禁用密码保护的网络共享...",
    "  [*] [22/50] Aligning LSA Protection, NTLMv2 & Credential Guard...": "  [*] [22/50] 正在对齐 LSA 保护、NTLMv2 与凭据保护...",
    "  [*] [23/50] Bypassing Smart App Control (SAC) Driver Block...": "  [*] [23/50] 正在绕过智能应用控制 (SAC) 驱动阻止...",
    "  [*] [24/50] Initializing IPP & Mopria Print Sharing Foundation...": "  [*] [24/50] 正在初始化 IPP 与 Mopria 打印共享基础组件...",
    "  [*] [25/50] Disabling WPP (Allowing Legacy Network Printer Drivers)...": "  [*] [25/50] 正在禁用 WPP(允许传统网络打印机驱动)...",
    "  [*] [26/50] Configuring RDP Printer Redirection & LPD Protocols...": "  [*] [26/50] 正在配置 RDP 打印机重定向与 LPD 协议...",
    "  [*] [27/50] Forcing Network Connection Profiles to Private Mode...": "  [*] [27/50] 正在强制网络连接配置文件为“专用”模式...",
    "  [*] [28/50] Deprioritizing Hyper-V / WSL Virtual Network Adapters...": "  [*] [28/50] 正在降低 Hyper-V / WSL 虚拟网络适配器优先级...",
    "  [*] [29/50] Flushing DNS Cache & Resetting Network Winsock...": "  [*] [29/50] 正在刷新 DNS 缓存并重置网络 Winsock...",
    "  [*] [30/50] Stopping Print Spooler Service...": "  [*] [30/50] 正在停止后台打印程序服务...",
    "  [*] [31/50] Configuring Spooler Auto-Restart on Failure...": "  [*] [31/50] 正在配置后台打印程序故障自动重启...",
    "  [*] [32/50] Purging Stale Spooler Dependencies (http & RPCSS)...": "  [*] [32/50] 正在清理过时的后台打印程序依赖项(http 与 RPCSS)...",
    "  [*] [33/50] Resetting PRINTERS Folder Permissions (Universal SID)...": "  [*] [33/50] 正在重置 PRINTERS 文件夹权限(通用 SID)...",
    "  [*] [34/50] Purging Stale Spooler Queue & Splwow64 Handles...": "  [*] [34/50] 正在清理过时的后台打印程序队列与 Splwow64 句柄...",
    "  [*] [35/50] Bypassing AppContainer Loopback for Edge & UWP Apps...": "  [*] [35/50] 正在绕过 Edge 与 UWP 应用的 AppContainer 回环...",
    "  [*] [36/50] Applying Advanced Point & Print Elevation Overrides...": "  [*] [36/50] 正在应用高级 Point and Print 提升覆盖...",
    "  [*] [37/50] Deploying Spooler Watchdog Scheduled Task...": "  [*] [37/50] 正在部署后台打印程序守护计划任务...",
    "  [*] [38/50] Restarting Background Intelligent Transfer Service (BITS)...": "  [*] [38/50] 正在重启后台智能传输服务 (BITS)...",
    "  [*] [39/50] Verifying Spooler Status...": "  [*] [39/50] 正在验证后台打印程序状态...",
    "  [+] Print Spooler validated operational.": "  [+] 后台打印程序已验证正常运行。",
    "  [*] [40/50] Purging Kerberos Ticket Cache...": "  [*] [40/50] 正在清理 Kerberos 票证缓存...",
    "  [*] [41/50] Restarting System Diagnostic Service (WdiSystemHost)...": "  [*] [41/50] 正在重启系统诊断服务 (WdiSystemHost)...",
    "  [*] [42/50] Registering Multicast DNS...": "  [*] [42/50] 正在注册多播 DNS...",
    "  [*] [43/50] Generating System Restore Point...": "  [*] [43/50] 正在创建系统还原点...",
    "  [*] [44/50] Scanning & Optimizing V4 Print Class Drivers...": "  [*] [44/50] 正在扫描并优化 V4 打印类驱动...",
    "  [*] [45/50] Securing Network Connection Profile to Private...": "  [*] [45/50] 正在将网络连接配置文件设为“专用”...",
    "  [*] [46/50] Forcibly Purging Corrupt Print Queue Files (.spl/.shd)...": "  [*] [46/50] 正在强制清理损坏的打印队列文件 (.spl/.shd)...",
    "  [*] [47/50] Resetting Spooler Registry Dependencies...": "  [*] [47/50] 正在重置后台打印程序注册表依赖项...",
    "  [*] [48/50] Sanitizing Printer Share Names (Removing illegal characters)...": "  [*] [48/50] 正在清理打印机共享名称(移除非法字符)...",
    "  [*] [49/50] Deploying Post-Update Auto-Reapply Scheduled Task...": "  [*] [49/50] 正在部署更新后自动重新应用计划任务...",
    "  [*] [50/50] Parsing PrintService Event Log & Final Spooler Validation...": "  [*] [50/50] 正在解析打印服务事件日志并最终验证后台打印程序...",
    "  [+] All validations passed. Print Spooler running smoothly.": "  [+] 所有验证通过,后台打印程序运行正常。",
    "ALLFIX CONCLUDED": "ALLFIX 完成",
    "    [+] ALLFIX COMPLETED! REBOOTING SYSTEM IN 3 SECONDS...": "    [+] ALLFIX 已完成!系统将在 3 秒后重启...",
    "   [?] View execution error logs? (Y/N)": "   [?] 查看执行错误日志?(Y/N)",
    "`n   --- ERROR SCAN RESULTS ---": "`n   --- 错误扫描结果 ---",
    "   [+] No errors recorded in log file.": "   [+] 日志文件中没有错误记录。",
    "   [?] Execute immediate system reboot? (Y/N)": "   [?] 立即重启系统?(Y/N)",
    "  [*] Proceeding, rebooting in 5 seconds...": "  [*] 正在继续,5 秒后重启...",
    "  [*] Reboot manually to apply all security changes.": "  [*] 请手动重启以应用所有安全更改。",
    "        EXTREME PATH FOR WIN 11 24H2 / 25H2 / 26H2+ & ARM64": "        Windows 11 24H2 / 25H2 / 26H2+ 及 ARM64 深度修复方案",
    "  [*] Applying deep policy modifications for strict security Windows 11 environments.": "  [*] 正在为安全策略严格的 Windows 11 环境应用深度策略修改。",
    "  [*] Running all automated fixes...": "  [*] 正在运行所有自动修复...",
    "Run Extreme Fix 24H2/25H2/26H2": "运行 Windows 11 24H2/25H2/26H2 深度修复",
    "  [*] Flushing GPO cache before applying fixes...": "  [*] 应用修复前正在刷新组策略缓存...",
    "Extreme Path completed!": "深度修复方案完成!",
    "  [+] Extreme security changes completed. System reboot is recommended.": "  [+] 深度安全更改已完成,建议重启系统。",
    "`n   [?] Execute immediate system reboot now? (Y/N)": "`n   [?] 立即重启系统吗?(Y/N)",
    "             WINDOWS & ARCHITECTURE DETECTION": "             系统版本与架构检测",
    "  [+] OS Version    : $script:productName": "  [+] 系统版本    : $script:productName",
    "  [+] OS Build      : $script:buildNumber": "  [+] 系统构建    : $script:buildNumber",
    "  [+] Architecture  : ARM64 (Snapdragon / Apple Silicon VM)": "  [+] 系统架构    : ARM64 (Snapdragon / Apple Silicon VM)",
    "  [+] Architecture  : AMD64 / x64 (64-Bit)": "  [+] 系统架构    : AMD64 / x64 (64 位)",
    "  [+] Edition       : Windows Server Edition": "  [+] 系统版本    : Windows Server 版",
    "  [+] Edition       : Windows Client (Home / Pro / Enterprise)": "  [+] 系统版本    : Windows 客户端版(家庭版 / 专业版 / 企业版)",
    "  [*] Opening HTML documentation in browser...": "  [*] 正在浏览器中打开 HTML 文档...",
    "  [-] documentation.html not found in installation directory.": "  [-] 安装目录中未找到 documentation.html。",
    "  [!] Use '?' for quick help or '? <number>' for specific module info.": "  [!] 使用 '?' 查看快速帮助,或用 '? <编号>' 查看具体模块信息。",
    "      MODULE INFORMATION [$Topic]": "      模块信息 [$Topic]",
    "  MODULE NAME : $($h[0])": "  模块名称 : $($h[0])",
    "  FUNCTION    : $($h[1])": "  功能说明 : $($h[1])",
    "  USAGE       : $($h[2])": "  适用场景 : $($h[2])",
    "  [-] Module number '$Topic' not found. Enter a number between 1 and 89.": "  [-] 找不到模块编号 '$Topic'。请输入 1 到 89 之间的数字。",
    "1. Quick & Automated Solutions (ALLFIX & Modern Win 11)": "1. 快速与自动化解决方案(ALLFIX 与现代 Win 11)",
    "  [-] Invalid choice.": "  [-] 选择无效。",
    "2. Fix Specific Error Codes (0x11b, 0x709, 0xbc4, 0x040, etc.)": "2. 修复特定错误代码(0x11b、0x709、0xbc4、0x040 等)",
    "3. Network, File & Printer Sharing (SMB) & Firewall": "3. 网络、文件和打印机共享(SMB)与防火墙",
    "`n  [*] Applying passwordless sharing & guest access permissions...": "`n  [*] 正在应用无密码共享与来宾访问权限...",
    "4. Print Spooler Service & Print Queue Maintenance": "4. 后台打印程序服务与打印队列维护",
    "5. Driver Management & Ghost / USB Printer Cleanup": "5. 驱动管理与幽灵 / USB 打印机清理",
    "  [+] Driver Isolation Disabled.": "  [+] 驱动隔离已禁用。",
    "6. Credentials, Access Rights & Security (Vault, LSA, UAC)": "6. 凭据、访问权限与安全(Vault、LSA、UAC)",
    "7. Port Mapping & Manual Connections (UNC Port Map & TCP/IP)": "7. 端口映射与手动连接(UNC 端口映射与 TCP/IP)",
    "8. Backup, System Diagnostics & Recovery": "8. 备份、系统诊断与恢复",
    "9. Help & Usage Guide": "9. 帮助与使用指南",
    "  EXECUTING REPAIR MODULE [$Code]": "  正在执行修复模块 [$Code]",
    "Application terminated.": "应用程序已终止。",
    "  [-] Module [$Code] not found. Enter valid code (1-89).": "  [-] 找不到模块 [$Code]。请输入有效代码 (1-89)。",
}

# 内联转换: $(if ($isEN) { "EN" } else { "ID" })
def inline_repl(m):
    en = m.group(1)
    id_ = m.group(2)
    zh = INLINE_ZH.get(en, '【待翻译】' + en)
    return ('$(switch ($script:lang) '
            '{ "ZH" { "%s" } "EN" { "%s" } default { "%s" } })' % (zh, en, id_))

pat_inline = re.compile(r'\$\(if \(\$isEN\) \{ "((?:[^"\\]|\\.)*)" \} else \{ "((?:[^"\\]|\\.)*)" \}\)')
content, n1 = pat_inline.subn(inline_repl, content)
print(f"[2/5] 内联转换: {n1} 处")

# 变量赋值转换: $x = if ($isEN) { "EN" } else { "ID" }
def var_repl(m):
    var = m.group(1)
    en = m.group(2)
    id_ = m.group(3)
    zh = INLINE_ZH.get(en, '【待翻译】' + en)
    return ('%sswitch ($script:lang) { "ZH" { "%s" } "EN" { "%s" } default { "%s" } }'
            % (var, zh, en, id_))

pat_var = re.compile(r'(\w+ = )if \(\$isEN\) \{ "((?:[^"\\]|\\.)*)" \} else \{ "((?:[^"\\]|\\.)*)" \}')
content, n2 = pat_var.subn(var_repl, content)
print(f"[3/5] 变量赋值转换: {n2} 处")

with open(SRC, 'w', encoding='utf-8') as f:
    f.write(content)
print("中间结果已保存(多行块待第二步处理)")