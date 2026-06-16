#!/usr/bin/env bash
# setup-mcp.sh - search-web setup 初始化脚本
#
# 用法:
#   bash scripts/setup-mcp.sh --api-key "EXA_API_KEY=xxx"
#   bash scripts/setup-mcp.sh --mcp exa --api-key "EXA_API_KEY=xxx"
#   bash scripts/setup-mcp.sh --mcp context7
#   bash scripts/setup-mcp.sh --agent codex --os windows --api-key "EXA_API_KEY=xxx"
#
# 必需文件: scripts/detect.sh (同目录下)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_NAME="search-web"

# ==============================================================================
# 参数解析
# ==============================================================================

AGENT=""
OS_TYPE=""
MCP_NAME="all"
API_KEY=""
SCOPE="user"
FORCE=0
ALL_MCP_LIST="context7 mcp-deepwiki github-fetcher exa"

usage() {
  cat <<'EOF'
用法: setup-mcp.sh [选项]

search-web setup 初始化脚本

选项:
  --agent <类型>     目标 code agent (claude-code|codex|opencode|qwen-code|hermes|pi)
                    不传则自动调用 detect.sh 检测
  --os <类型>        目标运行时 OS (windows|linux|macos)
                    不传则自动调用 detect.sh 检测
  --mcp <名称>       MCP 名称 (context7|exa|mcp-deepwiki|github-fetcher|all)，默认 all
  --api-key <值>     Exa API Key，格式 "EXA_API_KEY=value"；安装 exa 或未知 agent 时必需
  --scope <范围>     安装作用域 (user|project)，默认 user
  --force            强制重新安装 MCP，忽略检测
  -h, --help         显示帮助

示例:
  bash scripts/setup-mcp.sh --api-key "EXA_API_KEY=xxx"
  bash scripts/setup-mcp.sh --mcp all --api-key "EXA_API_KEY=xxx"
  bash scripts/setup-mcp.sh --mcp exa --api-key "EXA_API_KEY=xxx"
  bash scripts/setup-mcp.sh --mcp context7
  bash scripts/setup-mcp.sh --agent codex --os windows --api-key "EXA_API_KEY=xxx"
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

case "$MCP_NAME" in
  context7|mcp-deepwiki|github-fetcher|exa|all) ;;
  *) echo "错误: 不支持的 MCP 名称: $MCP_NAME（支持: context7|exa|mcp-deepwiki|github-fetcher|all）" >&2; exit 1 ;;
esac

# ==============================================================================
# MCP 注册表
# ==============================================================================

get_npm_package() {
  case "$1" in
    context7)       printf '%s' "@upstash/context7-mcp@latest" ;;
    mcp-deepwiki)   printf '%s' "mcp-deepwiki@latest" ;;
    github-fetcher) printf '%s' "github-fetcher-mcp@latest" ;;
    exa|all)        printf '' ;;
    *)              printf '' ;;
  esac
}

is_remote_mcp() {
  [ "$1" = "exa" ]
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_windows() {
  [ "$OS_TYPE" = "windows" ]
}

# ==============================================================================
# 环境检测（单次调用 detect.sh）
# ==============================================================================

detect_output="$(bash "$SCRIPT_DIR/detect.sh")"

if [ -z "$AGENT" ]; then
  AGENT="$(printf '%s' "$detect_output" | grep '^agent=' | cut -d= -f2)"
fi
if [ -z "$OS_TYPE" ]; then
  OS_TYPE="$(printf '%s' "$detect_output" | grep '^os=' | cut -d= -f2)"
fi
STATE_DIR="$(printf '%s' "$detect_output" | grep '^state_dir=' | cut -d= -f2-)"

if [ -z "$OS_TYPE" ] || [ "$OS_TYPE" = "unknown" ]; then
  echo "错误: 无法检测当前 OS 类型，请通过 --os 参数指定" >&2
  exit 1
fi

echo "Agent: $AGENT"
echo "OS: $OS_TYPE"
echo "状态目录: $STATE_DIR"

# ==============================================================================
# 必需 CLI 与密钥
# ==============================================================================

ensure_npm_available() {
  if ! command_exists npm; then
    echo "错误: 未找到 npm。请先安装 Node.js/npm 后重新运行 setup。" >&2
    exit 1
  fi
}

# 仅 @tiny-fish/cli 需要全局安装（CLI 要进 PATH）；
# context7 / mcp-deepwiki / github-fetcher 是 MCP server，由 npx -y 按需拉取，不全局安装。
ensure_tinyfish_cli() {
  ensure_npm_available
  if command_exists tinyfish; then
    echo "TinyFish CLI 已可用。"
    return 0
  fi
  echo "安装全局 npm 包: @tiny-fish/cli@latest"
  npm install -g @tiny-fish/cli@latest
  if ! command_exists tinyfish; then
    echo "错误: @tiny-fish/cli 已安装但 tinyfish 命令不可用，请检查 npm 全局 bin 是否在 PATH 中。" >&2
    exit 1
  fi
}

prompt_secret() {
  local label="$1"
  if [ ! -t 0 ]; then
    echo "错误: 当前为非交互环境（stdin 非 TTY），无法交互输入。请通过 --api-key 参数传入 Exa API Key。" >&2
    exit 1
  fi
  local value=""
  printf '%s' "$label" >&2
  read -r -s value
  printf '\n' >&2
  printf '%s' "$value"
}

# Exa Key 必需：优先 --api-key 参数，否则交互询问；为空则报错退出。
resolve_exa_key() {
  local key=""
  if [ -n "$API_KEY" ]; then
    case "$API_KEY" in
      EXA_API_KEY=*) ;;
      *) echo "错误: --api-key 必须使用 EXA_API_KEY=value 格式。" >&2; exit 1 ;;
    esac
    key="$(printf '%s' "$API_KEY" | cut -d '=' -f 2-)"
  else
    key="$(prompt_secret "请输入 Exa API Key: ")"
  fi
  if [ -z "$key" ]; then
    echo "错误: Exa MCP 必须提供 Exa API Key。" >&2
    exit 1
  fi
  printf '%s' "$key"
}

get_user_env_tinyfish_key() {
  if is_windows && command_exists powershell; then
    powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('TINYFISH_API_KEY', 'User')" 2>/dev/null | tr -d '\r'
  else
    printf '%s' "${TINYFISH_API_KEY:-}"
  fi
}

set_tinyfish_key_windows() {
  local key="$1"
  TINYFISH_KEY_TO_SAVE="$key" powershell -NoProfile -Command "[Environment]::SetEnvironmentVariable('TINYFISH_API_KEY', \$env:TINYFISH_KEY_TO_SAVE, 'User')"
  export TINYFISH_API_KEY="$key"
}

# 向指定 shell 配置文件写入/更新 TINYFISH_API_KEY（兼容 BSD/GNU sed）。
write_tinyfish_kv() {
  local file="$1" key="$2"
  local escaped
  escaped="$(printf '%s' "$key" | sed 's/[&|\\]/\\&/g')"
  touch "$file"
  if grep -q '^export TINYFISH_API_KEY=' "$file"; then
    sed -i.bak "s|^export TINYFISH_API_KEY=.*|export TINYFISH_API_KEY=\"$escaped\"|" "$file"
  else
    printf '\nexport TINYFISH_API_KEY="%s"\n' "$key" >> "$file"
  fi
}

# 类 Unix 默认写 ~/.bashrc；macOS 默认 zsh，若 $SHELL 含 zsh 或 ~/.zshrc 已存在，同步写入。
set_tinyfish_key_unix() {
  local key="$1"
  write_tinyfish_kv "$HOME/.bashrc" "$key"
  if printf '%s' "${SHELL:-}" | grep -q 'zsh' || [ -f "$HOME/.zshrc" ]; then
    write_tinyfish_kv "$HOME/.zshrc" "$key"
  fi
  export TINYFISH_API_KEY="$key"
}

ensure_tinyfish_api_key() {
  local current_key
  current_key="$(get_user_env_tinyfish_key)"
  if [ -n "$current_key" ]; then
    echo "TINYFISH_API_KEY 已设置。"
    return 0
  fi
  local key
  key="$(prompt_secret "请输入 TinyFish API Key: ")"
  if [ -z "$key" ]; then
    echo "错误: TinyFish CLI 已安装，但缺少 TINYFISH_API_KEY。" >&2
    exit 1
  fi
  if is_windows; then
    set_tinyfish_key_windows "$key"
  else
    set_tinyfish_key_unix "$key"
  fi
  echo "TINYFISH_API_KEY 已永久写入。"
}

# ==============================================================================
# MCP 安装检测（一次 mcp list，grep 变量判断）
# ==============================================================================

check_mcp_list() {
  local agent="$1"
  case "$agent" in
    claude-code) claude mcp list 2>/dev/null || echo "" ;;
    codex)       codex mcp list 2>/dev/null || echo "" ;;
    opencode)    opencode mcp list 2>/dev/null || cat "${HOME}/.config/opencode/opencode.json" 2>/dev/null || echo "" ;;
    qwen-code)   qwen mcp list 2>/dev/null || echo "" ;;
    hermes)      hermes mcp list 2>/dev/null || echo "" ;;
    pi)
      if [ -f ".pi/mcp.json" ]; then
        cat ".pi/mcp.json"
      else
        cat "${HOME}/.pi/agent/mcp.json" 2>/dev/null || echo ""
      fi
      ;;
    *)           echo "" ;;
  esac
}

MCP_LIST_OUTPUT=""

is_mcp_installed() {
  local mcp="$1"
  local agent="${2:-$AGENT}"
  case "$agent" in
    claude-code|qwen-code)
      printf '%s' "$MCP_LIST_OUTPUT" | grep -q "^${mcp}:"
      ;;
    codex)
      printf '%s' "$MCP_LIST_OUTPUT" | awk -v mcp="$mcp" 'NR>1 && $1==mcp { found=1 } END { exit !found }'
      ;;
    opencode)
      printf '%s' "$MCP_LIST_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g' | grep -qw "$mcp"
      ;;
    hermes)
      printf '%s' "$MCP_LIST_OUTPUT" | grep -q "$mcp"
      ;;
    pi)
      # pi 无 mcp list CLI；读 ~/.pi/agent/mcp.json，匹配 server 名作为 JSON key。
      printf '%s' "$MCP_LIST_OUTPUT" | grep -q "\"${mcp}\""
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_pi_mcp_extension() {
  if ! command_exists pi; then
    echo "错误: 未找到 pi 命令。" >&2
    exit 1
  fi
  # 依赖 `pi list` 输出包含 "pi-mcp-extension" 字样；pi 升级后若输出格式变更需同步更新此判定。
  if pi list 2>/dev/null | grep -q "pi-mcp-extension"; then
    echo "pi-mcp-extension 已安装。"
    return 0
  fi
  echo "Pi 原生不带 MCP 入口，需要先安装 extension："
  echo "  pi install npm:pi-mcp-extension"
  echo "请执行上述命令后重新运行本脚本。"
  exit 1
}

# ==============================================================================
# 安装命令
# ==============================================================================

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
    hermes)
      if is_windows; then
        hermes mcp add "$mcp" --command "cmd" --args "/c npx -y $npm_pkg"
      else
        hermes mcp add "$mcp" --command "npx" --args "-y $npm_pkg"
      fi
      ;;
    pi)
      echo "Pi 通过 pi-mcp-extension 读 ~/.pi/agent/mcp.json，请在 mcpServers 对象内添加："
      echo ""
      echo "  \"$mcp\": {"
      echo "    \"command\": \"npx\","
      echo "    \"args\": [\"-y\", \"$npm_pkg\"],"
      echo "    \"transport\": \"stdio\","
      echo "    \"lifecycle\": \"lazy\""
      echo "  }"
      echo ""
      echo "配置文件: ~/.pi/agent/mcp.json（全局）或 .pi/mcp.json（项目）"
      echo "编辑后重启 pi，在会话内用 /mcp 验证。"
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
  local exa_key
  exa_key="$(resolve_exa_key)" || exit 1
  local exa_url="https://mcp.exa.ai/mcp?exaApiKey=${exa_key}"

  case "$agent" in
    claude-code)
      echo "Exa MCP URL 已包含 API Key，输出中已隐藏。"
      claude mcp add --transport http -s "$SCOPE" exa "$exa_url"
      ;;
    codex)
      echo "Exa MCP URL 已包含 API Key，输出中已隐藏。"
      codex mcp add exa --url "$exa_url"
      ;;
    opencode)
      echo "OpenCode 无 CLI 命令，需要手动编辑 opencode.json："
      echo "以下配置包含 Exa API Key，请勿分享输出。"
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
      echo "Exa MCP URL 已包含 API Key，输出中已隐藏。"
      qwen mcp add -s "$SCOPE" -t http exa "$exa_url"
      ;;
    hermes)
      echo "Exa MCP URL 已包含 API Key，输出中已隐藏。"
      hermes mcp add exa --url "$exa_url"
      ;;
    pi)
      echo "Pi 通过 pi-mcp-extension 读 ~/.pi/agent/mcp.json，请在 mcpServers 对象内添加："
      echo "以下配置包含 Exa API Key，请勿分享输出。"
      echo ""
      echo "  \"exa\": {"
      echo "    \"transport\": \"streamable-http\","
      echo "    \"url\": \"$exa_url\","
      echo "    \"lifecycle\": \"eager\""
      echo "  }"
      echo ""
      echo "配置文件: ~/.pi/agent/mcp.json（全局）或 .pi/mcp.json（项目）"
      echo "编辑后重启 pi，在会话内用 /mcp 验证。"
      ;;
    *)
      echo "错误: 不支持的 agent 类型: $agent" >&2
      exit 1
      ;;
  esac
}

print_generic_mcp_json() {
  local exa_key="$1"
  cat <<EOF
当前 code agent 未识别，无法自动写入 MCP 配置。请参考以下通用 MCP JSON（写入对应 agent 的配置文件后重启）：
以下配置包含 Exa API Key，请勿分享输出。

{
  "mcpServers": {
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "exa": {
      "type": "http",
      "url": "https://mcp.exa.ai/mcp?exaApiKey=${exa_key}"
    },
    "mcp-deepwiki": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "mcp-deepwiki@latest"]
    },
    "github-fetcher": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "github-fetcher-mcp@latest"]
    }
  }
}
EOF
}

# ==============================================================================
# 执行
# ==============================================================================

run_install() {
  local mcp="$1"
  echo "========================================"
  echo "  安装 MCP: $mcp"
  echo "  Agent: $AGENT"
  echo "  OS: $OS_TYPE"
  echo "  Scope: $SCOPE"
  echo "========================================"

  install_mcp "$mcp" "$AGENT" "$OS_TYPE"

  echo ""
  echo "MCP $mcp 安装命令已执行。"
}

install_requested_mcp() {
  local mcp
  if [ "$MCP_NAME" = "all" ]; then
    echo "批量安装模式"
    echo ""
    for mcp in $ALL_MCP_LIST; do
      if [ "$FORCE" -eq 0 ] && is_mcp_installed "$mcp"; then
        echo "MCP $mcp 已安装，跳过。"
        echo ""
      else
        run_install "$mcp"
        echo ""
      fi
    done
  else
    if [ "$FORCE" -eq 0 ] && is_mcp_installed "$MCP_NAME"; then
      echo "MCP $MCP_NAME 已安装，跳过。"
    else
      run_install "$MCP_NAME"
    fi
  fi
}

# 1. 确保 npm 与 tinyfish CLI（所有 agent 都需要）
ensure_tinyfish_cli

# 2. 未知 agent：必需 exa key → 输出通用 JSON → 收尾
if [ -z "$AGENT" ] || [ "$AGENT" = "unknown" ]; then
  exa_key="$(resolve_exa_key)" || exit 1
  print_generic_mcp_json "$exa_key"
  ensure_tinyfish_api_key
  echo "请将上述 MCP JSON 写入你的 code agent 配置，并重启。"
  exit 0
fi

# 3. pi：先确保 extension，再检测/输出配置（pi 无 CLI add）
if [ "$AGENT" = "pi" ]; then
  ensure_pi_mcp_extension
fi

# 4. 检测并安装缺失 MCP
MCP_LIST_OUTPUT="$(check_mcp_list "$AGENT")"
install_requested_mcp

# 5. 写永久 TINYFISH_API_KEY
ensure_tinyfish_api_key

echo "setup 完成。请重启 code agent 后验证 MCP 是否可用。"
