---
name: mindmap
description: 生成思维导图；使用 markmap-mcp-server mcp 工具生成 #$ARGUMENTS 思维导图；通过 markmap 工具，自然语言描述生成流程图等可视化图表；生成文件后自动打开到浏览器；适用于用户需要把流程、结构、知识点或需求快速可视化为思维导图的场景。
---

# 生成思维导图

## Overview

使用 markmap-mcp-server mcp 工具把 #$ARGUMENTS 或自然语言描述转换成思维导图/流程图等可视化图表，并在生成后自动打开浏览器预览；

## Workflow

1. 收集用户的 #$ARGUMENTS；如果描述过于松散，先简短确认范围与层级。
2. 将内容整理为适合 markmap 的 Markdown 结构（标题 + 列表），保持层级清晰。
3. 调用 markmap-mcp-server mcp工具生成思维导图，生成后自动打开浏览器。
4. 告知输出文件位置，必要时补充文件名。

## 工具调用要点

- 使用 `markmap-mcp-server` mcp工具（对应 markmap/markdown_to_mindmap 能力）。
- 传入整理后的 Markdown 内容；默认即可生成文件并打开浏览器预览。
- 若用户需要特定标题或层级，用 Markdown 标题与列表显式表达。

## 功能说明

- 通过 markmap 工具，自然语言描述生成流程图等可视化图表
- 生成文件后自动打开到浏览器
