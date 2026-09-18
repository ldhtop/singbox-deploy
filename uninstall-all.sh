#!/usr/bin/env bash
set -Eeuo pipefail

# Complete removal for this singbox-deploy project.
# Removes sing-box service/package/config, SagerNet APT source/key,
# local menu/install scripts, and launchers created by this repo.
# It does NOT touch nginx, Docker, PostgreSQL, Redis, application files,
# or AWS Lightsail firewall rules.

[[ ${EUID:-$(id -u)} -eq 0 ]] || exec sudo bash "$0" "$@"

STATE_FILE="/etc/sing-box/reality.env"
OLD_PORT=""
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" || true
  OLD_PORT="${PORT:-}"
fi

printf '[1/7] 停止并禁用 sing-box...\n'
systemctl disable --now sing-box >/dev/null 2>&1 || true

printf '[2/7] 卸载 sing-box 软件包...\n'
if command -v apt-get >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get purge -y sing-box >/dev/null 2>&1 || true
fi

printf '[3/7] 删除 sing-box 配置和本项目状态...\n'
rm -rf /etc/sing-box
rm -f /root/sing-box-vless-url.txt

printf '[4/7] 删除 SagerNet APT 源和签名密钥...\n'
rm -f /etc/apt/sources.list.d/sagernet.sources
rm -f /etc/apt/keyrings/sagernet.asc

printf '[5/7] 删除本项目本地管理文件...\n'
rm -rf /usr/local/lib/singbox-deploy

printf '[6/7] 删除本项目创建的 menu/sbmenu 启动器...\n'
if [[ -f /usr/local/bin/menu ]] && grep -q 'singbox-deploy' /usr/local/bin/menu 2>/dev/null; then
  rm -f /usr/local/bin/menu
fi
if [[ -f /usr/local/bin/sbmenu ]]; then
  if grep -q 'singbox-deploy\|/usr/local/lib/singbox-deploy' /usr/local/bin/sbmenu 2>/dev/null; then
    rm -f /usr/local/bin/sbmenu
  fi
fi

printf '[7/7] 刷新 systemd...\n'
systemctl daemon-reload || true
systemctl reset-failed || true

printf '\n✅ 已完整删除本项目安装的 sing-box 节点和管理脚本。\n'
if [[ -n "$OLD_PORT" ]]; then
  printf '⚠️  AWS Lightsail 控制台还需要你手动删除 TCP %s 的防火墙规则。\n' "$OLD_PORT"
else
  printf '⚠️  AWS Lightsail 控制台中的节点端口防火墙规则需要你手动删除。\n'
fi
printf '✅ 未修改 nginx / Docker / PostgreSQL / Redis / jjkuajing 文件。\n'
