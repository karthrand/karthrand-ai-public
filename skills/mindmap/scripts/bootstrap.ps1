param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet("auto", "claude", "codex", "all")]
    [string]$Targets = "auto",
    [switch]$CheckOnly,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ServerName = "markmap-mcp-server"
$PackageName = "@jinzcdev/markmap-mcp-server"
$BootstrapVersion = "2026-03-27-v1"
$IsWindowsPlatform = $env:OS -eq "Windows_NT"

function Write-Info {
    param([string]$Message)
    Write-Host "[mindmap/bootstrap] $Message"
}

function Test-CommandExists {
    param([string]$Name)
    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @(),
        [switch]$AllowFailure
    )

    try {
        $output = & $Command @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        if (-not $AllowFailure) {
            throw
        }

        return @{
            Success = $false
            ExitCode = -1
            Output = @($_.Exception.Message)
        }
    }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $joined = @($output) -join [Environment]::NewLine
        throw "执行命令失败：$Command $($Arguments -join ' ')`n$joined"
    }

    return @{
        Success = $exitCode -eq 0
        ExitCode = $exitCode
        Output = @($output)
    }
}

function Get-StateFilePath {
    $stateDir = Join-Path $ProjectRoot ".agents\state"
    return Join-Path $stateDir "mindmap.json"
}

function Get-TargetHosts {
    switch ($Targets) {
        "claude" {
            if (-not (Test-CommandExists "claude")) {
                throw "未检测到 claude 命令。"
            }

            return @("claude")
        }
        "codex" {
            if (-not (Test-CommandExists "codex")) {
                throw "未检测到 codex 命令。"
            }

            return @("codex")
        }
        "all" {
            $hosts = @()
            foreach ($name in @("claude", "codex")) {
                if (Test-CommandExists $name) {
                    $hosts += $name
                }
            }

            if ($hosts.Count -eq 0) {
                throw "未检测到 claude 或 codex 命令。"
            }

            return $hosts
        }
        default {
            $hosts = @()
            foreach ($name in @("claude", "codex")) {
                if (Test-CommandExists $name) {
                    $hosts += $name
                }
            }

            if ($hosts.Count -eq 0) {
                throw "自动检测失败：未检测到 claude 或 codex 命令。"
            }

            return $hosts
        }
    }
}

function Test-StateMatches {
    param([string[]]$Hosts)

    if ($Force) {
        return $false
    }

    $stateFile = Get-StateFilePath
    if (-not (Test-Path $stateFile)) {
        return $false
    }

    try {
        $state = Get-Content $stateFile -Raw | ConvertFrom-Json
        $installedHosts = @($state.installed_hosts)
        if ($state.project_root -ne $ProjectRoot) {
            return $false
        }

        foreach ($targetName in $Hosts) {
            if ($installedHosts -notcontains $targetName) {
                return $false
            }
        }

        return $true
    }
    catch {
        return $false
    }
}

function Test-NodeToolchain {
    if (-not (Test-CommandExists "node")) {
        throw "缺少 node。请先安装 Node.js。"
    }

    if (-not (Test-CommandExists "npm")) {
        throw "缺少 npm。请先安装 npm。"
    }

    if (-not $IsWindowsPlatform -and -not (Test-CommandExists "npx")) {
        throw "类 Unix 环境缺少 npx，无法按约定使用 npx -y 安装 MCP。"
    }
}

function Test-HostInstalled {
    param([string]$HostName)

    if ($HostName -eq "claude") {
        $result = Invoke-External -Command "claude" -Arguments @("mcp", "get", $ServerName) -AllowFailure
        return $result.Success
    }

    $result = Invoke-External -Command "codex" -Arguments @("mcp", "list") -AllowFailure
    if (-not $result.Success) {
        return $false
    }

    $joined = @($result.Output) -join [Environment]::NewLine
    return $joined -match "(?m)^$([regex]::Escape($ServerName))(\s|$)"
}

function Remove-HostServer {
    param([string]$HostName)

    if ($HostName -eq "claude") {
        [void](Invoke-External -Command "claude" -Arguments @("mcp", "remove", "--scope", "user", $ServerName) -AllowFailure)
        return
    }

    [void](Invoke-External -Command "codex" -Arguments @("mcp", "remove", $ServerName) -AllowFailure)
}

function Ensure-GlobalBinary {
    if (Test-CommandExists $ServerName) {
        return $true
    }

    Write-Info "Windows 环境先尝试全局安装 $PackageName。"
    # 避免在严格模式下走 npm.ps1，优先使用 npm.cmd。
    if (Test-CommandExists "npm.cmd") {
        [void](Invoke-External -Command "npm.cmd" -Arguments @("install", "-g", $PackageName))
    }
    elseif (Test-CommandExists "cmd") {
        [void](Invoke-External -Command "cmd" -Arguments @("/c", "npm", "install", "-g", $PackageName))
    }
    else {
        [void](Invoke-External -Command "npm" -Arguments @("install", "-g", $PackageName))
    }

    return Test-CommandExists $ServerName
}

function Get-CommandSpec {
    param(
        [string]$HostName,
        [string]$Mode
    )

    if ($IsWindowsPlatform) {
        if ($Mode -eq "global") {
            $serverArgs = @("cmd", "/c", $ServerName)
        }
        else {
            $serverArgs = @("cmd", "/c", "npx", "-y", $PackageName)
        }
    }
    else {
        if ($Mode -eq "global") {
            $serverArgs = @($ServerName)
        }
        else {
            $serverArgs = @("npx", "-y", $PackageName)
        }
    }

    if ($HostName -eq "claude") {
        return @{
            Command = "claude"
            Arguments = @("mcp", "add", "--transport", "stdio", "--scope", "user", $ServerName, "--") + $serverArgs
        }
    }

    return @{
        Command = "codex"
        Arguments = @("mcp", "add", $ServerName, "--") + $serverArgs
    }
}

function Invoke-NativeAdd {
    param(
        [string]$HostName,
        [string]$Mode
    )

    $spec = Get-CommandSpec -HostName $HostName -Mode $Mode
    $result = Invoke-External -Command $spec.Command -Arguments $spec.Arguments -AllowFailure
    return $result.Success
}

function Set-CodexConfigValue {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $configDir = Join-Path $HOME ".codex"
    $configFile = Join-Path $configDir "config.toml"
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null

    $content = ""
    if (Test-Path $configFile) {
        $content = Get-Content $configFile -Raw
        $envPattern = "(?ms)^\[mcp_servers\.$([regex]::Escape($ServerName))\.env\]\r?\n.*?(?=^\[|\z)"
        $serverPattern = "(?ms)^\[mcp_servers\.$([regex]::Escape($ServerName))\]\r?\n.*?(?=^\[|\z)"
        $content = [regex]::Replace($content, $envPattern, "")
        $content = [regex]::Replace($content, $serverPattern, "")
        $content = $content.TrimEnd()
    }

    $tomlArgs = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ", "
    $block = @(
        "[mcp_servers.$ServerName]"
        "command = ""$Command"""
        "args = [$tomlArgs]"
    ) -join [Environment]::NewLine

    if ([string]::IsNullOrWhiteSpace($content)) {
        $newContent = "$block$([Environment]::NewLine)"
    }
    else {
        $newContent = "$content$([Environment]::NewLine)$([Environment]::NewLine)$block$([Environment]::NewLine)"
    }

    Set-Content -Path $configFile -Value $newContent -Encoding UTF8
}

function Set-ClaudeConfigValue {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $configFile = Join-Path $HOME ".claude.json"
    $config = @{}
    if (Test-Path $configFile) {
        try {
            $config = Get-Content $configFile -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            $config = @{}
        }
    }

    if (-not $config.ContainsKey("mcpServers")) {
        $config["mcpServers"] = @{}
    }

    $config["mcpServers"][$ServerName] = @{
        type = "stdio"
        command = $Command
        args = $Arguments
    }

    $json = $config | ConvertTo-Json -Depth 100
    Set-Content -Path $configFile -Value $json -Encoding UTF8
}

function Write-ManualConfig {
    param([string]$HostName)

    if ($IsWindowsPlatform) {
        if (Test-CommandExists $ServerName) {
            $command = "cmd"
            $arguments = @("/c", $ServerName)
        }
        else {
            $command = "cmd"
            $arguments = @("/c", "npx", "-y", $PackageName)
        }
    }
    else {
        $command = "npx"
        $arguments = @("-y", $PackageName)
    }

    if ($HostName -eq "claude") {
        Set-ClaudeConfigValue -Command $command -Arguments $arguments
        return
    }

    Set-CodexConfigValue -Command $command -Arguments $arguments
}

function Install-Host {
    param([string]$HostName)

    if ($Force) {
        Write-Info "检测到 --force，先移除 $HostName 的旧配置。"
        Remove-HostServer -HostName $HostName
    }

    if ($IsWindowsPlatform) {
        $hasGlobalBinary = Ensure-GlobalBinary
        if (-not $hasGlobalBinary) {
            throw "Windows 环境全局安装后仍未找到 $ServerName 命令。"
        }

        if (Invoke-NativeAdd -HostName $HostName -Mode "global") {
            return "native-global-bin"
        }

        Write-Info "$HostName 原生命令注册失败，尝试 cmd /c npx -y 回退。"
        if (Invoke-NativeAdd -HostName $HostName -Mode "npx") {
            return "native-inline-npx"
        }
    }
    else {
        if (Invoke-NativeAdd -HostName $HostName -Mode "npx") {
            return "native-inline-npx"
        }

        Write-Info "$HostName 原生 npx 注册失败，尝试直接调用全局命令。"
        if ((Test-CommandExists $ServerName) -and (Invoke-NativeAdd -HostName $HostName -Mode "global")) {
            return "native-global-bin"
        }
    }

    Write-Info "$HostName 原生命令注册失败，改为写入当前用户配置文件。"
    Write-ManualConfig -HostName $HostName
    return "manual-config"
}

function Save-State {
    param(
        [string[]]$Hosts,
        [string[]]$Modes
    )

    $stateFile = Get-StateFilePath
    $stateDir = Split-Path -Parent $stateFile
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    $payload = [ordered]@{
        skill_name = "mindmap"
        skill_version = $BootstrapVersion
        project_root = $ProjectRoot
        initialized_at = [DateTimeOffset]::UtcNow.ToString("o")
        detected_hosts = $Hosts
        installed_hosts = $Hosts
        install_mode = ($Modes | Select-Object -Unique)
        platform = $(if ($IsWindowsPlatform) { "windows" } else { "unix" })
        bootstrap_hash = $BootstrapVersion
    }

    $payload | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFile -Encoding UTF8
}

function Assert-Ready {
    param([string[]]$Hosts)

    $missing = @()
    foreach ($targetName in $Hosts) {
        if (-not (Test-HostInstalled -HostName $targetName)) {
            $missing += $targetName
        }
    }

    if ($missing.Count -gt 0) {
        throw "以下宿主的 MCP 仍未就绪：$($missing -join ', ')"
    }
}

Write-Info "开始执行 mindmap bootstrap。"
Write-Info "ProjectRoot=$ProjectRoot"
Write-Info "SkillRoot=$SkillRoot"

Test-NodeToolchain
$hosts = Get-TargetHosts

if (Test-StateMatches -Hosts $hosts) {
    Write-Info "检测到现有初始化状态，开始做快速校验。"
    Assert-Ready -Hosts $hosts
    Write-Info "已初始化，跳过。"
    exit 0
}

if ($CheckOnly) {
    $notReady = @()
    foreach ($targetName in $hosts) {
        if (-not (Test-HostInstalled -HostName $targetName)) {
            $notReady += $targetName
        }
    }

    if ($notReady.Count -gt 0) {
        Write-Info "以下宿主尚未安装：$($notReady -join ', ')"
        exit 1
    }

    Write-Info "所有目标宿主已完成 MCP 安装。"
    exit 0
}

$modes = @()
foreach ($targetName in $hosts) {
    if ((Test-HostInstalled -HostName $targetName) -and -not $Force) {
        Write-Info "$targetName 已安装 $ServerName，跳过注册。"
        $modes += "existing"
        continue
    }

    Write-Info "开始为 $targetName 安装/修复 $ServerName。"
    $modes += Install-Host -HostName $targetName
}

Assert-Ready -Hosts $hosts
Save-State -Hosts $hosts -Modes $modes
Write-Info "bootstrap 完成。"
