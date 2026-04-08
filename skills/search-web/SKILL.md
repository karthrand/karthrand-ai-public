---
name: search-web
description: 当用户要求搜索技术文档、查代码示例、查网页资料或查看 GitHub 仓库信息时使用。
---

# Search-Web 技能

## 概述

用最小搜索链路整合 `Context7`、`Exa`、网页正文读取和 `DeepWiki`。先确认必需 MCP 已可用，再拿官方文档、网页资料和仓库信息，避免首次使用时直接撞上工具缺失。

## 何时使用

- 查询库、框架、SDK 或语言的官方文档
- 查找代码示例、教程、博客文章或最新网页资料
- 读取指定网页正文
- 查看 GitHub 仓库结构、文档或源码入口
- 不适用于纯本地代码检索或无需联网的普通问答

## 核心流程

1. 使用时的第一个步骤，固定先检查 setup 状态文件；如果状态缺失、未完成、与真实环境不一致，或者任一必需 MCP 不可用，立即转 `references/setup.md`。
2. setup 状态通过后，再判断问题是否属于精确配置项、阈值、开关、`flag`、`option`、`parameter`、`env` 一类问题。
3. 命中配置项类问题时，先读 `references/strategies/config-index-shortcut.md`，优先定位官方配置索引入口。
4. 技术文档问题先走 `Context7`，固定顺序是先 `resolve-library-id` 再 `query-docs`；详细模板和错误示例看 `examples/usage.md`。
5. 只要属于联网搜索，固定使用 `Exa`；不得改用任何其他搜索型 MCP。`Exa` 不可用时只能回到 `references/setup.md` 修复。
6. `Context7` 之后继续走 `Exa`，补网页资料、最新信息或官方入口。
7. `Exa` 结果命中 GitHub 仓库时走 `DeepWiki`。
8. 只有在用户已给出明确 URL，或 `Exa` 已经定位到目标网页后，才允许进入网页正文读取。正文读取不是搜索步骤，不能替代 `Exa`。
9. 最终按 `references/rules/output-format.md` 组织回答，优先给官方文档，再给网页资料、正文读取结果和仓库信息。

## MCP 使用边界

- 技术文档：只允许 `Context7`
- 联网搜索：只允许 `Exa`
- GitHub 仓库：只允许 `mcp-deepwiki`
- 网页正文：只允许在“已知 URL 的非搜索读取”场景使用宿主已提供的正文读取工具
- 禁止把 `open-websearch`、通用浏览器搜索或其他搜索型 MCP 当成 `Exa` 的替代品

## 按需继续加载

只有在以下场景再读 `examples/usage.md`：

- 需要 `Context7`、`Exa`、网页正文读取或 `DeepWiki` 的参数示例
- 需要 `Context7` 的错误示范、调用顺序示例或多源整合案例
- 需要网页读取降级案例
- 需要常见失败场景或排障示例

如果示例文档与正文流程冲突，以本文件为准。

首次使用，或者遇到状态文件缺失、状态与真实环境不一致、`Context7` / `Exa` / `DeepWiki` 未注册或连接失败时，读 `references/setup.md`。

需要标准输出模板、来源标注规则或 Markdown 结构约束时，读 `references/rules/output-format.md`。

遇到精确配置项名、阈值、开关、`flag`、`option`、`parameter`、`env` 一类问题时，读 `references/strategies/config-index-shortcut.md`。

## 输出要求

- 最终回答前，必须按 `references/rules/output-format.md` 格式化
- 明确标注来源类型：`Context7`、`Exa`、网页读取、`DeepWiki`
- 保留原始链接、文档入口或仓库标识
- 如果 `Exa` 缺失、不可用或环境异常，不允许切换到其他搜索型 MCP，必须直接说明并回到 setup/repair
- 如果发生降级、读取失败或信息不足，要直接说明
- 不编造未读取到的内容
