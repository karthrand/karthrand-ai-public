#!/usr/bin/env sh
set -eu

SERVER_NAME="markmap-mcp-server"
PACKAGE_NAME="@jinzcdev/markmap-mcp-server"
BOOTSTRAP_VERSION="2026-03-27-v2"

PROJECT_ROOT="$(pwd)"
SKILL_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TARGETS="auto"
CHECK_ONLY="false"
FORCE="false"

log() {
  printf '[mindmap/bootstrap] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

initialization_file() {
  state_home="${XDG_STATE_HOME:-}"
  if [ -z "$state_home" ]; then
    state_home="${HOME}/.local/state"
  fi

  printf '%s/karthrand-ai/skills/mindmap/.initialized' "$state_home"
}

is_initialized() {
  [ "$FORCE" = "false" ] || return 1
  [ -f "$(initialization_file)" ]
}

write_initialization_flag() {
  file="$(initialization_file)"
  mkdir -p "$(dirname "$file")"
  printf 'initialized\n' > "$file"
}

remove_initialization_flag() {
  file="$(initialization_file)"
  [ -f "$file" ] && rm -f "$file" || true
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --skill-root)
      SKILL_ROOT="$2"
      shift 2
      ;;
    --targets)
      TARGETS="$2"
      shift 2
      ;;
    --check-only)
      CHECK_ONLY="true"
      shift
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    *)
      log "未知参数：$1"
      exit 2
      ;;
  esac
done

get_hosts() {
  hosts=""
  case "$TARGETS" in
    claude)
      has_cmd claude || { log "未检测到 claude 命令。"; exit 1; }
      hosts="claude"
      ;;
    codex)
      has_cmd codex || { log "未检测到 codex 命令。"; exit 1; }
      hosts="codex"
      ;;
    all|auto)
      if has_cmd claude; then
        hosts="claude"
      fi
      if has_cmd codex; then
        if [ -n "$hosts" ]; then
          hosts="${hosts}
codex"
        else
          hosts="codex"
        fi
      fi
      [ -n "$hosts" ] || { log "未检测到 claude 或 codex 命令。"; exit 1; }
      ;;
    *)
      log "非法 targets：$TARGETS"
      exit 2
      ;;
  esac

  printf '%s\n' "$hosts"
}

assert_node_toolchain() {
  has_cmd node || { log "缺少 node。请先安装 Node.js。"; exit 1; }
  has_cmd npm || { log "缺少 npm。请先安装 npm。"; exit 1; }
  has_cmd npx || { log "缺少 npx，无法按约定使用 npx -y 安装 MCP。"; exit 1; }
}

host_installed() {
  host_name="$1"
  if [ "$host_name" = "claude" ]; then
    claude mcp get "$SERVER_NAME" >/dev/null 2>&1
    return $?
  fi

  codex mcp list 2>/dev/null | grep -Eq "^${SERVER_NAME}([[:space:]]|$)"
}

remove_host_server() {
  host_name="$1"
  if [ "$host_name" = "claude" ]; then
    claude mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1 || true
  else
    codex mcp remove "$SERVER_NAME" >/dev/null 2>&1 || true
  fi
}

native_add_npx() {
  host_name="$1"
  if [ "$host_name" = "claude" ]; then
    claude mcp add --transport stdio --scope user "$SERVER_NAME" -- npx -y "$PACKAGE_NAME" >/dev/null
  else
    codex mcp add "$SERVER_NAME" -- npx -y "$PACKAGE_NAME" >/dev/null
  fi
}

native_add_global() {
  host_name="$1"
  if [ "$host_name" = "claude" ]; then
    claude mcp add --transport stdio --scope user "$SERVER_NAME" -- "$SERVER_NAME" >/dev/null
  else
    codex mcp add "$SERVER_NAME" -- "$SERVER_NAME" >/dev/null
  fi
}

strip_toml_section() {
  file="$1"
  header="$2"
  tmp_file="$(mktemp)"
  awk -v section="$header" '
    BEGIN { skip = 0 }
    $0 == section { skip = 1; next }
    skip && /^\[/ { skip = 0 }
    !skip { print }
  ' "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

write_codex_config() {
  config_dir="${HOME}/.codex"
  config_file="${config_dir}/config.toml"
  command_name="$1"
  shift

  mkdir -p "$config_dir"
  : > "${config_file}.tmp-init"
  rm -f "${config_file}.tmp-init"
  [ -f "$config_file" ] || : > "$config_file"

  strip_toml_section "$config_file" "[mcp_servers.${SERVER_NAME}.env]"
  strip_toml_section "$config_file" "[mcp_servers.${SERVER_NAME}]"

  {
    printf '\n[mcp_servers.%s]\n' "$SERVER_NAME"
    printf 'command = "%s"\n' "$command_name"
    printf 'args = ['
    first="true"
    for arg in "$@"; do
      if [ "$first" = "true" ]; then
        first="false"
      else
        printf ', '
      fi
      printf '"%s"' "$arg"
    done
    printf ']\n'
  } >> "$config_file"
}

write_claude_config() {
  config_file="${HOME}/.claude.json"
  command_name="$1"
  shift

  node -e '
const fs = require("fs");
const file = process.argv[1];
const command = process.argv[2];
const args = process.argv.slice(3);
let data = {};
if (fs.existsSync(file)) {
  try {
    data = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    data = {};
  }
}
if (!data.mcpServers || typeof data.mcpServers !== "object") {
  data.mcpServers = {};
}
data.mcpServers["markmap-mcp-server"] = {
  type: "stdio",
  command,
  args
};
fs.writeFileSync(file, JSON.stringify(data, null, 2));
' "$config_file" "$command_name" "$@"
}

write_manual_config() {
  host_name="$1"
  if [ "$host_name" = "claude" ]; then
    write_claude_config "npx" "-y" "$PACKAGE_NAME"
  else
    write_codex_config "npx" "-y" "$PACKAGE_NAME"
  fi
}

install_host() {
  host_name="$1"
  if [ "$FORCE" = "true" ]; then
    log "检测到 --force，先移除 ${host_name} 的旧配置。"
    remove_host_server "$host_name"
  fi

  if native_add_npx "$host_name"; then
    return 0
  fi

  if has_cmd "$SERVER_NAME" && native_add_global "$host_name"; then
    return 0
  fi

  log "${host_name} 原生命令注册失败，改为写入当前用户配置文件。"
  write_manual_config "$host_name"
}

assert_ready() {
  for target_name in "$@"; do
    host_installed "$target_name" || { log "${target_name} 的 MCP 安装后仍不可用。"; exit 1; }
  done
}

FLAG_FILE="$(initialization_file)"
log "开始执行 mindmap bootstrap。"
log "ProjectRoot=${PROJECT_ROOT}"
log "SkillRoot=${SKILL_ROOT}"
log "InitializationFlag=${FLAG_FILE}"
log "BootstrapVersion=${BOOTSTRAP_VERSION}"

if [ "$CHECK_ONLY" = "true" ]; then
  if [ -f "$FLAG_FILE" ]; then
    log "已检测到初始化标志文件。"
    exit 0
  fi

  log "未检测到初始化标志文件。"
  exit 1
fi

if is_initialized; then
  log "已初始化，跳过。"
  exit 0
fi

assert_node_toolchain
HOSTS_RAW="$(get_hosts)"

if [ "$FORCE" = "true" ]; then
  remove_initialization_flag
fi

for target_name in $HOSTS_RAW; do
  if [ "$FORCE" = "false" ] && host_installed "$target_name"; then
    log "${target_name} 已安装 ${SERVER_NAME}，跳过注册。"
    continue
  fi

  log "开始为 ${target_name} 安装/修复 ${SERVER_NAME}。"
  install_host "$target_name"
done

assert_ready $HOSTS_RAW
write_initialization_flag
log "bootstrap 完成。"
