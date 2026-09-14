$ProjectRoot = Split-Path $PSScriptRoot -Parent

$SourceFile = Join-Path $ProjectRoot "src\WindowsPrinterSharingFix.ps1"
$OutputDir  = Join-Path $ProjectRoot "release"
$OutputFile = Join-Path $OutputDir "WindowsPrinterSharingFix_CN.exe"
$IconFile   = Join-Path $ProjectRoot "assets\icon.ico"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not (Test-Path $SourceFile)) {
    Write-Host "[ERROR] Source file not found: $SourceFile" -ForegroundColor Red
    Write-Host "Ensure the script is executed from within the WindowsPrinterSharingFix project directory." -ForegroundColor Yellow
    exit 1
}

Write-Host "Verifying PS2EXE module..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "PS2EXE module not installed. Installing..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-Module -Name ps2exe -Force -Scope CurrentUser -AllowClobber
}

Write-Host "PS2EXE module found." -ForegroundColor Green
Write-Host "Compiling $SourceFile to $OutputFile..." -ForegroundColor Cyan

$ps2exeParams = @{
    inputFile   = $SourceFile
    outputFile  = $OutputFile
    requireAdmin = $true
    title       = "Windows 打印机共享修复工具"
    description = "Windows 打印机共享修复工具(中/英/印尼三语)"
    version     = "2.4.0.0"
    company     = "killLuoti"
    copyright   = "2026 killLuoti | 基于 khairudinfahmi 原版汉化"
}

if (Test-Path $IconFile) {
    $ps2exeParams.iconFile = $IconFile
}

try {
    Invoke-ps2exe @ps2exeParams
    
    Write-Host "`n编译成功!" -ForegroundColor Green
    Write-Host "EXE 文件已生成: $OutputFile" -ForegroundColor Cyan
    
    $docSource = Join-Path $ProjectRoot "docs\documentation.html"
    $docDest = Join-Path $OutputDir "documentation.html"
    if (Test-Path $docSource) {
        Copy-Item $docSource $docDest -Force
        Write-Host "文档已打包: $docDest" -ForegroundColor Green
    }
    
    Write-Host "正在进行代码签名..." -ForegroundColor Magenta
    $certName = "killLuoti"
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object Subject -match $certName | Select-Object -First 1
    
    if (-not $cert) {
        Write-Host "未找到代码签名证书 '$certName',正在生成新证书..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate -Subject "CN=$certName" -Type CodeSigningCert -CertStoreLocation "Cert:\CurrentUser\My"
        Write-Host "新证书已生成。" -ForegroundColor Green
    }
    
    $cerExportPath = Join-Path $ProjectRoot "assets\killLuoti_cert.cer"
    Export-Certificate -Cert $cert -FilePath $cerExportPath -Force | Out-Null
    Write-Host "证书文件已导出: $cerExportPath" -ForegroundColor Cyan
    
    Write-Host "正在为 $OutputFile 注入数字签名..." -ForegroundColor Cyan
    $sig = Set-AuthenticodeSignature -FilePath $OutputFile -Certificate $cert -TimestampServer "http://timestamp.sectigo.com"
    
    if ($sig.Status -eq "Valid" -or $sig.Status -eq "UnknownError") {
        Write-Host "签名注入成功!(状态: $($sig.Status))" -ForegroundColor Green
    } else {
        Write-Host "签名失败: $($sig.StatusMessage)" -ForegroundColor Red
    }

    # Inno Setup 安装包编译
    Write-Host "`n正在检查 Inno Setup 编译器 (ISCC.exe)..." -ForegroundColor Magenta
    $isccPath = $null
    $candidatePaths = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    foreach ($cand in $candidatePaths) {
        if ($cand -and (Test-Path $cand)) {
            $isccPath = $cand
            break
        }
    }
    if (-not $isccPath) {
        $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
        if ($cmd) { $isccPath = $cmd.Source }
    }

    $issScript = Join-Path $ProjectRoot "build\installer.iss"
    $installerExe = Join-Path $OutputDir "WindowsPrinterSharingFix_CN_Installer.exe"

    if ($isccPath -and (Test-Path $issScript)) {
        Write-Host "找到 Inno Setup 编译器: $isccPath" -ForegroundColor Green
        Write-Host "正在编译安装包: $issScript..." -ForegroundColor Cyan
        & $isccPath $issScript
        
        if (Test-Path $installerExe) {
            Write-Host "安装包编译成功: $installerExe" -ForegroundColor Green
            Write-Host "正在为 $installerExe 注入数字签名..." -ForegroundColor Cyan
            $sigInstaller = Set-AuthenticodeSignature -FilePath $installerExe -Certificate $cert -TimestampServer "http://timestamp.sectigo.com"
            if ($sigInstaller.Status -eq "Valid" -or $sigInstaller.Status -eq "UnknownError") {
                Write-Host "安装包签名注入成功!(状态: $($sigInstaller.Status))" -ForegroundColor Green
            } else {
                Write-Host "安装包签名失败: $($sigInstaller.StatusMessage)" -ForegroundColor Red
            }
        } else {
            Write-Host "安装包构建失败: 未找到输出文件。" -ForegroundColor Red
        }
    } else {
        Write-Host "未找到 ISCC.exe 或缺少 installer.iss,跳过安装包编译。" -ForegroundColor Yellow
    }

} catch {
    Write-Host "处理失败: $_" -ForegroundColor Red
}

Start-Sleep -Seconds 2


