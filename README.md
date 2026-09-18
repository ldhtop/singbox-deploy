# sing-box VLESS Reality 一键部署

适用场景：AWS Lightsail / Ubuntu，新加坡个人节点，用于 Shadowrocket、v2rayN 等客户端。

## 特点

- 官方 sing-box APT 仓库，不使用第三方 GitHub 代理。
- VLESS + TCP + Reality + `xtls-rprx-vision`。
- 默认端口 `28443/TCP`，不占用网站的 `80/443`。
- 第一次安装生成 UUID、Reality 密钥和 Short ID；重复运行不会自动更换凭据。
- 自动校验 sing-box 配置并启用 systemd 服务。
- 输出 `vless://` 链接和终端二维码。
- 不修改 Docker、PostgreSQL、Redis、Nginx、系统默认路由或全局代理。
- 若 UFW 已经启用，只增加节点 TCP 端口规则；不会自动启用 UFW。

## 推荐仓库结构

```text
singbox-deploy/
├── install-singbox-reality.sh
└── README.md
```

## 一键安装

推荐先下载、再执行：

```bash
curl -fsSLo /tmp/install-singbox-reality.sh \
  https://raw.githubusercontent.com/ldhtop/singbox-deploy/main/install-singbox-reality.sh

less /tmp/install-singbox-reality.sh
sudo bash /tmp/install-singbox-reality.sh
```

如果你确认仓库只有自己能修改，也可以一行执行：

```bash
curl -fsSL https://raw.githubusercontent.com/ldhtop/singbox-deploy/main/install-singbox-reality.sh | sudo bash
```

## 自定义端口 / SNI / 节点名

第一次安装时：

```bash
sudo PORT=28443 \
  SNI=www.microsoft.com \
  CLIENT_NAME=Andy-SG \
  bash install-singbox-reality.sh
```

第一次安装后参数会记录在：

```text
/etc/sing-box/reality.env
```

权限为 `600`。

## AWS Lightsail 必做

1. 给实例绑定 **Static IP**。
2. `Networking -> IPv4 Firewall` 新增：

```text
Application: Custom
Protocol: TCP
Port: 28443
Source: Anywhere IPv4
```

如果你自定义了端口，就开放对应端口。

不要向公网开放 PostgreSQL `5432` 或 Redis `6379`。

## 查看节点链接

```bash
sudo bash install-singbox-reality.sh --show
```

节点链接也保存在：

```text
/root/sing-box-vless-url.txt
```

权限为 `600`。

## 查看运行状态

```bash
sudo bash install-singbox-reality.sh --status
```

也可以：

```bash
sudo systemctl status sing-box --no-pager
sudo journalctl -u sing-box -n 100 --no-pager
```

## 轮换 UUID / Reality 密钥

如果怀疑链接泄漏：

```bash
sudo bash install-singbox-reality.sh --rotate
```

执行后旧客户端链接立即失效，需要重新导入新链接。

## 删除节点配置

```bash
sudo bash install-singbox-reality.sh --uninstall
```

该操作不会卸载 sing-box 软件，也不会自动删除 AWS Lightsail 防火墙规则。

## 更新策略

脚本重复执行不会主动升级已经安装的 sing-box。需要升级时建议先查看官方 release，再手动执行：

```bash
sudo apt update
sudo apt install --only-upgrade sing-box
sudo sing-box check -c /etc/sing-box/config.json
sudo systemctl restart sing-box
```

生产服务器不要使用 beta/alpha 版本。
