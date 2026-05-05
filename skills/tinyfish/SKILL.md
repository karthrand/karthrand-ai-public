---
name: tinyfish
description: "当需要网络搜索获取结构化结果、抓取网页正文、对网页执行浏览器自动化或批量操作、创建远程浏览器会话时使用。"
---

# TinyFish CLI

通过命令行调用 TinyFish 浏览器自动化能力：搜索、抓取正文、执行自动化任务、批量操作。

## 何时使用

- 需要网络搜索并获取结构化结果（标题、URL、摘要）
- 需要抓取网页正文（去除广告和导航噪音）
- 需要对网页执行自动化操作（提取数据、点击、填表等）
- 需要批量处理多个网页任务
- 需要创建远程浏览器会话进行程序化控制

## 何时不使用

- 纯本地文件操作或代码搜索
- 已有 MCP 工具（Context7、Exa、web-reader）能满足需求时优先用 MCP
- 不需要浏览器能力的简单 HTTP 请求

## 前置条件

CLI 已安装配置。运行 `tinyfish auth status` 确认认证状态。未认证时退出码为 1。

## 核心流程

```
需要搜索信息？──→ tinyfish search query
需要抓取网页正文？──→ tinyfish fetch content get
需要浏览器自动化？──→ tinyfish agent run --sync
需要批量处理？──→ tinyfish agent batch run --input file.csv
需要远程浏览器？──→ tinyfish browser session create
```

## 命令速查

| 命令 | 用途 | 关键 flags |
|------|------|-----------|
| `tinyfish search query "..."` | 网络搜索 | `--location`、`--language` |
| `tinyfish fetch content get <url> [url...]` | 抓取网页正文（支持多 URL） | `--format`、`--links` |
| `tinyfish agent run "goal" --url <url>` | 浏览器自动化 | `--sync`、`--async` |
| `tinyfish agent run list` | 列出运行记录 | `--status`、`--limit` |
| `tinyfish agent run get <id>` | 获取运行详情 | — |
| `tinyfish agent run cancel <id>` | 取消运行 | — |
| `tinyfish agent batch run --input <csv>` | 批量任务 | — |
| `tinyfish agent batch list` | 列出批量任务 | — |
| `tinyfish agent batch get <id>` | 获取批量结果 | — |
| `tinyfish browser session create` | 创建远程浏览器 | `--url` |

## 通用规则

- 所有命令默认输出 JSON 到 stdout，错误走 stderr（JSON 格式），失败退出码 1
- 所有命令支持 `--pretty` 获得人可读输出
- 在 Bash 工具中调用 `agent run` 时，**始终使用 `--sync`** 获取完整结果
- 排障时加 `--debug` 或设 `TINYFISH_DEBUG=1` 查看 HTTP 请求日志

## 常见错误

- `agent run` 缺少 `--url` 参数（必需）
- 流式模式下解析 JSON 时未按行处理（每行是独立 JSON 对象）
- `batch run` 的 CSV 缺少 `url` 或 `goal` 列
- 未认证时直接调用命令（先 `tinyfish auth status` 检查）

## 按需加载

需要 `search` 或 `fetch` 的完整 flags 和输出格式时，读 `references/search-and-fetch.md`。

需要 `agent run` 三种模式的详细说明、`batch` 命令、或运行管理命令时，读 `references/agent-run.md`。

需要 `browser session create` 的 CDP URL 说明和程序化控制用法时，读 `references/browser-session.md`。
