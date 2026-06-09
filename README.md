# Tokoyami-VPS

这个仓库保存 `install-custom-argosbx.sh`，用于在 VPS 上部署并定制 Argosbx 代理环境。

## 脚本做什么

- 安装基础工具和可选的 Codex CLI。
- 写入 BBR/fq 等网络调优参数。
- 写入 Clash/Mihomo 规则文件。
- 执行内嵌的 Argosbx 上游脚本副本，不再运行时拉取上游主脚本。
- 修改上游生成的 `/root/bin/agsbx`，定制订阅节点、规则组和 Argo CDN 默认值。
- 重新生成订阅。
- 校验 sing-box、Xray、Clash/Mihomo 和 Sing-box 订阅输出。

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

## 安全提醒

脚本会安装系统软件包、写入 `/etc` 和 `/root` 下的配置文件，并部署代理服务。请只在你控制的 VPS 上执行。

## 来源与许可

本项目内嵌并定制了 [yonggekkk/argosbx](https://github.com/yonggekkk/argosbx) 的 `argosbx.sh`，原项目使用 GPL-3.0 许可证。本仓库保留相同许可证，详见 `LICENSE`。
