#!/usr/bin/env bash
set -euo pipefail

STATE_SKILL_NAME="remote"
FORCE=0
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 统一执行环境判定逻辑，避免 setup 和执行脚本各自维护一套判断。
# shellcheck source=./runtime.sh
source "${SCRIPT_DIR}/runtime.sh"

log() {
  printf '[remote/setup] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
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

state_dir() {
  # 统一使用 XDG 默认目录：$XDG_DATA_HOME/remote 或 ~/.local/share/remote。
  # windows-msys 下 python(win32) 不认 /c/ 风格路径，用 cygpath -m 转为 C:/ 混合风格，
  # 使 bash 与 Windows python 都能正确解析同一物理目录。
  local base_path="${XDG_DATA_HOME:-}"
  if [ -z "$base_path" ]; then
    base_path="${HOME}/.local/share"
  fi
  local result="${base_path}/${STATE_SKILL_NAME}"
  if [ "$(remote_detect_runtime_type)" = "windows-msys" ] && has_cmd cygpath; then
    result="$(cygpath -m "$result")"
  fi
  printf '%s\n' "$result"
}

bootstrap_state_file() {
  printf '%s/bootstrap-state.json\n' "$(state_dir)"
}

current_host_os() {
  remote_detect_host_os
}

current_runtime_type() {
  remote_detect_runtime_type
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

current_sshpass_provider() {
  remote_detect_sshpass_provider
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

write_bootstrap_state() {
  local installed="$1"
  local version="$2"
  local py
  py="$(python_cmd)" || {
    log "缺少 python3/python，无法写入 bootstrap-state.json。"
    exit 1
  }

  STATE_DIR="$(state_dir)" \
  BOOTSTRAP_STATE_FILE="$(bootstrap_state_file)" \
  SSHPASS_INSTALLED="$installed" \
  SSHPASS_VERSION="$version" \
  CURRENT_HOST_OS="$(current_host_os)" \
  CURRENT_RUNTIME_TYPE="$(current_runtime_type)" \
  CURRENT_BASH_FLAVOR="$(current_bash_flavor)" \
  CURRENT_BASH_PATH="$(current_bash_path)" \
  CURRENT_SSHPASS_PROVIDER="$(current_sshpass_provider)" \
  "$py" - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

state_dir = Path(os.environ["STATE_DIR"])
state_file = Path(os.environ["BOOTSTRAP_STATE_FILE"])
state_dir.mkdir(parents=True, exist_ok=True)
now = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")

payload = {
    "skill_name": "remote",
    "sshpass_installed": os.environ["SSHPASS_INSTALLED"] == "true",
    "sshpass_version": os.environ["SSHPASS_VERSION"],
    "auth_mechanism": "sshpass",
    "ssh_installed": True,
    "os_type": os.environ["CURRENT_HOST_OS"],
    "runtime_type": os.environ["CURRENT_RUNTIME_TYPE"],
    "bash_available": True,
    "bash_flavor": os.environ["CURRENT_BASH_FLAVOR"],
    "bash_path": os.environ["CURRENT_BASH_PATH"],
    "sshpass_provider": os.environ["CURRENT_SSHPASS_PROVIDER"],
    "windows_remote_ready": os.environ["CURRENT_HOST_OS"] == "windows" and os.environ["CURRENT_BASH_FLAVOR"] != "unknown" and os.environ["SSHPASS_INSTALLED"] == "true",
    "last_setup_at": now,
    "last_verified_at": now,
}

state_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

probe_ssh_version() {
  local output
  output="$(ssh -V 2>&1 || true)"
  extract_version_from_text "$output"
}

write_bootstrap_state_msys() {
  # windows-msys 使用 SSH_ASKPASS 机制（无需 sshpass），状态字段对齐 setup.ps1。
  local py ssh_version
  py="$(python_cmd)" || {
    log "缺少 python3/python，无法写入 bootstrap-state.json。"
    exit 1
  }

  ssh_version="$(probe_ssh_version)"
  [ -n "$ssh_version" ] || ssh_version="unknown"

  STATE_DIR="$(state_dir)" \
  BOOTSTRAP_STATE_FILE="$(bootstrap_state_file)" \
  SSH_VERSION="$ssh_version" \
  CURRENT_BASH_PATH="$(current_bash_path)" \
  "$py" - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

state_dir = Path(os.environ["STATE_DIR"])
state_file = Path(os.environ["BOOTSTRAP_STATE_FILE"])
state_dir.mkdir(parents=True, exist_ok=True)
now = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")

payload = {
    "skill_name": "remote",
    "sshpass_installed": False,
    "sshpass_version": "none",
    "sshpass_provider": "none",
    "auth_mechanism": "ssh_askpass",
    "ssh_installed": True,
    "ssh_version": os.environ["SSH_VERSION"],
    "os_type": "windows",
    "runtime_type": "windows-msys",
    "bash_available": True,
    "bash_flavor": "msys",
    "bash_path": os.environ["CURRENT_BASH_PATH"],
    "windows_remote_ready": True,
    "last_setup_at": now,
    "last_verified_at": now,
}

state_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

setup_msys() {
  # windows-msys 使用 SSH_ASKPASS，走独立验证流程，不涉及 sshpass 安装。
  if ! has_cmd ssh; then
    log "windows-msys 下未检测到 ssh。SSH 通常随 Git for Windows 或 MSYS2 提供。"
    exit 13
  fi

  local ssh_out
  ssh_out="$(ssh -V 2>&1 || true)"
  if [ -z "$ssh_out" ]; then
    log "ssh -V 无输出，SSH 不可用。"
    exit 13
  fi

  write_bootstrap_state_msys
  log "SSH 已验证（SSH_ASKPASS 机制），状态文件已写入 $(bootstrap_state_file)。当前执行环境：windows-msys。"
}

install_with_sudo_if_needed() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return 0
  fi

  if has_cmd sudo; then
    sudo "$@"
    return 0
  fi

  log "当前用户不是 root，且未检测到 sudo，无法自动安装 sshpass。"
  exit 1
}

install_linux() {
  if has_cmd apt-get; then
    log "使用 apt-get 安装 sshpass。"
    install_with_sudo_if_needed apt-get update
    install_with_sudo_if_needed apt-get install -y sshpass
    return 0
  fi

  if has_cmd dnf; then
    log "使用 dnf 安装 sshpass。必要时会先尝试 epel-release。"
    install_with_sudo_if_needed dnf install -y epel-release || true
    install_with_sudo_if_needed dnf install -y sshpass
    return 0
  fi

  if has_cmd yum; then
    log "使用 yum 安装 sshpass。必要时会先尝试 epel-release。"
    install_with_sudo_if_needed yum install -y epel-release || true
    install_with_sudo_if_needed yum install -y sshpass
    return 0
  fi

  log "未识别到 apt-get、dnf 或 yum，无法自动安装 sshpass。"
  exit 1
}

install_macos() {
  has_cmd brew || {
    log "未检测到 brew，无法在 macOS 上自动安装 sshpass。"
    exit 1
  }

  log "使用 brew install hudochenkov/sshpass/sshpass。"
  brew install hudochenkov/sshpass/sshpass
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force)
        FORCE=1
        shift
        ;;
      *)
        log "不支持的参数：$1"
        exit 2
        ;;
    esac
  done

  local runtime_type
  runtime_type="$(current_runtime_type)"

  # windows-msys 使用 SSH_ASKPASS，走独立验证流程，不涉及 sshpass 安装。
  if [ "$runtime_type" = "windows-msys" ]; then
    setup_msys
    exit 0
  fi

  if [ "$FORCE" -eq 0 ] && probe_sshpass; then
    log "检测到 sshpass，跳过安装。"
  else
    case "$runtime_type" in
      macos-native)
        install_macos
        ;;
      linux-wsl|linux-native)
        install_linux
        ;;
      *)
        log "未识别到受支持的执行环境：$runtime_type"
        exit 1
        ;;
    esac
  fi

  if ! probe_sshpass; then
    write_bootstrap_state "false" "unknown"
    log "安装完成后仍未检测到可用的 sshpass。"
    exit 1
  fi

  write_bootstrap_state "true" "$PROBED_SSHPASS_VERSION"
  log "sshpass 已完成验证，状态文件已写入 $(bootstrap_state_file)。当前执行环境：$runtime_type。"
}

main "$@"
