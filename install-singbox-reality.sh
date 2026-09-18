#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# sing-box VLESS + Reality installer for personal use.
# Defaults:
#   PORT=random high TCP port
#   SNI=www.cloudflare.com
#   CLIENT_NAME=SG-Reality

STATE_FILE="/etc/sing-box/reality.env"
CONFIG_FILE="/etc/sing-box/config.json"
URL_FILE="/root/sing-box-vless-url.txt"
APT_KEY="/etc/apt/keyrings/sagernet.asc"
APT_SOURCE="/etc/apt/sources.list.d/sagernet.sources"

DEFAULT_SNI="www.cloudflare.com"
DEFAULT_CLIENT_NAME="SG-Reality"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 sudo/root 运行。"
}

random_port() {
  local p
  for _ in $(seq 1 30); do
    p=$((20000 + RANDOM % 40000))
    if ! ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$"; then
      printf '%s' "$p"
      return 0
    fi
  done
  die "无法找到可用随机端口。"
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] || die "PORT 必须是数字。"
  (( 1024 <= $1 && $1 <= 65535 )) || die "PORT 必须在 1024-65535。"
}

validate_sni() {
  [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] || die "SNI 格式不正确。"
  [[ "$1" == *.* ]] || die "SNI 应为域名，例如 www.cloudflare.com。"
}

load_state() {
  [[ -f "$STATE_FILE" ]] || return 1
  # shellcheck disable=SC1090
  source "$STATE_FILE"
  : "${UUID:?缺少 UUID}"
  : "${PRIVATE_KEY:?缺少 PRIVATE_KEY}"
  : "${PUBLIC_KEY:?缺少 PUBLIC_KEY}"
  : "${SHORT_ID:?缺少 SHORT_ID}"
  : "${PORT:?缺少 PORT}"
  : "${SNI:?缺少 SNI}"
  : "${CLIENT_NAME:?缺少 CLIENT_NAME}"
}

save_state() {
  install -d -m 0755 /etc/sing-box
  cat > "$STATE_FILE" <<STATE
UUID='${UUID}'
PRIVATE_KEY='${PRIVATE_KEY}'
PUBLIC_KEY='${PUBLIC_KEY}'
SHORT_ID='${SHORT_ID}'
PORT='${PORT}'
SNI='${SNI}'
CLIENT_NAME='${CLIENT_NAME}'
STATE
  chmod 600 "$STATE_FILE"
}

install_sing_box() {
  if command -v sing-box >/dev/null 2>&1; then
    log "检测到 sing-box: $(sing-box version 2>/dev/null | head -n1 || true)"
    return
  fi

  command -v apt-get >/dev/null 2>&1 || die "当前脚本仅支持 Debian/Ubuntu APT 系统。"

  log "安装必要软件..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl qrencode openssl

  log "添加 sing-box 官方 APT 仓库..."
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://sing-box.app/gpg.key -o "$APT_KEY"
  chmod a+r "$APT_KEY"

  cat > "$APT_SOURCE" <<'SRC'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
SRC

  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y sing-box
  command -v sing-box >/dev/null 2>&1 || die "sing-box 安装失败。"
}

generate_credentials() {
  UUID="$(sing-box generate uuid | tr -d '\r\n')"
  local keypair
  keypair="$(sing-box generate reality-keypair)"
  PRIVATE_KEY="$(printf '%s\n' "$keypair" | sed -nE 's/^PrivateKey:[[:space:]]*//p' | head -n1)"
  PUBLIC_KEY="$(printf '%s\n' "$keypair" | sed -nE 's/^PublicKey:[[:space:]]*//p' | head -n1)"
  [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || die "Reality 密钥生成失败。"
  SHORT_ID="$(openssl rand -hex 4)"
}

write_config() {
  install -d -m 0755 /etc/sing-box
  [[ -f "$CONFIG_FILE" ]] && cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

  cat > "$CONFIG_FILE" <<JSON
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "users": [
        {
          "name": "${CLIENT_NAME}",
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON
  chmod 600 "$CONFIG_FILE"
  sing-box check -c "$CONFIG_FILE"
}

open_ufw_if_active() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "${PORT}/tcp" >/dev/null || true
  fi
}

get_server_addr() {
  if [[ -n "${SERVER_ADDR:-}" ]]; then
    printf '%s' "$SERVER_ADDR"
    return
  fi
  local detected
  detected="$(curl -4fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '\r\n' || true)"
  if [[ "$detected" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf '%s' "$detected"
  else
    printf '%s' "YOUR_STATIC_IP"
  fi
}

build_url() {
  local addr name
  addr="$(get_server_addr)"
  name="$(printf '%s' "$CLIENT_NAME" | sed 's/ /%20/g')"
  VLESS_URL="vless://${UUID}@${addr}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${name}"
  printf '%s\n' "$VLESS_URL" > "$URL_FILE"
  chmod 600 "$URL_FILE"
}

show_client() {
  load_state || die "尚未安装或状态文件不存在。"
  build_url
  printf '\n========== VLESS Reality ==========\n'
  printf '节点名称 : %s\n' "$CLIENT_NAME"
  printf '端口     : %s/TCP\n' "$PORT"
  printf 'SNI      : %s\n' "$SNI"
  printf 'UUID     : %s\n' "$UUID"
  printf 'PublicKey: %s\n' "$PUBLIC_KEY"
  printf 'Short ID : %s\n' "$SHORT_ID"
  printf '\n导入链接：\n%s\n' "$VLESS_URL"
  if command -v qrencode >/dev/null 2>&1; then
    printf '\n二维码：\n'
    qrencode -t ANSIUTF8 "$VLESS_URL" || true
  fi
}

start_service() {
  systemctl enable sing-box >/dev/null
  systemctl restart sing-box
  sleep 1
  systemctl is-active --quiet sing-box || {
    journalctl -u sing-box -n 50 --no-pager >&2 || true
    die "sing-box 启动失败。"
  }
}

status() {
  systemctl status sing-box --no-pager || true
  if load_state 2>/dev/null; then
    ss -lntp 2>/dev/null | grep -E ":${PORT}([[:space:]]|$)" || true
  fi
}

set_sni() {
  local new_sni="${1:-}"
  [[ -n "$new_sni" ]] || die "用法：--set-sni DOMAIN"
  load_state || die "尚未安装。"
  validate_sni "$new_sni"
  SNI="$new_sni"
  save_state
  write_config
  start_service
  show_client
}

rotate() {
  install_sing_box
  load_state || die "尚未安装。"
  generate_credentials
  save_state
  write_config
  open_ufw_if_active
  start_service
  show_client
}

rebuild() {
  install_sing_box
  local old_port=""
  if load_state 2>/dev/null; then
    old_port="$PORT"
  fi
  PORT="${PORT:-$(random_port)}"
  SNI="${SNI:-$DEFAULT_SNI}"
  CLIENT_NAME="${CLIENT_NAME:-$DEFAULT_CLIENT_NAME}"
  validate_port "$PORT"
  validate_sni "$SNI"
  generate_credentials
  save_state
  write_config
  open_ufw_if_active
  start_service
  show_client
  if [[ -n "$old_port" && "$old_port" != "$PORT" ]]; then
    warn "旧端口 ${old_port}/TCP 已不再使用。请从 AWS Lightsail 防火墙删除旧端口，并开放新端口 ${PORT}/TCP。"
  else
    warn "请在 AWS Lightsail 防火墙开放 TCP ${PORT}。"
  fi
}

uninstall_node() {
  systemctl disable --now sing-box >/dev/null 2>&1 || true
  rm -f "$CONFIG_FILE" "$STATE_FILE" "$URL_FILE"
  warn "已删除 Reality 节点配置和凭据。"
}

main_install() {
  install_sing_box
  if load_state 2>/dev/null; then
    log "检测到已有配置，复用现有端口和凭据。"
  else
    PORT="${PORT:-$(random_port)}"
    SNI="${SNI:-$DEFAULT_SNI}"
    CLIENT_NAME="${CLIENT_NAME:-$DEFAULT_CLIENT_NAME}"
    validate_port "$PORT"
    validate_sni "$SNI"
    generate_credentials
    save_state
  fi
  write_config
  open_ufw_if_active
  start_service
  show_client
  warn "请在 AWS Lightsail -> Networking -> IPv4 Firewall 放行 TCP ${PORT}。"
}

require_root
case "${1:-}" in
  --show) show_client ;;
  --status) status ;;
  --rotate) rotate ;;
  --rebuild) rebuild ;;
  --set-sni) set_sni "${2:-}" ;;
  --uninstall) uninstall_node ;;
  "") main_install ;;
  *) die "未知参数：$1" ;;
esac
