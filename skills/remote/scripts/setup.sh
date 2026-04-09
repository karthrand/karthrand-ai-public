#!/usr/bin/env bash
set -euo pipefail

STATE_SKILL_NAME="remote"

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
  local base_path
  if [ -n "${LOCALAPPDATA:-}" ]; then
    base_path="${LOCALAPPDATA}\\${STATE_SKILL_NAME}"
    if has_cmd cygpath; then
      cygpath -u "$base_path"
      return 0
    fi
    printf '%s\n' "$base_path"
    return 0
  fi

  base_path="${XDG_DATA_HOME:-}"
  if [ -z "$base_path" ]; then
    base_path="${HOME}/.local/share"
  fi

  printf '%s/%s\n' "$base_path" "$STATE_SKILL_NAME"
}

bootstrap_state_file() {
  printf '%s/bootstrap-state.json\n' "$(state_dir)"
}

write_bootstrap_state() {
  local version="$1"
  local py
  py="$(python_cmd)" || {
    log "缺少 python3/python，无法写入 bootstrap-state.json。"
    exit 1
  }

  STATE_DIR="$(state_dir)" \
  BOOTSTRAP_STATE_FILE="$(bootstrap_state_file)" \
  SSKILL="$STATE_SKILL_NAME" \
  SVER="$version" \
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
    "skill_name": os.environ["SSKILL"],
    "sshpass_installed": True,
    "sshpass_version": os.environ["SVER"],
    "os_type": os.uname().sysname.lower() if hasattr(os, "uname") else "unknown",
    "last_setup_at": now,
    "last_verified_at": now,
}

state_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

sshpass_version() {
  sshpass -V 2>&1 | head -n 1 | sed -E 's/.*([0-9]+\.[0-9]+).*/\1/'
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
  local uname_out
  uname_out="$(uname -s)"

  if has_cmd sshpass; then
    log "检测到 sshpass，跳过安装。"
  else
    case "$uname_out" in
      Darwin)
        install_macos
        ;;
      Linux)
        install_linux
        ;;
      MINGW*|MSYS*|CYGWIN*)
        log "Windows 下请改用 powershell 执行 scripts/setup.ps1。"
        exit 1
        ;;
      *)
        log "不支持的系统：$uname_out"
        exit 1
        ;;
    esac
  fi

  has_cmd sshpass || {
    log "安装完成后仍未检测到 sshpass。"
    exit 1
  }

  sshpass -V >/dev/null 2>&1 || {
    log "sshpass 验证失败。"
    exit 1
  }

  local version
  version="$(sshpass_version)"
  write_bootstrap_state "$version"
  log "sshpass 已完成验证，状态文件已写入 $(bootstrap_state_file)"
}

main "$@"
