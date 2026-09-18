#!/usr/bin/env bash
set -Eeuo pipefail

# singbox-deploy interactive management menu
# Marker: singbox-deploy-menu

REPO_RAW="https://raw.githubusercontent.com/ldhtop/singbox-deploy/main"
LOCAL_DIR="/usr/local/lib/singbox-deploy"
INSTALLER="${LOCAL_DIR}/install-singbox-reality.sh"
MENU_LOCAL="${LOCAL_DIR}/singbox-menu.sh"
STATE_FILE="/etc/sing-box/reality.env"

c_green='\033[1;32m'
c_yellow='\033[1;33m'
c_red='\033[1;31m'
c_blue='\033[1;34m'
c_reset='\033[0m'

say()  { printf "%b%s%b\n" "$c_green" "$*" "$c_reset"; }
warn() { printf "%b%s%b\n" "$c_yellow" "$*" "$c_reset"; }
err()  { printf "%b%s%b\n" "$c_red" "$*" "$c_reset" >&2; }

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    exec sudo "$0" "$@"
  fi
}

pause() {
  printf '\n按 Enter 返回菜单...'
  read -r _ || true
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

refresh_local_scripts() {
  install -d -m 0755 "$LOCAL_DIR"
  local tmp1 tmp2
  tmp1="$(mktemp)"
  tmp2="$(mktemp)"
  trap 'rm -f "$tmp1" "$tmp2"' RETURN

  curl -fsSL "${REPO_RAW}/install-singbox-reality.sh" -o "$tmp1"
  curl -fsSL "${REPO_RAW}/singbox-menu.sh" -o "$tmp2"

  bash -n "$tmp1"
  bash -n "$tmp2"

  install -m 0700 "$tmp1" "$INSTALLER"
  install -m 0755 "$tmp2" "$MENU_LOCAL"

  say "管理脚本已更新到最新 main 版本。"
}

ensure_installer() {
  if [[ ! -x "$INSTALLER" ]]; then
    warn "本地管理脚本不存在，正在从你的 GitHub 仓库下载..."
    refresh_local_scripts
  fi
}

show_header() {
  clear || true
  printf "%b" "$c_blue"
  cat <<'EOF'
========================================
       sing-box Reality 管理菜单
========================================
EOF
  printf "%b" "$c_reset"

  local svc="未安装"
  if command -v sing-box >/dev/null 2>&1; then
    if systemctl is-active --quiet sing-box 2>/dev/null; then
      svc="运行中"
    else
      svc="已安装 / 未运行"
    fi
  fi
  load_state
  printf '服务状态 : %s\n' "$svc"
  printf '节点端口 : %s\n' "${PORT:-未配置}"
  printf 'Reality SNI: %s\n' "${SNI:-未配置}"
  printf '\n'
}

show_link() {
  ensure_installer
  "$INSTALLER" --show
}

show_status() {
  ensure_installer
  "$INSTALLER" --status
}

live_logs() {
  printf '实时日志已开启，按 Ctrl+C 返回。\n\n'
  set +e
  journalctl -u sing-box -f
  set -e
}

restart_service() {
  systemctl restart sing-box
  sleep 1
  if systemctl is-active --quiet sing-box; then
    say "sing-box 重启成功。"
  else
    err "sing-box 重启失败。"
    journalctl -u sing-box -n 50 --no-pager || true
  fi
}

change_sni() {
  ensure_installer
  load_state
  printf '当前 SNI: %s\n' "${SNI:-未配置}"
  printf '请输入新 SNI（例如 www.cloudflare.com）: '
  read -r new_sni
  [[ -n "$new_sni" ]] || { warn "未输入，已取消。"; return; }
  "$INSTALLER" --set-sni "$new_sni"
}

rotate_credentials() {
  ensure_installer
  warn "此操作会使旧节点链接立即失效。"
  printf '确认轮换 UUID / Reality 密钥？输入 YES: '
  read -r answer
  if [[ "$answer" == "YES" ]]; then
    "$INSTALLER" --rotate
  else
    warn "已取消。"
  fi
}

diagnose() {
  load_state
  printf '\n========== 节点诊断 ==========\n'

  printf '\n[1] sing-box 版本\n'
  sing-box version 2>/dev/null | head -n 3 || echo 'sing-box 未安装'

  printf '\n[2] systemd 状态\n'
  systemctl is-active sing-box 2>/dev/null || true

  printf '\n[3] 监听端口\n'
  if [[ -n "${PORT:-}" ]]; then
    ss -lntp 2>/dev/null | grep -E ":${PORT}([[:space:]]|$)" || echo "未发现 ${PORT}/TCP 监听"
  else
    echo '没有读取到 PORT'
  fi

  printf '\n[4] UFW\n'
  if command -v ufw >/dev/null 2>&1; then
    ufw status || true
  else
    echo 'ufw 未安装'
  fi

  printf '\n[5] 系统时间同步\n'
  timedatectl status 2>/dev/null | grep -E 'System clock synchronized|NTP service|Time zone' || true

  printf '\n[6] Reality handshake 目标连通性\n'
  if [[ -n "${SNI:-}" ]]; then
    if curl -fsSI --connect-timeout 5 --max-time 10 "https://${SNI}" >/dev/null; then
      echo "HTTPS ${SNI}:443 可访问"
    else
      echo "HTTPS ${SNI}:443 访问失败"
    fi
  else
    echo '没有读取到 SNI'
  fi

  printf '\n[7] 配置校验\n'
  sing-box check -c /etc/sing-box/config.json 2>&1 || true

  printf '\n[8] 最近 Reality/TLS 错误\n'
  journalctl -u sing-box -n 100 --no-pager 2>/dev/null | grep -Ei 'ERROR|REALITY|TLS handshake|invalid connection' | tail -n 20 || echo '未发现相关错误'

  printf '\n================================\n'
}

repair_install() {
  ensure_installer
  "$INSTALLER"
}

update_menu() {
  refresh_local_scripts
  say "更新完成。重新进入 menu 即可使用新版本。"
}

uninstall_node() {
  ensure_installer
  warn "将停止节点并删除 Reality 配置/凭据。"
  printf '确认卸载节点？输入 YES: '
  read -r answer
  if [[ "$answer" == "YES" ]]; then
    "$INSTALLER" --uninstall
  else
    warn "已取消。"
  fi
}

menu_loop() {
  while true; do
    show_header
    cat <<'EOF'
1) 查看节点链接 / 二维码
2) 查看服务状态
3) 查看实时日志
4) 重启 sing-box
5) 修改 Reality SNI
6) 轮换 UUID / Reality 密钥
7) 一键诊断节点
8) 修复 / 重装当前节点配置
9) 更新管理脚本
10) 卸载 Reality 节点
0) 退出
EOF
    printf '\n请选择 [0-10]: '
    read -r choice
    printf '\n'

    case "$choice" in
      1) show_link; pause ;;
      2) show_status; pause ;;
      3) live_logs ;;
      4) restart_service; pause ;;
      5) change_sni; pause ;;
      6) rotate_credentials; pause ;;
      7) diagnose; pause ;;
      8) repair_install; pause ;;
      9) update_menu; pause ;;
      10) uninstall_node; pause ;;
      0) exit 0 ;;
      *) warn "无效选项。"; sleep 1 ;;
    esac
  done
}

need_root "$@"
menu_loop
