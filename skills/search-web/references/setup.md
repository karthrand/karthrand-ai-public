# Search-Web 初始化

## 何时读取

出现以下任一情况时读取本文件：

- 首次使用 `search-web`
- `search-web` 的 setup 状态文件不存在
- setup 状态文件存在，但与当前宿主中的真实安装状态不一致
- `Context7`、`Exa`、`DeepWiki` 任一报未注册、连接失败、`server unavailable` 或类似环境类错误
- 需要为 `Claude Code`、`Codex` 或 `OpenCode` 配置 `search-web` 的必需 MCP

## 必需依赖与工具边界

本 skill 的必需 MCP 固定为：

- `context7`
- `exa`
- `mcp-deepwiki`

只有这三项都已安装且真实可用，才允许返回主流程。

固定边界：

- 联网搜索只能使用 `Exa`
- `Context7` 只负责技术文档
- `mcp-deepwiki` 只负责 GitHub 仓库
- 网页正文读取不属于必需 MCP；只有用户已给出明确 URL，或 `Exa` 已经定位到目标网页后，才允许使用宿主已提供的正文读取工具
- 不得把其他搜索型 MCP 当成 `Exa` 的替代品

## 宿主识别方式

多宿主 setup 必须先识别当前宿主，且只能调用本 skill 自己的脚本副本：

- `sh scripts/detect-agent.sh`
- `sh scripts/detect-agent.sh -v`

固定规则：

1. `scripts/detect-agent.sh` 必须是从 `skill-harness` 复制过来的物理副本，不能通过跨 skill 相对路径引用，也不能使用符号链接。
2. `sh scripts/detect-agent.sh` 的输出只能是 `claude-code`、`codex`、`opencode`、`unknown`。
3. 如果输出为 `unknown`，立即停止，不继续猜测配置路径，也不写入宿主专属状态。
4. 如果需要查看判定依据，才运行 `sh scripts/detect-agent.sh -v`。

禁止做法：

- 自行编写内联宿主检测逻辑
- 通过 `system prompt`、工具指纹、父进程名或本机命令存在性猜当前宿主
- 用跨 skill 路径调用别的 `detect-agent.sh`
- 在 `unknown` 状态下继续执行宿主专属 setup

## 固定决策

1. 先运行 `sh scripts/detect-agent.sh` 完成宿主识别。
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
    "agentType": "claude-code|codex|opencode|unknown",
    "detectionSource": "session_env|unknown"
  },
  "items": [
    {
      "name": "context7",
      "type": "mcp",
      "host": "claude-code|codex|opencode",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "lastError": ""
    },
    {
      "name": "exa",
      "type": "mcp",
      "host": "claude-code|codex|opencode",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "credentialPrompted": true,
      "credentialSource": "prompt|state|none",
      "lastError": ""
    },
    {
      "name": "mcp-deepwiki",
      "type": "mcp",
      "host": "claude-code|codex|opencode",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "lastError": ""
    }
  ]
}
```

固定规则：

- `agentType` 只能来自 `scripts/detect-agent.sh` 的结果
- `detectionSource` 只允许记录 `session_env` 或 `unknown`
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
- 宿主识别由 `sh scripts/detect-agent.sh` 完成，且结果不是 `unknown`
- 真实检测确认三项都已注册可用
- setup 状态文件已更新到用户级数据目录
- 返回主流程前，不再存在必需 MCP 缺失项

## 常见错误

- 没先运行 `sh scripts/detect-agent.sh`，就直接套用某个宿主的配置格式
- 继续保留手写的环境变量 / prompt / 工具指纹探测逻辑
- 没先检查状态文件，就直接开始调 `Context7`、`Exa` 或 `DeepWiki`
- 只看状态文件，不复验当前宿主真实环境
- 通过跨 skill 相对路径调用别的 `detect-agent.sh`
- 没写死不同宿主的配置路径，交给 agent 自己猜
- `Codex` 把 `context7` 或 `mcp-deepwiki` 错写成远程 URL 配置
- 用户明确没有 key，却仍然给 `exa` 传入占位符 key
- 用户明确有 key，却不先索取就直接写配置
- 把其他搜索型 MCP 当成 `Exa` 的备选搜索工具
