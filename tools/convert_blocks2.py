#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第二步:处理多行 if($isEN){...}else{...} 块 -> switch 三态
以及 helpData 逻辑三语化
关键修复:所有输出行带 \n
"""
import re

SRC = 'src/WindowsPrinterSharingFix.ps1'

# 多行块菜单翻译映射 (EN -> ZH)
MENU_ZH = {
    # 帮助指南 (块3126)
    "      USER GUIDE: Windows Printer Sharing Fix - @KHAIRUDINFAHMI": "      使用指南:Windows 打印机共享修复工具 - @KHAIRUDINFAHMI",
    "  ======================================================================================": "  ======================================================================================",
    " ": " ",
    "  HOW TO USE THIS UTILITY:": "  使用方法:",
    "    - Choose a category number (1 - 9) to open targeted repair submenus.": "    - 输入分类编号 (1 - 9) 打开对应的修复子菜单。",
    "    - You can also type classic module codes directly (e.g. '84', '83', '64', '86').": "    - 也可以直接输入经典模块代码(例如 '84'、'83'、'64'、'86')。",
    "    - Type 'L' at any time to switch language between Indonesian and English.": "    - 随时输入 'L' 可在 简体中文 / English / Bahasa Indonesia 之间切换语言。",
    "    - Type '?' to view this guide at any time.": "    - 随时输入 '?' 可查看本指南。",
    "    - Type '? <number>' (e.g. '? 84' or '? 86') to view details of any module.": "    - 输入 '? <编号>' (例如 '? 84' 或 '? 86') 可查看任一模块的详细说明。",
    "    - Type '? all' to open complete HTML documentation in your default browser.": "    - 输入 '? all' 可在默认浏览器中打开完整 HTML 文档。",
    "  RECOMMENDED STEPS FOR OFFICE WORKSTATIONS (Standard Flow):": "  办公电脑推荐步骤(标准流程):",
    "    1. Run Backup Registry [Menu 8 -> 1 or type 64] (Highly Recommended)": "    1. 备份注册表 [菜单 8 -> 1 或输入 64](强烈推荐)",
    "    2. Run ALLFIX [Menu 1 -> 1 or type 84] (Applies 50 automated fixes)": "    2. 运行 ALLFIX [菜单 1 -> 1 或输入 84](执行 50 项自动修复)",
    "    3. Restart your computer [Menu 0 or type 88]": "    3. 重启电脑 [菜单 0 或输入 88]",
    "    4. Connect to your shared network printer again.": "    4. 重新连接共享网络打印机。",
    "  STEPS FOR MODERN WINDOWS 11 24H2 / 25H2 / 26H2+ (Build 26000 and above):": "  适用于 Windows 11 24H2 / 25H2 / 26H2+ 及以上版本 (Build 26000+):",
    "    1. Run Backup Registry [Menu 8 -> 1 or type 64]": "    1. 备份注册表 [菜单 8 -> 1 或输入 64]",
    "    2. Run Win 11 Solution [Menu 1 -> 2 or type 83]": "    2. 运行 Windows 11 专属方案 [菜单 1 -> 2 或输入 83]",
    "    3. Restart your computer.": "    3. 重启电脑。",
    "  QUICK TROUBLESHOOTING CHEATSHEET:": "  快速故障排查速查表:",
    "    - Continuously asking for password? -> Run Menu 3 -> 2 (or type 12 & 82)": "    - 一直提示输入密码?-> 运行菜单 3 -> 2(或输入 12 和 82)",
    "    - 'Access Denied' error message?     -> Save Credentials via Menu 6 -> 1 (type 60)": "    - 提示“拒绝访问”(Access Denied)?-> 通过菜单 6 -> 1 保存凭据(输入 60)",
    "    - 'Check Printer Name' / Error 0x709? -> Map Local Port UNC via Menu 7 -> 1 (type 86)": "    - 提示“检查打印机名称”/ 错误 0x709?-> 通过菜单 7 -> 1 映射本地端口 UNC(输入 86)",
    "    - Printer stuck in offline status?   -> Force Online via Menu 8 -> 10 (type 71)": "    - 打印机一直处于离线状态?-> 通过菜单 8 -> 10 强制设为在线(输入 71)",
    "    - Computer not visible in Network?   -> Run Menu 3 -> 1 & Menu 3 -> 5": "    - 网络中看不到电脑?-> 运行菜单 3 -> 1 和菜单 3 -> 5",
    "    - Want to restore previous settings? -> Run Registry Rollback via Menu 8 -> 2 (type 65)": "    - 想恢复之前的设置?-> 通过菜单 8 -> 2 运行注册表回滚(输入 65)",
    # 子菜单1 (块3340)
    "  [1] ALLFIX - Run 50 Automated Fixes Simultaneously": "  [1] ALLFIX - 同时运行 50 项自动修复",
    "      (Most reliable one-click fix for almost all network printer problems)": "      (解决几乎所有网络打印机问题的最可靠一键修复)",
    "  [2] Extreme Path for Modern Windows 11 (24H2 / 25H2 / 26H2 & ARM64)": "  [2] 现代 Windows 11 深度修复方案 (24H2 / 25H2 / 26H2 及 ARM64)",
    "      (Bypasses RPC restrictions, SMB Signing, and new Win 11 security policies)": "      (绕过 RPC 限制、SMB 签名和 Win 11 新安全策略)",
    "  [3] Optimize Host / Print Server PC (Connected directly to printer)": "  [3] 优化主机 / 打印服务器电脑(直接连接打印机的电脑)",
    "      (Enforce remote RPC endpoint, Private network, guest sharing, and watchdog)": "      (启用远程 RPC 端点、专用网络、来宾共享和自动监视)",
    "  [4] Optimize Client PC (Connecting to shared printer over network)": "  [4] 优化客户端电脑(通过网络连接共享打印机的电脑)",
    "      (RPC Named Pipes, Point and Print bypass, SMB signing fix, HKCU permissions)": "      (RPC 命名管道、Point and Print 绕过、SMB 签名修复、HKCU 权限)",
    "  [5] Silent ALLFIX (Automated Fixes + Immediate Reboot)": "  [5] 静默 ALLFIX(自动修复 + 立即重启)",
    "      (For technicians/unattended deployment - WARNING: PC reboots immediately!)": "      (适合技术人员/无人值守部署 - 警告:电脑会立即重启!)",
    "  [6] Manage Windows Updates & Block Printer-Breaking Patches": "  [6] 管理 Windows 更新并阻止破坏打印机的补丁",
    "      (Pause updates 35 days, uninstall bad patches, prevent setting reverts)": "      (暂停更新 35 天、卸载问题补丁、防止设置被还原)",
    "  [L] Switch Language / Ganti Bahasa": "  [L] 切换语言 / Switch Language",
    "  [B] Back to Main Menu": "  [B] 返回主菜单",
    "Select option [1-6], L, or B: ": "请选择 [1-6], L 或 B: ",
    # 子菜单2 (块3406)
    "  [1] Error 0x0000011b - Patch RPC Authentication Block (RpcAuthnLevelPrivacy)": "  [1] 错误 0x0000011b - 修复 RPC 身份验证阻止 (RpcAuthnLevelPrivacy)",
    "  [2] Error 0x00000709 / 0x7c - Network Printer Connection Failure (Point and Print / RPC)": "  [2] 错误 0x00000709 / 0x7c - 网络打印机连接失败 (Point and Print / RPC)",
    "  [3] Error 0x00000bc4 - No Printers Were Found (Enforce RPC Named Pipes)": "  [3] 错误 0x00000bc4 - 未找到打印机(强制启用 RPC 命名管道)",
    "  [4] Error 0x80070035 - Network Path Not Found (Initialize Discovery Services)": "  [4] 错误 0x80070035 - 找不到网络路径(初始化发现服务)",
    "  [5] Error 0x000006d1 - Disable Client-Side Rendering (CSR)": "  [5] 错误 0x000006d1 - 禁用客户端渲染 (CSR)",
    "  [6] Error 0x80070005 - Access Denied to Spooler Folder (Reset Universal ACL Permissions)": "  [6] 错误 0x80070005 - 无法访问 Spooler 文件夹(重置通用 ACL 权限)",
    "  [7] Error 0x00000040 - Network Name Is No Longer Available (KeepConn & Ports)": "  [7] 错误 0x00000040 - 网络名称不再可用(KeepConn 与端口)",
    "  [8] Error 0x00000002 - Driver File Copy Policy Block (CopyFilesPolicy Ingestion)": "  [8] 错误 0x00000002 - 驱动文件复制策略阻止(CopyFilesPolicy 载入)",
    "  [9] Error 0x0000007e - RPC Driver Bitness Mismatch (32-bit & 64-bit Systems)": "  [9] 错误 0x0000007e - RPC 驱动位数不匹配(32 位与 64 位系统)",
    "Select error number [1-9], L, or B: ": "请选择错误编号 [1-9], L 或 B: ",
    # 子菜单3 (块3465)
    "  [1] Switch Network Profile to Private (Required for printer sharing)": "  [1] 将网络配置文件切换为“专用”(打印机共享必需)",
    "  [2] Open Passwordless Sharing (Guest Access & Anonymous Sharing)": "  [2] 开启无密码共享(来宾访问与匿名共享)",
    "      (Combines guest permissions and eliminates password-protected sharing)": "      (合并来宾权限并取消密码保护的共享)",
    "  [3] Disable SMB Signing Requirement (Fix Win 11 connection to Printer/NAS)": "  [3] 禁用 SMB 签名要求(修复 Win 11 连接打印机/NAS 失败)",
    "  [4] Manage SMB Protocols (Ensure Modern SMB2/SMB3 & SMB 1.0 Settings)": "  [4] 管理 SMB 协议(确保现代 SMB2/SMB3 及 SMB 1.0 设置)",
    "  [5] Open Windows Firewall Rules for File & Printer Sharing (Including WSD Port 3702)": "  [5] 开放文件和打印机共享的防火墙规则(包括 WSD 端口 3702)",
    "  [6] Enable Automatic Device Discovery (mDNS, LLMNR, and WSD Discovery)": "  [6] 启用自动设备发现(mDNS、LLMNR 和 WSD 发现)",
    "  [7] Set Network Provider Order & Resolve Virtual Hyper-V/WSL Conflicts": "  [7] 设置网络提供程序顺序并解决 Hyper-V/WSL 虚拟冲突",
    "  [8] Total Network & Socket Reset (Winsock, Flush DNS, NetBIOS & Port Purge)": "  [8] 完全重置网络与套接字(Winsock、刷新 DNS、NetBIOS 与端口清理)",
    "  [9] Disable IPv6 Protocol Stack (Use if office LAN is pure IPv4)": "  [9] 禁用 IPv6 协议栈(办公局域网为纯 IPv4 时使用)",
    "  [10] Install IPP / Mopria Sharing Foundation & Legacy LPR/LPD Protocols": "  [10] 安装 IPP / Mopria 共享基础组件与传统 LPR/LPD 协议",
    "Select option [1-10], L, or B: ": "请选择 [1-10], L 或 B: ",
    # 子菜单4 (块3558)
    "  [1] Clean Spooler Reset & Purge Jammed Print Queue Files (.spl/.shd)": "  [1] 干净重置后台打印程序并清理卡住的打印队列文件 (.spl/.shd)",
    "      (Stops spooler, removes locked documents, and cleanly restarts service)": "      (停止后台打印程序、移除锁定文档并干净重启服务)",
    "  [2] Configure Automatic Spooler Recovery on Crash (Auto-Restart)": "  [2] 配置后台打印程序崩溃时自动恢复(自动重启)",
    "  [3] Deploy Spooler Watchdog Scheduled Task (Monitors every 5 minutes)": "  [3] 部署后台打印程序守护计划任务(每 5 分钟监视一次)",
    "  [4] Repair & Reset Spooler Registry Dependencies (RPCSS & HTTP)": "  [4] 修复并重置后台打印程序的注册表依赖项(RPCSS 与 HTTP)",
    "  [5] Restart Core System RPC & DCOM Services": "  [5] 重启核心系统 RPC 与 DCOM 服务",
    "  [6] Restart Remote Spooler Service on Target Computer": "  [6] 重启目标电脑上的远程后台打印程序服务",
    "Select option [1-6], L, or B: ": "请选择 [1-6], L 或 B: ",
    # 子菜单5 (块3618)
    "  [1] Force-Kill Locking Driver Processes ('Driver is in use')": "  [1] 强制结束锁定驱动的进程(“驱动程序正在使用中”)",
    "  [2] Disable Print Driver Isolation (Prevent separate process crashes)": "  [2] 禁用打印驱动程序隔离(防止单独进程崩溃)",
    "  [3] Clean Stale & Corrupted Drivers (Driver Sweeper via pnputil)": "  [3] 清理过时与损坏的驱动程序(通过 pnputil 清理驱动)",
    "  [4] Remove Ghost & Duplicate USB Printers (Copy 1, Copy 2, dead ports)": "  [4] 移除幽灵与重复的 USB 打印机(Copy 1、Copy 2、失效端口)",
    "  [5] Repair Universal V4 Print Class Drivers & Switch PCL / PostScript Mode": "  [5] 修复通用 V4 打印类驱动并切换 PCL / PostScript 模式",
    "  [6] Fix Web Browser Printing (Chrome/Edge Sandbox & Modern UWP Apps)": "  [6] 修复浏览器打印问题(Chrome/Edge 沙箱与现代 UWP 应用)",
    "  [7] Reinstall Windows Virtual Built-in Printers (Microsoft Print to PDF / XPS)": "  [7] 重装 Windows 内置虚拟打印机(Microsoft Print to PDF / XPS)",
    "  [8] Lock Default Printer Permanently (Prevent automatic location switching)": "  [8] 永久锁定默认打印机(防止自动切换位置)",
    "  [9] Sanitize Printer Share Names (Strip spaces and illegal characters)": "  [9] 清理打印机共享名称(去除空格与非法字符)",
    "  [10] Open Print Server Properties Management Console": "  [10] 打开打印服务器属性管理控制台",
    "  [11] Force-Uninstall Specific Problematic Printer": "  [11] 强制卸载指定的问题打印机",
    "Select option [1-11], L, or B: ": "请选择 [1-11], L 或 B: ",
    # 子菜单6 (块3699)
    "  [1] Save Printer Credentials (Username & Password) to Windows Vault": "  [1] 将打印机凭据(用户名与密码)保存到 Windows 凭据管理器",
    "  [2] Clean Stale/Outdated Printer Credentials from Windows Vault": "  [2] 清理 Windows 凭据管理器中过期/失效的打印机凭据",
    "  [3] Deploy Login Credentials to All User Profiles on This Machine": "  [3] 将登录凭据部署到此电脑的所有用户配置文件",
    "  [4] Bypass Administrator UAC Network Token Filter for Workgroups": "  [4] 为工作组绕过管理员 UAC 网络令牌筛选",
    "  [5] Align NTLMv2 Authentication Response (LmCompatibilityLevel)": "  [5] 对齐 NTLMv2 身份验证响应(LmCompatibilityLevel)",
    "  [6] Relax Strict Security Protections (LSA Protection, Smart App Control, Credential Guard)": "  [6] 放宽严格安全保护(LSA 保护、智能应用控制、凭据保护)",
    "  [7] Manage Windows Protected Print / WPP (Win 11 Driver Mode)": "  [7] 管理 Windows 受保护打印 / WPP(Win 11 驱动模式)",
    "  [8] Bypass Point and Print Driver Restrictions (Elevation Override)": "  [8] 绕过 Point and Print 驱动限制(提升覆盖)",
    "  [9] Fix Printer Redirection on Remote Desktop Connections (RDP)": "  [9] 修复远程桌面连接 (RDP) 上的打印机重定向",
    "Select option [1-9], L, or B: ": "请选择 [1-9], L 或 B: ",
    # 子菜单7 (块3763)
    "  [1] Map Local Port to UNC Share (Ultimate Bypass for Error 0x00000709)": "  [1] 将本地端口映射到 UNC 共享(错误 0x00000709 的终极绕过方案)",
    "      (Example: connects local port directly to \\\\SERVER\\PRINTER)": "      (示例:将本地端口直接连接到 \\\\服务器\\打印机 )",
    "  [2] Remove Previously Created Local UNC Port Mapping": "  [2] 移除之前创建的本地 UNC 端口映射",
    "  [3] Convert WSD Printer Port to Stable Standard TCP/IP Socket": "  [3] 将 WSD 打印机端口转换为稳定的标准 TCP/IP 套接字",
    "  [4] Add Standard TCP/IP Printer Port Manually": "  [4] 手动添加标准 TCP/IP 打印机端口",
    "  [5] Scan & Discover Shared Printers on Remote Network Host": "  [5] 扫描并发现远程网络主机上的共享打印机",
    "Select option [1-5], L, or B: ": "请选择 [1-5], L 或 B: ",
    # 子菜单8 (块3812)
    "  [1] Backup Printer & Network Registry (Always Recommended Before Fixes)": "  [1] 备份打印机与网络注册表(修复前始终建议执行)",
    "  [2] Rollback Registry from Previous Backup Snapshot": "  [2] 从之前的备份快照回滚注册表",
    "  [3] Create System Restore Point for System Rollback": "  [3] 创建系统还原点以便系统回滚",
    "  [4] Scan & Repair System Files (SFC /scannow & DISM)": "  [4] 扫描并修复系统文件(SFC /scannow 与 DISM)",
    "  [5] Test Network Connectivity & Scan Ports (Ping & Port 135/445)": "  [5] 测试网络连接并扫描端口(Ping 与端口 135/445)",
    "  [6] Audit & Analyze Print Service Event Logs (Event Log Parser)": "  [6] 审计与分析打印服务事件日志(事件日志解析器)",
    "  [7] Generate Interactive HTML Diagnostic Report": "  [7] 生成交互式 HTML 诊断报告",
    "  [8] Scan Active Directory Domain Policy / GPO Intervention": "  [8] 扫描 Active Directory 域策略 / GPO 干预",
    "  [9] Backup & Migrate Printers to Another Computer (PrintBRM)": "  [9] 备份并将打印机迁移到另一台电脑(PrintBRM)",
    "  [10] Force Printer Status to 'Online' (If stuck offline)": "  [10] 强制打印机状态为“在线”(如果卡在离线状态)",
    "  [11] Open Windows Services Console (services.msc)": "  [11] 打开 Windows 服务控制台 (services.msc)",
    "  [12] Open Repair Execution Log File (Log Manager)": "  [12] 打开修复执行日志文件(日志管理器)",
    "  [13] Quick System Diagnostics Audit": "  [13] 快速系统诊断审计",
    "Select option [1-13], L, or B: ": "请选择 [1-13], L 或 B: ",
    # 子菜单9 (块3887)
    "  [1] Show Quick Guide & Office Troubleshooting Flow": "  [1] 显示快速指南与办公故障排查流程",
    "  [2] Open Offline HTML Documentation in Browser": "  [2] 在浏览器中打开离线 HTML 文档",
    "  [3] Detect Current Windows Version & Architecture": "  [3] 检测当前 Windows 版本与架构",
    "  [4] Run Windows Built-in Printer Troubleshooter (msdt)": "  [4] 运行 Windows 内置打印机故障排除程序 (msdt)",
    "Select option [1-4], L, or B: ": "请选择 [1-4], L 或 B: ",
}

with open(SRC, encoding='utf-8') as f:
    lines = f.readlines()

def extract_str(line):
    m = re.search(r'Write-Host "((?:[^"\\]|\\.)*)"', line)
    return m.group(1) if m else None

def convert_block(start, else_line, end, en_lines, id_lines):
    """将 if($isEN){EN}else{ID} 块转为 switch 三态,每行带 \\n"""
    indent = re.match(r'\s*', lines[start]).group(0)
    out = []
    out.append(f'{indent}switch ($script:lang) {{\n')
    out.append(f'{indent}    "ZH" {{\n')
    for en_l in en_lines:
        s = extract_str(en_l)
        if s is not None and s in MENU_ZH:
            body = en_l.replace(s, MENU_ZH[s], 1).strip()
        else:
            body = en_l.strip()
        out.append(f'{indent}        {body}\n')
    out.append(f'{indent}    }}\n')
    out.append(f'{indent}    "EN" {{\n')
    for en_l in en_lines:
        out.append(f'{indent}        {en_l.strip()}\n')
    out.append(f'{indent}    }}\n')
    out.append(f'{indent}    default {{\n')
    for id_l in id_lines:
        out.append(f'{indent}        {id_l.strip()}\n')
    out.append(f'{indent}    }}\n')
    out.append(f'{indent}}}\n')
    return out

new_lines = []
i = 0
converted = 0
missing = []
while i < len(lines):
    if re.match(r'\s*if \(\$isEN\) \{', lines[i]) and '} else {' not in lines[i]:
        start = i
        j = i + 1
        en_lines = []
        while j < len(lines) and '} else {' not in lines[j]:
            if 'Write-Host' in lines[j]:
                en_lines.append(lines[j])
            j += 1
        else_line = j
        k = j + 1
        id_lines = []
        depth = 1
        while k < len(lines):
            if 'Write-Host' in lines[k]:
                id_lines.append(lines[k])
            if re.match(r'\s*\}', lines[k]):
                depth -= 1
                if depth == 0:
                    break
            k += 1
        # 统计缺失翻译
        for en_l in en_lines:
            s = extract_str(en_l)
            if s and s not in MENU_ZH:
                missing.append((start + 1, s[:70]))
        new_lines.extend(convert_block(start, else_line, k, en_lines, id_lines))
        converted += 1
        i = k + 1
    else:
        new_lines.append(lines[i])
        i += 1

with open(SRC, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print(f"多行块转换: {converted} 个")
if missing:
    print(f"⚠ {len(missing)} 条未翻译:")
    for ln, s in missing:
        print(f"  行{ln}: {s}")
else:
    print("✓ 所有菜单文本均已翻译")