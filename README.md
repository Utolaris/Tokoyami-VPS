# Tokoyami-VPS

Tokoyami-VPS 是一个面向个人 VPS 的一键代理环境配置脚本。它会在 VPS 上部署 Argosbx 风格的 Xray、sing-box、cloudflared 组合，并生成可直接导入客户端的 Clash/Mihomo 与 Sing-box 订阅。

这个项目不是从零实现的代理安装器。它受到 [Argosbx](https://github.com/yonggekkk/argosbx) 的明显影响，并内嵌、定制了 Argosbx 的 `argosbx.sh`。Tokoyami-VPS 的重点是把原脚本的能力固定成一套更符合个人使用习惯的默认配置。

## 实际效果

执行脚本后，VPS 会被配置为一个代理服务器，并生成三类订阅地址：

- Clash/Mihomo: `http://VPS_IP:端口/token/clmi.yaml`
- Sing-box: `http://VPS_IP:端口/token/sbox.json`
- 聚合订阅: `http://VPS_IP:端口/token/jhsub.txt`

脚本默认会部署多种协议节点，并把它们整理到订阅中。当前定制方向是：

- 使用内嵌 Argosbx 脚本完成基础安装，不再运行时拉取上游主脚本。
- 写入本项目自带的 Clash/Mihomo 规则，测速、Apple/iCloud、局域网和中国 IP 等走直连，其余流量走主代理组。
- 修改 `/root/bin/agsbx` 的订阅生成逻辑，隐藏不想直接暴露给客户端的普通 VMess WS 节点。
- 去掉 Clash/Mihomo 订阅里的 `负载均衡` 策略组，只保留自动选择和手动选择。
- 写入默认 Argo CDN 域名，避免 CDN 配置文件为空时生成异常订阅。
- 重新生成订阅并检查 Xray、sing-box、Clash/Mihomo、Sing-box 输出是否可用。

脚本不会在外层额外强制刷新 Xray、sing-box、cloudflared 核心，也不会在 Argosbx 安装完成后再额外重启服务。核心下载、服务创建和初始启动主要交给内嵌的 Argosbx 流程完成。

## 使用

在 VPS 上复制下面的一键命令直接执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Utolaris/Tokoyami-VPS/main/install-custom-argosbx.sh | sudo bash
```

如果已经以 `root` 用户登录 VPS，也可以使用：

```bash
curl -fsSL https://raw.githubusercontent.com/Utolaris/Tokoyami-VPS/main/install-custom-argosbx.sh | bash
```

本地手动执行方式：

```bash
chmod +x install-custom-argosbx.sh
sudo ./install-custom-argosbx.sh
```

可通过环境变量覆盖部分默认值，例如：

```bash
REALITY_DOMAIN=apple.com ARGO_MODE=vmpt ./install-custom-argosbx.sh
```

## 与 Argosbx 的关系

Tokoyami-VPS 深受 Argosbx 影响。Argosbx 提供了核心安装、协议组合、订阅生成、Cloudflare Argo 隧道等主要基础能力；本项目在此基础上做了定制：

- 固定默认协议组合和参数。
- 内嵌上游脚本，减少执行时对上游 raw 脚本的依赖。
- 调整订阅输出，去掉部分不需要的节点或策略组。
- 增加自用 Clash/Mihomo 规则。
- 加入额外校验，确保生成的订阅内容基本可用。

因此，本项目应被理解为 Argosbx 的个人化定制版本，而不是独立替代 Argosbx 的通用项目。

## 安全提醒

脚本会安装系统软件包、写入 `/etc` 和 `/root` 下的配置文件，并部署代理服务。请只在你控制的 VPS 上执行。

一键命令属于远程脚本高权限执行。更谨慎的做法是先下载脚本，审阅后再运行：

```bash
curl -fsSL https://raw.githubusercontent.com/Utolaris/Tokoyami-VPS/main/install-custom-argosbx.sh -o install-custom-argosbx.sh
bash -n install-custom-argosbx.sh
sudo bash install-custom-argosbx.sh
```

## 来源与许可

本项目内嵌并定制了 [yonggekkk/argosbx](https://github.com/yonggekkk/argosbx) 的 `argosbx.sh`。原项目使用 GPL-3.0 许可证，本仓库保留相同许可证，详见 `LICENSE`。
