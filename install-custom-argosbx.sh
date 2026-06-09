#!/usr/bin/env bash
set -euo pipefail

# 上游 Argosbx 安装脚本地址；可通过环境变量 UPSTREAM_URL 覆盖。
UPSTREAM_URL="${UPSTREAM_URL:-https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh}"

# 写入 VPS 的 Clash/Mihomo 规则文件路径；后续会被订阅生成逻辑读取。
RULE_FILE="${RULE_FILE:-/root/clash-current-rule-groups-RsZJB0LcZ59N.yaml}"

# Argosbx 上游安装完成后生成的主控脚本路径。
SCRIPT_PATH="/root/bin/agsbx"

# Reality 节点伪装域名。
REALITY_DOMAIN="${REALITY_DOMAIN:-apple.com}"

# Argo 模式，默认生成 VMess + HTTP/TLS Argo 相关节点。
ARGO_MODE="${ARGO_MODE:-vmpt}"

# Hysteria2 端口范围。
HY_PORT_RANGE="${HY_PORT_RANGE:-40000:45000}"

# 订阅服务端口和订阅 token；为空时交给上游脚本自动生成。
SUB_PORT="${SUB_PORT:-}"
SUB_TOKEN="${SUB_TOKEN:-}"

# Argo 节点默认 CDN 域名，分别用于 TLS 与 HTTP 节点。
ARGO_TLS_CDN="${ARGO_TLS_CDN:-yg1.ygkkk.dpdns.org}"
ARGO_HTTP_CDN="${ARGO_HTTP_CDN:-yg6.ygkkk.dpdns.org}"

# 是否强制刷新 Xray、sing-box、cloudflared 三个核心二进制。
FORCE_CORE_UPDATE="${FORCE_CORE_UPDATE:-yes}"

# 确认脚本以 root 身份运行，因为后续会写 /etc、/root 并重启服务。
need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root." >&2
    exit 1
  fi
}

# 安装脚本运行所需的基础工具。
# 支持 Debian/Ubuntu 的 apt 和 Alpine 的 apk；安装失败时不会中断 VPN 安装主流程。
install_basic_tools() {
  if command -v apt >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    if ! apt update; then
      echo "apt update failed; skipping basic tool installation and continuing to VPN setup." >&2
      return 0
    fi
    apt install -y \
      curl wget ca-certificates gnupg lsb-release \
      jq python3 python3-yaml perl \
      nodejs npm git unzip tar gzip xz-utils \
      iptables iptables-persistent iproute2 dnsutils net-tools lsof cron busybox || {
        echo "apt package installation failed; continuing to VPN setup with existing tools." >&2
        return 0
      }
  elif command -v apk >/dev/null 2>&1; then
    if ! apk update; then
      echo "apk update failed; skipping basic tool installation and continuing to VPN setup." >&2
      return 0
    fi
    apk add --no-cache \
      curl wget ca-certificates gnupg \
      jq python3 py3-yaml perl \
      nodejs npm git unzip tar gzip xz \
      iptables iproute2 bind-tools net-tools lsof busybox-extras || {
        echo "apk package installation failed; continuing to VPN setup with existing tools." >&2
        return 0
      }
  else
    echo "No supported package manager found; skipping basic tool installation and continuing to VPN setup." >&2
  fi
}

# 通过 npm 安装或更新 OpenAI Codex CLI。
# 该步骤是辅助工具安装，失败或超时会继续执行代理服务部署。
install_codex_cli() {
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is not installed; skipping Codex CLI installation and continuing to VPN setup." >&2
    return 0
  fi

  echo "Installing or updating Codex CLI with npm..."
  if command -v timeout >/dev/null 2>&1; then
    timeout 180 npm install -g @openai/codex || {
      echo "Codex CLI installation failed or timed out; continuing to VPN setup." >&2
      return 0
    }
  else
    npm install -g @openai/codex || {
      echo "Codex CLI installation failed; continuing to VPN setup." >&2
      return 0
    }
  fi
  echo "Codex CLI: $(codex --version 2>/dev/null || echo installed)"
}

# 写入内核网络优化参数，启用 fq + BBR，并调大 TCP/UDP 缓冲区。
# 目标是改善跨境、高延迟链路下的代理吞吐表现。
write_network_tuning() {
  cat > /etc/sysctl.d/99-agsbx-network-tuning.conf <<'EOF'
# Network tuning for the Argosbx proxy workload on high-latency paths.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 262144
net.core.wmem_default = 262144

net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
EOF

  cat > /etc/modules-load.d/99-agsbx-bbr.conf <<'EOF'
tcp_bbr
EOF

  modprobe tcp_bbr 2>/dev/null || true
  sysctl -p /etc/sysctl.d/99-agsbx-network-tuning.conf >/dev/null || true
}

# 生成 Clash/Mihomo 规则文件。
# 规则前半部分把测速、Apple/iCloud、连通性检测和局域网/中国 IP 直连，
# 最后一条 MATCH 会把其余流量交给“🌍选择代理节点”策略组。
write_rule_file() {
  cat > "$RULE_FILE" <<'EOF'
rules:
  - DOMAIN-SUFFIX,speedtest.net,DIRECT
  - DOMAIN-SUFFIX,ookla.com,DIRECT
  - DOMAIN-SUFFIX,ooklaserver.net,DIRECT
  - DOMAIN-SUFFIX,fast.com,DIRECT
  - DOMAIN-SUFFIX,apple.com,DIRECT
  - DOMAIN-SUFFIX,apple.com.cn,DIRECT
  - DOMAIN-SUFFIX,aaplimg.com,DIRECT
  - DOMAIN-SUFFIX,apple-cloudkit.com,DIRECT
  - DOMAIN-SUFFIX,apple-mapkit.com,DIRECT
  - DOMAIN-SUFFIX,cdn-apple.com,DIRECT
  - DOMAIN-SUFFIX,icloud.com,DIRECT
  - DOMAIN-SUFFIX,icloud.com.cn,DIRECT
  - DOMAIN-SUFFIX,icloud-content.com,DIRECT
  - DOMAIN-SUFFIX,mzstatic.com,DIRECT
  - DOMAIN-SUFFIX,me.com,DIRECT
  - DOMAIN,rama991.siamparagon.org,DIRECT
  - DOMAIN-SUFFIX,265.com,DIRECT
  - DOMAIN-SUFFIX,2mdn.net,DIRECT
  - DOMAIN-SUFFIX,alt1-mtalk.google.com,DIRECT
  - DOMAIN-SUFFIX,alt2-mtalk.google.com,DIRECT
  - DOMAIN-SUFFIX,alt3-mtalk.google.com,DIRECT
  - DOMAIN-SUFFIX,alt4-mtalk.google.com,DIRECT
  - DOMAIN-SUFFIX,alt5-mtalk.google.com,DIRECT
  - DOMAIN-SUFFIX,alt6-mtalk.google.com,DIRECT
  - DOMAIN-SUFFIX,alt7-mtalk.google.com,DIRECT
  - DOMAIN-SUFFIX,alt8-mtalk.google.com,DIRECT
  - DOMAIN-SUFFIX,app-measurement.com,DIRECT
  - DOMAIN-SUFFIX,cache.pack.google.com,DIRECT
  - DOMAIN-SUFFIX,clickserve.dartsearch.net,DIRECT
  - DOMAIN-SUFFIX,crl.pki.goog,DIRECT
  - DOMAIN-SUFFIX,dl.google.com,DIRECT
  - DOMAIN-SUFFIX,dl.l.google.com,DIRECT
  - DOMAIN-SUFFIX,googletagmanager.com,DIRECT
  - DOMAIN-SUFFIX,googletagservices.com,DIRECT
  - DOMAIN-SUFFIX,gtm.oasisfeng.com,DIRECT
  - DOMAIN-SUFFIX,mtalk.google.com,DIRECT
  - DOMAIN-SUFFIX,ocsp.pki.goog,DIRECT
  - DOMAIN-SUFFIX,recaptcha.net,DIRECT
  - DOMAIN-SUFFIX,safebrowsing-cache.google.com,DIRECT
  - DOMAIN-SUFFIX,settings.crashlytics.com,DIRECT
  - DOMAIN-SUFFIX,ssl-google-analytics.l.google.com,DIRECT
  - DOMAIN-SUFFIX,toolbarqueries.google.com,DIRECT
  - DOMAIN-SUFFIX,tools.google.com,DIRECT
  - DOMAIN-SUFFIX,tools.l.google.com,DIRECT
  - DOMAIN-SUFFIX,www-googletagmanager.l.google.com,DIRECT
  - DOMAIN,asusrouter.com,DIRECT
  - DOMAIN,instant.arubanetworks.com,DIRECT
  - DOMAIN,router.asus.com,DIRECT
  - DOMAIN,setmeup.arubanetworks.com,DIRECT
  - DOMAIN,www.asusrouter.com,DIRECT
  - DOMAIN,www.mifiwi.com,DIRECT
  - DOMAIN-SUFFIX,captive.apple.com,DIRECT
  - DOMAIN-SUFFIX,connectivitycheck.gstatic.com,DIRECT
  - DOMAIN-SUFFIX,hiwifi.com,DIRECT
  - DOMAIN-SUFFIX,leike.cc,DIRECT
  - DOMAIN-SUFFIX,localhost.ptlogin2.qq.com,DIRECT
  - DOMAIN-SUFFIX,localhost.sec.qq.com,DIRECT
  - DOMAIN-SUFFIX,miwifi.com,DIRECT
  - DOMAIN-SUFFIX,msftconnecttest.com,DIRECT
  - DOMAIN-SUFFIX,msftncsi.com,DIRECT
  - DOMAIN-SUFFIX,my.router,DIRECT
  - DOMAIN-SUFFIX,networkcheck.kde.org,DIRECT
  - DOMAIN-SUFFIX,p.to,DIRECT
  - DOMAIN-SUFFIX,peiluyou.com,DIRECT
  - DOMAIN-SUFFIX,phicomm.me,DIRECT
  - DOMAIN-SUFFIX,plex.direct,DIRECT
  - DOMAIN-SUFFIX,router.ctc,DIRECT
  - DOMAIN-SUFFIX,routerlogin.com,DIRECT
  - DOMAIN-SUFFIX,tendawifi.com,DIRECT
  - DOMAIN-SUFFIX,tplinkwifi.net,DIRECT
  - DOMAIN-SUFFIX,tplogin.cn,DIRECT
  - DOMAIN-SUFFIX,wifi.cmcc,DIRECT
  - DOMAIN-SUFFIX,zte.home,DIRECT
  - DOMAIN-KEYWORD,aria2,DIRECT
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍选择代理节点
EOF
}

# 下载上游 Argosbx 安装脚本到 /tmp，并添加可执行权限。
download_upstream() {
  local tmp=/tmp/argosbx-upstream.sh
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$UPSTREAM_URL" -o "$tmp"
  else
    wget -qO "$tmp" "$UPSTREAM_URL"
  fi
  chmod +x "$tmp"
  echo "$tmp"
}

# 调用上游 Argosbx 安装脚本完成基础代理服务部署。
# 这里显式清空若干端口变量，让上游自行分配端口，同时传入 Argo、Reality 和 Hysteria2 配置。
install_argosbx_base() {
  local upstream
  upstream="$(download_upstream)"

  local sub_env=(sub=yes)
  if [ -n "$SUB_PORT" ]; then
    sub_env+=(subpt="$SUB_PORT")
  fi
  if [ -n "$SUB_TOKEN" ]; then
    sub_env+=(subid="$SUB_TOKEN")
  fi

  env \
    vlpt= \
    vmpt= \
    hypt= \
    tupt= \
    anpt= \
    arpt= \
    argo="$ARGO_MODE" \
    reym="$REALITY_DOMAIN" \
    hyjpt="$HY_PORT_RANGE" \
    "${sub_env[@]}" \
    bash "$upstream"
}

# 写入 Argo CDN 默认域名。
# 如果 /root/agsbx/cdnip1 或 cdnip2 已经有非空内容，就保留现有值。
write_argo_cdn_defaults() {
  mkdir -p /root/agsbx
  if [ -z "$(tr -d '[:space:]' < /root/agsbx/cdnip1 2>/dev/null || true)" ]; then
    printf '%s\n' "$ARGO_TLS_CDN" > /root/agsbx/cdnip1
  fi
  if [ -z "$(tr -d '[:space:]' < /root/agsbx/cdnip2 2>/dev/null || true)" ]; then
    printf '%s\n' "$ARGO_HTTP_CDN" > /root/agsbx/cdnip2
  fi
}

# 根据 CPU 架构选择要下载的核心二进制名称。
detect_core_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l|armv7|armhf) echo arm ;;
    *) echo amd64 ;;
  esac
}

# 强制刷新 Xray、sing-box 和 cloudflared 核心。
# 下载完成后输出版本信息，方便确认核心文件已经替换。
force_update_cores() {
  [ "$FORCE_CORE_UPDATE" = "yes" ] || return 0

  local arch
  arch="$(detect_core_arch)"
  mkdir -p /root/agsbx

  echo "Refreshing Xray, sing-box and cloudflared cores..."
  curl -fsSL "https://github.com/yonggekkk/argosbx/releases/download/argosbx/xray-${arch}" -o /root/agsbx/xray
  curl -fsSL "https://github.com/yonggekkk/argosbx/releases/download/argosbx/sing-box-${arch}" -o /root/agsbx/sing-box
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" -o /root/agsbx/cloudflared
  chmod +x /root/agsbx/xray /root/agsbx/sing-box /root/agsbx/cloudflared

  echo "Xray:       $(/root/agsbx/xray version 2>/dev/null | awk '/^Xray/{print $2; exit}')"
  echo "sing-box:   $(/root/agsbx/sing-box version 2>/dev/null | awk '/version/{print $NF; exit}')"
  echo "cloudflared: $(/root/agsbx/cloudflared --version 2>/dev/null | awk '{print $3; exit}')"
}

# 修改上游生成的 /root/bin/agsbx 脚本，让订阅输出符合本机定制需求。
# 主要动作包括：隐藏部分节点、修正 Argo CDN 读取、让 AnyTLS 走 WARP、
# 移除负载均衡组，以及把本脚本写入的 Clash/Mihomo 规则导入订阅。
patch_argosbx_script() {
  if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Missing $SCRIPT_PATH after upstream install." >&2
    exit 1
  fi

  # Client-facing node names should not include the VPS hostname.
  perl -0pi -e 's/-\$hostname//g' "$SCRIPT_PATH"

  # Keep the server-side VMess inbound for Argo, but hide direct VMess and SS2022 from subscriptions.
  perl -0pi -e 's/if grep ss-2022/if false \&\& grep ss-2022/g' "$SCRIPT_PATH"
  perl -0pi -e 's/if grep vmess-xr "\$HOME\/agsbx\/xr\.json" >\/dev\/null 2>\&1 \|\| grep vmess-sb "\$HOME\/agsbx\/sb\.json" >\/dev\/null 2>\&1; then/if false \&\& { grep vmess-xr "\$HOME\/agsbx\/xr.json" >\/dev\/null 2>\&1 || grep vmess-sb "\$HOME\/agsbx\/sb.json" >\/dev\/null 2>\&1; }; then/g' "$SCRIPT_PATH"

  # Make Argo CDN defaults robust even when the cdnip files exist but contain empty lines.
  perl -0pi -e 's/\[ -z "\$cdnip1" \] \&\& \[ -f "\$HOME\/agsbx\/cdnip1" \] \&\& cdnip1=\$\(cat "\$HOME\/agsbx\/cdnip1"\)/[ -z "\$cdnip1" ] \&\& [ -f "\$HOME\/agsbx\/cdnip1" ] \&\& cdnip1=\$\(tr -d '\''\\r\\n'\'' < "\$HOME\/agsbx\/cdnip1"\)/g' "$SCRIPT_PATH"
  perl -0pi -e 's/\[ -z "\$cdnip2" \] \&\& \[ -f "\$HOME\/agsbx\/cdnip2" \] \&\& cdnip2=\$\(cat "\$HOME\/agsbx\/cdnip2"\)/[ -z "\$cdnip2" ] \&\& [ -f "\$HOME\/agsbx\/cdnip2" ] \&\& cdnip2=\$\(tr -d '\''\\r\\n'\'' < "\$HOME\/agsbx\/cdnip2"\)/g' "$SCRIPT_PATH"

  # Route only AnyTLS server-side traffic through WARP.
  python3 - "$SCRIPT_PATH" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
block = '''      {
        "inbound": [
          "anytls-sb"
        ],
        "outbound": "warp-out"
      },'''
anchor = '''"strategy": "${sbyx}"
       },'''
if block not in text:
    if anchor not in text:
        raise SystemExit("Could not find sing-box route anchor for AnyTLS WARP patch")
    text = text.replace(anchor, anchor + "\n" + block, 1)
    path.write_text(text)
PY

  # Drop the load-balance group from Clash/Mihomo and keep only auto + manual select.
  perl -0pi -e 's/proxy-groups:\n- name: 负载均衡\n  type: load-balance\n  url: https:\/\/www\.gstatic\.com\/generate_204\n  interval: 300\n  strategy: round-robin\n  proxies:\n    \$clgz\n- name: 自动选择/proxy-groups:\n- name: 自动选择/s' "$SCRIPT_PATH"
  perl -0pi -e 's/\n    - 负载均衡[^\n]*//g' "$SCRIPT_PATH"

  # Let the generated Clash/Mihomo subscription import the embedded rule list.
  if ! grep -q 'clash_rules_file=' "$SCRIPT_PATH"; then
    perl -0pi -e 's/(sbgz=\$\(printf "%s\\n" "\$sbgz" \| sed '\''\$ s\/,\$\/'\''\)\n)/$1default_clash_rules="  - GEOIP,LAN,DIRECT\n  - GEOIP,CN,DIRECT\n  - MATCH,🌍选择代理节点"\nclash_rules="$default_clash_rules"\nclash_rules_file="$HOME\/clash-current-rule-groups-RsZJB0LcZ59N.yaml"\nif [ -s "$clash_rules_file" ]; then\nclash_rules_from_file=$(awk '\''\n  /^rules:[[:space:]]*$/ { in_rules=1; next }\n  in_rules \&\& /^[^[:space:]-]/ { exit }\n  in_rules \&\& /^[[:space:]]*- / { sub(\/^[[:space:]]*\/, ""); print "  " $0 }\n'\'' "$clash_rules_file")\n[ -n "$clash_rules_from_file" ] \&\& clash_rules="$clash_rules_from_file"\nfi\n/s' "$SCRIPT_PATH"
    perl -0pi -e 's/rules:\n  - GEOIP,LAN,DIRECT\n  - GEOIP,CN,DIRECT\n  - MATCH,🌍选择代理节点/rules:\n\$clash_rules/s' "$SCRIPT_PATH"
  fi

  bash -n "$SCRIPT_PATH"
}

# 直接修正运行时 sing-box 配置。
# 这里会移除 ss-2022 inbound，并确保 AnyTLS inbound 通过 warp-out 出站。
patch_runtime_configs() {
  python3 - <<'PY'
import json
from pathlib import Path

sb = Path("/root/agsbx/sb.json")
if sb.exists():
    data = json.loads(sb.read_text())
    data["inbounds"] = [i for i in data.get("inbounds", []) if i.get("tag") != "ss-2022"]
    route = data.setdefault("route", {})
    rules = route.setdefault("rules", [])
    rules = [r for r in rules if r.get("inbound") != ["anytls-sb"]]
    insert_at = 2 if len(rules) >= 2 else len(rules)
    rules.insert(insert_at, {"inbound": ["anytls-sb"], "outbound": "warp-out"})
    route["rules"] = rules
    sb.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
}

# 重启代理服务。
# 有 systemd 时走 systemctl；没有 systemd 时手动结束旧进程并用 setsid 拉起 sing-box 和 Xray。
restart_services() {
  if command -v systemctl >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart sb >/dev/null 2>&1 || true
    systemctl restart xr >/dev/null 2>&1 || true
    systemctl restart argo >/dev/null 2>&1 || true
  else
    for pid in $(pgrep -f '/root/agsbx/sing-box run -c /root/agsbx/sb.json' || true); do
      [ "$pid" = "$$" ] || kill "$pid" >/dev/null 2>&1 || true
    done
    for pid in $(pgrep -f '/root/agsbx/xray run -c /root/agsbx/xr.json' || true); do
      [ "$pid" = "$$" ] || kill "$pid" >/dev/null 2>&1 || true
    done
    setsid /root/agsbx/sing-box run -c /root/agsbx/sb.json >/tmp/agsbx-sing-box.log 2>&1 < /dev/null &
    setsid /root/agsbx/xray run -c /root/agsbx/xr.json >/tmp/agsbx-xray.log 2>&1 < /dev/null &
  fi
}

# 触发 /root/bin/agsbx 重新生成订阅文件。
regenerate_subscriptions() {
  "$SCRIPT_PATH" list >/tmp/agsbx-custom-list.log 2>&1
}

# 校验安装结果。
# 检查 sing-box 配置、Xray 配置、Clash/Mihomo 订阅和 Sing-box 订阅中的 Argo 节点是否有效。
verify_install() {
  /root/agsbx/sing-box check -c /root/agsbx/sb.json >/dev/null
  /root/agsbx/xray run -test -c /root/agsbx/xr.json >/dev/null 2>&1 || true
  python3 - <<'PY'
import json
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None

sbox = json.loads(Path("/root/agsbx/sbox.json").read_text())
if yaml:
    clash = yaml.safe_load(Path("/root/agsbx/clmi.yaml").read_text())
    print("Clash/Mihomo nodes:", ", ".join(p["name"] for p in clash["proxies"]))
    print("Clash/Mihomo groups:", ", ".join(g["name"] for g in clash["proxy-groups"]))
    print("Clash/Mihomo rules:", len(clash["rules"]))
    argo_nodes = [p for p in clash["proxies"] if "argo" in p.get("name", "")]
    bad_argo = [p.get("name") for p in argo_nodes if not p.get("server")]
    if len(argo_nodes) < 2 or bad_argo:
        raise SystemExit(f"Invalid Argo nodes in Clash/Mihomo subscription: {bad_argo or 'missing'}")
else:
    print("Clash/Mihomo subscription generated: /root/agsbx/clmi.yaml")
sing_argo = [o for o in sbox["outbounds"] if "argo" in o.get("tag", "")]
bad_sing_argo = [o.get("tag") for o in sing_argo if not o.get("server")]
if len(sing_argo) < 2 or bad_sing_argo:
    raise SystemExit(f"Invalid Argo nodes in Sing-box subscription: {bad_sing_argo or 'missing'}")
print("Sing-box outbounds:", ", ".join(o.get("tag", "") for o in sbox["outbounds"] if o.get("tag") not in ("proxy", "auto", "direct")))
PY
}

# 输出最终订阅链接。
# 链接依赖上游脚本写入的 server_ip.log、subport.log 和 subtoken.log。
show_links() {
  echo
  echo "Subscription links:"
  if [ -s /root/agsbx/server_ip.log ] && [ -s /root/agsbx/subport.log ] && [ -s /root/agsbx/subtoken.log ]; then
    local ip port token
    ip="$(cat /root/agsbx/server_ip.log)"
    port="$(cat /root/agsbx/subport.log)"
    token="$(cat /root/agsbx/subtoken.log)"
    echo "Clash/Mihomo: http://${ip}:${port}/${token}/clmi.yaml"
    echo "Sing-box:      http://${ip}:${port}/${token}/sbox.json"
    echo "Aggregate:     http://${ip}:${port}/${token}/jhsub.txt"
  else
    echo "Subscription files exist under /root/agsbx, but the HTTP subscription metadata was not found."
  fi
}

# 主流程：按顺序完成依赖安装、系统调优、Argosbx 部署、脚本补丁、
# 核心更新、服务重启、订阅再生成、结果校验和订阅链接输出。
main() {
  need_root
  install_basic_tools
  install_codex_cli
  write_network_tuning
  write_rule_file
  install_argosbx_base
  write_argo_cdn_defaults
  patch_argosbx_script
  force_update_cores
  patch_runtime_configs
  write_argo_cdn_defaults
  restart_services
  regenerate_subscriptions
  verify_install
  show_links
}

main "$@"
