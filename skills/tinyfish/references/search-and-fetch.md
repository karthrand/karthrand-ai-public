# Search & Fetch 命令参考

## tinyfish search query

执行网络搜索，返回排名结果（标题、URL、摘要）。

```bash
tinyfish search query "best React state management libraries"
```

### Flags

| Flag | 说明 |
|------|------|
| `--location <value>` | 地理位置（如 `"Vietnam"`），用于地区化搜索结果 |
| `--language <value>` | 语言提示（如 `"en"`） |
| `--pretty` | 人可读输出 |

### 输出格式

```json
{
  "query": "best React state management libraries",
  "total_results": 10,
  "results": [
    {
      "position": 1,
      "site_name": "Reddit",
      "title": "Best State Management for React in 2026",
      "url": "https://reddit.com/r/reactjs/...",
      "snippet": "Zustand and Jotai are the most popular choices..."
    }
  ]
}
```

### 使用示例

```bash
# 基本搜索
tinyfish search query "Python async await tutorial"

# 地区化搜索
tinyfish search query "best restaurants in Tokyo" --location "Japan" --language "ja"

# 人可读输出
tinyfish search query "Rust vs Go performance" --pretty
```

---

## tinyfish fetch content get

从 URL 抓取干净的网页内容，去除广告、导航等噪音，仅保留正文。支持多 URL 并行抓取。

```bash
# 单 URL
tinyfish fetch content get "https://example.com/article"

# 多 URL 并行
tinyfish fetch content get "https://example.com/article" "https://another.com/post" "https://third.com/page"
```

### Flags

| Flag | 说明 |
|------|------|
| `--format <format>` | 输出格式：`markdown`（默认）、`html`、`json` |
| `--links` | 包含页面中提取的链接 |
| `--image-links` | 包含页面中提取的图片 URL |
| `--pretty` | 人可读输出 |

### 输出格式

```json
{
  "results": [
    {
      "url": "https://example.com/article",
      "final_url": "https://example.com/article/",
      "title": "Example Domain",
      "description": null,
      "language": "en",
      "author": null,
      "published_date": null,
      "format": "markdown",
      "text": "The full article content in clean markdown...",
      "latency_ms": 36.87
    }
  ],
  "errors": []
}
```

注意：`description`、`author`、`published_date` 字段可能为 `null`（取决于页面是否提供）。

启用 `--links` 或 `--image-links` 时，每个 result 会额外包含：

```json
{
  "links": ["https://example.com/about", "https://example.com/contact"],
  "image_links": ["https://example.com/hero.png"]
}
```

### 使用示例

```bash
# 抓取单篇文章（默认 markdown）
tinyfish fetch content get "https://example.com/blog/post"

# 多 URL 并行抓取
tinyfish fetch content get "https://site-a.com/article" "https://site-b.com/article"

# 抓取并包含链接
tinyfish fetch content get "https://example.com" --links --image-links

# 指定输出格式
tinyfish fetch content get "https://example.com/api-docs" --format html
```
