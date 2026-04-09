$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host "[remote] $Message"
}

function Quote-BashArg {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'""'""'") + "'"
}

function Get-BashCommand {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($null -eq $bash) {
        throw "Windows 下 remote skill 必须通过 bash -lc 执行，但当前环境未检测到 bash。"
    }

    return $bash
}

function Get-RuntimeType {
    param([string]$BashPath)

    $runtimeType = (& $BashPath -lc "source ./runtime.sh; remote_detect_runtime_type").Trim()
    if ([string]::IsNullOrWhiteSpace($runtimeType) -or $runtimeType -eq "unknown") {
        throw "未识别到当前执行环境，无法安全执行 remote skill。"
    }

    return $runtimeType
}

$bash = Get-BashCommand
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Push-Location $scriptDir
try {
    $runtimeType = Get-RuntimeType -BashPath $bash.Source
    if ($runtimeType -ne "windows-msys" -and $runtimeType -ne "linux-wsl") {
        throw "当前执行环境不受支持：$runtimeType"
    }

    $quoted = New-Object System.Collections.Generic.List[string]
    $quoted.Add("REMOTE_BASH_LC=1")
    $quoted.Add("REMOTE_RUNTIME_TYPE=$(Quote-BashArg -Value $runtimeType)")
    $quoted.Add("REMOTE_HOST_BASH_PATH=$(Quote-BashArg -Value $bash.Source)")
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $quoted.Add("REMOTE_HOST_WINDOWS_LOCALAPPDATA=$(Quote-BashArg -Value $env:LOCALAPPDATA)")
    }
    $quoted.Add((Quote-BashArg -Value "./remote.sh"))
    foreach ($arg in $args) {
        $quoted.Add((Quote-BashArg -Value ([string]$arg)))
    }

    $commandString = [string]::Join(' ', $quoted)
    Write-Log "Windows 下固定通过 bash -lc 调用 remote.sh。当前执行环境：$runtimeType。"

    & $bash.Source -lc $commandString
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
