#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# jjkuajing / personal proxy node installer
# Installs sing-box from the official SagerNet APT repository and configures
# VLESS + TCP + Reality on a high TCP port for Shadowrocket / v2rayN.
#
# Safe defaults:
#   PORT=28443
#   SNI=www.cloudflare.com
#   CLIENT_NAME=SG-Reality
#
# First install examples:
#   sudo bash install-singbox-reality.sh
#   sudo PORT=28443 SNI=www.cloudflare.com CLIENT_NAME=Andy-SG bash install-singbox-reality.sh
#
# Management:
#   sudo bash install-singbox-reality.sh --show
#   sudo bash install-singbox-reality.sh --status
#   sudo bash install-singbox-reality.sh --rotate
#   sudo bash install-singbox-reality.sh --set-sni www.cloudflare.com
#   sudo bash install-singbox-reality.sh --uninstall

STATE_FILE="/etc/sing-box/reality.env"
CONFIG_FILE="/etc/sing-box/config.json"
URL_FILE="/root/sing-box-vless-url.txt"
APT_KEY="/etc/apt/keyrings/sagernet.asc"
APT_SOURCE="/etc/apt/sources.list.d/sagernet.sources"

DEFAULT_PORT="28443"
DEFAULT_SNI="www.cloudflare.com"
DEFAULT_CLIENT_NAME="SG-Reality"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 sudo/root 运行。"
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] || die "PORT 必须是数字。"
  (( 1024 <= $1 && $1 <= 65535 )) || die "PORT 建议使用 1024-65535 的高位端口。"
}

validate_sni() {
  [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] || die "SNI 格式不正确。"
  [[ "$1" == *.* ]] || die "SNI 应为可访问的域名，例如 www.cloudflare.com。"
}

load_state() {
  [[ -f "$STATE_FILE" ]] || return 1
  # shellcheck disable=SC1090
  source "$STATE_FILE"
  : "${UUID:?STATE_FILE 缺少 UUID}"
  : "${PRIVATE_KEY:?STATE_FILE 缺少 PRIVATE_KEY}"
  : "${PUBLIC_KEY:?STATE_FILE 缺少 PUBLIC_KEY}"
  : "${SHORT_ID:?STATE_FILE 缺少 SHORT_ID}"
  : "${PORT:?STATE_FILE 缺少 PORT}"
  : "${SNI:?STATE_FILE 缺少 SNI}"
  : "${CLIENT_NAME:?STATE_FILE 缺少 CLIENT_NAME}"
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
  log "已安装 $(sing-box version 2>/dev/null | head -n1 || echo sing-box)"
}

generate_credentials() {
  UUID="$(sing-box generate uuid | tr -d '\r\n')"

  local keypair
  keypair="$(sing-box generate reality-keypair)"
  PRIVATE_KEY="$(printf '%s\n' "$keypair" | sed -nE 's/^PrivateKey:[[:space:]]*//p' | head -n1)"
  PUBLIC_KEY="$(printf '%s\n' "$keypair" | sed -nE 's/^PublicKey:[[:space:]]*//p' | head -n1)"

  [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || die "Reality 密钥生成失败。输出：$keypair"

  # sing-box Reality short_id: 0-8 hexadecimal digits. Generate exactly 8.
  SHORT_ID="$(openssl rand -hex 4)"
}

write_config() {
  install -d -m 0755 /etc/sing-box

  if [[ -f "$CONFIG_FILE" ]]; then
    cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  fi

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
          "short_id": [
            "${SHORT_ID}"
          ],
          "max_time_difference": "1m"
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

  log "校验 sing-box 配置..."
  sing-box check -c "$CONFIG_FILE"
}

open_ufw_if_active() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    if ! ufw status | grep -Eq "^${PORT}/tcp[[:space:]]+ALLOW"; then
      log "UFW 已启用，放行 ${PORT}/tcp..."
      ufw allow "${PORT}/tcp" >/dev/null
    fi
  fi
}

get_server_addr() {
  if [[ -n "${SERVER_ADDR:-}" ]]; then
    printf '%s' "$SERVER_ADDR"
    return
  fi

  local detected=""
  detected="$(curl -4fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '\r\n' || true)"
  if [[ "$detected" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf '%s' "$detected"
  else
    printf '%s' "YOUR_STATIC_IP"
  fi
}

urlencode_name() {
  # Good enough for common ASCII node names; replace spaces with %20.
  printf '%s' "$1" | sed 's/ /%20/g'
}

build_url() {
  local addr name
  addr="$(get_server_addr)"
  name="$(urlencode_name "$CLIENT_NAME")"
  VLESS_URL="vless://${UUID}@${addr}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${name}"
  printf '%s\n' "$VLESS_URL" > "$URL_FILE"
  chmod 600 "$URL_FILE"
}

show_client() {
  load_state || die "尚未安装或状态文件不存在：$STATE_FILE"
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
    printf '\n二维码（Shadowrocket 可扫描）：\n'
    qrencode -t ANSIUTF8 "$VLESS_URL" || true
  fi

  printf '\n链接已保存：%s（权限 600）\n' "$URL_FILE"
  printf '====================================\n\n'
}

start_service() {
  systemctl enable sing-box >/dev/null
  systemctl restart sing-box
  sleep 1
  systemctl is-active --quiet sing-box || {
    journalctl -u sing-box -n 50 --no-pager >&2 || true
    die "sing-box 启动失败。"
  }
  log "sing-box 已启动。"
}

status() {
  printf '\n--- sing-box status ---\n'
  systemctl status sing-box --no-pager || true
  if load_state 2>/dev/null; then
    printf '\n--- listen port ---\n'
    ss -lntp 2>/dev/null | grep -E ":${PORT}([[:space:]]|$)" || true
  fi
}

set_sni() {
  local new_sni="${1:-}"
  [[ -n "$new_sni" ]] || die "用法：--set-sni DOMAIN，例如 --set-sni www.cloudflare.com"
  load_state || die "尚未安装或状态文件不存在：$STATE_FILE"
  validate_sni "$new_sni"
  SNI="$new_sni"
  save_state
  write_config
  start_service
  show_client
  warn "SNI/Reality handshake 目标已更新；请重新导入上面生成的新链接。"
}

rotate() {
  install_sing_box
  if load_state; then
    PORT="${PORT}"
    SNI="${SNI}"
    CLIENT_NAME="${CLIENT_NAME}"
  else
    PORT="${PORT:-$DEFAULT_PORT}"
    SNI="${SNI:-$DEFAULT_SNI}"
    CLIENT_NAME="${CLIENT_NAME:-$DEFAULT_CLIENT_NAME}"
  fi
  validate_port "$PORT"
  validate_sni "$SNI"
  generate_credentials
  save_state
  write_config
  open_ufw_if_active
  start_service
  show_client
  warn "凭据已轮换；旧客户端链接将立即失效。"
}

uninstall_node() {
  if systemctl list-unit-files 2>/dev/null | grep -q '^sing-box.service'; then
    systemctl disable --now sing-box >/dev/null 2>&1 || true
  fi
  rm -f "$CONFIG_FILE" "$STATE_FILE" "$URL_FILE"
  warn "已删除 Reality 节点配置和凭据。sing-box 软件包本身未删除。"
  warn "如需删除软件：sudo apt-get remove sing-box"
  warn "Lightsail 控制台中的 ${DEFAULT_PORT}/TCP 或自定义端口防火墙规则需要你手动删除。"
}

main_install() {
  install_sing_box

  if load_state 2>/dev/null; then
    log "检测到已有配置，复用现有凭据（不会自动换 UUID/密钥）。"
  else
    PORT="${PORT:-$DEFAULT_PORT}"
    SNI="${SNI:-$DEFAULT_SNI}"
    CLIENT_NAME="${CLIENT_NAME:-$DEFAULT_CLIENT_NAME}"
    validate_port "$PORT"
    validate_sni "$SNI"
    generate_credentials
    save_state
  fi

  validate_port "$PORT"
  validate_sni "$SNI"
  write_config
  open_ufw_if_active
  start_service
  show_client

  warn "还需要在 AWS Lightsail -> Networking -> IPv4 Firewall 手动放行 TCP ${PORT}。"
  warn "请确保实例已绑定 Static IP，否则重启/更换网络后节点地址可能变化。"
  warn "脚本不会修改 80/443、Docker、PostgreSQL、Redis 或系统全局代理。"
}

require_root

case "${1:-}" in
  --show)
    show_client
    ;;
  --status)
    status
    ;;
  --rotate)
    rotate
    ;;
  --set-sni)
    set_sni "${2:-}"
    ;;
  --uninstall)
    uninstall_node
    ;;
  -h|--help)
    sed -n '1,28p' "$0"
    ;;
  "")
    main_install
    ;;
  *)
    die "未知参数：$1。使用 --help 查看帮助。"
    ;;
esac
