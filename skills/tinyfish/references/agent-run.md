# Agent Run 命令参考

## tinyfish agent run

执行浏览器自动化任务。默认以流式 newline-delimited JSON 输出事件。

```bash
tinyfish agent run "goal" --url example.com
```

### Flags

| Flag | 说明 |
|------|------|
| `--url <url>` | 目标 URL（必需） |
| `--sync` | 等待任务完成后返回完整结果 |
| `--async` | 仅提交任务，立即返回 `run_id` |
| `--pretty` | 人可读输出 |

### 三种输出模式

**流式（默认）**：每行一个 JSON 事件，适合实时监控或管道处理。

```bash
tinyfish agent run "Extract the pricing" --url example.com/pricing
```

```json
{"type":"STARTED","run_id":"abc123","run_url":"https://agent.tinyfish.ai/runs/abc123"}
{"type":"PROGRESS","run_id":"abc123","purpose":"Navigating to the pricing page"}
{"type":"COMPLETE","run_id":"abc123","status":"COMPLETED","result":{"price":"$99"},"run_url":"https://agent.tinyfish.ai/runs/abc123"}
```

**同步（--sync）**：等待完成后返回单个 JSON 对象，适合脚本。

```bash
tinyfish agent run "Extract the pricing" --url example.com/pricing --sync
```

```json
{"status":"COMPLETED","run_id":"abc123","result":{"price":"$99"},"error":null,"num_of_steps":4,"started_at":"2026-05-05T04:18:11.508Z","finished_at":"2026-05-05T04:18:18.624Z","run_url":"https://agent.tinyfish.ai/runs/abc123"}
```

**异步（--async）**：提交后立即返回 `run_id`，适合 fire-and-forget 或自定义轮询。

```bash
tinyfish agent run "Extract the pricing" --url example.com/pricing --async
```

```json
{"run_id":"abc123","run_url":"https://agent.tinyfish.ai/runs/abc123","error":null}
```

### 模式选择建议

| 场景 | 推荐模式 |
|------|---------|
| 在 Bash 工具中直接调用并获取结果 | `--sync` |
| 需要实时查看进度 | 流式（默认） |
| 提交大量任务后自行管理 | `--async` |

---

## tinyfish agent run list

列出最近的运行记录。

```bash
tinyfish agent run list
```

### Flags

| Flag | 说明 |
|------|------|
| `--status <status>` | 按状态过滤：`PENDING`、`RUNNING`、`COMPLETED`、`FAILED`、`CANCELLED` |
| `--limit <n>` | 返回数量（默认 20，最大 100） |
| `--cursor <cursor>` | 分页游标 |
| `--pretty` | 人可读输出 |

---

## tinyfish agent run get <run_id>

获取指定运行的完整详情。

```bash
tinyfish agent run get abc123
```

### Flags

| Flag | 说明 |
|------|------|
| `--pretty` | 人可读输出 |

---

## tinyfish agent run cancel <run_id>

取消 `PENDING` 或 `RUNNING` 状态的运行。

```bash
tinyfish agent run cancel abc123
```

输出：

```json
{"run_id":"abc123","status":"CANCELLED","cancelled_at":"2024-01-15T10:30:00Z","message":null}
```

---

## tinyfish agent batch run

从 CSV 文件提交批量任务。CSV 必须包含 `url` 和 `goal` 列。

```bash
tinyfish agent batch run --input runs.csv
```

### CSV 格式

```csv
url,goal
https://example.com,"Extract the main heading"
https://another.com,"Get the price and availability"
```

### Flags

| Flag | 说明 |
|------|------|
| `--input <file>` | CSV 文件路径（必需） |
| `--pretty` | 人可读输出 |

### 输出

```json
{
  "data": {
    "batch_id": "550e8400-e29b-41d4-a716-446655440000",
    "total": 2,
    "submitted": 2,
    "results_url": "https://agent.tinyfish.ai/runs"
  }
}
```

---

## tinyfish agent batch list

列出所有本地跟踪的批量任务。

```bash
tinyfish agent batch list
```

输出：

```json
[
  {
    "batch_id": "550e8400-e29b-41d4-a716-446655440000",
    "run_ids": ["run-1", "run-2"],
    "total": 2,
    "submitted": 2,
    "created_at": "2026-04-10T10:30:00Z"
  }
]
```

---

## tinyfish agent batch get <batch_id>

获取批量任务的结果，包含每个运行的状态和提取数据。

```bash
tinyfish agent batch get 550e8400-e29b-41d4-a716-446655440000
```

输出：

```json
{
  "batch_id": "550e8400-e29b-41d4-a716-446655440000",
  "data": [
    {
      "run_id": "run-1",
      "status": "COMPLETED",
      "goal": "Extract the main heading",
      "num_of_steps": 5,
      "result": { "heading": "Welcome" }
    }
  ],
  "not_found": null
}
```

---

## tinyfish agent batch cancel <batch_id>

取消批量任务中的所有运行。

```bash
tinyfish agent batch cancel 550e8400-e29b-41d4-a716-446655440000
```

---

## 最佳实践

1. **在 goal 中指定输出格式**：明确要求返回 JSON 结构，便于程序化处理。如 `"Extract the pricing. Return JSON with keys: price, currency, plan_name."`
2. **多站点独立调用**：需要对多个网站执行不同任务时，分别调用而非合并为一个 goal。每个 site 独立 run 更可控。
3. **bare hostname 自动加 https://**：`--url example.com` 等同于 `--url https://example.com`，无需手动补全协议。
