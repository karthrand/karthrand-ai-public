#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PORT=22
VERBOSE=0
PARALLEL=0
ACTION="run"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# 统一执行环境判定逻辑，避免多个脚本各写一套。
# shellcheck source=./runtime.sh
source "${SCRIPT_DIR}/runtime.sh"

log() {
  printf '[remote] %s\n' "$*"
}

usage() {
  cat <<'EOF'
用法：
  remote.sh --save "<address>" --user "<username>" --password "<password>" [--port 22]
  remote.sh --show "<address>" [--port 22]
  remote.sh "<address>" "<command>"
  remote.sh --parallel "<address>" "<cmd1>" "<cmd2>" ...
  remote.sh --parallel -v "<address>" "<cmd1>" "<cmd2>" ...
EOF
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

current_runtime_type() {
  remote_detect_runtime_type
}

convert_windows_path() {
  local raw_path="$1"
  if [ -z "$raw_path" ]; then
    return 1
  fi

  if has_cmd wslpath; then
    wslpath "$raw_path"
    return 0
  fi

  if has_cmd cygpath; then
    cygpath -u "$raw_path"
    return 0
  fi

  printf '%s\n' "$raw_path"
}

ensure_windows_bash_lc() {
  if [ "$(current_runtime_type)" != "windows-msys" ]; then
    return 0
  fi

  if [ "${REMOTE_BASH_LC:-}" = "1" ]; then
    return 0
  fi

  log "windows-msys 执行环境下必须通过 bash -lc 调用 ${SCRIPT_NAME}。在 PowerShell 中请改用 skills/remote/scripts/remote.ps1。"
  exit 12
}

python_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    printf 'python3'
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    printf 'python'
    return 0
  fi
  return 1
}

current_host_os() {
  remote_detect_host_os
}

current_bash_flavor() {
  remote_detect_bash_flavor
}

current_bash_path() {
  if [ -n "${REMOTE_HOST_BASH_PATH:-}" ]; then
    printf '%s\n' "$REMOTE_HOST_BASH_PATH"
    return 0
  fi

  if has_cmd bash; then
    command -v bash
    return 0
  fi

  printf '\n'
}

current_bash_available() {
  if [ -n "$(current_bash_path)" ]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

current_sshpass_provider() {
  remote_detect_sshpass_provider
}

current_windows_remote_ready() {
  if [ "$(current_runtime_type)" = "windows-msys" ] && [ "${REMOTE_BASH_LC:-}" = "1" ]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

refresh_runtime_context() {
  CURRENT_RUNTIME_TYPE="$(current_runtime_type)"
  CURRENT_HOST_OS="$(current_host_os)"
  CURRENT_BASH_FLAVOR="$(current_bash_flavor)"
  CURRENT_BASH_PATH="$(current_bash_path)"
  CURRENT_BASH_AVAILABLE="$(current_bash_available)"
  CURRENT_SSHPASS_PROVIDER="$(current_sshpass_provider)"
  CURRENT_WINDOWS_REMOTE_READY="$(current_windows_remote_ready)"
}

state_dir() {
  local base_path
  base_path="${REMOTE_HOST_WINDOWS_LOCALAPPDATA:-}"
  if [ -n "$base_path" ]; then
    printf '%s/remote\n' "$(convert_windows_path "$base_path")"
    return 0
  fi

  base_path="${XDG_DATA_HOME:-}"
  if [ -z "$base_path" ]; then
    base_path="${HOME}/.local/share"
  fi

  printf '%s/remote\n' "$base_path"
}

bootstrap_state_file() {
  printf '%s/bootstrap-state.json\n' "$(state_dir)"
}

servers_state_file() {
  printf '%s/servers.json\n' "$(state_dir)"
}

extract_version_from_text() {
  printf '%s\n' "$1" | tr '\r' '\n' | sed -nE 's/.*([0-9]+\.[0-9]+).*/\1/p' | head -n 1
}

probe_sshpass() {
  PROBED_SSHPASS_VERSION="unknown"

  has_cmd sshpass || return 1

  local output version
  output="$(sshpass -V 2>&1 || true)"
  if [ -n "$output" ] && ! printf '%s' "$output" | grep -qi 'invalid option'; then
    if printf '%s' "$output" | grep -qi 'sshpass\|usage:'; then
      version="$(extract_version_from_text "$output")"
      [ -n "$version" ] && PROBED_SSHPASS_VERSION="$version"
      return 0
    fi
  fi

  output="$(sshpass -h 2>&1 || true)"
  if printf '%s' "$output" | grep -qi 'usage:'; then
    version="$(extract_version_from_text "$output")"
    [ -n "$version" ] && PROBED_SSHPASS_VERSION="$version"
    return 0
  fi

  output="$(sshpass 2>&1 || true)"
  if printf '%s' "$output" | grep -qi 'usage:'; then
    return 0
  fi

  return 1
}

load_bootstrap_state() {
  if ! BOOTSTRAP_STATE_JSON="$(
    BOOTSTRAP_STATE_FILE="$(bootstrap_state_file)" \
    "$PYTHON_BIN" - <<'PY'
import json
import os
from pathlib import Path

state_file = Path(os.environ["BOOTSTRAP_STATE_FILE"])
if not state_file.exists():
    raise SystemExit(3)

payload = json.loads(state_file.read_text(encoding="utf-8"))
print(json.dumps(payload, ensure_ascii=False))
PY
  )"; then
    return 1
  fi

  return 0
}

read_bootstrap_field() {
  local field_name="$1"
  RECORD_JSON="$BOOTSTRAP_STATE_JSON" FIELD_NAME="$field_name" "$PYTHON_BIN" - <<'PY'
import json
import os

record = json.loads(os.environ["RECORD_JSON"])
value = record.get(os.environ["FIELD_NAME"], "")
if isinstance(value, bool):
    print(str(value).lower())
else:
    print("" if value is None else value)
PY
}

bootstrap_matches_runtime() {
  local saved_bash_path saved_runtime_type

  saved_runtime_type="$(read_bootstrap_field runtime_type)"
  if [ -n "$saved_runtime_type" ]; then
    [ "$saved_runtime_type" = "$CURRENT_RUNTIME_TYPE" ] || return 1
  fi

  [ "$(read_bootstrap_field os_type)" = "$CURRENT_HOST_OS" ] || return 1
  [ "$(read_bootstrap_field bash_available)" = "$CURRENT_BASH_AVAILABLE" ] || return 1
  [ "$(read_bootstrap_field bash_flavor)" = "$CURRENT_BASH_FLAVOR" ] || return 1
  [ "$(read_bootstrap_field sshpass_provider)" = "$CURRENT_SSHPASS_PROVIDER" ] || return 1

  saved_bash_path="$(read_bootstrap_field bash_path)"
  if [ -n "$CURRENT_BASH_PATH" ] || [ -n "$saved_bash_path" ]; then
    [ "$saved_bash_path" = "$CURRENT_BASH_PATH" ] || return 1
  fi

  if [ "$CURRENT_HOST_OS" = "windows" ]; then
    [ "$(read_bootstrap_field windows_remote_ready)" = "true" ] || return 1
  fi

  return 0
}

write_bootstrap_state() {
  local installed="$1"
  local version="$2"
  local touch_setup="${3:-false}"

  refresh_runtime_context

  STATE_DIR="$(state_dir)" \
  BOOTSTRAP_STATE_FILE="$(bootstrap_state_file)" \
  INSTALLED="$installed" \
  VERSION="$version" \
  TOUCH_SETUP="$touch_setup" \
  CURRENT_HOST_OS="$CURRENT_HOST_OS" \
  CURRENT_RUNTIME_TYPE="$CURRENT_RUNTIME_TYPE" \
  CURRENT_BASH_AVAILABLE="$CURRENT_BASH_AVAILABLE" \
  CURRENT_BASH_FLAVOR="$CURRENT_BASH_FLAVOR" \
  CURRENT_BASH_PATH="$CURRENT_BASH_PATH" \
  CURRENT_SSHPASS_PROVIDER="$CURRENT_SSHPASS_PROVIDER" \
  CURRENT_WINDOWS_REMOTE_READY="$CURRENT_WINDOWS_REMOTE_READY" \
  "$PYTHON_BIN" - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

state_dir = Path(os.environ["STATE_DIR"])
state_file = Path(os.environ["BOOTSTRAP_STATE_FILE"])
state_dir.mkdir(parents=True, exist_ok=True)
now = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")

if state_file.exists():
    payload = json.loads(state_file.read_text(encoding="utf-8"))
else:
    payload = {"skill_name": "remote"}

payload["skill_name"] = "remote"
payload["sshpass_installed"] = os.environ["INSTALLED"] == "true"
payload["sshpass_version"] = os.environ["VERSION"]
payload["os_type"] = os.environ["CURRENT_HOST_OS"]
payload["runtime_type"] = os.environ["CURRENT_RUNTIME_TYPE"]
payload["bash_available"] = os.environ["CURRENT_BASH_AVAILABLE"] == "true"
payload["bash_flavor"] = os.environ["CURRENT_BASH_FLAVOR"]
payload["bash_path"] = os.environ["CURRENT_BASH_PATH"]
payload["sshpass_provider"] = os.environ["CURRENT_SSHPASS_PROVIDER"]
payload["windows_remote_ready"] = os.environ["CURRENT_WINDOWS_REMOTE_READY"] == "true" and os.environ["INSTALLED"] == "true"
payload["last_verified_at"] = now
if os.environ["TOUCH_SETUP"] == "true":
    payload["last_setup_at"] = now
else:
    payload["last_setup_at"] = payload.get("last_setup_at") or now

state_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

ensure_sshpass() {
  refresh_runtime_context

  local bootstrap_present="false"
  local bootstrap_matches="false"
  local bootstrap_installed="false"

  if load_bootstrap_state; then
    bootstrap_present="true"
    if bootstrap_matches_runtime; then
      bootstrap_matches="true"
      bootstrap_installed="$(read_bootstrap_field sshpass_installed)"
      if [ "$bootstrap_installed" = "true" ] && has_cmd sshpass; then
        return 0
      fi
    fi
  fi

  if probe_sshpass; then
    if [ "$bootstrap_present" = "true" ] && [ "$bootstrap_matches" = "false" ]; then
      log "检测到 bootstrap-state 与当前运行时不一致，已按当前环境重新校验 sshpass。"
    elif [ "$bootstrap_present" = "true" ] && [ "$bootstrap_installed" != "true" ]; then
      log "状态文件显示 sshpass 未就绪，已按真实环境重新校验。"
    fi

    write_bootstrap_state "true" "$PROBED_SSHPASS_VERSION" "false"
    return 0
  fi

  write_bootstrap_state "false" "unknown" "false"
  log "未检测到可用的 sshpass，请先执行 skills/remote/scripts/setup.sh 或 setup.ps1。"
  exit 10
}

now_iso() {
  "$PYTHON_BIN" - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"))
PY
}

parse_target() {
  local raw="$1"
  if [[ "$raw" == *"@"* ]]; then
    PARSED_USER="${raw%@*}"
    PARSED_ADDRESS="${raw#*@}"
  else
    PARSED_USER=""
    PARSED_ADDRESS="$raw"
  fi
}

save_server_record() {
  local address="$1"
  local port="$2"
  local username="$3"
  local password="$4"
  local last_error="${5:-}"
  local last_verified_at="${6:-}"

  STATE_DIR="$(state_dir)" \
  SERVERS_STATE_FILE="$(servers_state_file)" \
  ADDRESS="$address" \
  PORT="$port" \
  USERNAME="$username" \
  PASSWORD="$password" \
  LAST_ERROR="$last_error" \
  LAST_VERIFIED_AT="$last_verified_at" \
  "$PYTHON_BIN" - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

state_dir = Path(os.environ["STATE_DIR"])
state_file = Path(os.environ["SERVERS_STATE_FILE"])
state_dir.mkdir(parents=True, exist_ok=True)

if state_file.exists():
    data = json.loads(state_file.read_text(encoding="utf-8"))
else:
    data = {"skill_name": "remote", "updated_at": "", "servers": []}

servers = data.setdefault("servers", [])
address = os.environ["ADDRESS"]
port = int(os.environ["PORT"])
server_id = f"{address}:{port}"
now = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
last_verified_at = os.environ["LAST_VERIFIED_AT"]

record = {
    "server_id": server_id,
    "address": address,
    "port": port,
    "username": os.environ["USERNAME"],
    "password": os.environ["PASSWORD"],
    "last_verified_at": last_verified_at,
    "last_error": os.environ["LAST_ERROR"],
    "updated_at": now,
}

for index, item in enumerate(servers):
    if item.get("server_id") == server_id:
        servers[index] = record
        break
else:
    servers.append(record)

data["skill_name"] = "remote"
data["updated_at"] = now
state_file.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

show_server_record() {
  local address="$1"
  local port="$2"

  SERVERS_STATE_FILE="$(servers_state_file)" \
  ADDRESS="$address" \
  PORT="$port" \
  "$PYTHON_BIN" - <<'PY'
import json
import os
from pathlib import Path

state_file = Path(os.environ["SERVERS_STATE_FILE"])
if not state_file.exists():
    raise SystemExit(3)

data = json.loads(state_file.read_text(encoding="utf-8"))
server_id = f'{os.environ["ADDRESS"]}:{int(os.environ["PORT"])}'
for item in data.get("servers", []):
    if item.get("server_id") == server_id:
        print(json.dumps(item, ensure_ascii=False, indent=2))
        raise SystemExit(0)

raise SystemExit(4)
PY
}

load_server_record() {
  local address="$1"
  local port="$2"

  if ! SERVER_RECORD_JSON="$(
    SERVERS_STATE_FILE="$(servers_state_file)" \
    ADDRESS="$address" \
    PORT="$port" \
    "$PYTHON_BIN" - <<'PY'
import json
import os
from pathlib import Path

state_file = Path(os.environ["SERVERS_STATE_FILE"])
if not state_file.exists():
    raise SystemExit(3)

data = json.loads(state_file.read_text(encoding="utf-8"))
server_id = f'{os.environ["ADDRESS"]}:{int(os.environ["PORT"])}'
for item in data.get("servers", []):
    if item.get("server_id") == server_id:
        print(json.dumps(item, ensure_ascii=False))
        raise SystemExit(0)

raise SystemExit(4)
PY
  )"; then
    return 1
  fi

  return 0
}

read_field() {
  local field_name="$1"
  RECORD_JSON="$SERVER_RECORD_JSON" FIELD_NAME="$field_name" "$PYTHON_BIN" - <<'PY'
import json
import os

record = json.loads(os.environ["RECORD_JSON"])
value = record.get(os.environ["FIELD_NAME"], "")
print("" if value is None else value)
PY
}

build_connection_context() {
  local raw_target="$1"
  parse_target "$raw_target"

  local address="$PARSED_ADDRESS"
  local port="${REMOTE_SSH_PORT:-$DEFAULT_PORT}"

  if [ -n "${CLI_PORT:-}" ]; then
    port="$CLI_PORT"
  fi

  local user="${REMOTE_SSH_USER:-}"
  if [ -n "$PARSED_USER" ]; then
    user="$PARSED_USER"
  fi

  local password="${REMOTE_SSH_PASSWORD:-}"

  if load_server_record "$address" "$port"; then
    [ -n "$user" ] || user="$(read_field username)"
    [ -n "$password" ] || password="$(read_field password)"
  fi

  if [ -z "$user" ] || [ -z "$password" ]; then
    log "未找到 ${address}:${port} 的完整服务器记录，请先提供地址、用户名和密码并执行 --save。"
    exit 20
  fi

  CONNECTION_ADDRESS="$address"
  CONNECTION_PORT="$port"
  CONNECTION_USER="$user"
  CONNECTION_PASSWORD="$password"
  CONNECTION_TARGET="${user}@${address}"
}

ssh_common_args() {
  printf '%s\n' \
    "-o" "ConnectTimeout=10" \
    "-o" "ServerAliveInterval=30" \
    "-o" "ServerAliveCountMax=3" \
    "-o" "PreferredAuthentications=password,keyboard-interactive" \
    "-o" "PubkeyAuthentication=no" \
    "-o" "StrictHostKeyChecking=no" \
    "-o" "UserKnownHostsFile=/dev/null" \
    "-o" "LogLevel=ERROR" \
    "-p" "$CONNECTION_PORT"
}

run_remote_command() {
  local command_text="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local -a ssh_args=()
  while IFS= read -r line; do
    ssh_args+=("$line")
  done < <(ssh_common_args)

  sshpass -p "$CONNECTION_PASSWORD" ssh "${ssh_args[@]}" "$CONNECTION_TARGET" "$command_text" >"$stdout_file" 2>"$stderr_file"
}

update_bootstrap_verified_at() {
  local version="unknown"
  if probe_sshpass; then
    version="$PROBED_SSHPASS_VERSION"
  fi

  write_bootstrap_state "true" "$version" "false"
}

render_failure_diagnosis() {
  local stderr_file="$1"

  if [ ! -s "$stderr_file" ]; then
    return 0
  fi

  local stderr_text
  stderr_text="$(cat "$stderr_file")"

  printf 'Diagnosis:\n'
  if printf '%s' "$stderr_text" | grep -qi 'Permission denied'; then
    printf '结论: 远端拒绝了密码认证。\n'
    printf '证据: SSH 返回 Permission denied。\n'
    printf '推断: 可能是用户名、密码或服务端认证策略问题；不能仅凭当前输出判断为特殊字符转义或 sshpass 兼容性问题。\n'
    printf '下一步: 先核对账号密码与 SSH 密码登录策略；若需重试，只通过 remote 标准主链再做一次最小验证。\n'
    return 0
  fi

  if printf '%s' "$stderr_text" | grep -qi 'Connection timed out\|Operation timed out'; then
    printf '结论: SSH 连接超时。\n'
    printf '证据: SSH 返回 timed out。\n'
    printf '推断: 可能是网络不通、端口不可达或目标主机响应慢。\n'
    printf '下一步: 先核对地址、端口和网络连通性，再决定是否继续诊断。\n'
    return 0
  fi

  if printf '%s' "$stderr_text" | grep -qi 'Connection refused'; then
    printf '结论: 目标主机拒绝了 SSH 连接。\n'
    printf '证据: SSH 返回 Connection refused。\n'
    printf '推断: 可能是 SSH 服务未监听目标端口，或中间链路转发配置不正确。\n'
    printf '下一步: 先核对端口与 SSH 服务状态。\n'
    return 0
  fi

  printf '结论: 远程命令执行失败。\n'
  printf '证据: 请查看上方 Error 输出。\n'
  printf '推断: 当前证据不足，不能直接归因为密码特殊字符、sshpass 参数或兼容性问题。\n'
  printf '下一步: 保持标准主链，基于错误输出继续定位。\n'
}

render_single_result() {
  local command_text="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local rc="$4"
  local duration="$5"

  printf '━━━ Remote Command Execution ━━━\n'
  printf 'Host: %s\n' "$CONNECTION_TARGET"
  printf 'Port: %s\n' "$CONNECTION_PORT"
  printf 'Command: %s\n' "$command_text"
  printf '────────────────────────────────\n'
  printf 'Output:\n'
  if [ -s "$stdout_file" ]; then
    cat "$stdout_file"
  else
    printf '(empty)\n'
  fi
  if [ -s "$stderr_file" ]; then
    printf 'Error:\n'
    cat "$stderr_file"
  fi
  if [ "$rc" -eq 0 ]; then
    printf '结果: 成功\n'
  else
    printf '结果: 失败 (rc=%s)\n' "$rc"
    render_failure_diagnosis "$stderr_file"
  fi
  printf 'Duration: %ss\n' "$duration"
}

execute_single() {
  local command_text="$1"
  local tmp_dir stdout_file stderr_file start_time end_time duration rc
  tmp_dir="$(mktemp -d)"
  stdout_file="${tmp_dir}/stdout"
  stderr_file="${tmp_dir}/stderr"
  start_time="$(date +%s)"

  set +e
  run_remote_command "$command_text" "$stdout_file" "$stderr_file"
  rc=$?
  set -e

  end_time="$(date +%s)"
  duration=$((end_time - start_time))

  render_single_result "$command_text" "$stdout_file" "$stderr_file" "$rc" "$duration"

  if [ "$rc" -eq 0 ]; then
    save_server_record "$CONNECTION_ADDRESS" "$CONNECTION_PORT" "$CONNECTION_USER" "$CONNECTION_PASSWORD" "" "$(now_iso)"
    update_bootstrap_verified_at
  else
    local last_error
    last_error="$(cat "$stderr_file" 2>/dev/null || true)"
    save_server_record "$CONNECTION_ADDRESS" "$CONNECTION_PORT" "$CONNECTION_USER" "$CONNECTION_PASSWORD" "$last_error" ""
  fi

  rm -rf "$tmp_dir"
  return "$rc"
}

execute_parallel() {
  local -a commands=("$@")
  local total="${#commands[@]}"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local -a pids=()
  local -a out_files=()
  local -a err_files=()
  local -a rc_files=()

  printf '━━━ Parallel Remote Execution ━━━\n'
  printf 'Host: %s\n' "$CONNECTION_TARGET"
  printf 'Port: %s\n' "$CONNECTION_PORT"
  printf 'Tasks: %s\n' "$total"
  printf '────────────────────────────────\n'
  printf 'Commands:\n'

  local i
  for i in "${!commands[@]}"; do
    printf '  [%s] %s\n' "$((i + 1))" "${commands[$i]}"
  done

  printf '\n'

  for i in "${!commands[@]}"; do
    out_files[$i]="${tmp_dir}/stdout_${i}"
    err_files[$i]="${tmp_dir}/stderr_${i}"
    rc_files[$i]="${tmp_dir}/rc_${i}"
    (
      set +e
      run_remote_command "${commands[$i]}" "${out_files[$i]}" "${err_files[$i]}"
      rc=$?
      set -e
      printf '%s' "$rc" > "${rc_files[$i]}"
    ) &
    pids[$i]=$!
  done

  for i in "${!commands[@]}"; do
    wait "${pids[$i]}"
    printf '.'
  done
  printf ' Done!\n'

  local success_count=0
  local fail_count=0
  local final_rc=0

  printf '\n═══════════════════════════════\n'
  printf 'Results:\n'

  for i in "${!commands[@]}"; do
    local rc
    rc="$(cat "${rc_files[$i]}")"
    if [ "$rc" -eq 0 ]; then
      success_count=$((success_count + 1))
    else
      fail_count=$((fail_count + 1))
      final_rc=1
    fi
  done

  printf 'Success: %s | Failed: %s\n' "$success_count" "$fail_count"
  printf '═══════════════════════════════\n'

  for i in "${!commands[@]}"; do
    local rc
    rc="$(cat "${rc_files[$i]}")"
    printf '\n--- Command %s: %s ---\n' "$((i + 1))" "${commands[$i]}"
    if [ "$rc" -eq 0 ]; then
      printf 'SUCCESS\n'
    else
      printf 'FAILED (exit code: %s)\n' "$rc"
    fi

    if [ -s "${out_files[$i]}" ]; then
      cat "${out_files[$i]}"
      printf '\n'
    else
      printf '(empty)\n'
    fi

    if [ "$VERBOSE" -eq 1 ] && [ -s "${err_files[$i]}" ]; then
      printf 'Error:\n'
      cat "${err_files[$i]}"
      printf '\n'
    fi
  done

  if [ "$final_rc" -eq 0 ]; then
    save_server_record "$CONNECTION_ADDRESS" "$CONNECTION_PORT" "$CONNECTION_USER" "$CONNECTION_PASSWORD" "" "$(now_iso)"
    update_bootstrap_verified_at
  else
    save_server_record "$CONNECTION_ADDRESS" "$CONNECTION_PORT" "$CONNECTION_USER" "$CONNECTION_PASSWORD" "parallel execution failed" ""
  fi

  rm -rf "$tmp_dir"
  return "$final_rc"
}

PYTHON_BIN="$(python_cmd)" || {
  log "缺少 python3/python，无法读写 remote 状态文件。"
  exit 11
}

ensure_windows_bash_lc

CLI_PORT=""
CLI_USER=""
CLI_PASSWORD=""
POSITIONAL=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --parallel)
      PARALLEL=1
      shift
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    --save)
      ACTION="save"
      shift
      ;;
    --show)
      ACTION="show"
      shift
      ;;
    --port)
      CLI_PORT="$2"
      shift 2
      ;;
    --user)
      CLI_USER="$2"
      shift 2
      ;;
    --password)
      CLI_PASSWORD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

case "$ACTION" in
  save)
    [ "${#POSITIONAL[@]}" -ge 1 ] || {
      usage
      exit 2
    }
    parse_target "${POSITIONAL[0]}"
    [ -n "$CLI_USER" ] || CLI_USER="$PARSED_USER"
    [ -n "$CLI_USER" ] || {
      log "--save 必须提供用户名。"
      exit 2
    }
    [ -n "$CLI_PASSWORD" ] || {
      log "--save 必须提供密码。"
      exit 2
    }
    [ -n "$CLI_PORT" ] || CLI_PORT="$DEFAULT_PORT"
    save_server_record "$PARSED_ADDRESS" "$CLI_PORT" "$CLI_USER" "$CLI_PASSWORD" "" ""
    log "已保存服务器记录：${PARSED_ADDRESS}:${CLI_PORT}"
    exit 0
    ;;
  show)
    [ "${#POSITIONAL[@]}" -ge 1 ] || {
      usage
      exit 2
    }
    parse_target "${POSITIONAL[0]}"
    [ -n "$CLI_PORT" ] || CLI_PORT="$DEFAULT_PORT"
    if ! show_server_record "$PARSED_ADDRESS" "$CLI_PORT"; then
      log "未找到服务器记录：${PARSED_ADDRESS}:${CLI_PORT}"
      exit 21
    fi
    exit 0
    ;;
  run)
    ensure_sshpass
    if [ "$PARALLEL" -eq 1 ]; then
      [ "${#POSITIONAL[@]}" -ge 2 ] || {
        usage
        exit 2
      }
      REMOTE_SSH_USER="${CLI_USER:-${REMOTE_SSH_USER:-}}" \
      REMOTE_SSH_PASSWORD="${CLI_PASSWORD:-${REMOTE_SSH_PASSWORD:-}}" \
      REMOTE_SSH_PORT="${CLI_PORT:-${REMOTE_SSH_PORT:-}}" \
      build_connection_context "${POSITIONAL[0]}"
      execute_parallel "${POSITIONAL[@]:1}"
      exit $?
    fi

    [ "${#POSITIONAL[@]}" -eq 2 ] || {
      usage
      exit 2
    }
    REMOTE_SSH_USER="${CLI_USER:-${REMOTE_SSH_USER:-}}" \
    REMOTE_SSH_PASSWORD="${CLI_PASSWORD:-${REMOTE_SSH_PASSWORD:-}}" \
    REMOTE_SSH_PORT="${CLI_PORT:-${REMOTE_SSH_PORT:-}}" \
    build_connection_context "${POSITIONAL[0]}"
    execute_single "${POSITIONAL[1]}"
    exit $?
    ;;
esac
