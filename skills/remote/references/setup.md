# Remote setup 说明

仅在以下情况参考本文件：

- 第一次使用 `remote` skill
- `bootstrap-state.json` 不存在
- `bootstrap-state.json` 显示 `sshpass_installed=false`
- `bootstrap-state.json` 与当前运行时不一致
- 远程执行前发现 `sshpass` 真实不可用

## 状态目录

- Windows：`%LOCALAPPDATA%\remote\`
- macOS / Linux：`${XDG_DATA_HOME:-$HOME/.local/share}/remote/`

setup 成功后写入：

- `bootstrap-state.json`

## 检测方式

统一规则：

```text
1. 命令存在
2. `sshpass -V` 或 `sshpass -h` 至少一种可识别
```

如命令不存在或帮助/版本输出异常，判定为未完成 setup。

## 自动 setup

### Windows

执行方式：

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\remote\scripts\setup.ps1
```

`setup.ps1` 会先识别当前 `bash` 运行时：

- `wsl`
  - 调用 `setup.sh`
  - 在 WSL 内安装 Linux `sshpass`
  - 状态文件写为 `bash_flavor=wsl`、`sshpass_provider=linux`
- `msys`
  - 固定先尝试：

```powershell
winget install --source winget --exact --id xhcoding.sshpass-win32
```

  - 失败后再尝试：

```powershell
scoop install Sshpass
```

  - 状态文件写为 `bash_flavor=msys`、`sshpass_provider=windows`

注意：

- Windows 下远程访问必须通过 `scripts/remote.ps1` 进入。
- 不允许在 PowerShell 中裸跑 `sshpass ... ssh ...`。
- 不允许在 Windows 下直接执行 `remote.sh`。
- 如果手工使用 `bash -lc`，必须让调用链带上 `REMOTE_BASH_LC=1` 运行标记。
- `setup.ps1` 只负责安装与验证，不负责直接远程连接。

### macOS

```bash
brew install hudochenkov/sshpass/sshpass
```

说明：

- Homebrew 核心仓库不包含 `sshpass`，需通过第三方 tap 安装。

### Linux / WSL

按以下顺序自动选择：

```bash
apt-get update && apt-get install -y sshpass
dnf install -y sshpass
yum install -y sshpass
```

说明：

- RHEL / CentOS / Fedora 系如缺依赖，可先启用 `epel-release`。

## 成功标准

- `bootstrap-state.json` 中 `sshpass_installed=true`
- `bootstrap-state.json` 中 `bash_flavor` 与当前运行时一致
- `bootstrap-state.json` 中 `sshpass_provider` 与当前 provider 一致
- Windows 下 `bootstrap-state.json` 还必须满足 `bash_available=true` 与 `windows_remote_ready=true`
- `bootstrap-state.json` 记录最近一次 setup 与验证时间

## 修复边界

只有以下情况才触发 setup 或强制修复：

- `sshpass` 命令不存在
- `bootstrap-state.json` 缺失
- `bootstrap-state.json` 与当前运行时不一致
- 状态文件显示未安装，且脚本复核真实环境后仍不可用

以下情况不触发 setup：

- 地址输错
- 端口错误
- 用户名或密码错误
- 远程命令本身执行失败
