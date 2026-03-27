---
name: mindmap
description: 当用户要求把内容生成思维导图、流程图、结构图，或明确提到使用 mindmap 或 markmap 做可视化时触发。
---

# 生成思维导图

## Overview

使用 markmap-mcp-server mcp 工具把 #$ARGUMENTS 或自然语言描述转换成思维导图/流程图等可视化图表，并在生成后自动打开浏览器预览。

本 skill 将 bootstrap 状态拆成两层：

- 共享服务标志：`service.initialized`
- 宿主注册标志：`host.claude.initialized`、`host.codex.initialized`、`host.opencode.initialized`

标志目录位置：

- Windows：`%APPDATA%\karthrand-ai\skills\mindmap\`
- 类 Unix：`${XDG_STATE_HOME:-$HOME/.local/state}/karthrand-ai/skills/mindmap/`

只有以下两种情况才需要参考 `references/bootstrap.md`：

- 检测不到共享服务标志或当前宿主标志
- 调用 `markmap-mcp-server` 时出现环境类错误（例如 server 未注册、命令不存在、transport 启动失败）

## Workflow

1. 先检查共享服务标志与当前宿主标志是否存在。
2. 若共享服务标志不存在，参考 `references/bootstrap.md` 并显式传入当前宿主执行 bootstrap；仅在共享服务真实验证通过后写入 `service.initialized`。
3. 若当前宿主标志不存在，参考 `references/bootstrap.md` 并显式传入当前宿主执行 bootstrap；仅在该宿主注册真实验证通过后写入对应的 `host.<宿主>.initialized`。
4. 收集用户的 #$ARGUMENTS；如果描述过于松散，先简短确认范围与层级。
5. 将内容整理为适合 markmap 的 Markdown 结构（标题 + 列表），保持层级清晰。
6. 调用 markmap-mcp-server mcp 工具生成思维导图，生成后自动打开浏览器。
7. 若工具调用出现环境类错误，再次参考 `references/bootstrap.md` 使用强制修复方式执行 bootstrap，然后仅重试一次。
8. 告知输出文件位置，必要时补充文件名。

## 工具调用要点

- 使用 `markmap-mcp-server` mcp 工具（对应 markmap/markdown_to_mindmap 能力）。
- 共享服务标志与当前宿主标志都存在时，直接继续主流程，不要额外做 bootstrap 检查。
- bootstrap 的安装策略、平台差异、回退方式与修复命令统一参考 `references/bootstrap.md`。
- bootstrap 必须显式指定当前宿主：`claude`、`codex` 或 `opencode`；不要使用自动推断目标宿主的方式。
- 传入整理后的 Markdown 内容；默认即可生成文件并打开浏览器预览。
- 若用户需要特定标题或层级，用 Markdown 标题与列表显式表达。
- 只有环境类错误才触发 bootstrap；内容错误、结构错误、生成错误不触发重装。
