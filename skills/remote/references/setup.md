# Remote setup 说明

仅在以下情况参考本文件：

- 第一次使用 `remote` skill
- `bootstrap-state.json` 不存在
- `sshpass -V` 失败
- 远程执行前发现 `sshpass` 不可用

## 状态目录

- Windows：`%LOCALAPPDATA%\remote\`
- macOS / Linux：`${XDG_DATA_HOME:-$HOME/.local/share}/remote/`

setup 成功后写入：

- `bootstrap-state.json`

## 检测方式

统一使用：

```bash
sshpass -V
```

如命令不存在或返回异常，判定为未完成 setup。

## 自动 setup

### Windows

固定先尝试：

```powershell
winget install --source winget --exact --id xhcoding.sshpass-win32
```

失败后再尝试：

```powershell
scoop install Sshpass
```

执行方式：

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\remote\scripts\setup.ps1
```

注意：

- Windows 下远程访问必须通过 `bash -lc` 执行。
- 不允许在 PowerShell 中裸跑 `sshpass ... ssh ...`。
- 不允许在 Windows 下直接执行 `remote.sh`。
- 推荐从 PowerShell 调 `scripts/remote.ps1`，由它内部固定转发到 `bash -lc`。
- 如果手工使用 `bash -lc`，必须让调用链带上 `REMOTE_BASH_LC=1` 运行标记。
- `setup.ps1` 只负责安装与验证，不负责直接远程连接。

### macOS

```bash
brew install hudochenkov/sshpass/sshpass
```

说明：

- Homebrew 核心仓库不包含 `sshpass`，需通过第三方 tap 安装。

### Linux

按以下顺序自动选择：

```bash
apt-get update && apt-get install -y sshpass
dnf install -y sshpass
yum install -y sshpass
```

说明：

- RHEL / CentOS / Fedora 系如缺依赖，可先启用 `epel-release`。

## 成功标准

- `sshpass -V` 返回成功
- `bootstrap-state.json` 中 `sshpass_installed=true`
- Windows 下 `bootstrap-state.json` 还必须满足 `bash_available=true` 与 `windows_remote_ready=true`
- `bootstrap-state.json` 记录最近一次 setup 与验证时间

## 修复边界

只有以下情况才触发 setup 或强制修复：

- `sshpass` 命令不存在
- `sshpass -V` 失败
- 脚本检测到状态文件缺失或与真实环境不一致

以下情况不触发 setup：

- 地址输错
- 端口错误
- 用户名或密码错误
- 远程命令本身执行失败
