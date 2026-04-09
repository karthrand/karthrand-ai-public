# Remote setup 说明

仅在以下情况参考本文件：

- 第一次使用 `remote` skill
- `bootstrap-state.json` 不存在
- `bootstrap-state.json` 显示 `sshpass_installed=false`
- `bootstrap-state.json` 与当前运行时不一致
- 远程执行前发现 `sshpass` 真实不可用

## 执行环境判定

`remote` 不做 code agent 探测，只做执行环境判定。唯一判定方法由 `scripts/runtime.sh` 定义，统一收敛为四种执行环境：

- `windows-msys`
  - `uname -s` 命中 `MINGW*`、`MSYS*` 或 `CYGWIN*`
  - `sshpass` provider 使用 Windows `sshpass-win32`
- `linux-wsl`
  - `uname -s` 为 `Linux`
  - 且命中 `WSL_DISTRO_NAME`、`WSL_INTEROP`，或 `/proc/version` 包含 `microsoft`
  - 视为 Linux 分支处理
- `linux-native`
  - `uname -s` 为 `Linux`
  - 且不命中 WSL 信号
- `macos-native`
  - `uname -s` 为 `Darwin`

判定优先级固定为：

```text
windows-msys -> linux-wsl -> linux-native / macos-native
```

agent 不要靠口头约定或手工判断环境；必须复用标准脚本内的判定方法。

## 状态目录

- Windows：`%LOCALAPPDATA%\remote\`
- macOS / Linux：`${XDG_DATA_HOME:-$HOME/.local/share}/remote/`

setup 成功后写入：

- `bootstrap-state.json`
- Windows 写入必须使用无 BOM UTF-8；读取端需要兼容历史 BOM 文件

## 检测方式

统一规则：

```text
1. 命令存在
2. `sshpass -V` 或 `sshpass -h` 至少一种可识别
```

如命令不存在或帮助/版本输出异常，判定为未完成 setup。
这一步必须由标准脚本完成，agent 不应手工探测后再裸跑 SSH。

## 自动 setup

### windows-msys

执行方式：

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\remote\scripts\setup.ps1
```

固定先尝试：

```powershell
winget install --source winget --exact --id xhcoding.sshpass-win32
```

失败后再尝试：

```powershell
scoop install Sshpass
```

状态文件写为 `runtime_type=windows-msys`、`bash_flavor=msys`、`sshpass_provider=windows`

注意：

- `windows-msys` 下远程访问必须通过 `scripts/remote.ps1` 进入。
- 不允许在 PowerShell 中裸跑 `sshpass ... ssh ...`。
- 不允许在 `windows-msys` 下直接执行 `remote.sh`。
- 不允许在连接失败后依次切换 `sshpass -k`、`sshpass -e`、`sshpass -p` 试错。
- 如果手工使用 `bash -lc`，必须让调用链带上 `REMOTE_BASH_LC=1` 运行标记。
- `setup.ps1` 只负责安装与验证，不负责直接远程连接。

### linux-wsl / linux-native

执行方式：

```bash
bash ./skills/remote/scripts/setup.sh
```

自动安装顺序：

```bash
apt-get update && apt-get install -y sshpass
dnf install -y sshpass
yum install -y sshpass
```

说明：

- `linux-wsl` 直接按 Linux 分支处理，不需要单独引入 Windows setup 规则
- RHEL / CentOS / Fedora 系如缺依赖，可先启用 `epel-release`
- 如果从 Windows PowerShell 进入 WSL，标准入口仍然是 `setup.ps1`，由它转发到 `setup.sh`

### macos-native

```bash
brew install hudochenkov/sshpass/sshpass
```

说明：

- Homebrew 核心仓库不包含 `sshpass`，需通过第三方 tap 安装。

## 成功标准

- `bootstrap-state.json` 中 `sshpass_installed=true`
- `bootstrap-state.json` 中 `runtime_type` 与当前执行环境一致
- `bootstrap-state.json` 中 `bash_flavor` 与当前执行环境映射一致
- `bootstrap-state.json` 中 `sshpass_provider` 与当前执行环境对应的 provider 一致
- `windows-msys` 下 `bootstrap-state.json` 还必须满足 `bash_available=true` 与 `windows_remote_ready=true`
- `bootstrap-state.json` 记录最近一次 setup 与验证时间

## 修复边界

只有以下情况才触发 setup 或强制修复：

- `sshpass` 命令不存在
- `bootstrap-state.json` 缺失
- `bootstrap-state.json` 与当前执行环境不一致
- 状态文件显示未安装，且脚本复核真实环境后仍不可用

以下情况不触发 setup：

- 地址输错
- 端口错误
- 用户名或密码错误
- 远程命令本身执行失败
