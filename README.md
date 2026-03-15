# Karthrand AI Tools

Karthrand 的 AI 工具库，包含 Claude Code 插件、Skills、Agents 等资源。

## 目录结构

```
karthrand-ai-public/
├── .claude-plugin/
│   ├── plugin.json       # 插件清单
│   └── marketplace.json  # 市场配置
├── skills/               # Skills 目录
├── agents/               # Agents 目录
├── commands/             # 斜杠命令目录
├── rules/                # 各语言规则文件
├── mcps/                 # MCP 服务器配置
├── hooks/                # 事件钩子
│   └── hooks.json
└── README.md
```

## 开发指南

### 添加新组件

1. **Skill** - 在 `skills/` 目录创建 `<name>.md` 文件
2. **Agent** - 在 `agents/` 目录创建 `<name>.md` 文件
3. **Command** - 在 `commands/` 目录创建 `<name>.md` 文件
4. **Rule** - 在 `rules/` 目录创建语言规则文件（如 `python.json`、`javascript.json`）
5. **MCP** - 在 `mcps/` 目录存放 MCP 服务器配置文件
6. **Hook** - 在 `hooks/hooks.json` 中添加事件钩子配置


## 许可证

MIT License
