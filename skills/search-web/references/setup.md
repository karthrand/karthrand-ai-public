# Search-Web Setup 参考

## 目录

- 何时读取
- 固定决策
- 状态管理
- 密钥与依赖规则
- 脚本安装方式（推荐）
- 通用 MCP JSON
- Pi 专项：extension + mcp.json
- 手动配置参考（自动安装失败时）
- 成功标准
- 常见错误

## 何时读取

只有出现以下任一情况时读取本文件：

- 用户调用 `$search-web setup`
- 用户明确要求配置、修复或重新安装 `search-web` 的搜索依赖
- 普通搜索中 MCP 报未注册、未加载、连接失败或 `server unavailable`，需要向用户解释 setup 流程

## 固定决策

1. `setup` 第一步运行 `bash scripts/detect.sh`，获取 `agent`、`os`、`state_dir`。
2. 检查 npm 是否可用；不可用则停止并提示安装 Node.js/npm。
3. 确保 `tinyfish` CLI 可用（`npm install -g @tiny-fish/cli@latest`）。其余 3 个 MCP server 由 `npx -y` 按需拉取，不全局安装。
4. 对支持的 code agent 检测四项 MCP 是否已安装：
   - claude-code/codex/qwen-code/hermes：调用一次 `xxx mcp list`，grep 判断。
   - opencode：优先调用 `opencode mcp list`，不可用时读 `~/.config/opencode/opencode.json` 判断。
   - pi：原生无 MCP list 子命令，优先读项目 `.pi/mcp.json`，不存在时读 `~/.pi/agent/mcp.json` 判断。
5. 对缺失的 MCP 执行安装；`exa` 必需 Exa API Key，安装前询问并直接写入 MCP URL。
6. 检查 `TINYFISH_API_KEY`；不存在则询问并永久写入。
7. 未知 code agent：不自动写配置，输出含 Exa Key 的通用 MCP JSON 示例。
8. `opencode` 和 `pi` 属于手动配置型 agent：只输出配置片段，用户编辑后重启即可。
9. `pi` 走完整流程：先 `pi install npm:pi-mcp-extension`，再按 pi-mcp-extension 格式编辑 `~/.pi/agent/mcp.json` 或 `.pi/mcp.json`。
10. setup 完成后提示用户重启 code agent。

## 状态管理

状态目录由 `detect.sh` 输出的 `state_dir` 决定，默认位于 `~/.config/search-web/`，仅供诊断与脚本内部定位使用。

- 普通搜索不依赖 `detect.sh`，也不存在初始化标志文件。
- 不读写本地密钥文件；Exa Key 只写入 MCP URL，TinyFish Key 只写入永久环境变量。

## 密钥与依赖规则

### Context7

固定使用 `@upstash/context7-mcp@latest`，不使用 API Key，不询问 Context7 Key。

### Exa

是 remote MCP。**Exa API Key 必需**：检测到 exa 缺失并安装时必须询问并获取 Key，为空则中止；Key 直接写入 MCP URL（`https://mcp.exa.ai/mcp?exaApiKey=...`），不保存到本地文件。非交互调用（stdin 非 TTY，例如被其他工具通过管道调用）必须通过 `--api-key "EXA_API_KEY=..."` 传入，否则脚本直接报错退出。

### TinyFish

通过 `npm install -g @tiny-fish/cli@latest` 安装。`TINYFISH_API_KEY` 不写入文件；Windows 写用户级环境变量，类 Unix 写 `~/.bashrc`，macOS zsh 同步写 `~/.zshrc`（`$SHELL` 含 zsh 或 `~/.zshrc` 已存在时）。该写入需永久生效，非交互（非 TTY）环境下请在终端手动执行。

Windows PowerShell：

```powershell
[Environment]::SetEnvironmentVariable("TINYFISH_API_KEY", "你的TinyFishKey", "User")
$env:TINYFISH_API_KEY = "你的TinyFishKey"
```

类 Unix：

```bash
echo 'export TINYFISH_API_KEY="你的TinyFishKey"' >> ~/.bashrc
export TINYFISH_API_KEY="你的TinyFishKey"
```

## 脚本安装方式（推荐）

```bash
# 完整 setup，默认安装全部 MCP
bash scripts/setup-mcp.sh --api-key "EXA_API_KEY=你的ExaKey"

# 单项调试
bash scripts/setup-mcp.sh --mcp exa --api-key "EXA_API_KEY=你的ExaKey"
bash scripts/setup-mcp.sh --mcp context7
bash scripts/setup-mcp.sh --mcp mcp-deepwiki
bash scripts/setup-mcp.sh --mcp github-fetcher
```

脚本内部会自动调用 `detect.sh` 获取 agent/os/state_dir，调用一次 MCP list 检测已安装项，并按需写入 MCP 配置。MCP 注册后不会自动进入当前会话，必须重启 code agent。

## 通用 MCP JSON

当 code agent 未识别时，脚本输出通用 MCP JSON。手动配置时也可参考：

```json
{
  "mcpServers": {
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "exa": {
      "type": "http",
      "url": "https://mcp.exa.ai/mcp?exaApiKey=你的ExaKey"
    },
    "mcp-deepwiki": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "mcp-deepwiki@latest"]
    },
    "github-fetcher": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "github-fetcher-mcp@latest"]
    }
  }
}
```

## Pi 专项：extension + mcp.json

原生 Pi（`@mariozechner/pi-coding-agent`）**没有** MCP add/list 内建命令，接 MCP 必须通过 extension。

### 1. 安装 extension（一次性）

```bash
pi install npm:pi-mcp-extension
pi list
```

### 2. 编辑配置文件

- 全局：`~/.pi/agent/mcp.json`
- 项目：`.pi/mcp.json`（覆盖全局；脚本检测时优先读取）

Pi-mcp-extension 的 server 用 `transport`（不是 `type`）+ `lifecycle` 字段。完整示例：

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "transport": "stdio",
      "lifecycle": "lazy"
    },
    "exa": {
      "transport": "streamable-http",
      "url": "https://mcp.exa.ai/mcp?exaApiKey=你的ExaKey",
      "lifecycle": "eager"
    },
    "mcp-deepwiki": {
      "command": "npx",
      "args": ["-y", "mcp-deepwiki@latest"],
      "transport": "stdio",
      "lifecycle": "lazy"
    },
    "github-fetcher": {
      "command": "npx",
      "args": ["-y", "github-fetcher-mcp@latest"],
      "transport": "stdio",
      "lifecycle": "lazy"
    }
  }
}
```

- `transport`：`stdio`（本地进程）、`streamable-http`（远程，推荐）、`sse`（旧版兼容）。
- `lifecycle`：`eager`（会话启动即连）、`lazy`（手动 `/mcp:start`）。远程建议 `eager`，本地 stdio 建议 `lazy`。

### 3. 验证

编辑后重启 pi，在会话内输入 `/mcp` 查看连接状态；`/mcp <server>` 看详情，`/mcp:start <server>` 手动启动 lazy server。

## 手动配置参考（自动安装失败时）

正常情况由 `setup-mcp.sh` 自动处理，无需手动编辑。以下仅在自动安装失败或 code agent 未被识别时作参考。

### Claude Code

```bash
claude mcp add-json -s user context7 '{"type":"stdio","command":"npx","args":["-y","@upstash/context7-mcp@latest"]}'
claude mcp add --transport http -s user exa "https://mcp.exa.ai/mcp?exaApiKey=你的ExaKey"
claude mcp add-json -s user mcp-deepwiki '{"type":"stdio","command":"npx","args":["-y","mcp-deepwiki@latest"]}'
claude mcp add-json -s user github-fetcher '{"type":"stdio","command":"npx","args":["-y","github-fetcher-mcp@latest"]}'
```

Windows 下 stdio 命令可改为 `cmd /c npx -y <package>`。

### Codex

```bash
codex mcp add context7 -- npx -y @upstash/context7-mcp@latest
codex mcp add exa --url "https://mcp.exa.ai/mcp?exaApiKey=你的ExaKey"
codex mcp add mcp-deepwiki -- npx -y mcp-deepwiki@latest
codex mcp add github-fetcher -- npx -y github-fetcher-mcp@latest
```

Windows 下 stdio 命令可改为 `cmd /c npx -y <package>`。

### OpenCode

编辑 `~/.config/opencode/opencode.json`，在 MCP 配置对象内加入，编辑后重启 opencode 即可：

```json
{
  "context7": {
    "type": "local",
    "command": ["npx", "-y", "@upstash/context7-mcp@latest"],
    "enabled": true
  },
  "exa": {
    "type": "remote",
    "url": "https://mcp.exa.ai/mcp?exaApiKey=你的ExaKey",
    "enabled": true
  },
  "mcp-deepwiki": {
    "type": "local",
    "command": ["npx", "-y", "mcp-deepwiki@latest"],
    "enabled": true
  },
  "github-fetcher": {
    "type": "local",
    "command": ["npx", "-y", "github-fetcher-mcp@latest"],
    "enabled": true
  }
}
```

### Qwen Code

```bash
qwen mcp add -s user -t stdio context7 npx -y @upstash/context7-mcp@latest
qwen mcp add -s user -t http exa "https://mcp.exa.ai/mcp?exaApiKey=你的ExaKey"
qwen mcp add -s user -t stdio mcp-deepwiki npx -y mcp-deepwiki@latest
qwen mcp add -s user -t stdio github-fetcher npx -y github-fetcher-mcp@latest
```

### Hermes

```bash
hermes mcp add context7 --command "npx" --args "-y @upstash/context7-mcp@latest"
hermes mcp add exa --url "https://mcp.exa.ai/mcp?exaApiKey=你的ExaKey"
hermes mcp add mcp-deepwiki --command "npx" --args "-y mcp-deepwiki@latest"
hermes mcp add github-fetcher --command "npx" --args "-y github-fetcher-mcp@latest"
```

### Pi

不要使用 Pi 的 MCP add 子命令。按上文“Pi 专项”安装 `pi-mcp-extension` 并编辑 `~/.pi/agent/mcp.json`。

## 成功标准

- 普通 `$search-web` 不运行 `detect.sh`。
- `$search-web setup` 才执行 setup 流程。
- Context7 不询问、不使用 API Key。
- Exa API Key 必需，缺失时中止。
- 全局 npm 安装仅 `@tiny-fish/cli@latest`。
- 3 个本地 MCP server 由 `npx -y` 按需拉取。
- Pi 使用 `pi-mcp-extension`、`transport` 和 `lifecycle` 配置。
- setup 后提示重启 code agent。

## 常见错误

- 把 Context7 当成需要 Key 的 MCP。
- Exa 未提供 Key 时继续安装无 Key URL。
- 把 `TinyFish` 当成 MCP 安装。
- 对 Pi 调用不存在的 MCP add/list 子命令。
- 写完 MCP 配置后不重启 code agent。
