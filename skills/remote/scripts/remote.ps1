$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host "[remote] $Message"
}

function Quote-BashArg {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'""'""'") + "'"
}

$bash = Get-Command bash -ErrorAction SilentlyContinue
if ($null -eq $bash) {
    throw "Windows 下 remote skill 必须通过 bash -lc 执行，但当前环境未检测到 bash。"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$quoted = New-Object System.Collections.Generic.List[string]
$quoted.Add("REMOTE_BASH_LC=1")
$quoted.Add((Quote-BashArg -Value "./remote.sh"))
foreach ($arg in $args) {
    $quoted.Add((Quote-BashArg -Value ([string]$arg)))
}

$commandString = [string]::Join(' ', $quoted)
Write-Log "Windows 下固定通过 bash -lc 调用 remote.sh。"

Push-Location $scriptDir
try {
    & $bash.Source -lc $commandString
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
