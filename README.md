# VPS 一键配置

这个仓库保存 `install-custom-argosbx.sh`，用于在 VPS 上部署并定制 Argosbx 代理环境。

## 脚本做什么

- 安装基础工具和可选的 Codex CLI。
- 写入 BBR/fq 等网络调优参数。
- 写入 Clash/Mihomo 规则文件。
- 下载并执行上游 Argosbx 安装脚本。
- 修改上游生成的 `/root/bin/agsbx`，定制订阅节点、规则组和 Argo CDN 默认值。
- 更新 Xray、sing-box、cloudflared 核心。
- 重启代理服务并重新生成订阅。
- 校验 sing-box、Xray、Clash/Mihomo 和 Sing-box 订阅输出。

## 使用

```bash
chmod +x install-custom-argosbx.sh
sudo ./install-custom-argosbx.sh
```

可通过环境变量覆盖部分默认值，例如：

```bash
REALITY_DOMAIN=apple.com ARGO_MODE=vmpt ./install-custom-argosbx.sh
```

## 安全提醒

脚本包含 VPS 部署相关配置和订阅生成逻辑，建议仓库保持私有。
