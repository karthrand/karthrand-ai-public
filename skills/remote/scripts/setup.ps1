param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host "[remote/setup] $Message"
}

function Quote-BashArg {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'""'""'") + "'"
}

function Get-StateDir {
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        throw "未检测到 LOCALAPPDATA，无法写入 remote 状态目录。"
    }

    return Join-Path $base "remote"
}

function Get-BootstrapStateFile {
    return Join-Path (Get-StateDir) "bootstrap-state.json"
}

function Get-BashCommand {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($null -eq $bash) {
        throw "Windows 下 remote skill 必须通过 bash -lc 执行，但当前环境未检测到 bash。"
    }

    return $bash
}

function Get-BashFlavor {
    param([string]$BashPath)

    $unameShort = (& $BashPath -lc "uname -s").Trim()
    $unameLong = (& $BashPath -lc "uname -a").Trim()

    if ($unameShort -match '^(MINGW|MSYS|CYGWIN)') {
        return "msys"
    }

    if ($unameLong -match '(?i)microsoft|wsl') {
        return "wsl"
    }

    return "unknown"
}

function Test-SshpassWindowsBinary {
    $cmd = Get-Command sshpass -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Test-SshpassWindows {
    if (-not (Test-SshpassWindowsBinary)) {
        return $false
    }

    try {
        $versionOutput = (& sshpass -V 2>&1 | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($versionOutput) -and $versionOutput -match 'sshpass|Usage:') {
            return $true
        }
    } catch {
    }

    try {
        $helpOutput = (& sshpass -h 2>&1 | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($helpOutput) -and $helpOutput -match 'Usage:') {
            return $true
        }
    } catch {
    }

    return $false
}

function Get-SshpassVersionWindows {
    foreach ($script in @(
        { (& sshpass -V 2>&1 | Out-String).Trim() },
        { (& sshpass -h 2>&1 | Out-String).Trim() }
    )) {
        try {
            $output = & $script
            if ($output -match '([0-9]+\.[0-9]+)') {
                return $Matches[1]
            }
        } catch {
        }
    }

    return "unknown"
}

function Install-WithWinget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        return $false
    }

    Write-Log "使用 winget 安装 sshpass-win32。"
    & winget install --source winget --exact --id xhcoding.sshpass-win32 --accept-package-agreements --accept-source-agreements
    return $LASTEXITCODE -eq 0
}

function Install-WithScoop {
    $scoop = Get-Command scoop -ErrorAction SilentlyContinue
    if ($null -eq $scoop) {
        return $false
    }

    Write-Log "winget 失败，改用 scoop 安装 Sshpass。"
    & scoop install Sshpass
    return $LASTEXITCODE -eq 0
}

function Write-BootstrapState {
    param(
        [bool]$SshpassInstalled,
        [string]$BashFlavor,
        [string]$BashPath,
        [string]$SshpassProvider
    )

    $stateDir = Get-StateDir
    $stateFile = Get-BootstrapStateFile
    $null = New-Item -ItemType Directory -Path $stateDir -Force

    $now = [DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")
    $payload = [ordered]@{
        skill_name           = "remote"
        sshpass_installed    = $SshpassInstalled
        sshpass_version      = (Get-SshpassVersionWindows)
        os_type              = "windows"
        bash_available       = $true
        bash_flavor          = $BashFlavor
        bash_path            = $BashPath
        sshpass_provider     = $SshpassProvider
        windows_remote_ready = ($SshpassInstalled -and $BashFlavor -ne "unknown")
        last_setup_at        = $now
        last_verified_at     = $now
    }

    $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $stateFile -Encoding UTF8
}

$bash = Get-BashCommand
$bashFlavor = Get-BashFlavor -BashPath $bash.Source
if ($bashFlavor -eq "unknown") {
    throw "未识别到当前 bash 运行时，无法安全完成 remote setup。"
}

if ($bashFlavor -eq "wsl") {
    Write-Log "当前 bash 运行时为 WSL，改为在 WSL 内安装 Linux sshpass。"
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $quoted = New-Object System.Collections.Generic.List[string]
    $quoted.Add("REMOTE_BASH_LC=1")
    $quoted.Add("REMOTE_HOST_OS=windows")
    $quoted.Add("REMOTE_HOST_BASH_FLAVOR=$(Quote-BashArg -Value $bashFlavor)")
    $quoted.Add("REMOTE_HOST_BASH_PATH=$(Quote-BashArg -Value $bash.Source)")
    $quoted.Add("REMOTE_HOST_WINDOWS_LOCALAPPDATA=$(Quote-BashArg -Value $env:LOCALAPPDATA)")
    $quoted.Add((Quote-BashArg -Value "./setup.sh"))
    if ($Force) {
        $quoted.Add("--force")
    }

    Push-Location $scriptDir
    try {
        & $bash.Source -lc ([string]::Join(' ', $quoted))
        exit $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
}

if ($bashFlavor -ne "msys") {
    throw "当前 Windows bash 运行时既不是 WSL 也不是 MSYS，无法继续 setup。"
}

if ((-not $Force) -and (Test-SshpassWindows)) {
    Write-Log "检测到 Windows sshpass，跳过安装。"
} else {
    $installed = Install-WithWinget
    if (-not $installed) {
        $installed = Install-WithScoop
    }

    if (-not $installed) {
        throw "winget 与 scoop 都未成功安装 sshpass。"
    }
}

$verified = Test-SshpassWindows
Write-BootstrapState -SshpassInstalled $verified -BashFlavor $bashFlavor -BashPath $bash.Source -SshpassProvider "windows"
if (-not $verified) {
    throw "安装完成后仍未检测到可用的 Windows sshpass。"
}

Write-Log "sshpass 已完成验证，状态文件已写入 $(Get-BootstrapStateFile)"
Write-Log "Windows 下远程访问必须通过 scripts/remote.ps1 进入，当前 provider 为 windows。"
