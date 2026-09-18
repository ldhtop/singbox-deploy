# sing-box VLESS Reality 一键部署

适用场景：AWS Lightsail / Ubuntu，新加坡个人节点，用于 Shadowrocket、v2rayN 等客户端。

## 特点

- 官方 sing-box APT 仓库，不使用第三方 GitHub 代理。
- VLESS + TCP + Reality + `xtls-rprx-vision`。
- 默认端口 `28443/TCP`，不占用网站的 `80/443`。
- 第一次安装生成 UUID、Reality 密钥和 Short ID；重复运行不会自动更换凭据。
- 自动校验 sing-box 配置并启用 systemd 服务。
- 输出 `vless://` 链接和终端二维码。
- 提供交互式 `menu` / `sbmenu` 管理菜单。
- 不修改 Docker、PostgreSQL、Redis、Nginx、系统默认路由或全局代理。
- 若 UFW 已经启用，只增加节点 TCP 端口规则；不会自动启用 UFW。

## 一键安装 Reality 节点

推荐先下载、再执行：

```bash
curl -fsSLo /tmp/install-singbox-reality.sh https://raw.githubusercontent.com/ldhtop/singbox-deploy/main/install-singbox-reality.sh
sudo bash /tmp/install-singbox-reality.sh
```

也可以一行执行：

```bash
curl -fsSL https://raw.githubusercontent.com/ldhtop/singbox-deploy/main/install-singbox-reality.sh | sudo bash
```

默认：

```text
Port: 28443/TCP
SNI: www.cloudflare.com
Protocol: VLESS + Reality
Flow: xtls-rprx-vision
```

## 安装交互式 menu

Reality 节点安装后，再执行这一行：

```bash
curl -fsSL https://raw.githubusercontent.com/ldhtop/singbox-deploy/main/install-menu.sh | sudo bash
```

安装完成后，以后直接输入：

```bash
menu
```

如果服务器原本已经存在别的 `menu` 命令，脚本不会覆盖它，此时使用：

```bash
sbmenu
```

菜单当前提供：

```text
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
```

你现在节点显示 `-1` 或无法联网时，优先运行：

```bash
menu
```

然后选择：

```text
7) 一键诊断节点
```

它会检查服务、监听端口、UFW、系统时间、Reality handshake 目标、配置校验以及最近的 Reality/TLS 错误。

## 查看节点链接

如果已经装了 menu：

```bash
menu
```

选择 `1`。

或者直接：

```bash
sudo cat /root/sing-box-vless-url.txt
```

显示完整节点信息和二维码：

```bash
curl -fsSL https://raw.githubusercontent.com/ldhtop/singbox-deploy/main/install-singbox-reality.sh | sudo bash -s -- --show
```

## 查看运行状态

```bash
sudo systemctl status sing-box --no-pager
```

最近日志：

```bash
sudo journalctl -u sing-box -n 100 --no-pager
```

实时日志：

```bash
sudo journalctl -u sing-box -f
```

## 修改 Reality SNI

例如：

```bash
curl -fsSLo /tmp/install-singbox-reality.sh https://raw.githubusercontent.com/ldhtop/singbox-deploy/main/install-singbox-reality.sh
sudo bash /tmp/install-singbox-reality.sh --set-sni www.cloudflare.com
```

或者 `menu -> 5`。

修改后要删除客户端旧节点，并重新导入新生成的 `vless://` 链接。

## 轮换 UUID / Reality 密钥

如果怀疑节点链接泄漏：

```bash
sudo bash /usr/local/lib/singbox-deploy/install-singbox-reality.sh --rotate
```

或者 `menu -> 6`。

旧链接会立即失效。

## AWS Lightsail 必做

给实例绑定 **Static IP**，然后在：

```text
Lightsail -> Networking -> IPv4 Firewall
```

增加：

```text
Application: Custom
Protocol: TCP
Port: 28443
Source: Anywhere IPv4
```

不要向公网开放 PostgreSQL `5432` 或 Redis `6379`。

## 本地文件

```text
/etc/sing-box/config.json          sing-box 服务配置
/etc/sing-box/reality.env          UUID / Reality 密钥 / SNI 等状态
/root/sing-box-vless-url.txt       当前 vless:// 节点链接
/usr/local/lib/singbox-deploy/     menu 本地管理脚本
```

敏感文件权限为 `600`，不要把 `reality.env` 或完整节点链接提交到 GitHub。
