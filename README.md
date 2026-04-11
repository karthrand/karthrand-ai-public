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

## Skill清单

| Skill | 领域 | 描述 |
|-------|------|------|
| `mindmap` | 通用 | 将上下文内容转换为思维导图/流程图等可视化图表 |
| `plan-mode` | 通用 | 基于专业文档和网络搜索获取信息为基准的 Plan 模式，在编码前产出计划文档 |
| `plugin-builder` | AI | 创建和管理私有 Claude Code 插件，打包 skills/agents/commands/hooks/MCP 配置 |
| `remote` | 运维 | 远程访问 Linux 服务器，复用本地保存的服务器信息，支持单条或并行命令 |
| `search-web` | 通用 | 整合 Context7、Exa、DeepWiki 等工具搜索技术文档、代码示例和网页资料 |

### 添加单个Skill

```bash
npx skills add https://github.com/karthrand/karthrand-ai-public.git -g -y --skill <skill-name>
```
 - `-g`: 全局安装
 - `-y`: 静默安装
 - `--skill`: 指定 Skill 名称

**示例：安装所有 Skill**

```bash
npx skills add https://github.com/karthrand/karthrand-ai-public.git -g -y --skill mindmap
```

```bash
npx skills add https://github.com/karthrand/karthrand-ai-public.git -g -y --skill plan-mode
```

```bash
npx skills add https://github.com/karthrand/karthrand-ai-public.git -g -y --skill plugin-builder
```

```bash
npx skills add https://github.com/karthrand/karthrand-ai-public.git -g -y --skill remote
```

```bash
npx skills add https://github.com/karthrand/karthrand-ai-public.git -g -y --skill search-web
```

### 更新
- 检查更新

```bash
npx skills check
```

- 更新

```bash
npx skills update
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
