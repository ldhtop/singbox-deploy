#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/ldhtop/singbox-deploy/main"
LOCAL_DIR="/usr/local/lib/singbox-deploy"
MENU_LOCAL="${LOCAL_DIR}/singbox-menu.sh"
INSTALLER_LOCAL="${LOCAL_DIR}/install-singbox-reality.sh"

[[ ${EUID:-$(id -u)} -eq 0 ]] || exec sudo bash "$0" "$@"

command -v curl >/dev/null 2>&1 || {
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl
}

install -d -m 0755 "$LOCAL_DIR"

tmp_menu="$(mktemp)"
tmp_installer="$(mktemp)"
trap 'rm -f "$tmp_menu" "$tmp_installer"' EXIT

curl -fsSL "${REPO_RAW}/singbox-menu.sh" -o "$tmp_menu"
curl -fsSL "${REPO_RAW}/install-singbox-reality.sh" -o "$tmp_installer"

bash -n "$tmp_menu"
bash -n "$tmp_installer"

install -m 0755 "$tmp_menu" "$MENU_LOCAL"
install -m 0700 "$tmp_installer" "$INSTALLER_LOCAL"

cat > /usr/local/bin/sbmenu <<'EOF'
#!/usr/bin/env bash
exec sudo /usr/local/lib/singbox-deploy/singbox-menu.sh "$@"
EOF
chmod 0755 /usr/local/bin/sbmenu

if [[ ! -e /usr/local/bin/menu ]] || grep -q 'singbox-deploy' /usr/local/bin/menu 2>/dev/null; then
  cat > /usr/local/bin/menu <<'EOF'
#!/usr/bin/env bash
# singbox-deploy menu launcher
exec sudo /usr/local/lib/singbox-deploy/singbox-menu.sh "$@"
EOF
  chmod 0755 /usr/local/bin/menu
  MENU_CMD="menu"
else
  MENU_CMD="sbmenu"
  printf '[!] /usr/local/bin/menu 已存在且不是本项目文件，为避免覆盖，未修改它。\n'
fi

printf '\n[+] 管理菜单安装/更新完成。\n'
printf '[+] 可执行命令：sbmenu\n'
printf '[+] 快捷命令：%s\n' "$MENU_CMD"
printf '[+] 现在请在当前 SSH 提示符输入：%s\n\n' "$MENU_CMD"

# Important: do not auto-enter the menu here. This installer is commonly run via
# `curl ... | sudo bash`; stdin is then the curl pipe rather than the terminal.
# Auto-entering would make menu reads hit EOF and immediately return to shell.
exit 0
