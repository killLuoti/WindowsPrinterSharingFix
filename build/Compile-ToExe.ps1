$ProjectRoot = Split-Path $PSScriptRoot -Parent

$SourceFile = Join-Path $ProjectRoot "src\WindowsPrinterSharingFix.ps1"
$OutputDir  = Join-Path $ProjectRoot "release"
$OutputFile = Join-Path $OutputDir "WindowsPrinterSharingFix_CN.exe"
$IconFile   = Join-Path $ProjectRoot "assets\icon.ico"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not (Test-Path $SourceFile)) {
    Write-Host "[错误] 未找到源文件: $SourceFile" -ForegroundColor Red
    Write-Host "请确保在 WindowsPrinterSharingFix 项目目录中执行此脚本。" -ForegroundColor Yellow
    exit 1
}

Write-Host "正在验证 PS2EXE 模块..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "未安装 PS2EXE 模块。正在安装..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-Module -Name ps2exe -Force -Scope CurrentUser -AllowClobber
}

Write-Host "PS2EXE 模块已就绪。" -ForegroundColor Green
Write-Host "正在将 $SourceFile 编译为 $OutputFile..." -ForegroundColor Cyan

$ps2exeParams = @{
    inputFile   = $SourceFile
    outputFile  = $OutputFile
    requireAdmin = $true
    title       = "Windows 打印机共享修复工具"
    description = "Windows 打印机共享修复工具（汉化版）"
    version     = "2.3.2.0"
    company     = "khairudinfahmi"
    copyright   = "2026 khairudinfahmi"
}

if (Test-Path $IconFile) {
    $ps2exeParams.iconFile = $IconFile
}

try {
    Invoke-ps2exe @ps2exeParams
    
    Write-Host "`n编译成功！" -ForegroundColor Green
    Write-Host "EXE 文件已生成: $OutputFile" -ForegroundColor Cyan
    
    $docSource = Join-Path $ProjectRoot "docs\documentation.html"
    $docDest = Join-Path $OutputDir "documentation.html"
    if (Test-Path $docSource) {
        Copy-Item $docSource $docDest -Force
        Write-Host "文档已打包: $docDest" -ForegroundColor Green
    }
    
    Write-Host "正在开始代码签名..." -ForegroundColor Magenta
    $certName = "khairudinfahmi"
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object Subject -match $certName | Select-Object -First 1
    
    if (-not $cert) {
        Write-Host "未找到代码签名证书 '$certName'。正在生成新证书..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate -Subject "CN=$certName" -Type CodeSigningCert -CertStoreLocation "Cert:\CurrentUser\My"
        Write-Host "新证书已生成。" -ForegroundColor Green
    }
    
    $cerExportPath = Join-Path $ProjectRoot "assets\khairudinfahmi_cert.cer"
    Export-Certificate -Cert $cert -FilePath $cerExportPath -Force | Out-Null
    Write-Host "证书文件已导出到: $cerExportPath" -ForegroundColor Cyan
    
    Write-Host "正在向 $OutputFile 注入数字签名..." -ForegroundColor Cyan
    $sig = Set-AuthenticodeSignature -FilePath $OutputFile -Certificate $cert -TimestampServer "http://timestamp.sectigo.com"
    
    if ($sig.Status -eq "Valid" -or $sig.Status -eq "UnknownError") {
        Write-Host "签名已注入！（状态: $($sig.Status)）" -ForegroundColor Green
    } else {
        Write-Host "签名失败: $($sig.StatusMessage)" -ForegroundColor Red
    }

} catch {
    Write-Host "处理失败: $_" -ForegroundColor Red
}

Start-Sleep -Seconds 2
