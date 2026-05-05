# Browser Session 命令参考

## tinyfish browser session create

创建远程浏览器实例，返回 CDP（Chrome DevTools Protocol）WebSocket URL，可用于程序化控制。

```bash
tinyfish browser session create
```

### Flags

| Flag | 说明 |
|------|------|
| `--url <url>` | 创建会话后自动导航到指定 URL |
| `--pretty` | 人可读输出 |

### 输出格式

```json
{
  "session_id": "tf-9c669a12-a0d3-456e-8126-6524c32f10fc",
  "cdp_url": "wss://ip-13-56-193-1.tetra-data.production.tinyfish.io/tf-9c669a12-a0d3-456e-8126-6524c32f10fc",
  "base_url": "https://ip-13-56-193-1.tetra-data.production.tinyfish.io/tf-9c669a12-a0d3-456e-8126-6524c32f10fc"
}
```

### 使用示例

```bash
# 创建空白浏览器会话
tinyfish browser session create

# 创建并导航到指定页面
tinyfish browser session create --url "https://example.com"
```

### 关键字段说明

- `session_id`：会话唯一标识
- `cdp_url`：CDP WebSocket 端点，用于 Playwright、Puppeteer 等工具连接
- `base_url`：基于 HTTP 的调试入口，可在浏览器 DevTools 中打开
