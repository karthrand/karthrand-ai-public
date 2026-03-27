# Mindmap 思维导图生成器

将自然语言描述快速转换为思维导图、流程图等可视化图表的Skill。

## 功能特性

- 🧠 **自然语言转换**：将文本描述自动整理为结构化思维导图
- 🌐 **浏览器预览**：生成后自动在浏览器中打开预览
- 📊 **多种图表**：支持思维导图、流程图、层级结构等可视化形式
- ✨ **基于 Markmap**：使用 markmap-mcp-server 提供高质量的交互式导图

## 依赖要求

⚠️ **使用本 Skill 前必须具备 `markmap-mcp-server` MCP**

本 Skill 已内置 bootstrap 脚本，但不再每次会话都执行。它将状态拆成**共享服务标志**和**宿主注册标志**两层：

- Windows：`%APPDATA%\karthrand-ai\skills\mindmap\`
- macOS/Linux：`${XDG_STATE_HOME:-$HOME/.local/state}/karthrand-ai/skills/mindmap/`

其中包含：

- `service.initialized`
- `host.claude.initialized`
- `host.codex.initialized`
- `host.opencode.initialized`

触发 bootstrap 的时机只有两种：

1. 第一次使用，检测不到共享服务标志或当前宿主标志
2. 调用 `markmap-mcp-server` 时出现环境类错误，需要强制修复

自动安装策略：

- **类 Unix（macOS/Linux）**：优先使用 `npx -y`
- **Windows**：优先全局安装包，再直接调用 `markmap-mcp-server`
- **注册方式**：优先使用 `codex mcp add` / `claude mcp add`，`opencode` 通过全局配置文件注册
- **最终回退**：原生命令失败时，写入当前用户配置文件
- **宿主目标**：bootstrap 必须显式指定 `claude`、`codex`、`opencode` 或 `all`，不再自动推断目标宿主
- **标志写入**：共享服务与宿主注册都必须通过真实验证后才会写入标志文件

如需手动安装，请根据您使用的工具选择对应方式。

### MCP 依赖安装

#### Claude Code 安装方式

##### **类 Unix (macOS/Linux)**

```bash
claude mcp add --transport stdio --scope user markmap-mcp-server -- npx -y @jinzcdev/markmap-mcp-server
```

#####  **Windows (PowerShell)**

```powershell
npm install -g @jinzcdev/markmap-mcp-server
claude mcp add --transport stdio --scope user markmap-mcp-server -- cmd /c markmap-mcp-server
```

####  Codex 安装方式

##### **类 Unix (macOS/Linux)**：

```bash
codex mcp add markmap-mcp-server -- npx -y @jinzcdev/markmap-mcp-server
```

##### **Windows (PowerShell)**：

```powershell
npm install -g @jinzcdev/markmap-mcp-server
codex mcp add markmap-mcp-server -- cmd /c markmap-mcp-server
```

#### OpenCode 安装方式

OpenCode 通过全局配置文件 `~/.config/opencode/opencode.json` 的 `mcp` 字段注册 `markmap-mcp-server`，由 bootstrap 自动写入。

### bootstrap 手动执行

如果您想先独立完成首次初始化，可直接执行：

#### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\mindmap\scripts\bootstrap.ps1 -ProjectRoot "$PWD" -SkillRoot "$PWD\skills\mindmap" -Targets claude
```

#### 类 Unix

```bash
bash ./skills/mindmap/scripts/bootstrap.sh --project-root "$PWD" --skill-root "$PWD/skills/mindmap" --targets claude
```

按实际终端宿主传入 `Targets` / `--targets`：

- `claude` 终端传 `claude`
- `codex` 终端传 `codex`
- `opencode` 终端传 `opencode`

初始化成功并通过真实验证后，才会自动写入共享服务标志和对应宿主标志。

### 验证 MCP 安装

安装完成后，可通过以下方式验证：

#### **Claude Code**：

```bash
claude mcp list
```

或在 Claude Code 会话中使用：

```
/mcp
```

#### **Codex**：

```bash
codex mcp list
```

#### **OpenCode**：

```bash
opencode mcp list
```

## 故障排查

### Windows 下 Claude Code 安装异常

优先按以下顺序处理：

1. 先执行 `npm install -g @jinzcdev/markmap-mcp-server`
2. 再执行 `claude mcp add --transport stdio --scope user markmap-mcp-server -- cmd /c markmap-mcp-server`
3. 若 `claude mcp add` 仍失败，再编辑当前用户的 `~/.claude.json`

### 强制修复

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\mindmap\scripts\bootstrap.ps1 -ProjectRoot "$PWD" -SkillRoot "$PWD\skills\mindmap" -Targets claude -Force
```

```bash
bash ./skills/mindmap/scripts/bootstrap.sh --project-root "$PWD" --skill-root "$PWD/skills/mindmap" --targets claude --force
```

按实际终端宿主传入 `Targets` / `--targets`：

- `claude` 终端传 `claude`
- `codex` 终端传 `codex`
- `opencode` 终端传 `opencode`
- 人工全量修复时才使用 `all`

仅当 `markmap-mcp-server` 出现环境类错误时才需要强制修复。

## 安装 Skill

使用 npx 方式安装：

```bash
npx skills add https://github.com/karthrand/karthrand-ai-public.git --skill mindmap
```

## 使用方式

在 cli编码工具 中直接调用：

```
/mindmap 你的内容描述
```
或者

```
上诉内容使用 mindmap skill 生成思维导图
```

**示例**：

```
/mindmap 学习路径：HTML → CSS → JavaScript → React → Node.js
```
