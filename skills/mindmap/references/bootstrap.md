# mindmap bootstrap 说明

仅在以下两种情况参考本文件：

- 共享服务标志或当前宿主标志不存在
- `markmap-mcp-server` 调用出现环境类错误

状态标志目录位置：

- Windows：`%APPDATA%\karthrand-ai\skills\mindmap\`
- macOS/Linux：`${XDG_STATE_HOME:-$HOME/.local/state}/karthrand-ai/skills/mindmap/`

状态标志拆分为：

- 共享服务标志：`service.initialized`
- 宿主注册标志：`host.claude.initialized`
- 宿主注册标志：`host.codex.initialized`
- 宿主注册标志：`host.opencode.initialized`

## 何时执行 bootstrap

### 首次初始化

当共享服务标志或目标宿主标志不存在时，执行对应平台脚本：

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

### 强制修复

当 `markmap-mcp-server` 调用出现环境类错误时，使用强制修复方式执行：

#### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\mindmap\scripts\bootstrap.ps1 -ProjectRoot "$PWD" -SkillRoot "$PWD\skills\mindmap" -Targets claude -Force
```

#### 类 Unix

```bash
bash ./skills/mindmap/scripts/bootstrap.sh --project-root "$PWD" --skill-root "$PWD/skills/mindmap" --targets claude --force
```

按实际终端宿主传入 `Targets` / `--targets`：

- `claude` 终端传 `claude`
- `codex` 终端传 `codex`
- `opencode` 终端传 `opencode`
- 只有人工全量修复时才使用 `all`

## 安装与注册注意点

- 共享服务层只负责准备 `markmap-mcp-server` 的本地启动条件。
- 类 Unix 环境下，共享服务默认使用 `npx -y` 启动，无需额外全局安装。
- Windows 环境下，共享服务优先全局安装 `@jinzcdev/markmap-mcp-server`，确保本地服务可被宿主复用。
- `claude`、`codex`、`opencode` 的 MCP 注册状态彼此独立，不能共享标志。
- bootstrap 不再支持自动推断目标宿主，必须显式指定 `claude`、`codex`、`opencode` 或 `all`。
- `claude` 优先使用 `claude mcp add --transport stdio --scope user` 注册。
- `codex` 优先使用 `codex mcp add` 注册。
- `opencode` 通过全局配置文件 `~/.config/opencode/opencode.json` 的 `mcp` 字段写入本地 MCP 配置。
- bootstrap 会优先尝试原生命令注册；若 `claude/codex` 注册失败，再回退到写入当前用户配置文件。
- 强制修复时，优先移除旧配置后再重新注册，避免旧配置残留。
- 共享服务阶段会执行真实命令验证；只有验证通过后才写入 `service.initialized`。
- 宿主注册阶段会在注册后再次校验；只有校验通过后才写入 `host.<宿主>.initialized`。

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
- 浏览器预览失败但文件已生成

## bootstrap 成功标准

- 共享服务阶段真实验证通过后写入 `service.initialized`
- 目标宿主注册真实验证通过后写入对应的 `host.<宿主>.initialized`
- `claude`、`codex`、`opencode` 中的目标宿主已完成各自 MCP 注册
- 后续可直接调用 `markmap-mcp-server`
