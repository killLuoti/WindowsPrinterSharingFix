[Setup]
AppName=Windows 打印机共享修复工具
AppVersion=2.4.0
AppPublisher=killLuoti
AppPublisherURL=https://github.com/killLuoti/WindowsPrinterSharingFix
AppSupportURL=https://github.com/killLuoti/WindowsPrinterSharingFix/issues
DefaultDirName={autopf}\Windows打印机共享修复工具
DefaultGroupName=Windows 打印机共享修复工具
OutputDir=..\release
OutputBaseFilename=WindowsPrinterSharingFix_CN_Installer
Compression=lzma
SolidCompression=yes
SetupIconFile=..\assets\icon.ico
UninstallDisplayIcon={app}\icon.ico
UninstallDisplayName=Windows 打印机共享修复工具
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
DisableWelcomePage=no
VersionInfoCompany=killLuoti
VersionInfoProductName=Windows 打印机共享修复工具
VersionInfoProductVersion=2.4.0.0
VersionInfoVersion=2.4.0.0
VersionInfoDescription=Windows 打印机共享修复工具 安装程序(中/英/印尼三语)

[Files]
Source: "..\release\WindowsPrinterSharingFix_CN.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\icon.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\documentation.html"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\killLuoti_cert.cer"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Windows 打印机共享修复工具"; Filename: "{app}\WindowsPrinterSharingFix_CN.exe"; IconFilename: "{app}\icon.ico"
Name: "{group}\Windows 打印机共享修复工具 文档"; Filename: "{app}\documentation.html"
Name: "{autodesktop}\Windows 打印机共享修复工具"; Filename: "{app}\WindowsPrinterSharingFix_CN.exe"; Tasks: desktopicon; IconFilename: "{app}\icon.ico"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{sys}\certutil.exe"; Parameters: "-addstore TrustedPublisher ""{app}\killLuoti_cert.cer"""; Flags: runhidden waituntilterminated; StatusMsg: "正在安装发布者证书..."
Filename: "{sys}\certutil.exe"; Parameters: "-addstore Root ""{app}\killLuoti_cert.cer"""; Flags: runhidden waituntilterminated; StatusMsg: "正在将证书安装到受信任根..."

[UninstallRun]
Filename: "{sys}\certutil.exe"; Parameters: "-delstore TrustedPublisher ""killLuoti"""; Flags: runhidden; RunOnceId: "DelTrustedPub"
Filename: "{sys}\certutil.exe"; Parameters: "-delstore Root ""killLuoti"""; Flags: runhidden; RunOnceId: "DelRoot"