#!/usr/bin/env sh
set -eu

SERVER_NAME="markmap-mcp-server"
PACKAGE_NAME="@jinzcdev/markmap-mcp-server"
BOOTSTRAP_VERSION="2026-03-28-v1"

PROJECT_ROOT="$(pwd)"
SKILL_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TARGETS=""
CHECK_ONLY="false"
FORCE="false"

log() {
  printf '[mindmap/bootstrap] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

state_dir() {
  if [ -n "${APPDATA:-}" ]; then
    printf '%s/karthrand-ai/skills/mindmap' "$APPDATA"
    return 0
  fi

  state_home="${XDG_STATE_HOME:-}"
  if [ -z "$state_home" ]; then
    state_home="${HOME}/.local/state"
  fi

  printf '%s/karthrand-ai/skills/mindmap' "$state_home"
}

service_flag() {
  printf '%s/service.initialized' "$(state_dir)"
}

host_flag() {
  printf '%s/host.%s.initialized' "$(state_dir)" "$1"
}

is_service_initialized() {
  [ "$FORCE" = "false" ] || return 1
  [ -f "$(service_flag)" ]
}

is_host_initialized() {
  [ "$FORCE" = "false" ] || return 1
  [ -f "$(host_flag "$1")" ]
}

write_flag() {
  file="$1"
  mkdir -p "$(dirname "$file")"
  printf 'initialized\n' > "$file"
}

remove_flag() {
  file="$1"
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
  [ -n "$TARGETS" ] || { log "必须显式指定 --targets，可选值：claude、codex、opencode、all。"; exit 2; }
  case "$TARGETS" in
    claude|codex|opencode)
      has_cmd "$TARGETS" || { log "未检测到 $TARGETS 命令。"; exit 1; }
      hosts="$TARGETS"
      ;;
    all)
      for name in claude codex opencode; do
        if has_cmd "$name"; then
          if [ -n "$hosts" ]; then
            hosts="${hosts}
$name"
          else
            hosts="$name"
          fi
        fi
      done
      [ -n "$hosts" ] || { log "未检测到 claude、codex 或 opencode 命令。"; exit 1; }
      ;;
    *)
      log "非法 targets：$TARGETS"
      exit 2
      ;;
  esac

  printf '%s\n' "$hosts"
}

all_flags_present() {
  hosts_raw="$1"
  is_service_initialized || return 1
  shared_service_ready || return 1
  for target_name in $hosts_raw; do
    is_host_initialized "$target_name" || return 1
    host_installed "$target_name" || return 1
  done
  return 0
}

assert_node_toolchain() {
  has_cmd node || { log "缺少 node。请先安装 Node.js。"; exit 1; }
  has_cmd npm || { log "缺少 npm。请先安装 npm。"; exit 1; }
  has_cmd npx || { log "缺少 npx。请先安装 npx。"; exit 1; }
}

ensure_shared_service() {
  assert_node_toolchain

  if [ "$(uname -s)" = "Linux" ] || [ "$(uname -s)" = "Darwin" ]; then
    log "类 Unix 环境使用 npx 启动共享服务，无需额外全局安装。"
    return 0
  fi

  if has_cmd "$SERVER_NAME"; then
    log "检测到全局 $SERVER_NAME 命令，跳过共享安装。"
    return 0
  fi

  log "开始安装共享服务 $PACKAGE_NAME。"
  if has_cmd "npm.cmd"; then
    npm.cmd install -g "$PACKAGE_NAME" >/dev/null
  elif has_cmd cmd; then
    cmd /c npm install -g "$PACKAGE_NAME" >/dev/null
  else
    npm install -g "$PACKAGE_NAME" >/dev/null
  fi

  has_cmd "$SERVER_NAME" || { log "共享服务安装后仍未找到 $SERVER_NAME 命令。"; exit 1; }
}

shared_service_ready() {
  assert_node_toolchain
  command_json="$(server_command_json)"
  node -e '
const spec = JSON.parse(process.argv[1]);
const result = require("child_process").spawnSync(spec[0], spec.slice(1).concat("--help"), { stdio: "ignore" });
process.exit(result.status === 0 ? 0 : 1);
' "$command_json" >/dev/null 2>&1
}

server_command_json() {
  if [ "$(uname -s)" = "Linux" ] || [ "$(uname -s)" = "Darwin" ]; then
    if has_cmd "$SERVER_NAME"; then
      printf '%s' "[\"$SERVER_NAME\"]"
    else
      printf '%s' "[\"npx\",\"-y\",\"$PACKAGE_NAME\"]"
    fi
    return 0
  fi

  if has_cmd "$SERVER_NAME"; then
    printf '%s' "[\"cmd\",\"/c\",\"$SERVER_NAME\"]"
  else
    printf '%s' "[\"cmd\",\"/c\",\"npx\",\"-y\",\"$PACKAGE_NAME\"]"
  fi
}

host_installed() {
  host_name="$1"
  case "$host_name" in
    claude)
      claude mcp get "$SERVER_NAME" >/dev/null 2>&1
      ;;
    codex)
      codex mcp list 2>/dev/null | grep -Eq "^${SERVER_NAME}([[:space:]]|$)"
      ;;
    opencode)
      opencode mcp list 2>/dev/null | grep -Fq "$SERVER_NAME"
      ;;
    *)
      return 1
      ;;
  esac
}

remove_host_server() {
  host_name="$1"
  case "$host_name" in
    claude)
      claude mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1 || true
      ;;
    codex)
      codex mcp remove "$SERVER_NAME" >/dev/null 2>&1 || true
      ;;
    opencode)
      remove_opencode_config_value
      ;;
  esac
}

claude_native_add() {
  command_json="$(server_command_json)"
  node -e '
const args = JSON.parse(process.argv[1]);
const result = require("child_process").spawnSync("claude", ["mcp", "add", "--transport", "stdio", "--scope", "user", "markmap-mcp-server", "--", ...args], { stdio: "ignore" });
process.exit(result.status ?? 1);
' "$command_json"
}

codex_native_add() {
  command_json="$(server_command_json)"
  node -e '
const args = JSON.parse(process.argv[1]);
const result = require("child_process").spawnSync("codex", ["mcp", "add", "markmap-mcp-server", "--", ...args], { stdio: "ignore" });
process.exit(result.status ?? 1);
' "$command_json"
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
  command_name="$1"
  shift
  config_dir="${HOME}/.codex"
  config_file="${config_dir}/config.toml"
  mkdir -p "$config_dir"
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
  command_name="$1"
  shift
  config_file="${HOME}/.claude.json"
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

opencode_config_file() {
  printf '%s/.config/opencode/opencode.json' "$HOME"
}

write_opencode_config() {
  config_file="$(opencode_config_file)"
  mkdir -p "$(dirname "$config_file")"
  command_json="$(server_command_json)"
  node -e '
const fs = require("fs");
const file = process.argv[1];
const serverName = process.argv[2];
const command = JSON.parse(process.argv[3]);
let config = {};
if (fs.existsSync(file)) {
  try {
    config = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    config = {};
  }
}
if (!config.$schema) {
  config.$schema = "https://opencode.ai/config.json";
}
if (!config.mcp || typeof config.mcp !== "object" || Array.isArray(config.mcp)) {
  config.mcp = {};
}
config.mcp[serverName] = {
  type: "local",
  command,
  enabled: true
};
fs.writeFileSync(file, JSON.stringify(config, null, 2));
' "$config_file" "$SERVER_NAME" "$command_json"
}

remove_opencode_config_value() {
  config_file="$(opencode_config_file)"
  [ -f "$config_file" ] || return 0
  node -e '
const fs = require("fs");
const file = process.argv[1];
const serverName = process.argv[2];
let config = {};
try {
  config = JSON.parse(fs.readFileSync(file, "utf8"));
} catch {
  process.exit(0);
}
if (config.mcp && typeof config.mcp === "object" && !Array.isArray(config.mcp)) {
  delete config.mcp[serverName];
}
fs.writeFileSync(file, JSON.stringify(config, null, 2));
' "$config_file" "$SERVER_NAME"
}

install_host() {
  host_name="$1"

  if [ "$FORCE" = "true" ]; then
    log "检测到 --force，先移除 ${host_name} 的旧配置。"
    remove_host_server "$host_name"
    remove_flag "$(host_flag "$host_name")"
  fi

  case "$host_name" in
    claude)
      claude_native_add || {
        log "claude 原生命令注册失败，改为写入当前用户配置文件。"
        command_json="$(server_command_json)"
        command_name="$(node -e 'const command = JSON.parse(process.argv[1]); process.stdout.write(command[0]);' "$command_json")"
        args_json="$(node -e 'const command = JSON.parse(process.argv[1]); process.stdout.write(JSON.stringify(command.slice(1)));' "$command_json")"
        node -e '
const fs = require("fs");
const file = process.argv[1];
const command = process.argv[2];
const args = JSON.parse(process.argv[3]);
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
' "${HOME}/.claude.json" "$command_name" "$args_json"
      }
      ;;
    codex)
      codex_native_add || {
        log "codex 原生命令注册失败，改为写入当前用户配置文件。"
        command_json="$(server_command_json)"
        command_name="$(node -e 'const command = JSON.parse(process.argv[1]); process.stdout.write(command[0]);' "$command_json")"
        args_json="$(node -e 'const command = JSON.parse(process.argv[1]); process.stdout.write(JSON.stringify(command.slice(1)));' "$command_json")"
        config_dir="${HOME}/.codex"
        config_file="${config_dir}/config.toml"
        mkdir -p "$config_dir"
        [ -f "$config_file" ] || : > "$config_file"
        strip_toml_section "$config_file" "[mcp_servers.${SERVER_NAME}.env]"
        strip_toml_section "$config_file" "[mcp_servers.${SERVER_NAME}]"
        {
          printf '\n[mcp_servers.%s]\n' "$SERVER_NAME"
          printf 'command = "%s"\n' "$command_name"
          printf 'args = ['
          node -e '
const args = JSON.parse(process.argv[1]);
process.stdout.write(args.map(arg => JSON.stringify(arg)).join(", "));
' "$args_json"
          printf ']\n'
        } >> "$config_file"
      }
      ;;
    opencode)
      log "开始写入 opencode 的 MCP 配置。"
      write_opencode_config
      ;;
  esac
}

assert_hosts_ready() {
  hosts_raw="$1"
  for target_name in $hosts_raw; do
    host_installed "$target_name" || { log "${target_name} 的 MCP 安装后仍不可用。"; exit 1; }
  done
}

HOSTS_RAW="$(get_hosts)"
STATE_DIR="$(state_dir)"
SERVICE_FLAG="$(service_flag)"

log "开始执行 mindmap bootstrap。"
log "ProjectRoot=${PROJECT_ROOT}"
log "SkillRoot=${SKILL_ROOT}"
log "StateDirectory=${STATE_DIR}"
log "ServiceFlag=${SERVICE_FLAG}"
log "BootstrapVersion=${BOOTSTRAP_VERSION}"

if [ "$CHECK_ONLY" = "true" ]; then
  if all_flags_present "$HOSTS_RAW"; then
    log "已检测到共享服务标志与目标宿主标志。"
    exit 0
  fi

  log "共享服务标志或目标宿主标志缺失。"
  exit 1
fi

if all_flags_present "$HOSTS_RAW"; then
  log "共享服务与目标宿主均已初始化，跳过。"
  exit 0
fi

if [ "$FORCE" = "true" ]; then
  remove_flag "$SERVICE_FLAG"
fi

service_initialized="false"
if is_service_initialized; then
  service_initialized="true"
fi

if [ "$service_initialized" = "true" ] && ! shared_service_ready; then
  log "检测到共享服务标志，但共享服务实际不可用，移除标志后重新准备。"
  remove_flag "$SERVICE_FLAG"
  service_initialized="false"
fi

if [ "$service_initialized" = "false" ]; then
  log "开始准备共享服务。"
  ensure_shared_service
  shared_service_ready || {
    remove_flag "$SERVICE_FLAG"
    log "共享服务准备后仍不可用。"
    exit 1
  }
  write_flag "$SERVICE_FLAG"
else
  log "已检测到共享服务标志，跳过共享服务准备。"
fi

for target_name in $HOSTS_RAW; do
  host_initialized="false"
  if is_host_initialized "$target_name"; then
    host_initialized="true"
  fi

  if [ "$host_initialized" = "true" ] && ! host_installed "$target_name"; then
    log "检测到 ${target_name} 宿主标志，但注册实际不可用，移除标志后重新注册。"
    remove_flag "$(host_flag "$target_name")"
    host_initialized="false"
  fi

  if [ "$host_initialized" = "true" ]; then
    log "已检测到 ${target_name} 宿主标志，跳过注册。"
    continue
  fi

  if [ "$FORCE" = "false" ] && host_installed "$target_name"; then
    log "${target_name} 已存在 ${SERVER_NAME} 注册，补写宿主标志。"
    write_flag "$(host_flag "$target_name")"
    continue
  fi

  log "开始为 ${target_name} 安装/修复 ${SERVER_NAME}。"
  install_host "$target_name"
  host_installed "$target_name" || {
    remove_flag "$(host_flag "$target_name")"
    log "${target_name} 的 MCP 注册后仍不可用。"
    exit 1
  }
  write_flag "$(host_flag "$target_name")"
done

assert_hosts_ready "$HOSTS_RAW"
log "bootstrap 完成。"
