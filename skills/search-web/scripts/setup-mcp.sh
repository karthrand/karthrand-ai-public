#!/usr/bin/env bash
# setup-mcp.sh - search-web 技能 MCP 自动安装脚本
#
# 用法:
#   bash scripts/setup-mcp.sh --mcp context7
#   bash scripts/setup-mcp.sh --mcp exa --api-key "EXA_API_KEY=xxx"
#   bash scripts/setup-mcp.sh --mcp github-fetcher --force
#   bash scripts/setup-mcp.sh --agent claude-code --os windows --mcp context7
#
# 必需文件: scripts/detect.sh (同目录下)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="search-web"

# ==============================================================================
# 参数解析
# ==============================================================================

AGENT=""
OS_TYPE=""
MCP_NAME=""
API_KEY=""
SCOPE="user"
FORCE=0

usage() {
  cat <<'EOF'
用法: setup-mcp.sh [选项]

search-web 技能 MCP 自动安装脚本

选项:
  --agent <类型>     目标 code agent (claude-code|codex|opencode|qwen-code)
                    不传则自动调用 detect.sh agent 检测
  --os <类型>        目标运行时 OS (windows|linux|macos)
                    不传则自动调用 detect.sh os 检测
  --mcp <名称>      MCP 名称 (context7|exa|mcp-deepwiki|github-fetcher)
                    必需参数
  --api-key <值>     API Key，格式 "ENV_VAR_NAME=value"
                    仅 context7/exa 可选
  --scope <范围>     安装作用域 (user|project)，默认 user
  --force            强制重新安装，忽略状态标记
  -h                 显示帮助

示例:
  bash scripts/setup-mcp.sh --mcp context7
  bash scripts/setup-mcp.sh --mcp exa --api-key "EXA_API_KEY=xxx"
  bash scripts/setup-mcp.sh --mcp github-fetcher --force
  bash scripts/setup-mcp.sh --agent claude-code --os windows --mcp context7
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)   AGENT="$2"; shift 2 ;;
    --os)      OS_TYPE="$2"; shift 2 ;;
    --mcp)     MCP_NAME="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --scope)   SCOPE="$2"; shift 2 ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$MCP_NAME" ]; then
  echo "错误: --mcp 参数是必需的" >&2
  usage
  exit 1
fi

# ==============================================================================
# MCP 注册表
# ==============================================================================

get_npm_package() {
  case "$1" in
    context7)       printf '%s' "@upstash/context7-mcp@latest" ;;
    mcp-deepwiki)   printf '%s' "mcp-deepwiki@latest" ;;
    github-fetcher) printf '%s' "github-fetcher-mcp" ;;
    *)              printf '' ;;
  esac
}

is_remote_mcp() {
  [ "$1" = "exa" ]
}

case "$MCP_NAME" in
  context7|mcp-deepwiki|github-fetcher|exa) ;;
  *) echo "错误: 不支持的 MCP 名称: $MCP_NAME（支持: context7|exa|mcp-deepwiki|github-fetcher）" >&2; exit 1 ;;
esac

# ==============================================================================
# 自动检测
# ==============================================================================

if [ -z "$AGENT" ]; then
  AGENT="$(bash "$SCRIPT_DIR/detect.sh" agent)"
  if [ -z "$AGENT" ] || [ "$AGENT" = "unknown" ]; then
    echo "错误: 无法检测当前 code agent 类型，请通过 --agent 参数指定" >&2
    exit 1
  fi
  echo "自动检测 agent: $AGENT"
fi

if [ -z "$OS_TYPE" ]; then
  OS_TYPE="$(bash "$SCRIPT_DIR/detect.sh" os)"
  if [ -z "$OS_TYPE" ] || [ "$OS_TYPE" = "unknown" ]; then
    echo "错误: 无法检测当前 OS 类型，请通过 --os 参数指定" >&2
    exit 1
  fi
  echo "自动检测 OS: $OS_TYPE"
fi

STATE_DIR="$(bash "$SCRIPT_DIR/detect.sh" state-dir "$SKILL_NAME")"
echo "状态目录: $STATE_DIR"

# ==============================================================================
# 从状态文件读取已存储的 API Key
# ==============================================================================

read_stored_key() {
  local mcp="$1"
  local state_file="${STATE_DIR}setup-state.json"
  if [ -f "$state_file" ] && command -v python3 &>/dev/null; then
    local key
    key="$(python3 -c "
import json, sys
try:
    data = json.load(open('$state_file'))
    cred = data.get('credentials', {}).get('$mcp', {})
    if cred.get('hasApiKey') and cred.get('apiKey'):
        print(cred['apiKey'])
except: pass
" 2>/dev/null || true)"
    if [ -n "$key" ]; then
      printf '%s' "$key"
      return 0
    fi
  fi
  return 1
}

# ==============================================================================
# 状态检查
# ==============================================================================

STATE_FILE="${STATE_DIR}setup-state.json"

if [ "$FORCE" -eq 0 ] && [ -f "$STATE_FILE" ]; then
  if grep -q "\"$MCP_NAME\"" "$STATE_FILE" 2>/dev/null; then
    if grep -q '"installed"[[:space:]]*:[[:space:]]*true' "$STATE_FILE" 2>/dev/null; then
      echo "MCP $MCP_NAME 已标记为已安装。使用 --force 强制重新安装。"
      exit 0
    fi
  fi
fi

# ==============================================================================
# 安装命令
# ==============================================================================

is_windows() {
  [ "$OS_TYPE" = "windows" ]
}

install_mcp() {
  local mcp="$1"
  local agent="$2"
  local os="$3"

  if is_remote_mcp "$mcp"; then
    install_remote_mcp "$mcp" "$agent" "$os"
  else
    install_stdio_mcp "$mcp" "$agent" "$os"
  fi
}

install_stdio_mcp() {
  local mcp="$1"
  local agent="$2"
  local os="$3"
  local npm_pkg
  npm_pkg="$(get_npm_package "$mcp")"

  if [ -z "$npm_pkg" ]; then
    echo "错误: 未知 MCP 名称: $mcp" >&2
    exit 1
  fi

  case "$agent" in
    claude-code)
      if is_windows; then
        claude mcp add-json -s "$SCOPE" "$mcp" "{\"type\":\"stdio\",\"command\":\"cmd\",\"args\":[\"/c\",\"npx\",\"-y\",\"$npm_pkg\"]}"
      else
        claude mcp add-json -s "$SCOPE" "$mcp" "{\"type\":\"stdio\",\"command\":\"npx\",\"args\":[\"-y\",\"$npm_pkg\"]}"
      fi
      ;;
    codex)
      if is_windows; then
        codex mcp add "$mcp" -- cmd /c npx -y "$npm_pkg"
      else
        codex mcp add "$mcp" -- npx -y "$npm_pkg"
      fi
      ;;
    opencode)
      echo "OpenCode 无 CLI 命令，需要手动编辑 opencode.json："
      echo ""
      if is_windows; then
        echo "  \"$mcp\": {"
        echo "    \"type\": \"local\","
        echo "    \"command\": [\"cmd\", \"/c\", \"npx\", \"-y\", \"$npm_pkg\"],"
        echo "    \"enabled\": true"
        echo "  }"
      else
        echo "  \"$mcp\": {"
        echo "    \"type\": \"local\","
        echo "    \"command\": [\"npx\", \"-y\", \"$npm_pkg\"],"
        echo "    \"enabled\": true"
        echo "  }"
      fi
      echo ""
      echo "配置文件位置: ~/.config/opencode/opencode.json"
      echo "请在编辑完成后重新运行本脚本进行状态标记更新。"
      ;;
    qwen-code)
      if is_windows; then
        qwen mcp add -s "$SCOPE" -t stdio "$mcp" cmd /c npx -y "$npm_pkg"
      else
        qwen mcp add -s "$SCOPE" -t stdio "$mcp" npx -y "$npm_pkg"
      fi
      ;;
    *)
      echo "错误: 不支持的 agent 类型: $agent" >&2
      exit 1
      ;;
  esac
}

install_remote_mcp() {
  local mcp="$1"
  local agent="$2"
  local os="$3"

  local exa_url="https://mcp.exa.ai/mcp"

  # 优先使用 --api-key 参数，其次从状态文件读取
  if [ -n "$API_KEY" ]; then
    local key_value
    key_value="$(printf '%s' "$API_KEY" | cut -d '=' -f 2-)"
    if [ -n "$key_value" ]; then
      exa_url="https://mcp.exa.ai/mcp?exaApiKey=${key_value}"
    fi
  else
    local stored_key
    if stored_key="$(read_stored_key exa)" && [ -n "$stored_key" ]; then
      exa_url="https://mcp.exa.ai/mcp?exaApiKey=${stored_key}"
      echo "从状态文件读取已存储的 Exa API Key"
    fi
  fi

  case "$agent" in
    claude-code)
      claude mcp add --transport http -s "$SCOPE" exa "$exa_url"
      ;;
    codex)
      codex mcp add exa --url "$exa_url"
      ;;
    opencode)
      echo "OpenCode 无 CLI 命令，需要手动编辑 opencode.json："
      echo ""
      echo "  \"exa\": {"
      echo "    \"type\": \"remote\","
      echo "    \"url\": \"$exa_url\","
      echo "    \"enabled\": true"
      echo "  }"
      echo ""
      echo "配置文件位置: ~/.config/opencode/opencode.json"
      ;;
    qwen-code)
      qwen mcp add -s "$SCOPE" -t http exa "$exa_url"
      ;;
    *)
      echo "错误: 不支持的 agent 类型: $agent" >&2
      exit 1
      ;;
  esac
}

# ==============================================================================
# 执行
# ==============================================================================

echo "========================================"
echo "  安装 MCP: $MCP_NAME"
echo "  Agent: $AGENT"
echo "  OS: $OS_TYPE"
echo "  Scope: $SCOPE"
echo "========================================"

install_mcp "$MCP_NAME" "$AGENT" "$OS_TYPE"

echo ""
echo "MCP $MCP_NAME 安装命令已执行。"
echo "请重启 code agent 后验证 MCP 是否可用。"
echo ""
echo "如需更新状态文件，请在 code agent 中重新进入 search-web 主流程。"
