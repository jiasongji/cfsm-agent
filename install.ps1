$ErrorActionPreference = "Stop"

# Installing/uninstalling writes to C:\Program Files and registers a SYSTEM
# scheduled task, both of which require an elevated (administrator) session.
# Fail fast with a clear prompt instead of a raw "Access is denied" later.
$cfPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $cfPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] 安装或卸载 cf-probe 需要管理员权限。" -ForegroundColor Red
    Write-Host "请右键点击 PowerShell，选择“以管理员身份运行”，然后重新执行本命令。" -ForegroundColor Yellow
    exit 1
}

$Repo = "jiasongji/cfsm-agent"
$GitHubProxy = ""
$InstallVersion = "latest"

$needValueFor = ""
foreach ($arg in $args) {
    if ($needValueFor) {
        switch ($needValueFor) {
            "proxy" { $GitHubProxy = $arg }
            "version" { $InstallVersion = $arg }
        }
        $needValueFor = ""
        continue
    }
    switch -Regex ($arg) {
        "^--install-ghproxy=(.+)$" { $GitHubProxy = $Matches[1]; continue }
        "^--install-ghproxy$" { $needValueFor = "proxy"; continue }
        "^--install-version=(.+)$" { $InstallVersion = $Matches[1]; continue }
        "^--install-version$" { $needValueFor = "version"; continue }
    }
}

function Get-ArchName {
    # PROCESSOR_ARCHITECTURE is emulated on Windows ARM64 (amd64 processes
    # under Prism see "AMD64"), so prefer the true native architecture.
    if ($env:PROCESSOR_ARCHITEW6432) {
        switch ($env:PROCESSOR_ARCHITEW6432) {
            "ARM64" { "arm64"; return }
            "ARM64EC" { "arm64"; return }
            "AMD64" { "amd64"; return }
            "x86" { "386"; return }
        }
    }
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        # 0=x86 1=MIPS 2=Alpha 6=IA64 9=x64 12=ARM64
        if ($cpu.DeviceArchitecture -eq 12) { "arm64"; return }
        if ($cpu.DeviceArchitecture -eq 9) { "amd64"; return }
    } catch {
        # Fall through to the environment variable below.
    }
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "amd64"; break }
        "ARM64" { "arm64"; break }
        "x86" { "386"; break }
        default { throw "unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
    }
}

$command = if ($args.Count -gt 0) { $args[0] } else { "install" }
$payloadArgs = @($args)
if ($command -in @("uninstall", "remove", "delete", "purge")) {
    Write-Host "[INFO] downloading temporary uninstaller"
    $payloadArgs = @($command)
}

$arch = Get-ArchName
$asset = "cf-probe-windows-$arch.exe"
$path = if ($InstallVersion -eq "latest") { "latest/download" } else { "download/$InstallVersion" }
$url = "https://github.com/$Repo/releases/$path/$asset"
if ($GitHubProxy) {
    $url = $GitHubProxy.TrimEnd("/") + "/" + $url
}

$tmp = Join-Path $env:TEMP "cf-probe-bootstrap-$PID.exe"
Write-Host "CF-Server-Monitor Go Probe bootstrap"
Write-Host "  repo    : $Repo"
Write-Host "  version : $InstallVersion"
Write-Host "  target  : windows/$arch"
Write-Host "  asset   : $asset"
Write-Host "  url     : $url"

try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 300

    # 校验二进制 sha256，防止代理劫持或下载损坏的二进制被直接以管理员权限执行
    $checksumsUrl = "https://github.com/$Repo/releases/$path/checksums.txt"
    if ($GitHubProxy) {
        $checksumsUrl = $GitHubProxy.TrimEnd("/") + "/" + $checksumsUrl
    }
    $checksumsFile = Join-Path $env:TEMP "cf-probe-checksums-$PID.txt"
    Invoke-WebRequest -Uri $checksumsUrl -OutFile $checksumsFile -UseBasicParsing -TimeoutSec 120
    # checksums.txt 中资产名带 dist/ 前缀（如 dist/cf-probe-windows-amd64.exe），按文件名后缀匹配
    $expected = $null
    foreach ($line in Get-Content $checksumsFile) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $name = $parts[1].Trim().TrimStart("/")
            if ($name -eq $asset -or $name.EndsWith("/$asset")) {
                $expected = $parts[0].Trim().ToLowerInvariant()
                break
            }
        }
    }
    Remove-Item $checksumsFile -ErrorAction SilentlyContinue
    if (-not $expected) {
        throw "checksum for $asset not found in checksums.txt"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $tmp).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "checksum mismatch for ${asset}: expected $expected, got $actual"
    }

    if ($args.Count -eq 0) {
        & $tmp install
    } else {
        & $tmp @payloadArgs
    }
    exit $LASTEXITCODE
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
