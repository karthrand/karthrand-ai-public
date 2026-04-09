param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host "[remote/setup] $Message"
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

function Test-Bash {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Test-SshpassBinary {
    $cmd = Get-Command sshpass -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

function Test-Sshpass {
    if (-not (Test-SshpassBinary)) {
        return $false
    }

    if (-not (Test-Bash)) {
        return $true
    }

    try {
        & bash -lc "sshpass -V" *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Get-SshpassVersion {
    if (-not (Test-Bash)) {
        return "unknown"
    }

    $output = & bash -lc "sshpass -V 2>&1 | head -n 1" | Select-Object -First 1
    if ($output -match '([0-9]+\.[0-9]+)') {
        return $Matches[1]
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
        [bool]$BashAvailable
    )

    $stateDir = Get-StateDir
    $stateFile = Get-BootstrapStateFile
    $null = New-Item -ItemType Directory -Path $stateDir -Force

    $now = [DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")
    $payload = [ordered]@{
        skill_name           = "remote"
        sshpass_installed    = $SshpassInstalled
        sshpass_version      = (Get-SshpassVersion)
        os_type              = "windows"
        bash_available       = $BashAvailable
        windows_remote_ready = ($SshpassInstalled -and $BashAvailable)
        last_setup_at        = $now
        last_verified_at     = $now
    }

    $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $stateFile -Encoding UTF8
}

if ((-not $Force) -and (Test-SshpassBinary)) {
    Write-Log "检测到 sshpass，跳过安装。"
} else {
    $installed = Install-WithWinget
    if (-not $installed) {
        $installed = Install-WithScoop
    }

    if (-not $installed) {
        throw "winget 与 scoop 都未成功安装 sshpass。"
    }
}

if (-not (Test-Sshpass)) {
    Write-BootstrapState -SshpassInstalled $false -BashAvailable (Test-Bash)
    throw "安装完成后仍未检测到可用的 sshpass。"
}

Write-BootstrapState -SshpassInstalled $true -BashAvailable (Test-Bash)
if (-not (Test-Bash)) {
    throw "Windows 下 remote skill 必须通过 bash -lc 执行，但当前环境未检测到 bash。"
}

Write-Log "sshpass 已完成验证，状态文件已写入 $(Get-BootstrapStateFile)"
Write-Log "Windows 下远程访问必须通过 bash -lc 调用 scripts/remote.sh，或调用 scripts/remote.ps1。"
