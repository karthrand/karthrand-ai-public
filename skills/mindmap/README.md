# Mindmap 思维导图生成器

将自然语言描述快速转换为思维导图、流程图等可视化图表的Skill。

## 功能特性

- 🧠 **自然语言转换**：将文本描述自动整理为结构化思维导图
- 🌐 **浏览器预览**：生成后自动在浏览器中打开预览
- 📊 **多种图表**：支持思维导图、流程图、层级结构等可视化形式
- ✨ **基于 Markmap**：使用 markmap-mcp-server 提供高质量的交互式导图

## 依赖要求

⚠️ **使用本 Skill 前必须安装 markmap-mcp-server MCP**

本 Skill 依赖 [markmap-mcp-server](https://github.com/jinzcdev/markmap-mcp-server) MCP 服务，请根据您使用的工具选择对应的安装方式。

### MCP 依赖安装

#### Claude Code 安装方式

##### **类 Unix (macOS/Linux)**

```bash
claude mcp add markmap-mcp-server --scope user -- npx -y @jinzcdev/markmap-mcp-server
```

#####  **Windows (PowerShell)**

```powershell
claude mcp add markmap-mcp-server --scope user -- cmd /c npx -y @jinzcdev/markmap-mcp-server
```

####  Codex 安装方式

##### **类 Unix (macOS/Linux)**：

```bash
codex mcp add markmap-mcp-server -- npx -y @jinzcdev/markmap-mcp-server
```

##### **Windows (PowerShell)**：

```powershell
codex mcp add markmap-mcp-server -- cmd /c npx -y @jinzcdev/markmap-mcp-server
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