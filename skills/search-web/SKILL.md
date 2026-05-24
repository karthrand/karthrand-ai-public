---
name: search-web
description: "当需要网络搜索获取最新资料时使用。搜索技术文档、API 参考、代码示例、npm 包用法、框架指南、GitHub 仓库（README、源码、目录结构）。"
---

# Search-Web 技能

## 概述

用最小搜索链路整合 `Context7`、`Exa`、`TinyFish`、网页正文读取、`DeepWiki` 和 `github-fetcher`。先确认必需 MCP 与备用 CLI 已可用，再拿官方文档、网页资料和仓库信息，避免首次使用时直接撞上工具缺失。

原则：每类搜索目标使用固定工具链；联网搜索优先使用 `Exa`，仅在 `Exa` 失败、额度到限、服务不可用或空结果时使用 `TinyFish` CLI 备用。

## 何时使用

- 查询库、框架、SDK 或语言的官方文档（library docs, API reference, framework guides）
- 查找代码示例、教程、博客文章或最新网页资料（code examples, npm packages）
- 读取指定网页正文（仅在已知 URL 后）
- 查看 GitHub 仓库结构、文档、源码入口（README, source code, directory structure）
- 读取 GitHub 仓库中的具体文件或目录结构
- 遇到 `library not found`、`rate limit`、`documentation outdated` 需要查最新资料时

## 何时不使用

- 纯本地代码检索或无需联网的普通问答
- 需要直接执行代码、运行测试或调试业务逻辑
- 已有完整本地文档且无需联网验证
- 需要修改、重构代码（refactoring）

## MCP 快速参考

| 搜索目标 | 工具 | 固定规则 |
|---------|-----|---------|
| 技术文档 | Context7 | 先 `resolve-library-id` 再 `query-docs`，每问题≤3次 |
| 网络搜索 | Exa / TinyFish | `Exa` 优先；`Exa` 失败、额度到限、服务不可用或空结果时使用 `TinyFish` |
| GitHub 仓库文档 | mcp-deepwiki | 仓库级文档概览和深读 |
| GitHub 文件/目录 | github-fetcher | 具体文件或目录结构 |
| 网页正文 | 宿主读取工具 / TinyFish | 仅已知 URL 后使用；宿主读取失败时可用 `TinyFish` 抓取正文 |

## 核心流程

1. 使用时的第一个步骤，运行 `bash scripts/detect.sh`，解析输出：
   - `initialized=true`：直接进入步骤 2
   - `initialized=false`：进入 `references/setup.md` 执行安装流程
   **进入 setup 前，先读取 `credentials/` 目录下 `context7`、`exa` 和 `tinyfish` 文件：文件不存在或为空时询问用户是否配置 Key，用户选择跳过则写入 "skipped"，后续不再询问。`exa` 的 Key 为可选，不提供时使用无 Key 模式安装；`tinyfish` 若已存在 `TINYFISH_API_KEY`，先写回 `credentials/tinyfish` 并跳过询问；`tinyfish` 的 Key 写入 `credentials/tinyfish` 后，还必须永久写入 `TINYFISH_API_KEY` 环境变量。**
   **MCP 缺失时，先通过 `setup-mcp.sh` 安装（下一会话生效），然后直接告知用户需要重启以激活新 MCP。**
   **任何 MCP 在步骤 2-6 执行中报告未注册或不可用时，停止当前搜索，告知用户需要重启以加载 MCP。**
2. 配置项类问题（阈值、开关、flag、option、parameter、env）先读 `references/strategies/config-index-shortcut.md`。
3. 技术文档先走 `Context7`（先 `resolve-library-id` 再 `query-docs`），模板和错误示例见 `examples/usage.md`。
4. 联网搜索先使用 `Exa`；当 `Exa` 搜索失败、额度到限、服务不可用或空结果时，按 `references/tinyfish-fallback.md` 使用 `TinyFish` CLI 备用。Context7 之后仍先走 `Exa` 补网页资料。
5. 搜索命中 GitHub 仓库时走 `DeepWiki` 获取文档；需读具体文件或目录时走 `github-fetcher`。
6. 只有用户已给出明确 URL、`Exa` 已定位 URL 或 `TinyFish` 搜索已定位 URL 后才允许网页正文读取。正文读取不是搜索步骤；宿主读取工具失败时，可用 `tinyfish fetch content get` 作为正文抓取备用。
7. 最终按 `references/rules/output-format.md` 组织回答，优先给官方文档，再给网页资料、正文读取结果和仓库信息。

## MCP 使用边界

工具映射见上方"MCP 快速参考"表。固定禁止：

- 禁止用 `open-websearch` 或其他未指定搜索工具替代 `Exa` / `TinyFish`
- 禁止用 `mcp-deepwiki` 替代 `github-fetcher` 的文件读取，或反之
- MCP 缺失时先通过 `setup-mcp.sh` 安装并提示用户重启；`TinyFish` 是 CLI 备用工具，不加入 MCP 安装列表

## 常见错误

- 跳过 `resolve-library-id` 直接猜测 `libraryId`（Context7 必须两步调用）
- 缺少 `libraryName` 参数调用 `resolve-library-id`
- 用 `libraryName` 传给 `query-docs`（应该用 `libraryId`）
- `Exa` MCP 未注册或未加载时直接走 `TinyFish`（应按 MCP 缺失处理并提示重启；只有 `Exa` 搜索调用返回失败、额度到限、服务不可用或空结果时才用 `TinyFish`）
- 把网页正文读取当成搜索步骤替代 `Exa`
- 用 `mcp-deepwiki` 替代 `github-fetcher` 读文件，或反之
- Context7 超过 3 次调用限制后仍继续调用（应转 Exa）
- MCP 未加载时反复进入 setup 循环而不提示用户重启（应安装后提示重启）
- `credentials/tinyfish` 已有 Key 时仍重复询问用户（应跳过询问并确保 `TINYFISH_API_KEY` 已永久写入）

## 按需继续加载

只有在以下场景再读 `examples/usage.md`：

- 需要 `Context7`、`Exa`、`TinyFish`、网页正文读取、`DeepWiki` 或 `github-fetcher` 的参数示例
- 需要 `Context7` 的错误示范、调用顺序示例或多源整合案例
- 需要网页读取降级案例
- 需要常见失败场景或排障示例

如果示例文档与正文流程冲突，以本文件为准。

首次使用，或者 `bash scripts/detect.sh` 输出 `initialized=false` 时，读 `references/setup.md`。

需要标准输出模板、来源标注规则或 Markdown 结构约束时，读 `references/rules/output-format.md`。

需要 `TinyFish` 安装、`TINYFISH_API_KEY` 写入、备用搜索或正文抓取命令时，读 `references/tinyfish-fallback.md`。

遇到精确配置项名、阈值、开关、`flag`、`option`、`parameter`、`env` 一类问题时，读 `references/strategies/config-index-shortcut.md`。

## 输出要求

- 最终回答前，必须按 `references/rules/output-format.md` 格式化
- 明确标注来源类型：`Context7`、`Exa`、`TinyFish`、网页读取、`DeepWiki`、`github-fetcher`
- 保留原始链接、文档入口或仓库标识
- 如果从 `Exa` 降级到 `TinyFish`，必须说明 `Exa` 的失败原因
- 如果发生降级、读取失败或信息不足，要直接说明
- 不编造未读取到的内容
