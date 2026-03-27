# mindmap bootstrap 说明

仅在以下两种情况参考本文件：

- 全局初始化标志文件不存在
- `markmap-mcp-server` 调用出现环境类错误

全局初始化标志文件位置：

- Windows：`%APPDATA%\karthrand-ai\skills\mindmap\.initialized`
- macOS/Linux：`${XDG_STATE_HOME:-$HOME/.local/state}/karthrand-ai/skills/mindmap/.initialized`

## 何时执行 bootstrap

### 首次初始化

当全局初始化标志文件不存在时，执行对应平台脚本：

#### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\mindmap\scripts\bootstrap.ps1 -ProjectRoot "$PWD" -SkillRoot "$PWD\skills\mindmap"
```

#### 类 Unix

```bash
bash ./skills/mindmap/scripts/bootstrap.sh --project-root "$PWD" --skill-root "$PWD/skills/mindmap"
```

### 强制修复

当 `markmap-mcp-server` 调用出现环境类错误时，使用强制修复方式执行：

#### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\mindmap\scripts\bootstrap.ps1 -ProjectRoot "$PWD" -SkillRoot "$PWD\skills\mindmap" -Force
```

#### 类 Unix

```bash
bash ./skills/mindmap/scripts/bootstrap.sh --project-root "$PWD" --skill-root "$PWD/skills/mindmap" --force
```

## 安装与注册注意点

- 类 Unix 环境下，bootstrap 优先使用 `npx -y` 方式注册 MCP。
- Windows 环境下，bootstrap 优先全局安装 `@jinzcdev/markmap-mcp-server`，再通过 `cmd /c markmap-mcp-server` 注册。
- bootstrap 会优先尝试原生命令注册；若注册失败，再回退到写入当前用户配置文件。
- 强制修复时，优先移除旧配置后再重新注册，避免旧配置残留。

## 环境类错误判定

只有以下错误才应触发 bootstrap：

- MCP server 未注册
- `markmap-mcp-server` 命令不存在
- `command not found`
- `executable not found`
- stdio / transport 启动失败
- server unavailable
- connection failed

以下错误不触发 bootstrap：

- Markdown 内容错误
- 结构整理错误
- 生成逻辑错误
- 浏览器预览失败但文件已生成2

## bootstrap 成功标准

- `claude` / `codex` 中的目标宿主已完成 MCP 注册
- 脚本写入全局初始化标志文件
- 后续可直接调用 `markmap-mcp-server`
