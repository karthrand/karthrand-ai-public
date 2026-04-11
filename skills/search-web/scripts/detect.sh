#!/usr/bin/env bash
# detect.sh - 统一运行时环境检测脚本
# 子命令: agent / os / state-dir
#
# 用法:
#   bash scripts/detect.sh agent                    → claude-code / codex / opencode / qwen-code / unknown
#   bash scripts/detect.sh os                       → windows / linux / macos / unknown
#   bash scripts/detect.sh state-dir <skill_name>   → 状态目录路径（Windows 用 \，其他用 /）
#   bash scripts/detect.sh -v <子命令>              → 详细模式（stderr）

set -euo pipefail

VERBOSE=0

# ==============================================================================
# 通用工具
# ==============================================================================

verbose_log() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo "$1" >&2
  fi
}

usage() {
  cat <<'EOF'
用法: detect.sh [选项] <子命令> [参数]

统一检测脚本：Agent 类型 / OS 类型 / 状态目录路径

选项:
  -v    详细模式，显示检测过程（全局，作用于所有子命令）
  -h    显示帮助

子命令:
  agent              检测当前 AI Code Agent 类型
                     输出: claude-code / codex / opencode / qwen-code / unknown

  os                 检测当前宿主机操作系统类型
                     输出: windows / linux / macos / unknown（WSL 视为 linux）

  state-dir <名称>   输出指定 skill 的状态目录路径
                     路径统一为 ~/.config/{名称}/
                     Windows (Git Bash) 下输出使用 \ 分隔符
                     路径末尾带分隔符

示例:
  bash scripts/detect.sh agent
  bash scripts/detect.sh -v os
  bash scripts/detect.sh state-dir my-skill
EOF
}

# ==============================================================================
# OS 检测
# ==============================================================================

# WSL 检测（三重判定）
is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  [ -n "${WSL_INTEROP:-}" ] && return 0
  [ -r /proc/version ] && grep -qi 'microsoft' /proc/version && return 0
  return 1
}

# 细分运行时类型
detect_runtime_type() {
  local uname_out
  uname_out="$(uname -s 2>/dev/null || printf 'unknown')"
  case "$uname_out" in
    Windows*)
      printf 'windows-native'
      ;;
    MINGW*|MSYS*|CYGWIN*)
      printf 'windows-msys'
      ;;
    Linux)
      if is_wsl; then
        printf 'linux-wsl'
      else
        printf 'linux-native'
      fi
      ;;
    Darwin)
      printf 'macos-native'
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

# 聚合 OS 类型（WSL → linux）
detect_os_type() {
  local runtime_type="${1:-$(detect_runtime_type)}"
  case "$runtime_type" in
    windows-msys|windows-native) printf 'windows' ;;
    linux-wsl|linux-native) printf 'linux' ;;
    macos-native) printf 'macos' ;;
    *) printf 'unknown' ;;
  esac
}

# ==============================================================================
# Agent 检测
# ==============================================================================

append_signal() {
  local current_signals="$1"
  local next_signal="$2"

  if [ -n "$current_signals" ]; then
    printf '%s\n%s' "$current_signals" "$next_signal"
  else
    printf '%s' "$next_signal"
  fi
}

print_signal_block() {
  local title="$1"
  local signals="$2"
  local empty_message="$3"

  echo "## $title" >&2
  if [ -z "$signals" ]; then
    echo "  $empty_message" >&2
    return 0
  fi

  printf '%s\n' "$signals" | while IFS= read -r signal; do
    echo "  信号: $signal" >&2
  done
}

detect_by_env() {
  local signals=""
  local agent=""
  local confidence=0
  local found_claude=0
  local found_codex=0
  local found_opencode=0
  local found_qwen=0
  local opencode_confidence=0
  local codex_confidence=0
  local qwen_confidence=0

  if [ -n "${CLAUDECODE:-}" ]; then
    signals=$(append_signal "$signals" "CLAUDECODE=$CLAUDECODE")
    agent="claude-code"
    confidence=90
    found_claude=1
  fi

  if [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
    signals=$(append_signal "$signals" "CLAUDE_CODE_ENTRYPOINT=$CLAUDE_CODE_ENTRYPOINT")
    found_claude=1
    if [ "$agent" != "claude-code" ]; then
      agent="claude-code"
      confidence=85
    else
      confidence=95
    fi
  fi

  if [ -n "${CODEX_THREAD_ID:-}" ]; then
    signals=$(append_signal "$signals" "CODEX_THREAD_ID=$CODEX_THREAD_ID")
    found_codex=1
    if [ "$codex_confidence" -eq 0 ]; then
      codex_confidence=90
    fi
  fi

  if [ -n "${OPENCODE:-}" ]; then
    signals=$(append_signal "$signals" "OPENCODE=$OPENCODE")
    found_opencode=1
    if [ "$opencode_confidence" -eq 0 ]; then
      opencode_confidence=90
    fi
  fi

  if [ -n "${OPENCODE_PID:-}" ]; then
    signals=$(append_signal "$signals" "OPENCODE_PID=$OPENCODE_PID")
    found_opencode=1
    if [ "$opencode_confidence" -eq 0 ]; then
      opencode_confidence=85
    else
      opencode_confidence=95
    fi
  fi

  if [ -n "${QWEN_CODE:-}" ]; then
    signals=$(append_signal "$signals" "QWEN_CODE=$QWEN_CODE")
    found_qwen=1
    if [ "$qwen_confidence" -eq 0 ]; then
      qwen_confidence=90
    fi
  fi

  if [ "$found_claude" -eq 0 ]; then
    if [ "$found_codex" -eq 1 ] && [ "$found_opencode" -eq 0 ] && [ "$found_qwen" -eq 0 ]; then
      agent="codex"
      confidence=$codex_confidence
    elif [ "$found_opencode" -eq 1 ] && [ "$found_codex" -eq 0 ] && [ "$found_qwen" -eq 0 ]; then
      agent="opencode"
      confidence=$opencode_confidence
    elif [ "$found_qwen" -eq 1 ] && [ "$found_codex" -eq 0 ] && [ "$found_opencode" -eq 0 ]; then
      agent="qwen-code"
      confidence=$qwen_confidence
    fi
  fi

  if [ "$VERBOSE" -eq 1 ]; then
    print_signal_block "环境变量检测结果" "$signals" "未检测到任何 Agent 特征环境变量"
  fi

  printf '%s|%s\n' "$agent" "$confidence"
}

detect_agent() {
  local env_result env_agent env_confidence
  env_result=$(detect_by_env)
  env_agent=$(printf '%s' "$env_result" | cut -d '|' -f 1)
  env_confidence=$(printf '%s' "$env_result" | cut -d '|' -f 2)

  if [ -n "$env_agent" ]; then
    printf '%s|%s|环境变量\n' "$env_agent" "$env_confidence"
  else
    printf 'unknown|0|无匹配信号\n'
  fi
}

# ==============================================================================
# 状态目录
# ==============================================================================

get_state_dir() {
  local skill_name="$1"
  local runtime_type
  runtime_type="$(detect_runtime_type)"
  local base_path="$HOME/.config/${skill_name}"

  if [ "$runtime_type" = "windows-msys" ] || [ "$runtime_type" = "windows-native" ]; then
    if command -v cygpath &>/dev/null; then
      base_path="$(cygpath -w "$base_path")\\"
    else
      # cygpath 不可用时，将 POSIX 路径中的 / 替换为 \
      base_path="$(printf '%s' "$base_path" | sed 's/\//\\/g')\\"
    fi
  else
    base_path="${base_path}/"
  fi

  printf '%s\n' "$base_path"
}

# ==============================================================================
# 子命令入口
# ==============================================================================

cmd_agent() {
  local result agent confidence method
  result=$(detect_agent)
  agent=$(printf '%s' "$result" | cut -d '|' -f 1)
  confidence=$(printf '%s' "$result" | cut -d '|' -f 2)
  method=$(printf '%s' "$result" | cut -d '|' -f 3-)

  if [ "$VERBOSE" -eq 1 ]; then
    echo "" >&2
    echo "========================================" >&2
    echo "  Agent 类型: $agent" >&2
    echo "  置信度: ${confidence}%" >&2
    echo "  判定依据: $method" >&2
    echo "========================================" >&2
  fi

  echo "$agent"
}

cmd_os() {
  local runtime_type os_type uname_out
  runtime_type=$(detect_runtime_type)
  os_type=$(detect_os_type "$runtime_type")
  uname_out="$(uname -s 2>/dev/null || printf 'unknown')"

  if [ "$VERBOSE" -eq 1 ]; then
    echo "" >&2
    echo "========================================" >&2
    echo "  OS 类型: $os_type" >&2
    echo "  运行时: $runtime_type" >&2
    echo "  uname -s: $uname_out" >&2

    case "$runtime_type" in
      windows-msys)
        echo "  OSTYPE: ${OSTYPE:-<未设置>}" >&2
        ;;
      windows-native)
        echo "  OSTYPE: ${OSTYPE:-<未设置>}" >&2
        ;;
      linux-wsl)
        echo "  WSL_DISTRO_NAME: ${WSL_DISTRO_NAME:-<未设置>}" >&2
        echo "  WSL_INTEROP: ${WSL_INTEROP:-<未设置>}" >&2
        if [ -r /proc/version ]; then
          echo "  /proc/version: $(grep -oi 'microsoft' /proc/version | head -1)" >&2
        fi
        ;;
    esac

    echo "========================================" >&2
  fi

  echo "$os_type"
}

cmd_state_dir() {
  local skill_name="${1:-}"
  if [ -z "$skill_name" ]; then
    echo "错误: state-dir 子命令必须提供 skill 名称参数" >&2
    echo "" >&2
    usage
    exit 1
  fi

  local runtime_type
  runtime_type="$(detect_runtime_type)"
  local state_path
  state_path="$(get_state_dir "$skill_name")"

  if [ "$VERBOSE" -eq 1 ]; then
    echo "" >&2
    echo "========================================" >&2
    echo "  Skill 名称: $skill_name" >&2
    echo "  运行时: $runtime_type" >&2
    if [ "$runtime_type" = "windows-msys" ] || [ "$runtime_type" = "windows-native" ]; then
      echo "  路径转换: cygpath -w（Windows 原生路径）" >&2
    else
      echo "  路径格式: POSIX" >&2
    fi
    echo "  状态目录: $state_path" >&2
    echo "========================================" >&2
  fi

  echo "$state_path"
}

# ==============================================================================
# 参数解析与分发
# ==============================================================================

while getopts "vh" opt; do
  case "$opt" in
    v) VERBOSE=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

SUBCOMMAND="${1:-}"
shift || true

case "$SUBCOMMAND" in
  agent)     cmd_agent ;;
  os)        cmd_os ;;
  state-dir) cmd_state_dir "$@" ;;
  *)         usage; exit 1 ;;
esac
