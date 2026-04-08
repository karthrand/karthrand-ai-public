#!/usr/bin/env sh
# detect-agent.sh - 检测当前 AI Code Agent 类型
# 通过环境变量检测，判断当前运行在哪个 Agent 中

set -eu

VERBOSE=0

append_signal() {
  current_signals=$1
  next_signal=$2

  if [ -n "$current_signals" ]; then
    printf '%s\n%s' "$current_signals" "$next_signal"
  else
    printf '%s' "$next_signal"
  fi
}

print_signal_block() {
  title=$1
  signals=$2
  empty_message=$3

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
  signals=""
  agent=""
  confidence=0
  found_claude=0
  found_codex=0
  found_opencode=0
  opencode_confidence=0
  codex_confidence=0

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

  if [ "$found_claude" -eq 0 ]; then
    if [ "$found_codex" -eq 1 ] && [ "$found_opencode" -eq 0 ]; then
      agent="codex"
      confidence=$codex_confidence
    elif [ "$found_opencode" -eq 1 ] && [ "$found_codex" -eq 0 ]; then
      agent="opencode"
      confidence=$opencode_confidence
    fi
  fi

  if [ "$VERBOSE" -eq 1 ]; then
    print_signal_block "环境变量检测结果" "$signals" "未检测到任何 Agent 特征环境变量"
  fi

  printf '%s|%s\n' "$agent" "$confidence"
}

detect_agent() {
  env_result=$(detect_by_env)
  env_agent=$(printf '%s' "$env_result" | cut -d '|' -f 1)
  env_confidence=$(printf '%s' "$env_result" | cut -d '|' -f 2)

  if [ -n "$env_agent" ]; then
    printf '%s|%s|环境变量\n' "$env_agent" "$env_confidence"
  else
    printf 'unknown|0|无匹配信号\n'
  fi
}

output_result() {
  agent=$1
  confidence=$2
  method=$3

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

usage() {
  cat <<'EOF'
用法: detect-agent.sh [选项]

检测当前运行在哪个 AI Code Agent 中。

选项:
  -v    详细模式，显示检测过程和置信度
  -h    显示帮助

支持检测的 Agent:
  claude-code   Anthropic Claude Code
  codex         OpenAI Codex
  opencode      OpenCode
EOF
}

while getopts "vh" opt; do
  case "$opt" in
    v) VERBOSE=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

main() {
  result=$(detect_agent)
  agent=$(printf '%s' "$result" | cut -d '|' -f 1)
  confidence=$(printf '%s' "$result" | cut -d '|' -f 2)
  method=$(printf '%s' "$result" | cut -d '|' -f 3-)

  output_result "$agent" "$confidence" "$method"
}

main "$@"
