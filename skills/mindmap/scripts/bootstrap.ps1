param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Targets = "",
    [switch]$CheckOnly,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ServerName = "markmap-mcp-server"
$PackageName = "@jinzcdev/markmap-mcp-server"
$BootstrapVersion = "2026-03-28-v1"
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

function Get-StateDirectory {
    if ($IsWindowsPlatform) {
        $baseDir = $env:APPDATA
        if ([string]::IsNullOrWhiteSpace($baseDir)) {
            $baseDir = Join-Path $HOME "AppData\Roaming"
        }

        return Join-Path $baseDir "karthrand-ai\skills\mindmap"
    }

    $stateHome = $env:XDG_STATE_HOME
    if ([string]::IsNullOrWhiteSpace($stateHome)) {
        $stateHome = Join-Path $HOME ".local/state"
    }

    return Join-Path $stateHome "karthrand-ai/skills/mindmap"
}

function Get-ServiceFlagPath {
    return Join-Path (Get-StateDirectory) "service.initialized"
}

function Get-HostFlagPath {
    param([string]$HostName)
    return Join-Path (Get-StateDirectory) "host.$HostName.initialized"
}

function Test-ServiceInitialized {
    if ($Force) {
        return $false
    }

    return Test-Path (Get-ServiceFlagPath)
}

function Test-HostInitialized {
    param([string]$HostName)

    if ($Force) {
        return $false
    }

    return Test-Path (Get-HostFlagPath -HostName $HostName)
}

function Write-Flag {
    param([string]$Path)

    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -Path $Path -Value "initialized" -Encoding UTF8
}

function Remove-Flag {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Remove-ServiceFlag {
    Remove-Flag -Path (Get-ServiceFlagPath)
}

function Write-ServiceFlag {
    Write-Flag -Path (Get-ServiceFlagPath)
}

function Remove-HostFlag {
    param([string]$HostName)
    Remove-Flag -Path (Get-HostFlagPath -HostName $HostName)
}

function Write-HostFlag {
    param([string]$HostName)
    Write-Flag -Path (Get-HostFlagPath -HostName $HostName)
}

function Get-TargetHosts {
    $knownHosts = @("claude", "codex", "opencode")

    if ([string]::IsNullOrWhiteSpace($Targets)) {
        throw "必须显式指定 Targets，可选值：claude、codex、opencode、all。"
    }

    switch ($Targets) {
        "all" {
            $hosts = @()
            foreach ($name in $knownHosts) {
                if (Test-CommandExists $name) {
                    $hosts += $name
                }
            }

            if ($hosts.Count -eq 0) {
                throw "未检测到 claude、codex 或 opencode 命令。"
            }

            return $hosts
        }
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
        "opencode" {
            if (-not (Test-CommandExists "opencode")) {
                throw "未检测到 opencode 命令。"
            }

            return @("opencode")
        }
        default {
            throw "非法 Targets：$Targets。可选值：claude、codex、opencode、all。"
        }
    }
}

function Test-NodeToolchain {
    if (-not (Test-CommandExists "node")) {
        throw "缺少 node。请先安装 Node.js。"
    }

    if (-not (Test-CommandExists "npm")) {
        throw "缺少 npm。请先安装 npm。"
    }

    if (-not (Test-CommandExists "npx")) {
        throw "缺少 npx。请先安装 npx。"
    }
}

function Ensure-SharedService {
    Test-NodeToolchain

    if ($IsWindowsPlatform) {
        if (Test-CommandExists $ServerName) {
            Write-Info "检测到全局 $ServerName 命令，跳过共享安装。"
            return
        }

        Write-Info "开始安装共享服务 $PackageName。"
        if (Test-CommandExists "npm.cmd") {
            [void](Invoke-External -Command "npm.cmd" -Arguments @("install", "-g", $PackageName))
        }
        elseif (Test-CommandExists "cmd") {
            [void](Invoke-External -Command "cmd" -Arguments @("/c", "npm", "install", "-g", $PackageName))
        }
        else {
            [void](Invoke-External -Command "npm" -Arguments @("install", "-g", $PackageName))
        }

        if (-not (Test-CommandExists $ServerName)) {
            throw "共享服务安装后仍未找到 $ServerName 命令。"
        }

        return
    }

    Write-Info "类 Unix 环境使用 npx 启动共享服务，无需额外全局安装。"
}

function Test-SharedServiceReady {
    Test-NodeToolchain

    $server = Get-ServerCommandSpec
    $arguments = @($server.Arguments) + @("--help")
    $result = Invoke-External -Command $server.Command -Arguments $arguments -AllowFailure
    return $result.Success
}

function Get-ServerCommandSpec {
    if ($IsWindowsPlatform) {
        if (Test-CommandExists $ServerName) {
            return @{
                Command = "cmd"
                Arguments = @("/c", $ServerName)
            }
        }

        return @{
            Command = "cmd"
            Arguments = @("/c", "npx", "-y", $PackageName)
        }
    }

    if (Test-CommandExists $ServerName) {
        return @{
            Command = $ServerName
            Arguments = @()
        }
    }

    return @{
        Command = "npx"
        Arguments = @("-y", $PackageName)
    }
}

function Test-HostInstalled {
    param([string]$HostName)

    switch ($HostName) {
        "claude" {
            $result = Invoke-External -Command "claude" -Arguments @("mcp", "get", $ServerName) -AllowFailure
            return $result.Success
        }
        "codex" {
            $result = Invoke-External -Command "codex" -Arguments @("mcp", "list") -AllowFailure
            if (-not $result.Success) {
                return $false
            }

            $joined = @($result.Output) -join [Environment]::NewLine
            return $joined -match "(?m)^$([regex]::Escape($ServerName))(\s|$)"
        }
        "opencode" {
            $result = Invoke-External -Command "opencode" -Arguments @("mcp", "list") -AllowFailure
            if (-not $result.Success) {
                return $false
            }

            $joined = @($result.Output) -join [Environment]::NewLine
            return $joined -match [regex]::Escape($ServerName)
        }
        default {
            throw "未知宿主：$HostName"
        }
    }
}

function Remove-HostServer {
    param([string]$HostName)

    switch ($HostName) {
        "claude" {
            [void](Invoke-External -Command "claude" -Arguments @("mcp", "remove", "--scope", "user", $ServerName) -AllowFailure)
            return
        }
        "codex" {
            [void](Invoke-External -Command "codex" -Arguments @("mcp", "remove", $ServerName) -AllowFailure)
            return
        }
        "opencode" {
            Remove-OpenCodeConfigValue
            return
        }
        default {
            throw "未知宿主：$HostName"
        }
    }
}

function Get-ClaudeCommandSpec {
    $server = Get-ServerCommandSpec
    return @{
        Command = "claude"
        Arguments = @("mcp", "add", "--transport", "stdio", "--scope", "user", $ServerName, "--", $server.Command) + $server.Arguments
    }
}

function Get-CodexCommandSpec {
    $server = Get-ServerCommandSpec
    return @{
        Command = "codex"
        Arguments = @("mcp", "add", $ServerName, "--", $server.Command) + $server.Arguments
    }
}

function Invoke-NativeAdd {
    param([string]$HostName)

    switch ($HostName) {
        "claude" {
            $spec = Get-ClaudeCommandSpec
        }
        "codex" {
            $spec = Get-CodexCommandSpec
        }
        default {
            throw "未知宿主：$HostName"
        }
    }

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

function Get-OpenCodeConfigFilePath {
    return Join-Path $HOME ".config/opencode/opencode.json"
}

function Set-OpenCodeConfigValue {
    $configFile = Get-OpenCodeConfigFilePath
    $configDir = Split-Path -Parent $configFile
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null

    $server = Get-ServerCommandSpec
    $commandParts = @($server.Command) + $server.Arguments
    $commandJson = ($commandParts | ConvertTo-Json -Compress)

    @"
const fs = require("fs");
const file = process.argv[1];
const serverName = process.argv[2];
const command = JSON.parse(process.argv[3]);
let config = {};
if (fs.existsSync(file)) {
  try {
    config = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    config = {};
  }
}
if (!config["`$schema"]) {
  config["`$schema"] = "https://opencode.ai/config.json";
}
if (!config.mcp || typeof config.mcp !== "object" || Array.isArray(config.mcp)) {
  config.mcp = {};
}
config.mcp[serverName] = {
  type: "local",
  command,
  enabled: true
};
fs.writeFileSync(file, JSON.stringify(config, null, 2));
"@ | node - $configFile $ServerName $commandJson
}

function Remove-OpenCodeConfigValue {
    $configFile = Get-OpenCodeConfigFilePath
    if (-not (Test-Path $configFile)) {
        return
    }

    @"
const fs = require("fs");
const file = process.argv[1];
const serverName = process.argv[2];
let config = {};
try {
  config = JSON.parse(fs.readFileSync(file, "utf8"));
} catch {
  process.exit(0);
}
if (config.mcp && typeof config.mcp === "object" && !Array.isArray(config.mcp)) {
  delete config.mcp[serverName];
}
fs.writeFileSync(file, JSON.stringify(config, null, 2));
"@ | node - $configFile $ServerName
}

function Write-ManualConfig {
    param([string]$HostName)

    $server = Get-ServerCommandSpec
    if ($HostName -eq "claude") {
        Set-ClaudeConfigValue -Command $server.Command -Arguments $server.Arguments
        return
    }

    if ($HostName -eq "codex") {
        Set-CodexConfigValue -Command $server.Command -Arguments $server.Arguments
        return
    }

    if ($HostName -eq "opencode") {
        Set-OpenCodeConfigValue
        return
    }
}

function Install-Host {
    param([string]$HostName)

    if ($Force) {
        Write-Info "检测到 --force，先移除 $HostName 的旧配置。"
        Remove-HostServer -HostName $HostName
        Remove-HostFlag -HostName $HostName
    }

    if ($HostName -eq "opencode") {
        Write-Info "开始写入 opencode 的 MCP 配置。"
        Set-OpenCodeConfigValue
        return
    }

    if (Invoke-NativeAdd -HostName $HostName) {
        return
    }

    Write-Info "$HostName 原生命令注册失败，改为写入当前用户配置文件。"
    Write-ManualConfig -HostName $HostName
}

function Assert-HostsReady {
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

function Test-AllFlagsPresent {
    param([string[]]$Hosts)

    if (-not (Test-ServiceInitialized)) {
        return $false
    }

    if (-not (Test-SharedServiceReady)) {
        return $false
    }

    foreach ($targetName in $Hosts) {
        if (-not (Test-HostInitialized -HostName $targetName)) {
            return $false
        }

        if (-not (Test-HostInstalled -HostName $targetName)) {
            return $false
        }
    }

    return $true
}

$stateDir = Get-StateDirectory
$serviceFlag = Get-ServiceFlagPath
Write-Info "开始执行 mindmap bootstrap。"
Write-Info "ProjectRoot=$ProjectRoot"
Write-Info "SkillRoot=$SkillRoot"
Write-Info "StateDirectory=$stateDir"
Write-Info "ServiceFlag=$serviceFlag"

$hosts = Get-TargetHosts

if ($CheckOnly) {
    if (Test-AllFlagsPresent -Hosts $hosts) {
        Write-Info "已检测到共享服务标志与目标宿主标志。"
        exit 0
    }

    Write-Info "共享服务标志或目标宿主标志缺失。"
    exit 1
}

if (Test-AllFlagsPresent -Hosts $hosts) {
    Write-Info "共享服务与目标宿主均已初始化，跳过。"
    exit 0
}

if ($Force) {
    Remove-ServiceFlag
}

$serviceInitialized = Test-ServiceInitialized
if ($serviceInitialized -and -not (Test-SharedServiceReady)) {
    Write-Info "检测到共享服务标志，但共享服务实际不可用，移除标志后重新准备。"
    Remove-ServiceFlag
    $serviceInitialized = $false
}

if (-not $serviceInitialized) {
    Write-Info "开始准备共享服务。"
    Ensure-SharedService
    if (-not (Test-SharedServiceReady)) {
        Remove-ServiceFlag
        throw "共享服务准备后仍不可用。"
    }

    Write-ServiceFlag
}
else {
    Write-Info "已检测到共享服务标志，跳过共享服务准备。"
}

foreach ($targetName in $hosts) {
    $hostInitialized = Test-HostInitialized -HostName $targetName
    if ($hostInitialized -and -not (Test-HostInstalled -HostName $targetName)) {
        Write-Info "检测到 $targetName 宿主标志，但注册实际不可用，移除标志后重新注册。"
        Remove-HostFlag -HostName $targetName
        $hostInitialized = $false
    }

    if ($hostInitialized) {
        Write-Info "已检测到 $targetName 宿主标志，跳过注册。"
        continue
    }

    if ((Test-HostInstalled -HostName $targetName) -and -not $Force) {
        Write-Info "$targetName 已存在 $ServerName 注册，补写宿主标志。"
        Write-HostFlag -HostName $targetName
        continue
    }

    Write-Info "开始为 $targetName 安装/修复 $ServerName。"
    Install-Host -HostName $targetName
    if (-not (Test-HostInstalled -HostName $targetName)) {
        Remove-HostFlag -HostName $targetName
        throw "$targetName 的 MCP 注册后仍不可用。"
    }

    Write-HostFlag -HostName $targetName
}

Assert-HostsReady -Hosts $hosts
Write-Info "bootstrap 完成。"
