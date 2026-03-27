# Karthrand AI Tools

Karthrand 的 AI 工具库，包含 Claude Code 插件、Skills、Agents 等资源。

## 设置代理(推荐)

- github仓库有时网络不稳定，需要设置专属代理
- 仅对githun仓库生效，不影响其他项目，如自建gitlab
- `127.0.0.1:7890`请替换为实际的代理IP与端口

```
git config --global http.https://github.com.proxy http://127.0.0.1:7890
git config --global https.https://github.com.proxy http://127.0.0.1:7890
```

## Skill安装

| Skill | 领域 | 描述 | 
|-------|------|--------|
| `mindmap` | 通用 | 将上下文的内容转换为思维导图 |
| `plan-mode` | 通用 | 基于专业文档和网络搜素获取信息为基准的Plan模式 |
| `plugin-builder` | AI | 快速创建一个用于防止AI技能的代码仓库 |


- 添加单个Skill

```bash 
npx skills add https://github.com/karthrand/karthrand-ai-private.git --skill mindmap
```

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

## 许可证

MIT License
