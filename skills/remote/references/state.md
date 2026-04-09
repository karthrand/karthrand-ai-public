# Remote 状态文件说明

`remote` skill 的本地状态目录固定为：

- Windows：`%LOCALAPPDATA%\remote\`
- macOS / Linux：`${XDG_DATA_HOME:-$HOME/.local/share}/remote/`

状态文件只写入宿主本地目录，不写入仓库。

## 1. bootstrap-state.json

用于表达 setup 结果，推荐结构：

```json
{
  "skill_name": "remote",
  "sshpass_installed": true,
  "sshpass_version": "1.09",
  "os_type": "linux",
  "last_setup_at": "2026-04-09T12:00:00+08:00",
  "last_verified_at": "2026-04-09T12:00:00+08:00"
}
```

约束：

- 只表达安装与验证结果
- 不保存服务器业务数据
- Windows 下额外记录：
  - `bash_available`
  - `windows_remote_ready`

## 2. servers.json

用于保存服务器连接信息，推荐结构：

```json
{
  "skill_name": "remote",
  "updated_at": "2026-04-09T12:00:00+08:00",
  "servers": [
    {
      "server_id": "10.0.0.8:22",
      "address": "10.0.0.8",
      "port": 22,
      "username": "root",
      "password": "secret",
      "last_verified_at": "2026-04-09T12:00:00+08:00",
      "last_error": "",
      "updated_at": "2026-04-09T12:00:00+08:00"
    }
  ]
}
```

约束：

- `server_id` 固定使用 `address:port`
- 端口默认 `22`
- 用户修改任一服务器信息后，立即更新本地记录
- 登录失败后，允许把失败信息写入 `last_error`
- 本 skill 属于内部 skill，允许在宿主本地状态目录明文保存密码
- 凭据内容不得写入仓库或 `.work`
