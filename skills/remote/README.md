# Remote 远程访问技能

`remote` 是一个面向内部场景的 Linux 服务器远程访问 skill。它默认使用 `sshpass`，并在宿主本地状态目录保存：

- `bootstrap-state.json`：`sshpass` setup 与验证状态
- `servers.json`：服务器地址、端口、用户名、密码与最近一次验证结果

## 目录结构

```text
skills/remote/
├── README.md
├── SKILL.md
├── agents/
│   └── openai.yaml
├── references/
│   ├── remote-guidelines.md
│   ├── setup.md
│   └── state.md
└── scripts/
    ├── remote.ps1
    ├── remote.sh
    ├── setup.ps1
    └── setup.sh
```

## 状态目录

- Windows：`%LOCALAPPDATA%\remote\`
- macOS / Linux：`${XDG_DATA_HOME:-$HOME/.local/share}/remote/`

其中包含：

- `bootstrap-state.json`
- `servers.json`

## setup

### Windows

必须先执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\remote\scripts\setup.ps1
```

### macOS / Linux

```bash
bash ./skills/remote/scripts/setup.sh
```

验证方式：

```bash
sshpass -V
```

## 远程执行

### Windows

Windows 下所有远程访问都必须走 `bash -lc`。推荐入口是 `remote.ps1`，它内部固定转发到 `bash -lc`：

```powershell
.\skills\remote\scripts\remote.ps1 --save "10.0.0.8" --user root --password "secret"
.\skills\remote\scripts\remote.ps1 "10.0.0.8" "hostname && whoami"
```

如果手工执行，也只能显式使用：

```powershell
bash -lc 'REMOTE_BASH_LC=1 ./skills/remote/scripts/remote.sh "10.0.0.8" "hostname && whoami"'
```

禁止：

- 在 PowerShell 中裸跑 `sshpass ... ssh ...`
- 在 Windows 下直接执行 `remote.sh`

### macOS / Linux

```bash
./skills/remote/scripts/remote.sh --save "10.0.0.8" --user root --password "secret"
./skills/remote/scripts/remote.sh "10.0.0.8" "hostname && whoami"
./skills/remote/scripts/remote.sh --parallel "10.0.0.8" "uptime" "free -h" "df -h"
```

## 服务器记录管理

首次访问或用户修改连接信息后，先写入服务器记录：

```bash
./skills/remote/scripts/remote.sh --save "10.0.0.8" --user root --password "secret" --port 22
```

查看当前记录：

```bash
./skills/remote/scripts/remote.sh --show "10.0.0.8"
```

## 工作边界

- 默认只做读取、诊断、检查
- 默认不做批量改动、重启、删除、停服务
- 诊断类任务首轮不应先用 `grep/head/tail` 过滤
- 多维采集优先并行执行
