# Mindmap 思维导图生成器

将自然语言描述快速转换为思维导图、流程图等可视化图表的Skill。

## 功能特性

- 🧠 **自然语言转换**：将文本描述自动整理为结构化思维导图
- 🌐 **浏览器预览**：生成后自动在浏览器中打开预览
- 📊 **多种图表**：支持思维导图、流程图、层级结构等可视化形式
- ✨ **基于 Markmap**：使用 markmap-mcp-server 提供高质量的交互式导图

## 依赖要求

⚠️ **使用本 Skill 前必须具备 `markmap-mcp-server` MCP**

本 Skill 已内置 bootstrap 脚本。首次调用时会先检测当前环境中的 `claude` / `codex`，然后自动完成 `markmap-mcp-server` 的安装或修复。

自动安装策略：

- **类 Unix（macOS/Linux）**：优先使用 `npx -y`
- **Windows**：优先全局安装包，再直接调用 `markmap-mcp-server`
- **注册方式**：优先使用 `codex mcp add` / `claude mcp add`
- **最终回退**：原生命令失败时，写入当前用户配置文件

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

### bootstrap 手动执行

如果您想先独立完成预检查，可直接执行：

#### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\mindmap\scripts\bootstrap.ps1 -ProjectRoot "$PWD" -SkillRoot "$PWD\skills\mindmap"
```

#### 类 Unix

```bash
bash ./skills/mindmap/scripts/bootstrap.sh --project-root "$PWD" --skill-root "$PWD/skills/mindmap"
```

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

## 故障排查

### Windows 下 Claude Code 安装异常

优先按以下顺序处理：

1. 先执行 `npm install -g @jinzcdev/markmap-mcp-server`
2. 再执行 `claude mcp add --transport stdio --scope user markmap-mcp-server -- cmd /c markmap-mcp-server`
3. 若 `claude mcp add` 仍失败，再编辑当前用户的 `~/.claude.json`

### 强制重装

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\mindmap\scripts\bootstrap.ps1 -ProjectRoot "$PWD" -SkillRoot "$PWD\skills\mindmap" -Force
```

```bash
bash ./skills/mindmap/scripts/bootstrap.sh --project-root "$PWD" --skill-root "$PWD/skills/mindmap" --force
```

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
