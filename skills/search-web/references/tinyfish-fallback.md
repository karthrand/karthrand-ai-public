# TinyFish 备用搜索

## 何时读取

出现以下任一情况时读取本文件：

- `Exa` 搜索失败、额度到限、服务不可用或返回空结果
- 需要安装或验证 `TinyFish` CLI
- 需要设置 `credentials/tinyfish` 和 `TINYFISH_API_KEY`
- 已有 URL 的正文读取失败，需要用 `TinyFish` 抓取正文

## 固定边界

- `TinyFish` 是 `Exa` 的备用 CLI，不是 MCP
- 不把 `TinyFish` 加入 `setup-mcp.sh --mcp all`
- 只在 `Exa` 失败、额度到限、服务不可用或空结果时使用 `TinyFish` 做联网搜索
- 只迁入 `search` 和 `fetch` 能力；浏览器自动化、批量任务和远程浏览器会话仍由独立 `skills/tinyfish` 负责

## 安装与检查

```bash
npm install -g @tiny-fish/cli
tinyfish --version
```

如果 `tinyfish --version` 失败，说明 CLI 未安装或不在 `PATH` 中。此时不要继续执行 `tinyfish search query`，直接提示安装命令。

## API Key 管理

Key 文件固定为：

```text
~/.config/search-web/credentials/tinyfish
```

环境变量固定为：

```text
TINYFISH_API_KEY
```

固定流程：

1. 先读取 `credentials/tinyfish`。
2. 文件不存在或为空，但当前环境已有 `TINYFISH_API_KEY` 时，先写回 `credentials/tinyfish`，并跳过询问。
3. 文件不存在或为空，且当前环境没有 `TINYFISH_API_KEY` 时，询问用户是否配置 TinyFish API Key。
4. 用户提供 Key 时，写入 `credentials/tinyfish`。
5. 用户跳过时，写入 `skipped`，后续不再询问。
6. 文件存在且非空时，跳过询问。
7. 文件内容不是 `skipped` 时，将该值永久写入 `TINYFISH_API_KEY`，并注入当前会话。

### 类 Unix

只检查和写入 `~/.bashrc`：

```bash
printf '%s\n' "${TINYFISH_API_KEY:-}"
[ -f ~/.bashrc ] && grep -n 'TINYFISH_API_KEY' ~/.bashrc || true
export TINYFISH_API_KEY="从credentials/tinyfish读取的key"
```

如果 `~/.bashrc` 没有 `TINYFISH_API_KEY`，追加：

```bash
touch ~/.bashrc
export TINYFISH_API_KEY="从credentials/tinyfish读取的key"
```

如果 `~/.bashrc` 已有 `TINYFISH_API_KEY`，更新该行，不重复追加。

### Windows PowerShell

使用用户级环境变量：

```powershell
[Environment]::GetEnvironmentVariable("TINYFISH_API_KEY", "User")
[Environment]::SetEnvironmentVariable("TINYFISH_API_KEY", "从credentials/tinyfish读取的key", "User")
$env:TINYFISH_API_KEY = "从credentials/tinyfish读取的key"
```

禁止写入系统级环境变量。

## 搜索命令

```bash
tinyfish search query "Next.js 15 release notes"
```

可选参数：

| Flag | 说明 |
|------|------|
| `--location <value>` | 地区化搜索结果 |
| `--language <value>` | 语言提示 |
| `--pretty` | 人可读输出 |

默认输出 JSON 到 stdout，失败输出 JSON 到 stderr，失败退出码为 1。

输出字段：

```json
{
  "query": "Next.js 15 release notes",
  "total_results": 10,
  "results": [
    {
      "position": 1,
      "site_name": "Example",
      "title": "Example Title",
      "url": "https://example.com",
      "snippet": "摘要内容"
    }
  ]
}
```

## 正文抓取命令

仅在已有明确 URL 后使用：

```bash
tinyfish fetch content get "https://example.com/article" --format markdown
```

多 URL 抓取：

```bash
tinyfish fetch content get "https://example.com/a" "https://example.com/b" --format markdown
```

常用参数：

| Flag | 说明 |
|------|------|
| `--format <format>` | 输出格式：`markdown`、`html`、`json` |
| `--links` | 包含页面链接 |
| `--image-links` | 包含图片 URL |
| `--pretty` | 人可读输出 |

## 降级输出要求

- 明确说明 `Exa` 的失败原因
- 明确说明已切换到 `TinyFish`
- 来源标注使用 `TinyFish`
- 如果 `credentials/tinyfish` 为 `skipped`、`TINYFISH_API_KEY` 不可用或 CLI 未安装，直接说明 TinyFish 不可用，不编造搜索结果
