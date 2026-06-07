# Search-Web 初始化

## 何时读取

出现以下任一情况时读取本文件：

- `bash scripts/detect.sh` 输出 `initialized=false`（标志文件不存在）
- `Context7`、`Exa`、`DeepWiki`、`github-fetcher` 任一报未注册、连接失败、`server unavailable` 或类似环境类错误
- `Exa` 失败后需要启用 `TinyFish` 备用搜索，但 `TinyFish` CLI、`credentials/tinyfish` 或 `TINYFISH_API_KEY` 未配置
- 需要为 `Claude Code`、`Codex`、`OpenCode`、`QwenCode`、`Hermes` 或 `Pi` 配置 `search-web` 的必需 MCP

## 必需依赖与工具边界

本 skill 的必需 MCP 固定为：

- `context7`
- `exa`
- `mcp-deepwiki`
- `github-fetcher`

可选 CLI 备用依赖：

- `tinyfish`（通过 `npm install -g @tiny-fish/cli` 安装）

安装完成后创建标志文件并告知用户重启。新安装的 MCP 在重启后生效，当前会话无法使用。

指定偏好与边界：

- 联网搜索优先使用 `Exa`，仅在 `Exa` 搜索失败、额度到限、服务不可用或空结果时使用 `TinyFish` CLI
- `Context7` 只负责技术文档
- `mcp-deepwiki` 只负责 GitHub 仓库文档
- `github-fetcher` 只负责 GitHub 仓库文件和目录读取
- 网页正文读取不属于必需 MCP；只有用户已给出明确 URL，或 `Exa` / `TinyFish` 已经定位到目标网页后，才允许使用宿主已提供的正文读取工具
- 不得把其他搜索型 MCP 当成 `Exa` 的替代品；指定备用只允许 `TinyFish` CLI
- 不得用 `mcp-deepwiki` 替代 `github-fetcher` 的文件读取，反之亦然

## 宿主识别方式

多宿主 setup 必须先识别当前宿主，调用本 skill 自己的脚本副本：

```bash
bash scripts/detect.sh
```

单次调用，无参数，输出四行：
```
agent=claude-code
os=windows
state_dir=C:/Users/Administrator/.config/search-web/
initialized=true
```

固定规则：

1. `scripts/detect.sh` 必须是从 `skill-harness` 复制过来的物理副本，不能通过跨 skill 相对路径引用，也不能使用符号链接。
2. `agent` 只能是 `claude-code`、`codex`、`opencode`、`qwen-code`、`hermes`、`pi`、`unknown`。
3. `os` 只能是 `windows`、`linux`、`macos`、`unknown`。
4. `state_dir` 所有平台统一为 `~/.config/search-web/`。
5. `initialized` 通过标志文件 `state_dir/{agent}` 是否存在判定；`agent=unknown` 时跳过标志文件检查，直接视为已初始化。
6. 如果 `agent` 输出为 `unknown`，跳过 setup 直接走搜索流程；MCP 在实际调用时不可用则停止并告知用户需手动配置。

禁止做法：

- 自行编写内联宿主检测逻辑
- 通过 `system prompt`、工具指纹、父进程名或本机命令存在性猜当前宿主
- 用跨 skill 路径调用别的检测脚本

## 固定决策

1. 运行 `bash scripts/detect.sh`（无参数），获取 agent、os、state_dir、initialized 四项信息。
2. 检查 `credentials/` 目录下 `context7`、`exa` 和 `tinyfish` 文件：
   - 文件不存在或为空：询问用户"是否配置 API Key？"
     - 用户选择配置 → 写入 Key 值到对应文件
     - 用户选择跳过 → 写入 "skipped" 到对应文件，后续不再询问
   - 文件内容为 "skipped"：用户曾明确跳过，不再询问
   - 文件内容为其他值：已配置，安装 MCP 时自动读取注入
   - `exa` 的 API Key 为可选；不提供 Key 时使用无 Key URL（`https://mcp.exa.ai/mcp`），安装后仍可正常使用
   - `tinyfish` 的 API Key 必须同步到永久环境变量 `TINYFISH_API_KEY`；如果 `credentials/tinyfish` 已存在且非空，跳过询问，直接确保环境变量已写入；如果 `credentials/tinyfish` 缺失但当前环境已有 `TINYFISH_API_KEY`，先写回 `credentials/tinyfish` 并跳过询问
3. 调用一次 `xxx mcp list`（如 `claude mcp list`），将输出存为变量，逐项 grep 检查 `context7`、`exa`、`mcp-deepwiki`、`github-fetcher` 是否已安装。
   - 已安装的跳过，未安装的执行 `setup-mcp.sh` 安装。
   - `mcp list` 只调用一次，后续全部 grep 变量判断，严禁每个 MCP 单独调用。
4. 仅在需要启用 `TinyFish` 备用搜索，或用户已配置 `credentials/tinyfish` 时检查 `tinyfish` CLI：
   - 未安装：提示运行 `npm install -g @tiny-fish/cli`
   - 已安装：继续使用 `credentials/tinyfish` 和 `TINYFISH_API_KEY` 管理备用搜索能力
5. 所有缺失 MCP 安装完成后，创建标志文件 `{state_dir}/{agent}`，使 `initialized=true`。
6. 四项 MCP 都可用时，返回主流程，不重复 setup。
7. `exa` 需要 key 时，优先从 `credentials/exa` 文件读取已存储的 Key；如未存储，再询问。

## 状态管理

使用目录结构 + 平面文件，零解析依赖。位置：`~/.config/search-web/`（全平台统一）。

```
~/.config/search-web/
  claude-code                        # initialized 标志文件（detect.sh 管理）
  codex                              # 其他 agent 的标志文件
  credentials/
    context7                         # API Key 值、"skipped"、或空
    exa                              # API Key 值、"skipped"、或空
    tinyfish                         # API Key 值、"skipped"、或空；非 skipped 时同步到 TINYFISH_API_KEY
```

### 标志文件规则

- 标志文件名即 agent 类型（如 `claude-code`、`codex`），存在即表示该 agent 已完成 setup
- `detect.sh` 通过检查 `{state_dir}/{agent}` 文件是否存在来判定 `initialized`
- 安装完成后由 `setup-mcp.sh` 创建，不手动管理
- 删除标志文件即触发下次使用时重新 setup

### credentials 固定规则

- 文件不存在或为空：未配置，进入 setup 前需询问
- 文件内容为 "skipped"：用户曾明确跳过，不再询问
- 文件内容为其他值：已配置，安装 MCP 时自动读取注入
- Key 存储在 `credentials/` 目录下的独立文件中，跨 agent 共享
- 多 code agent 共享同一 `credentials/`，只需询问一次 Key
- `credentials/tinyfish` 文件内容为其他值时，后续 setup 不再询问用户，但必须确保该值已永久写入 `TINYFISH_API_KEY`

## TinyFish CLI 备用搜索

`TinyFish` 是 `Exa` 的备用 CLI，不是 MCP，不加入 `setup-mcp.sh --mcp all`。

### 安装与检测

```bash
npm install -g @tiny-fish/cli
tinyfish --version
```

如果 `tinyfish --version` 失败，说明 CLI 未安装或不在 `PATH` 中。此时不要尝试使用 TinyFish 搜索，直接提示安装命令。

### API Key 固定规则

- Key 文件固定为 `{state_dir}/credentials/tinyfish`
- 环境变量固定为 `TINYFISH_API_KEY`
- `credentials/tinyfish` 不存在或为空时，询问用户是否配置 TinyFish API Key
- `credentials/tinyfish` 不存在或为空，但当前环境已有 `TINYFISH_API_KEY` 时，先把环境变量值写入 `credentials/tinyfish`，并跳过询问
- 用户提供 Key 后，先写入 `credentials/tinyfish`，再永久写入 `TINYFISH_API_KEY`
- 用户跳过时，写入 `skipped`，后续不再询问；TinyFish 备用链路不可用时直接说明
- `credentials/tinyfish` 已存在且非空时，跳过询问；如果值不是 `skipped`，用该值写入或更新永久环境变量

### 类 Unix 写入方式

类 Unix 环境只检查和写入 `~/.bashrc`：

```bash
# 查看当前会话
printf '%s\n' "${TINYFISH_API_KEY:-}"

# 查看 ~/.bashrc 是否已有配置
[ -f ~/.bashrc ] && grep -n 'TINYFISH_API_KEY' ~/.bashrc || true

# 写入或更新后，让当前会话立即可用
export TINYFISH_API_KEY="从credentials/tinyfish读取的key"
```

如果 `~/.bashrc` 没有 `TINYFISH_API_KEY`，追加：

```bash
touch ~/.bashrc
export TINYFISH_API_KEY="从credentials/tinyfish读取的key"
```

如果 `~/.bashrc` 已有 `TINYFISH_API_KEY`，更新为 `credentials/tinyfish` 中的值，不重复追加多行。

### Windows PowerShell 写入方式

Windows 下使用用户级环境变量，不写系统级环境变量：

```powershell
# 查看用户级环境变量
[Environment]::GetEnvironmentVariable("TINYFISH_API_KEY", "User")

# 永久写入用户级环境变量
[Environment]::SetEnvironmentVariable("TINYFISH_API_KEY", "从credentials/tinyfish读取的key", "User")

# 写入当前 PowerShell 会话
$env:TINYFISH_API_KEY = "从credentials/tinyfish读取的key"
```

如果用户级环境变量已有值，但 `credentials/tinyfish` 也已有非空非 `skipped` 值，以 `credentials/tinyfish` 为准并更新用户级环境变量。

## 宿主配置路径

不同 code agent 的 MCP 配置路径固定如下：

| Agent | 配置文件路径 |
|-------|-------------|
| Claude Code | `~/.claude/settings.json` |
| Codex | `~/.codex/config.toml` |
| OpenCode | `~/.config/opencode/opencode.json` |
| QwenCode | `~/.qwen/settings.json` |
| Hermes | `~/.hermes/config.yaml` |
| Pi | `~/.pi/agent/mcp.json` |

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

# 批量安装全部四项（跳过已安装的）
bash scripts/setup-mcp.sh --mcp all

# 批量强制重装
bash scripts/setup-mcp.sh --mcp all --force
```

脚本内部会自动调用 `detect.sh`（单次）获取 agent/os/state_dir，调用一次 `xxx mcp list` 检测已安装的 MCP，并从 `credentials/` 目录读取已存储的 API Key。

`TinyFish` 不是 MCP，不通过 `setup-mcp.sh` 安装。需要单独使用：

```bash
npm install -g @tiny-fish/cli
```

## 标准安装方式

使用 `skill-harness` setup 中的标准方式，不让 agent 自行发挥宿主配置结构。

### 1. `context7`

#### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `context7`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.context7]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.context7`
- `QwenCode`：检查 `settings.json` 中是否存在 `mcpServers.context7`
- `Hermes`：检查 `config.yaml` 的 `mcp_servers` 中是否存在 `context7`
- `Pi`：检查 `mcp.json` 的 `mcpServers` 中是否存在 `context7`

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

#### `Hermes`

```bash
# Unix / macOS
hermes mcp add context7 --command "npx" --args "-y @upstash/context7-mcp@latest"

# Windows
hermes mcp add context7 --command "cmd" --args "/c npx -y @upstash/context7-mcp@latest"
```

或手动编辑 `~/.hermes/config.yaml`：

```yaml
mcp_servers:
  context7:
    command: "npx"
    args: ["-y", "@upstash/context7-mcp@latest"]
```

Windows：

```yaml
mcp_servers:
  context7:
    command: "cmd"
    args: ["/c", "npx", "-y", "@upstash/context7-mcp@latest"]
```

#### `Pi`

手动编辑 `~/.pi/agent/mcp.json`，在 `mcpServers` 对象内添加：

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    }
  }
}
```

Windows：

```json
{
  "mcpServers": {
    "context7": {
      "command": "cmd",
      "args": ["/c", "npx", "-y", "@upstash/context7-mcp@latest"]
    }
  }
}
```

### 2. `exa`

#### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `exa`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.exa]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.exa`
- `QwenCode`：检查 `settings.json` 中是否存在 `mcpServers.exa`
- `Hermes`：检查 `config.yaml` 的 `mcp_servers` 中是否存在 `exa`
- `Pi`：检查 `mcp.json` 的 `mcpServers` 中是否存在 `exa`

```json
{
  "mcpServers": {
    "exa": {
      "url": "https://mcp.exa.ai/mcp"
    }
  }
}
```

有 key（优先从 `credentials/exa` 文件读取）：

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

#### `Hermes`

无 key：

```bash
hermes mcp add exa --url "https://mcp.exa.ai/mcp"
```

有 key：

```bash
hermes mcp add exa --url "https://mcp.exa.ai/mcp?exaApiKey=从credentials读取的_EXA_API_KEY"
```

或手动编辑 `~/.hermes/config.yaml`：

```yaml
mcp_servers:
  exa:
    url: "https://mcp.exa.ai/mcp"
```

#### `Pi`

手动编辑 `~/.pi/agent/mcp.json`，在 `mcpServers` 对象内添加：

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
      "url": "https://mcp.exa.ai/mcp?exaApiKey=从credentials读取的_EXA_API_KEY"
    }
  }
}
```

### 3. `mcp-deepwiki`

#### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `mcp-deepwiki`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.mcp-deepwiki]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.mcp-deepwiki`
- `QwenCode`：检查 `settings.json` 中是否存在 `mcpServers.mcp-deepwiki`
- `Hermes`：检查 `config.yaml` 的 `mcp_servers` 中是否存在 `mcp-deepwiki`
- `Pi`：检查 `mcp.json` 的 `mcpServers` 中是否存在 `mcp-deepwiki`

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

#### `Hermes`

```bash
# Unix / macOS
hermes mcp add mcp-deepwiki --command "npx" --args "-y mcp-deepwiki@latest"

# Windows
hermes mcp add mcp-deepwiki --command "cmd" --args "/c npx -y mcp-deepwiki@latest"
```

或手动编辑 `~/.hermes/config.yaml`：

```yaml
mcp_servers:
  mcp-deepwiki:
    command: "npx"
    args: ["-y", "mcp-deepwiki@latest"]
```

#### `Pi`

手动编辑 `~/.pi/agent/mcp.json`，在 `mcpServers` 对象内添加：

```json
{
  "mcpServers": {
    "mcp-deepwiki": {
      "command": "npx",
      "args": ["-y", "mcp-deepwiki@latest"]
    }
  }
}
```

Windows：

```json
{
  "mcpServers": {
    "mcp-deepwiki": {
      "command": "cmd",
      "args": ["/c", "npx", "-y", "mcp-deepwiki@latest"]
    }
  }
}
```

### 4. `github-fetcher`

#### 检测方式

- `Claude Code`：检查 `mcpServers` 中是否存在 `github-fetcher`
- `Codex`：检查 `config.toml` 中是否存在 `[mcp_servers.github-fetcher]`
- `OpenCode`：检查 `opencode.json` 中是否存在 `mcp.github-fetcher`
- `QwenCode`：检查 `settings.json` 中是否存在 `mcpServers.github-fetcher`
- `Hermes`：检查 `config.yaml` 的 `mcp_servers` 中是否存在 `github-fetcher`
- `Pi`：检查 `mcp.json` 的 `mcpServers` 中是否存在 `github-fetcher`

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

#### `Hermes`

```bash
# Unix / macOS
hermes mcp add github-fetcher --command "npx" --args "-y github-fetcher-mcp"

# Windows
hermes mcp add github-fetcher --command "cmd" --args "/c npx -y github-fetcher-mcp"
```

或手动编辑 `~/.hermes/config.yaml`：

```yaml
mcp_servers:
  github-fetcher:
    command: "npx"
    args: ["-y", "github-fetcher-mcp"]
```

#### `Pi`

手动编辑 `~/.pi/agent/mcp.json`，在 `mcpServers` 对象内添加：

```json
{
  "mcpServers": {
    "github-fetcher": {
      "command": "npx",
      "args": ["-y", "github-fetcher-mcp"]
    }
  }
}
```

Windows：

```json
{
  "mcpServers": {
    "github-fetcher": {
      "command": "cmd",
      "args": ["/c", "npx", "-y", "github-fetcher-mcp"]
    }
  }
}
```

## 成功标准

- 缺失的 MCP 已通过 `setup-mcp.sh` 安装（注册到配置文件）
- 标志文件 `{state_dir}/{agent}` 已创建
- 告知用户需要重启以激活新安装的 MCP
- 重启后四项 MCP 均应可用

## 重启说明

`claude mcp add` / `codex mcp add` / `hermes mcp add` / `pi`（手动编辑 mcp.json）等命令将 MCP 注册到配置文件，但不会在当前会话中加载。这是所有 code agent 的共同行为：
- 安装完成后，MCP 配置已写入，但当前会话仍无法使用
- 用户重启 code agent 后，新 MCP 才会被加载
- 安装完成后应告知用户重启，不在当前会话中尝试使用未加载的 MCP

## 常见错误

- 没先运行 `bash scripts/detect.sh`，就直接套用某个宿主的配置格式
- 继续保留手写的环境变量 / prompt / 工具指纹探测逻辑
- 每检测一个 MCP 就调用一次 `mcp list`（应只调一次，结果存变量 grep 判断）
- 通过跨 skill 相对路径调用别的检测脚本
- 没写死不同宿主的配置路径，交给 agent 自己猜
- `Codex` 把 `context7`、`mcp-deepwiki` 或 `github-fetcher` 错写成远程 URL 配置
- 用户明确没有 key，却仍然给 `exa` 传入占位符 key
- 用户明确有 key，却不先索取就直接写配置
- 把其他搜索型 MCP 当成 `Exa` 的备选搜索工具；指定备用只允许 `TinyFish` CLI
- `credentials/tinyfish` 已有非空值时仍重复询问用户
- 写入 `credentials/tinyfish` 后没有同步写入永久环境变量 `TINYFISH_API_KEY`
- Windows 下写入系统级环境变量而不是用户级环境变量
- 安装 MCP 后不提示用户重启
- 用 `mcp-deepwiki` 替代 `github-fetcher` 的文件读取，或反之
