#!/usr/bin/env sh
set -eu

SERVER_NAME="markmap-mcp-server"
PACKAGE_NAME="@jinzcdev/markmap-mcp-server"
BOOTSTRAP_VERSION="2026-03-27-v1"

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

state_file() {
  printf '%s/.agents/state/mindmap.json' "$PROJECT_ROOT"
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

state_matches() {
  [ "$FORCE" = "false" ] || return 1
  file="$(state_file)"
  [ -f "$file" ] || return 1
  has_cmd node || return 1

  node -e '
const fs = require("fs");
const file = process.argv[1];
const root = process.argv[2];
const hosts = process.argv.slice(3);
try {
  const state = JSON.parse(fs.readFileSync(file, "utf8"));
  if (state.project_root !== root) process.exit(1);
  const installed = new Set(state.installed_hosts || []);
  for (const host of hosts) {
    if (!installed.has(host)) process.exit(1);
  }
  process.exit(0);
} catch {
  process.exit(1);
}
' "$file" "$PROJECT_ROOT" "$@"
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
    remove_host_server "$host_name"
  fi

  if native_add_npx "$host_name"; then
    printf '%s\n' "native-inline-npx"
    return 0
  fi

  if has_cmd "$SERVER_NAME" && native_add_global "$host_name"; then
    printf '%s\n' "native-global-bin"
    return 0
  fi

  log "${host_name} 原生命令注册失败，改为写入当前用户配置文件。"
  write_manual_config "$host_name"
  printf '%s\n' "manual-config"
}

save_state() {
  file="$(state_file)"
  mkdir -p "$(dirname "$file")"

  node -e '
const fs = require("fs");
const file = process.argv[1];
const root = process.argv[2];
const version = process.argv[3];
const hosts = process.argv[4].split(",").filter(Boolean);
const modes = process.argv[5].split(",").filter(Boolean);
const payload = {
  skill_name: "mindmap",
  skill_version: version,
  project_root: root,
  initialized_at: new Date().toISOString(),
  detected_hosts: hosts,
  installed_hosts: hosts,
  install_mode: [...new Set(modes)],
  platform: "unix",
  bootstrap_hash: version
};
fs.writeFileSync(file, JSON.stringify(payload, null, 2));
' "$file" "$PROJECT_ROOT" "$BOOTSTRAP_VERSION" "$HOSTS_CSV" "$MODES_CSV"
}

HOSTS_RAW="$(get_hosts)"
assert_node_toolchain

HOSTS_ARGS=""
for target_name in $HOSTS_RAW; do
  HOSTS_ARGS="${HOSTS_ARGS} ${target_name}"
done

# shellcheck disable=SC2086
if state_matches $HOSTS_ARGS; then
  for target_name in $HOSTS_RAW; do
    host_installed "$target_name" || { log "检测到状态文件，但 ${target_name} 的 MCP 不可用。"; exit 1; }
  done
  log "已初始化，跳过。"
  exit 0
fi

if [ "$CHECK_ONLY" = "true" ]; then
  missing=""
  for target_name in $HOSTS_RAW; do
    if ! host_installed "$target_name"; then
      if [ -n "$missing" ]; then
        missing="${missing}, ${target_name}"
      else
        missing="${target_name}"
      fi
    fi
  done

  if [ -n "$missing" ]; then
    log "以下宿主尚未安装：$missing"
    exit 1
  fi

  log "所有目标宿主已完成 MCP 安装。"
  exit 0
fi

MODES_LIST=""
HOSTS_CSV=""
for target_name in $HOSTS_RAW; do
  if [ -z "$HOSTS_CSV" ]; then
    HOSTS_CSV="$target_name"
  else
    HOSTS_CSV="${HOSTS_CSV},${target_name}"
  fi

  if [ "$FORCE" = "false" ] && host_installed "$target_name"; then
    log "${target_name} 已安装 ${SERVER_NAME}，跳过注册。"
    mode="existing"
  else
    log "开始为 ${target_name} 安装/修复 ${SERVER_NAME}。"
    mode="$(install_host "$target_name")"
  fi

  if [ -z "$MODES_LIST" ]; then
    MODES_LIST="$mode"
  else
    MODES_LIST="${MODES_LIST},${mode}"
  fi
done

for target_name in $HOSTS_RAW; do
  host_installed "$target_name" || { log "${target_name} 的 MCP 安装后仍不可用。"; exit 1; }
done

MODES_CSV="$MODES_LIST"
save_state
log "bootstrap 完成。"
