# Search-Web 初始化

## 何时读取

出现以下任一情况时读取本文件：

- 首次使用 `search-web`
- `search-web` 的 setup 状态文件不存在
- setup 状态文件存在，但与当前宿主中的真实安装状态不一致
- `Context7`、`Exa`、`DeepWiki`、`github-fetcher` 任一报未注册、连接失败、`server unavailable` 或类似环境类错误
- 需要为 `Claude Code`、`Codex`、`OpenCode` 或 `QwenCode` 配置 `search-web` 的必需 MCP

## 必需依赖与工具边界

本 skill 的必需 MCP 固定为：

- `context7`
- `exa`
- `mcp-deepwiki`
- `github-fetcher`

只有这四项都已安装且真实可用，才允许返回主流程。

固定边界：

- 联网搜索只能使用 `Exa`
- `Context7` 只负责技术文档
- `mcp-deepwiki` 只负责 GitHub 仓库文档
- `github-fetcher` 只负责 GitHub 仓库文件和目录读取
- 网页正文读取不属于必需 MCP；只有用户已给出明确 URL，或 `Exa` 已经定位到目标网页后，才允许使用宿主已提供的正文读取工具
- 不得把其他搜索型 MCP 当成 `Exa` 的替代品
- 不得用 `mcp-deepwiki` 替代 `github-fetcher` 的文件读取，反之亦然

## 宿主识别方式

多宿主 setup 必须先识别当前宿主，且只能调用本 skill 自己的脚本副本：

- `bash scripts/detect.sh agent` — 检测 code agent 类型
- `bash scripts/detect.sh os` — 检测运行时 OS 类型
- `bash scripts/detect.sh state-dir search-web` — 获取状态目录路径
- `bash scripts/detect.sh -v agent` — 详细模式，查看判定依据

固定规则：

1. `scripts/detect.sh` 必须是从 `skill-harness` 复制过来的物理副本，不能通过跨 skill 相对路径引用，也不能使用符号链接。
2. `bash scripts/detect.sh agent` 的输出只能是 `claude-code`、`codex`、`opencode`、`qwen-code`、`unknown`。
3. `bash scripts/detect.sh os` 的输出只能是 `windows`、`linux`、`macos`、`unknown`。
4. `bash scripts/detect.sh state-dir search-web` 输出状态目录路径，所有平台统一为 `~/.config/search-web/`。
5. 如果 agent 输出为 `unknown`，立即停止，不继续猜测配置路径，也不写入宿主专属状态。

禁止做法：

- 自行编写内联宿主检测逻辑
- 通过 `system prompt`、工具指纹、父进程名或本机命令存在性猜当前宿主
- 用跨 skill 路径调用别的检测脚本
- 在 `unknown` 状态下继续执行宿主专属 setup

## 固定决策

1. 先运行 `bash scripts/detect.sh agent` 完成宿主识别。
2. 再运行 `bash scripts/detect.sh os` 完成 OS 检测。
3. 再运行 `bash scripts/detect.sh state-dir search-web` 获取状态目录路径。
4. 读取用户级状态文件 `setup-state.json`（位于状态目录下，全平台统一为 `~/.config/search-web/setup-state.json`）。
5. 检查 `credentials` 节中 `context7` 和 `exa` 的 API Key 状态：
   - 如果 `credentials.context7.hasApiKey === false` 且 `apiKey === null`：询问用户"是否配置 Context7 API Key？"
     - 用户选择配置 → 记录 Key 到 `credentials.context7.apiKey`，设 `hasApiKey=true`
     - 用户选择跳过 → 保留 `hasApiKey=false`，不再后续询问
   - 如果 `credentials.exa.hasApiKey === false` 且 `apiKey === null`：询问用户"是否配置 Exa API Key？"
     - 用户选择配置 → 记录 Key 到 `credentials.exa.apiKey`，设 `hasApiKey=true`
     - 用户选择跳过 → 保留 `hasApiKey=false`，不再后续询问
6. 读取状态后，逐项真实检测 `context7`、`exa`、`mcp-deepwiki`、`github-fetcher` 是否已经注册可用；不能只看状态文件，也不能只看本机是否装过某个命令。
7. 四项都可用时，更新状态后立即停止，不重复 setup。
8. 任一项缺失、未注册、连接失败或状态失真时，进入对应项的 setup / repair。
9. `exa` 需要 key 时，优先从 `credentials.exa.apiKey` 读取已存储的 Key；如未存储，再询问。
10. 安装 MCP 时，`setup-mcp.sh` 自动从状态文件 `credentials` 节读取已存储的 Key 并注入。
11. 所有必需项 setup 成功后回写状态文件；失败则记录失败项和最近一次环境错误。

## 状态文件

状态文件只记录 setup 结果，不承担安装逻辑。

位置：`~/.config/search-web/setup-state.json`（全平台统一，通过 `detect.sh state-dir search-web` 获取）。

```json
{
  "version": 2,
  "updatedAt": "ISO-8601",
  "runtime": {
    "agentType": "claude-code|codex|opencode|qwen-code|unknown",
    "osType": "windows|linux|macos|unknown",
    "detectionSource": "session_env|unknown"
  },
  "stateDir": "~/.config/search-web/",
  "credentials": {
    "context7": {
      "hasApiKey": false,
      "apiKey": null
    },
    "exa": {
      "hasApiKey": false,
      "apiKey": null
    }
  },
  "items": [
    {
      "name": "context7",
      "type": "mcp",
      "host": "claude-code|codex|opencode|qwen-code",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "lastError": ""
    },
    {
      "name": "exa",
      "type": "mcp",
      "host": "claude-code|codex|opencode|qwen-code",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "lastError": ""
    },
    {
      "name": "mcp-deepwiki",
      "type": "mcp",
      "host": "claude-code|codex|opencode|qwen-code",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "lastError": ""
    },
    {
      "name": "github-fetcher",
      "type": "mcp",
      "host": "claude-code|codex|opencode|qwen-code",
      "installed": true,
      "verifiedAt": "ISO-8601",
      "lastError": ""
    }
  ]
}
```

### credentials 固定规则

- `hasApiKey=false` 且 `apiKey=null`：未配置，进入 setup 前需询问
- `hasApiKey=false` 且 `apiKey` 非空：用户曾明确跳过，不再询问（此状态不使用，跳过时保持 null）
- `hasApiKey=true` 且 `apiKey` 有值：已配置，安装 MCP 时自动从状态文件读取注入
- Key 存储在 `~/.config/search-web/setup-state.json`，内部 skill 不考虑安全问题
- 多 code agent 共享同一状态文件，只需询问一次 Key

固定规则：

- `agentType` 只能来自 `bash scripts/detect.sh agent` 的结果
- `osType` 只能来自 `bash scripts/detect.sh os` 的结果
- `stateDir` 只能来自 `bash scripts/detect.sh state-dir search-web` 的结果
- `detectionSource` 只允许记录 `session_env` 或 `unknown`
- 默认不记录真实 API Key 到 `items` 中，Key 只存储在 `credentials` 节
- 状态文件只能写到用户级数据目录，不能写回仓库

## 宿主配置路径

不同 code agent 的 MCP 配置路径固定如下：

| Agent | 配置文件路径 |
|-------|-------------|
| Claude Code | `~/.claude/settings.json` |
| Codex | `~/.codex/config.toml` |
| OpenCode | `~/.config/opencode/opencode.json` |
| QwenCode | `~/.qwen/settings.json` |

## 脚本安装方式（推荐）

本技能提供 `scripts/setup-mcp.sh` 自动安装脚本，支持根据宿主类型和 OS 类型自动选择安装命令：

```bash
# 安装 context7
bash scripts/setup-mcp.sh --mcp context7

# 安装 exa（无 API Key）
bash scripts/setup-mcp.sh --mcp exa

# 安装 exa（有 API Key）
bash scripts/setup-mcp.sh --mcp exa --api-key "EXA_API_KEY=你的key"

# 安装 context7（有 API Key）
bash scripts/setup-mcp.sh --mcp context7 --api-key "CONTEXT7_API_KEY=你的key"

# 安装 mcp-deepwiki
bash scripts/setup-mcp.sh --mcp mcp-deepwiki

# 安装 github-fetcher
bash scripts/setup-mcp.sh --mcp github-fetcher

# 强制重新安装
bash scripts/setup-mcp.sh --mcp context7 --force
```

脚本内部会自动调用 `detect.sh agent` 和 `detect.sh os` 进行检测，并从 `setup-state.json` 的 `credentials` 节读取已存储的 API Key。

## 标准安装方式

使用 `skill-harness` setup 中的标准方式，不让 agent 自行发挥宿主配置结构。

### 1. `context7`

#### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `context7`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.context7]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.context7`
- `QwenCode`：检查 `settings.json` 中是否存在 `mcpServers.context7`

#### `Claude Code`

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

#### `Codex`

```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp@latest"]
```

Windows 下可改成：

```toml
[mcp_servers.context7]
command = "cmd"
args = ["/c", "npx", "-y", "@upstash/context7-mcp@latest"]
```

#### `OpenCode`

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

#### `QwenCode`

```bash
# Unix / macOS
qwen mcp add -s user -t stdio context7 npx -y @upstash/context7-mcp@latest

# Windows
qwen mcp add -s user -t stdio context7 cmd /c npx -y @upstash/context7-mcp@latest
```

### 2. `exa`

#### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `exa`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.exa]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.exa`
- `QwenCode`：检查 `settings.json` 中是否存在 `mcpServers.exa`

#### `Claude Code`

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

有 key（优先从 `credentials.exa.apiKey` 读取）：

```json
{
  "mcpServers": {
    "exa": {
      "url": "https://mcp.exa.ai/mcp?exaApiKey=从credentials读取的_EXA_API_KEY"
    }
  }
}
```

#### `Codex`

无 key：

```toml
[mcp_servers.exa]
url = "https://mcp.exa.ai/mcp"
```

有 key：

```toml
[mcp_servers.exa]
url = "https://mcp.exa.ai/mcp?exaApiKey=从credentials读取的_EXA_API_KEY"
```

只有在用户更偏好命令行时，才补充：

```powershell
codex mcp add exa --url "https://mcp.exa.ai/mcp"
```

#### `OpenCode`

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
      "url": "https://mcp.exa.ai/mcp?exaApiKey=从credentials读取的_EXA_API_KEY",
      "enabled": true
    }
  }
}
```

#### `QwenCode`

```bash
# 无 key
qwen mcp add -s user -t http exa https://mcp.exa.ai/mcp

# 有 key
qwen mcp add -s user -t http exa "https://mcp.exa.ai/mcp?exaApiKey=从credentials读取的_EXA_API_KEY"
```

### 3. `mcp-deepwiki`

#### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `mcp-deepwiki`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.mcp-deepwiki]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.mcp-deepwiki`
- `QwenCode`：检查 `settings.json` 中是否存在 `mcpServers.mcp-deepwiki`

#### `Claude Code`

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

#### `Codex`

```toml
[mcp_servers.mcp-deepwiki]
command = "npx"
args = ["-y", "mcp-deepwiki@latest"]
```

Windows 下可改成：

```toml
[mcp_servers.mcp-deepwiki]
command = "cmd"
args = ["/c", "npx", "-y", "mcp-deepwiki@latest"]
```

#### `OpenCode`

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

#### `QwenCode`

```bash
# Unix / macOS
qwen mcp add -s user -t stdio mcp-deepwiki npx -y mcp-deepwiki@latest

# Windows
qwen mcp add -s user -t stdio mcp-deepwiki cmd /c npx -y mcp-deepwiki@latest
```

### 4. `github-fetcher`

#### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `github-fetcher`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.github-fetcher]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.github-fetcher`
- `QwenCode`：检查 `settings.json` 中是否存在 `mcpServers.github-fetcher`

#### `Claude Code`

```json
{
  "mcpServers": {
    "github-fetcher": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "github-fetcher-mcp"]
    }
  }
}
```

Windows 下可改成：

```json
{
  "mcpServers": {
    "github-fetcher": {
      "type": "stdio",
      "command": "cmd",
      "args": ["/c", "npx", "-y", "github-fetcher-mcp"]
    }
  }
}
```

#### `Codex`

```toml
[mcp_servers.github-fetcher]
command = "npx"
args = ["-y", "github-fetcher-mcp"]
```

Windows 下可改成：

```toml
[mcp_servers.github-fetcher]
command = "cmd"
args = ["/c", "npx", "-y", "github-fetcher-mcp"]
```

#### `OpenCode`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "github-fetcher": {
      "type": "local",
      "command": ["npx", "-y", "github-fetcher-mcp"],
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
    "github-fetcher": {
      "type": "local",
      "command": ["cmd", "/c", "npx", "-y", "github-fetcher-mcp"],
      "enabled": true
    }
  }
}
```

#### `QwenCode`

```bash
# Unix / macOS
qwen mcp add -s user -t stdio github-fetcher npx -y github-fetcher-mcp

# Windows
qwen mcp add -s user -t stdio github-fetcher cmd /c npx -y github-fetcher-mcp
```

## 成功标准

- 当前宿主里已经存在有效的 `context7`、`exa`、`mcp-deepwiki`、`github-fetcher` 配置
- 宿主识别由 `bash scripts/detect.sh agent` 完成，且结果不是 `unknown`
- OS 检测由 `bash scripts/detect.sh os` 完成，且结果不是 `unknown`
- 状态目录由 `bash scripts/detect.sh state-dir search-web` 获取
- 真实检测确认四项都已注册可用
- setup 状态文件已更新到用户级数据目录
- 返回主流程前，不再存在必需 MCP 缺失项

## 常见错误

- 没先运行 `bash scripts/detect.sh agent`，就直接套用某个宿主的配置格式
- 继续保留手写的环境变量 / prompt / 工具指纹探测逻辑
- 没先检查状态文件，就直接开始调 `Context7`、`Exa`、`DeepWiki` 或 `github-fetcher`
- 只看状态文件，不复验当前宿主真实环境
- 通过跨 skill 相对路径调用别的检测脚本
- 没写死不同宿主的配置路径，交给 agent 自己猜
- `Codex` 把 `context7`、`mcp-deepwiki` 或 `github-fetcher` 错写成远程 URL 配置
- 用户明确没有 key，却仍然给 `exa` 传入占位符 key
- 用户明确有 key，却不先索取就直接写配置
- 把其他搜索型 MCP 当成 `Exa` 的备选搜索工具
- 用 `mcp-deepwiki` 替代 `github-fetcher` 的文件读取，或反之
- 状态文件写到仓库内而非 `~/.config/search-web/`