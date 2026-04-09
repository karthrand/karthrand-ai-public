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

$bash = Get-BashCommand
$bashFlavor = Get-BashFlavor -BashPath $bash.Source
if ($bashFlavor -eq "unknown") {
    throw "未识别到当前 bash 运行时，无法安全执行 remote skill。"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$quoted = New-Object System.Collections.Generic.List[string]
$quoted.Add("REMOTE_BASH_LC=1")
$quoted.Add("REMOTE_HOST_OS=windows")
$quoted.Add("REMOTE_HOST_BASH_FLAVOR=$(Quote-BashArg -Value $bashFlavor)")
$quoted.Add("REMOTE_HOST_BASH_PATH=$(Quote-BashArg -Value $bash.Source)")
$quoted.Add("REMOTE_HOST_WINDOWS_LOCALAPPDATA=$(Quote-BashArg -Value $env:LOCALAPPDATA)")
$quoted.Add((Quote-BashArg -Value "./remote.sh"))
foreach ($arg in $args) {
    $quoted.Add((Quote-BashArg -Value ([string]$arg)))
}

$commandString = [string]::Join(' ', $quoted)
Write-Log "Windows 下固定通过 bash -lc 调用 remote.sh。当前 bash 运行时：$bashFlavor。"

Push-Location $scriptDir
try {
    & $bash.Source -lc $commandString
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
