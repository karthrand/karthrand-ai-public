# Search-Web

集成多源搜索的技术查询技能，整合 Context7 文档查询、Exa 网络搜索、TinyFish 备用搜索、mcp-deepwiki（DeepWiki）仓库文档和 github-fetcher 仓库文件读取。

## 前置条件

### 必需的 MCP 服务器

| MCP 工具 | 用途 | 类型 |
|----------|------|------|
| **context7** | 技术文档和代码示例查询 | stdio (npx) |
| **exa** | 网络搜索 | 远程 HTTP |
| **mcp-deepwiki** | GitHub 仓库文档查询 | stdio (npx) |
| **github-fetcher** | GitHub 仓库文件与目录读取 | stdio (npx) |

### 可选 CLI 备用工具

| CLI 工具 | 用途 | 安装方式 |
|----------|------|----------|
| **tinyfish** | Exa 失败后的备用网页搜索与正文抓取 | `npm install -g @tiny-fish/cli@latest` |

### 已适配 setup 的 Code Agent

- Claude Code
- Codex
- OpenCode
- QwenCode
- Hermes
- Pi

未列出的 code agent 也可使用本 skill。普通搜索不做环境初始化；需要配置时运行 `$search-web setup` 获取通用 MCP JSON。

### 验证安装

- 直接询问 code agent 有哪些 skills
- 运行 `$search-web setup` 后重启 code agent，再确认 MCP 是否可用

## 整体流程

普通搜索：

1. 根据用户目标选择 `Context7`、`Exa`、`mcp-deepwiki`、`github-fetcher` 或网页正文读取。
2. `Exa` 失败、额度到限、服务不可用或空结果时，使用 `TinyFish` CLI 备用。
3. MCP 未注册或不可用时，停止并提示运行 `$search-web setup` 后重启。

手动 setup：

1. 检测 code agent 与 OS。
2. 确保 `tinyfish` CLI 可用（全局装 `@tiny-fish/cli@latest`）。
3. 检测并安装缺失 MCP（exa 必需 Key）。
4. 设置永久 `TINYFISH_API_KEY`。
5. 提示重启 code agent。

## 手动初始化

```bash
# 执行完整 setup（exa key 必需）
$search-web setup

# 脚本等价入口
bash scripts/setup-mcp.sh --api-key "EXA_API_KEY=你的ExaKey"

# 单项调试
bash scripts/setup-mcp.sh --mcp exa --api-key "EXA_API_KEY=你的ExaKey"
bash scripts/setup-mcp.sh --mcp context7
```

完整初始化指南见 `references/setup.md`。

## MCP 使用边界

| 搜索目标 | 使用的工具 | 说明 |
|---------|-----------|------|
| 技术文档 | Context7 | 固定顺序：先 resolve-library-id 再 query-docs |
| 网络搜索 | Exa / TinyFish | Exa 优先；失败、额度到限、服务不可用或空结果时使用 TinyFish |
| GitHub 仓库文档 | mcp-deepwiki | 仓库级别的文档概览和深读 |
| GitHub 仓库文件/目录 | github-fetcher | 读取具体文件内容或目录结构 |
| 网页正文 | 宿主提供的读取工具 / TinyFish | 仅在已知 URL 后使用；宿主读取失败时可用 TinyFish |

## 目录结构

```
search-web/
├── SKILL.md                              # 技能主文件
├── README.md                             # 本文件
├── scripts/
│   ├── detect.sh                         # 统一环境检测脚本（agent/os/state-dir）
│   └── setup-mcp.sh                      # MCP 安装脚本
├── references/
│   ├── setup.md                          # 初始化配置指南
│   ├── tinyfish-fallback.md              # TinyFish 备用搜索与正文抓取
│   ├── rules/
│   │   └── output-format.md              # 输出格式规范
│   └── strategies/
│       └── config-index-shortcut.md      # 配置索引直达策略
└── examples/
    └── usage.md                          # 使用示例
```
