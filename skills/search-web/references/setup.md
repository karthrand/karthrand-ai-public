# Search-Web Setup

## 何时读取

出现以下任一情况时读取本文件：

- 首次使用 `search-web`
- `search-web` 的 setup 状态文件不存在
- setup 状态文件存在，但与当前宿主中的真实安装状态不一致
- `Context7`、`Exa`、`DeepWiki` 任一报未注册、连接失败、`server unavailable` 或类似环境类错误
- 需要为 `Claude Code`、`Codex` 或 `OpenCode` 配置 `search-web` 的必需 MCP

## 必需依赖

本 skill 的必需 MCP 固定为：

- `context7`
- `exa`
- `mcp-deepwiki`

只有这三项都已安装且真实可用，才允许返回主流程。

## 宿主识别方式

先识别当前宿主，固定输出：

- `agent_type`：`claudecode` / `codex` / `opencode` / `unknown`
- `detection_source`：`session_env` / `system_prompt` / `tool_fingerprint` / `unknown`

固定检测顺序：

1. 先看当前会话中的精确宿主环境信号：
   - `claudecode`：`CLAUDECODE=1`、`CLAUDE_CODE_ENTRYPOINT`、`CLAUDE_CODE_SESSION_ID`
   - `codex`：精确 `CODEX_*` 会话变量，优先 `CODEX_THREAD_ID`
   - `opencode`：`OPENCODE_SESSION_ID`、`OPENCODE_SESSION`；只有没有其他宿主信号冲突时，才允许退化为 `OPENCODE_*` 前缀变量族
2. 如果环境变量无法唯一确认，再看当前会话的 system prompt 或 developer prompt 中是否存在唯一宿主标识：
   - `claudecode`：例如 `You are Claude Code`
   - `codex`：例如 `You are Codex`
   - `opencode`：当前宿主明确暴露的唯一身份标识
3. 如果 system prompt 仍无法唯一确认，再看工具集指纹是否唯一对应某个宿主：
   - `Claude Code` 常见指纹：`Agent`、`TaskCreate`、`TodoWrite`、`CronCreate`、`TeamCreate`、`Skill`、`mcp__*`
   - `OpenCode` 常见指纹：工具名整体偏小写，且更接近 `view` 这类命名风格
   - `Codex`：以当前会话实际暴露的 Codex 工具族为准，必须能和其他宿主区分
4. 任一步如果出现多宿主信号冲突，或者仍无法唯一确认时，一律返回 `unknown`

禁止作为当前宿主判定依据：

- 不存在的 `KARTHRAND_AGENT_TYPE`
- 仅凭本机装过 `claude`、`codex`、`opencode` 命令
- 仅凭父进程名或上层可执行文件名猜测
- 仅凭宽泛的 `CLAUDE_*`、`CODEX_*`、`OPENCODE_*` 前缀直接判定
- 仅凭某个配置文件存在，或只说明“理论支持某宿主”，但没有当前会话证据

如果 `agent_type=unknown`，立即停止，不继续猜测配置路径，也不写入宿主专属状态。

## 固定决策

1. 先完成宿主识别。
2. 再读取用户级状态文件 `bootstrap-state.json`：
   - Windows：`%LOCALAPPDATA%\search-web\bootstrap-state.json`
   - 类 Unix：`$XDG_DATA_HOME/search-web/bootstrap-state.json`
   - 如果类 Unix 未设置 `XDG_DATA_HOME`，回退到 `~/.local/share/search-web/bootstrap-state.json`
3. 读取状态后，逐项真实检测 `context7`、`exa`、`mcp-deepwiki` 是否已经注册可用；不能只看状态文件，也不能只看本机是否装过某个命令。
4. 三项都可用时，更新状态后立即停止，不重复 setup。
5. 任一项缺失、未注册、连接失败或状态失真时，进入对应项的 setup / repair。
6. `exa` 需要 key 时，只有在确认当前宿主缺少 `exa` 时才询问 `EXA_API_KEY`。
7. 用户明确没有 `EXA_API_KEY` 时：
   - 不传入 key
   - 直接使用 `https://mcp.exa.ai/mcp`
8. 用户明确有 `EXA_API_KEY` 时：
   - 先索取 key
   - 再把 URL 改成 `https://mcp.exa.ai/mcp?exaApiKey=用户提供的_EXA_API_KEY`
9. 所有必需项 setup 成功后回写状态文件；失败则记录失败项和最近一次环境错误。

## 状态文件

状态文件只记录 setup 结果，不承担安装逻辑。

推荐最小结构：

```json
{
  "version": 1,
  "updatedAt": "ISO-8601",
  "runtime": {
    "agentType": "claudecode|codex|opencode|unknown",
    "detectionSource": "session_env|system_prompt|tool_fingerprint|unknown"
  },
  "items": [
    {
      "name": "context7",
      "type": "mcp",
      "host": "claudecode|codex|opencode",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "lastError": ""
    },
    {
      "name": "exa",
      "type": "mcp",
      "host": "claudecode|codex|opencode",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "credentialPrompted": true,
      "credentialSource": "prompt|state|none",
      "lastError": ""
    },
    {
      "name": "mcp-deepwiki",
      "type": "mcp",
      "host": "claudecode|codex|opencode",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "lastError": ""
    }
  ]
}
```

固定规则：

- 默认不记录真实 `EXA_API_KEY`
- 只允许记录是否问过、来源和最近一次验证结果
- 状态文件只能写到用户级数据目录，不能写回仓库

## 宿主配置路径

不同 code agent 的 MCP 配置路径固定如下，文档必须直接写死：

- `Claude Code`
  - Windows：`%USERPROFILE%\.claude.json`
  - 类 Unix：`~/.claude.json`
- `Codex`
  - Windows：`%USERPROFILE%\.codex\config.toml`
  - 类 Unix：`~/.codex/config.toml`
- `OpenCode`
  - Windows：`%USERPROFILE%\.config\opencode\opencode.json`
  - 类 Unix：`~/.config/opencode/opencode.json`

## 标准安装方式

使用 `skill-harness` setup 中的标准方式，不让 agent 自行发挥宿主配置结构。

## 1. `context7`

### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `context7`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.context7]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.context7`

### `Claude Code`

```json
{
  "mcpServers": {
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    }
  }
}
```

Windows 下可改成：

```json
{
  "mcpServers": {
    "context7": {
      "type": "stdio",
      "command": "cmd",
      "args": ["/c", "npx", "-y", "@upstash/context7-mcp@latest"]
    }
  }
}
```

### `Codex`

```toml
[mcp_servers.context7]
command = "cmd"
args = ["/c", "npx", "-y", "@upstash/context7-mcp@latest"]
```

### `OpenCode`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "context7": {
      "type": "local",
      "command": ["npx", "-y", "@upstash/context7-mcp@latest"],
      "enabled": true
    }
  }
}
```

Windows 下可写成：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "context7": {
      "type": "local",
      "command": ["cmd", "/c", "npx", "-y", "@upstash/context7-mcp@latest"],
      "enabled": true
    }
  }
}
```

## 2. `exa`

### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `exa`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.exa]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.exa`

### `Claude Code`

无 key：

```json
{
  "mcpServers": {
    "exa": {
      "url": "https://mcp.exa.ai/mcp"
    }
  }
}
```

有 key：

```json
{
  "mcpServers": {
    "exa": {
      "url": "https://mcp.exa.ai/mcp?exaApiKey=用户提供的_EXA_API_KEY"
    }
  }
}
```

### `Codex`

无 key：

```toml
[mcp_servers.exa]
url = "https://mcp.exa.ai/mcp"
```

有 key：

```toml
[mcp_servers.exa]
url = "https://mcp.exa.ai/mcp?exaApiKey=用户提供的_EXA_API_KEY"
```

只有在用户更偏好命令行时，才补充：

```powershell
codex mcp add exa --url "https://mcp.exa.ai/mcp"
```

### `OpenCode`

无 key：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "exa": {
      "type": "remote",
      "url": "https://mcp.exa.ai/mcp",
      "enabled": true
    }
  }
}
```

有 key：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "exa": {
      "type": "remote",
      "url": "https://mcp.exa.ai/mcp?exaApiKey=用户提供的_EXA_API_KEY",
      "enabled": true
    }
  }
}
```

## 3. `mcp-deepwiki`

### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `mcp-deepwiki`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.mcp-deepwiki]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.mcp-deepwiki`

### `Claude Code`

```json
{
  "mcpServers": {
    "mcp-deepwiki": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "mcp-deepwiki@latest"]
    }
  }
}
```

Windows 下可改成：

```json
{
  "mcpServers": {
    "mcp-deepwiki": {
      "type": "stdio",
      "command": "cmd",
      "args": ["/c", "npx", "-y", "mcp-deepwiki@latest"]
    }
  }
}
```

### `Codex`

```toml
[mcp_servers.mcp-deepwiki]
command = "cmd"
args = ["/c", "npx", "-y", "mcp-deepwiki@latest"]
```

### `OpenCode`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "mcp-deepwiki": {
      "type": "local",
      "command": ["npx", "-y", "mcp-deepwiki@latest"],
      "enabled": true
    }
  }
}
```

Windows 下可写成：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "mcp-deepwiki": {
      "type": "local",
      "command": ["cmd", "/c", "npx", "-y", "mcp-deepwiki@latest"],
      "enabled": true
    }
  }
}
```

## 成功标准

- 当前宿主里已经存在有效的 `context7`、`exa`、`mcp-deepwiki` 配置
- 真实检测确认三项都已注册可用
- setup 状态文件已更新到用户级数据目录
- 返回主流程前，不再存在必需 MCP 缺失项

## 常见错误

- 没先做宿主识别，就直接套用某个宿主的配置格式
- 没先检查状态文件，就直接开始调 `Context7`、`Exa` 或 `DeepWiki`
- 只看状态文件，不复验当前宿主真实环境
- 只因本机装过某个宿主命令、父进程名像某宿主，或宽泛前缀变量存在，就误判当前会话宿主
- 没写死不同宿主的配置路径，交给 agent 自己猜
- `Codex` 把 `context7` 或 `mcp-deepwiki` 错写成远程 URL 配置
- 用户明确没有 key，却仍然给 `exa` 传入占位符 key
- 用户明确有 key，却不先索取就直接写配置
