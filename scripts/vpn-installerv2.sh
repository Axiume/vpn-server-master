#!/usr/bin/env bash
#=====================================================================
#  VPN Panel Auto Installer  v2.0
#  One command:   bash <(curl -fsSL https://raw.githubusercontent.com/Axiume/vpn-server-master/main/scripts/vpn-installerv2.sh)
#  After the first run the command  vpn  is installed on the server.
#=====================================================================
VERSION="2.0.0"
SELF_URL="https://raw.githubusercontent.com/Axiume/vpn-server-master/main/scripts/vpn-installerv2.sh"
CONF="/etc/vpn-installer.conf"
LOG="/var/log/vpn-installer.log"
BIN="/usr/local/bin/vpn"
STAMP="/var/lib/vpn-installer.deps"

# ---------- Source URLs (edit here if a project moves) ----------
URL_3XUI="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
URL_XUI_ALIREZA="https://raw.githubusercontent.com/alireza0/x-ui/master/install.sh"
URL_MARZBAN="https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh"
URL_MARZNESHIN="https://github.com/marzneshin/Marzneshin/raw/master/script.sh"
URL_PASARGUARD="https://github.com/PasarGuard/scripts/raw/main/pasarguard.sh"
URL_HIDDIFY="https://i.hiddify.com/release"
URL_WG_ANGRISTAN="https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh"
URL_OVPN="https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh"
URL_IPSEC="https://get.vpnsetup.net"
URL_XRAY="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
URL_SINGBOX="https://sing-box.app/deb-install.sh"
URL_HY2="https://get.hy2.sh/"
URL_CHISEL="https://i.jpillora.com/chisel!"
WG_EASY_IMAGE="ghcr.io/wg-easy/wg-easy:15"

# ---------- Colors / helpers ----------
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; W=$'\e[1m'; N=$'\e[0m'
log()  { echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null; }
msg()  { echo "${C}[*]${N} $*"; log "INFO $*"; }
ok()   { echo "${G}[+]${N} $*"; log "OK   $*"; }
warn() { echo "${Y}[!]${N} $*"; log "WARN $*"; }
err()  { echo "${R}[-]${N} $*"; log "ERR  $*"; }
pause(){ echo; read -rp "Press Enter to go back to the menu... " _; }
rand() { openssl rand -hex "${1:-8}"; }

# ask "prompt" [default]  -> prints answer (with -y: returns the default)
ask() {
  local p="$1" d="${2:-}" v
  if [[ ${ASSUME_YES:-0} == 1 && $# -ge 2 ]]; then echo "$d"; return; fi
  if [[ -n $d ]]; then read -rp "$p [$d]: " v; echo "${v:-$d}"
  else read -rp "$p: " v; echo "$v"; fi
}
confirm() {
  [[ ${ASSUME_YES:-0} == 1 ]] && return 0
  local a; read -rp "$1 [y/N]: " a; [[ $a =~ ^[Yy]$ ]]
}

usage() {
  cat <<EOF
VPN Panel Auto Installer v${VERSION}

  vpn                                    interactive menu
  vpn --install <target>[,<target>...]   direct install   (add -y for defaults)
  vpn --status                           show installed services
  vpn --update                           update this script
  vpn --mirror <url|off>                 set / clear GitHub mirror prefix
  vpn --version

Targets:
  Panels   : 3xui xui marzban marzneshin pasarguard hiddify
  Cores    : xray singbox hysteria2
  VPN      : wg-easy wireguard ikev2 openvpn
  Tunnels  : iptables socat gost frp backhaul rathole chisel cloudflared
  Tools    : bbr docker firewall fail2ban swap

Example:  vpn --install bbr,firewall,3xui
EOF
}

parse_args() {
  MODE=menu; TARGETS=""; ASSUME_YES=0; MIRROR_ARG=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)     ASSUME_YES=1 ;;
      --install)    MODE=install; TARGETS="${2:-}"; shift ;;
      --status)     MODE=status ;;
      --update)     MODE=update ;;
      --mirror)     MODE=mirror; MIRROR_ARG="${2:-}"; shift ;;
      --list|-h|--help) usage; exit 0 ;;
      --version)    echo "$VERSION"; exit 0 ;;
      *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done
}

need_root() { [[ $EUID -eq 0 ]] || { err "Run as root:  sudo bash $0"; exit 1; }; }

detect_system() {
  if   command -v apt-get >/dev/null 2>&1; then PM=apt
  elif command -v dnf     >/dev/null 2>&1; then PM=dnf
  elif command -v yum     >/dev/null 2>&1; then PM=yum
  else err "Unsupported OS (needs apt/dnf/yum)"; exit 1; fi
  case "$(uname -m)" in
    x86_64|amd64)  ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *)             ARCH="$(uname -m)" ;;
  esac
  mkdir -p "$(dirname "$LOG")" /var/lib 2>/dev/null
}

pkg_install() {
  if [[ $PM == apt ]]; then DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
  else "$PM" install -y "$@"; fi
}

install_deps() {
  if [[ ! -f $STAMP || -z "$(find "$STAMP" -mmin -1440 2>/dev/null)" ]]; then
    msg "Installing base dependencies..."
    if [[ $PM == apt ]]; then
      apt-get update -y
      pkg_install curl wget ca-certificates tar unzip openssl jq iproute2 iptables
    else
      pkg_install curl wget ca-certificates tar unzip openssl jq iproute iptables
    fi && touch "$STAMP"
  fi
  SERVER_IP="$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -4fsS --max-time 8 https://ifconfig.me 2>/dev/null || echo YOUR_SERVER_IP)"
}

#---------------------------------------------------------------------
#  GitHub mirror (optional, for servers where GitHub is blocked)
#---------------------------------------------------------------------
mirror_url() {
  local u="$1"
  if [[ -n ${GH_MIRROR:-} && $u =~ ^https://(github\.com|raw\.githubusercontent\.com)/ ]]; then
    echo "${GH_MIRROR%/}/$u"
  else
    echo "$u"
  fi
}

set_mirror() {
  local m="${1:-}"
  if [[ -z $m || $m == off ]]; then
    rm -f "$CONF"; GH_MIRROR=""; ok "GitHub mirror disabled"; return
  fi
  [[ $m == https://* ]] || { err "Mirror must start with https://"; return 1; }
  echo "GH_MIRROR=\"${m%/}\"" > "$CONF"; chmod 600 "$CONF"; GH_MIRROR="${m%/}"
  ok "Mirror set: $GH_MIRROR"
  warn "A third-party mirror can see and alter what you download, and these scripts run as root."
  warn "Release binaries are checksum-verified when GitHub publishes digests; installer scripts are NOT."
}

menu_mirror() {
  clear
  echo "${W}=== GitHub mirror ===${N}"
  echo "Current: ${GH_MIRROR:-<none>}"
  echo "Only the first-stage downloads use it; panel installers fetch their own files."
  echo " 1) Set mirror prefix (e.g. https://your-mirror.example)"
  echo " 2) Disable mirror"
  echo " 0) Back"
  read -rp "Select: " c
  case $c in
    1) read -rp "Mirror URL prefix: " m; set_mirror "$m"; pause ;;
    2) set_mirror off; pause ;;
    *) ;;
  esac
}

#---------------------------------------------------------------------
#  Core helpers
#---------------------------------------------------------------------
# Download a remote installer to a temp file, then run it with args
run_remote() {
  local url="$1"; shift
  local tmp rc
  tmp="$(mktemp /tmp/inst.XXXXXX)"
  msg "Downloading: $url"
  if ! curl -fsSL --retry 3 --connect-timeout 15 -o "$tmp" "$(mirror_url "$url")"; then
    err "Download failed. The URL may be blocked from this server, or it has changed."
    err "Try:  vpn --mirror <url>   or update the URL at the top of the script."
    rm -f "$tmp"; return 1
  fi
  bash "$tmp" "$@"; rc=$?
  rm -f "$tmp"
  return $rc
}

port_busy() { ss -lntu 2>/dev/null | awk 'NR>1{print $5}' | grep -Eq "[:.]$1\$"; }

check_port() { # port label  -> warns if busy, asks to continue
  if port_busy "$1"; then
    warn "Port $1 is already in use ($2). Current listener:"
    ss -lntup 2>/dev/null | grep -E "[:.]$1\s" | head -3
    confirm "Continue anyway?" || return 1
  fi
  return 0
}

open_port() {
  local port="$1" proto="${2:-tcp}"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "${port}/${proto}" >/dev/null && ok "ufw: opened ${port}/${proto}"
  elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="${port//:/-}/${proto}" >/dev/null
    firewall-cmd --reload >/dev/null && ok "firewalld: opened ${port}/${proto}"
  fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    msg "Installing Docker..."
    curl -fsSL https://get.docker.com | sh || { err "Docker install failed"; return 1; }
  fi
  systemctl enable --now docker >/dev/null 2>&1
  return 0
}

mk_service() { # name description exec-command
  local name="$1" desc="$2" exec="$3"
  cat > "/etc/systemd/system/${name}.service" <<EOF
[Unit]
Description=${desc}
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${exec}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "${name}.service" >/dev/null 2>&1
  sleep 1
  if systemctl is-active --quiet "${name}.service"; then ok "Service ${name} is running"
  else err "Service ${name} failed.  Check: journalctl -u ${name} -n 30"; fi
}

remove_service() {
  systemctl disable --now "$1.service" >/dev/null 2>&1
  rm -f "/etc/systemd/system/$1.service"
  systemctl daemon-reload
  ok "Removed service $1"
}

# GitHub latest-release helper (checksum verified when published). Sets EXTRACT_DIR
fetch_release() { # repo regex
  local repo="$1" pat="$2" meta url digest tmp f got
  meta="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | jq -r --arg p "$pat" '[.assets[] | select(.browser_download_url | test($p))][0] | "\(.browser_download_url) \(.digest // "")"')"
  url="${meta%% *}"; digest="${meta#* }"
  if [[ -z $url || $url == null ]]; then
    err "No matching release asset in ${repo} (pattern: ${pat}) - GitHub API blocked or asset renamed"
    return 1
  fi
  msg "Downloading $url"
  tmp="$(mktemp -d)"; f="$tmp/pkg.${url##*.}"
  curl -fsSL --retry 3 -o "$f" "$(mirror_url "$url")" || { err "Download failed"; return 1; }
  if [[ $digest == sha256:* ]]; then
    got="$(sha256sum "$f" | awk '{print $1}')"
    if [[ "sha256:$got" != "$digest" ]]; then err "Checksum mismatch - aborting"; return 1; fi
    ok "SHA256 verified"
  else
    warn "No published checksum for this asset - verification skipped"
  fi
  case "$url" in
    *.zip) unzip -qo "$f" -d "$tmp" || { err "Extract failed"; return 1; } ;;
    *)     tar -xzf "$f" -C "$tmp"  || { err "Extract failed"; return 1; } ;;
  esac
  EXTRACT_DIR="$tmp"
}

install_bin() { # binary-name
  local f
  f="$(find "$EXTRACT_DIR" -type f -name "$1" | head -1)"
  [[ -n $f ]] || { err "Binary $1 not found in archive"; return 1; }
  install -m 755 "$f" "/usr/local/bin/$1" && ok "Installed /usr/local/bin/$1"
}

install_panel() { # "Display name" url [args...]
  local name="$1"; shift
  echo; msg "Installing: ${W}${name}${N}"
  if run_remote "$@"; then ok "${name} installer finished."
  else err "${name} installer exited with errors."; return 1; fi
}

self_install() {
  local src="${BASH_SOURCE[0]}"
  if [[ -f $src && $src != /dev/fd/* && $src != /proc/* ]]; then
    [[ $src -ef $BIN ]] || install -m 755 "$src" "$BIN"
  elif [[ $SELF_URL == http* ]]; then
    curl -fsSL "$SELF_URL" -o "$BIN" && chmod +x "$BIN"
  fi
  [[ -x $BIN ]] && ok "Command installed - from now on just type:  vpn"
}

self_update() {
  local tmp; tmp="$(mktemp)"
  [[ $SELF_URL == http* ]] || { err "No update URL configured"; return 1; }
  curl -fsSL "$SELF_URL" -o "$tmp" || { err "Update download failed"; return 1; }
  head -1 "$tmp" | grep -q '^#!/usr/bin/env bash' && bash -n "$tmp" || { err "Downloaded file looks invalid"; return 1; }
  install -m 755 "$tmp" "$BIN" && rm -f "$tmp" && ok "Updated to: $("$BIN" --version)"
}

#=====================================================================
#  Installers  (one function per target)
#=====================================================================
inst_3xui()       { install_panel "3X-UI" "$URL_3XUI"; }
inst_xui()        { install_panel "X-UI (alireza0)" "$URL_XUI_ALIREZA"; }
inst_marzban()    { install_panel "Marzban" "$URL_MARZBAN" install && msg "Create admin:  marzban cli admin create --sudo"; }
inst_marzneshin() { install_panel "Marzneshin" "$URL_MARZNESHIN" install; }
inst_pasarguard() { install_panel "PasarGuard" "$URL_PASARGUARD" install; }
inst_hiddify()    { install_panel "Hiddify Manager" "$URL_HIDDIFY"; }
inst_xray()       { install_panel "Xray-core" "$URL_XRAY" install; }
inst_singbox() {
  if [[ $PM == apt ]]; then install_panel "sing-box" "$URL_SINGBOX"
  else warn "sing-box deb installer needs Debian/Ubuntu"; return 1; fi
}

inst_wireguard() { install_panel "WireGuard (angristan)" "$URL_WG_ANGRISTAN"; }

inst_wgeasy() {
  ensure_docker || return 1
  local webport vpnport
  vpnport="$(ask "WireGuard UDP port" 51820)"
  webport="$(ask "Web panel TCP port" 51821)"
  check_port "$webport" "wg-easy web" || return 1
  docker rm -f wg-easy >/dev/null 2>&1
  mkdir -p /opt/wg-easy
  msg "Starting wg-easy container..."
  docker run -d --name wg-easy --restart unless-stopped \
    --cap-add NET_ADMIN --cap-add SYS_MODULE \
    --sysctl net.ipv4.ip_forward=1 \
    --sysctl net.ipv4.conf.all.src_valid_mark=1 \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
    --sysctl net.ipv6.conf.all.forwarding=1 \
    --sysctl net.ipv6.conf.default.forwarding=1 \
    -p "${vpnport}:51820/udp" -p "${webport}:51821/tcp" \
    -v /opt/wg-easy:/etc/wireguard \
    "$WG_EASY_IMAGE" || { err "Container failed to start"; return 1; }
  open_port "$vpnport" udp; open_port "$webport" tcp
  ok "wg-easy is up:  http://${SERVER_IP}:${webport}   (create the admin account on first visit)"
}

inst_ikev2() {
  echo "Installs IPsec/L2TP, Cisco IPsec and IKEv2 together (hwdsl2 setup)."
  echo "Credentials + IKEv2 client profile are printed at the end."
  confirm "Continue?" || return 0
  install_panel "IPsec / IKEv2 / L2TP" "$URL_IPSEC"
  open_port 500 udp; open_port 4500 udp
}

inst_openvpn() {
  if confirm "Use automatic defaults (no questions)?"; then export AUTO_INSTALL=y; fi
  install_panel "OpenVPN" "$URL_OVPN"
  unset AUTO_INSTALL
}

inst_hysteria2() {
  local port pass dir=/etc/hysteria
  port="$(ask "Hysteria2 UDP port" 443)"
  check_port "$port" "Hysteria2 (UDP)" || return 1
  run_remote "$URL_HY2" || return 1
  pass="$(rand 12)"
  mkdir -p "$dir"
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$dir/server.key" -out "$dir/server.crt" \
    -subj "/CN=www.bing.com" -days 3650 2>/dev/null
  cat > "$dir/config.yaml" <<EOF
listen: :${port}

tls:
  cert: ${dir}/server.crt
  key: ${dir}/server.key

auth:
  type: password
  password: ${pass}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF
  id hysteria >/dev/null 2>&1 && chown -R hysteria:hysteria "$dir"
  systemctl enable --now hysteria-server.service >/dev/null 2>&1
  systemctl restart hysteria-server.service
  open_port "$port" udp
  if systemctl is-active --quiet hysteria-server.service; then
    ok "Hysteria2 is running."
    echo "  Client link (self-signed cert, so insecure=1):"
    echo "  ${W}hy2://${pass}@${SERVER_IP}:${port}/?insecure=1&sni=www.bing.com#Hysteria2${N}"
  else
    err "Hysteria2 failed.  Check: journalctl -u hysteria-server -n 30"
  fi
}

#---------------------------------------------------------------------
#  Tunnels
#---------------------------------------------------------------------
save_iptables() {
  if [[ $PM == apt ]]; then
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    pkg_install iptables-persistent >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
  else
    pkg_install iptables-services >/dev/null 2>&1
    systemctl enable iptables >/dev/null 2>&1
    service iptables save >/dev/null 2>&1
  fi
}

inst_iptables() {
  local rip lp rp dest proto
  rip="$(ask "Remote (destination) server IP")"
  lp="$(ask "Local port to forward (e.g. 443 or range 2000:3000)")"
  rp="$(ask "Remote port (ignored for ranges)" "${lp}")"
  [[ -n $rip && -n $lp ]] || { err "IP and port are required"; return 1; }
  if [[ $lp == *:* ]]; then dest="$rip"; else dest="${rip}:${rp}"; fi
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-forward.conf
  for proto in tcp udp; do
    iptables -t nat -C PREROUTING -p $proto --dport "$lp" -j DNAT --to-destination "$dest" 2>/dev/null \
      || iptables -t nat -A PREROUTING -p $proto --dport "$lp" -j DNAT --to-destination "$dest"
  done
  iptables -t nat -C POSTROUTING -d "$rip" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -d "$rip" -j MASQUERADE
  save_iptables
  open_port "$lp" tcp; open_port "$lp" udp
  ok "Forwarding (TCP+UDP) :${lp}  ->  ${dest}   (rules saved)"
}

inst_socat() {
  local rip lp rp
  pkg_install socat >/dev/null 2>&1
  rip="$(ask "Remote (destination) server IP")"
  lp="$(ask "Local TCP port")"
  rp="$(ask "Remote port" "${lp}")"
  [[ -n $rip && -n $lp ]] || { err "IP and port are required"; return 1; }
  check_port "$lp" "socat" || return 1
  mk_service "socat-${lp}" "socat forward ${lp} -> ${rip}:${rp}" \
    "$(command -v socat) TCP-LISTEN:${lp},fork,reuseaddr TCP:${rip}:${rp}"
  open_port "$lp" tcp
}

inst_gost() {
  local rip lp rp
  fetch_release go-gost/gost "linux_${ARCH}\.tar\.gz$" || return 1
  install_bin gost || return 1
  rip="$(ask "Remote (destination) server IP")"
  lp="$(ask "Local TCP port")"
  rp="$(ask "Remote port" "${lp}")"
  [[ -n $rip && -n $lp ]] || { err "IP and port are required"; return 1; }
  check_port "$lp" "GOST" || return 1
  mk_service "gost-${lp}" "GOST forward ${lp} -> ${rip}:${rp}" \
    "/usr/local/bin/gost -L tcp://:${lp}/${rip}:${rp}"
  open_port "$lp" tcp
}

inst_frp() {
  local role token bp sip lp rp
  fetch_release fatedier/frp "linux_${ARCH}\.tar\.gz$" || return 1
  install_bin frps; install_bin frpc
  mkdir -p /etc/frp
  role="$(ask "Role: 1) server (frps)   2) client (frpc)" 1)"
  token="$(ask "Shared auth token (same on both sides)" "$(rand 8)")"
  if [[ $role == 1 ]]; then
    bp="$(ask "frps bind port" 7000)"
    cat > /etc/frp/frps.toml <<EOF
bindAddr = "0.0.0.0"
bindPort = ${bp}
auth.method = "token"
auth.token = "${token}"
EOF
    mk_service frps "frp server" "/usr/local/bin/frps -c /etc/frp/frps.toml"
    open_port "$bp" tcp
    ok "frps ready.  Token: ${token}   (also open the remote ports you will expose)"
  else
    sip="$(ask "frps server IP")"
    bp="$(ask "frps bind port" 7000)"
    lp="$(ask "Local service port on THIS machine")"
    rp="$(ask "Port to expose on the frps server" "${lp}")"
    cat > /etc/frp/frpc.toml <<EOF
serverAddr = "${sip}"
serverPort = ${bp}
auth.method = "token"
auth.token = "${token}"

[[proxies]]
name = "tunnel-${lp}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${lp}
remotePort = ${rp}
EOF
    mk_service frpc "frp client" "/usr/local/bin/frpc -c /etc/frp/frpc.toml"
  fi
}

inst_backhaul() {
  local role token bp sip lp
  fetch_release Musixal/Backhaul "linux_${ARCH}\.tar\.gz$" || return 1
  install_bin backhaul || return 1
  mkdir -p /etc/backhaul
  msg "The side with a reachable public IP should be the SERVER."
  role="$(ask "Role: 1) server   2) client" 1)"
  token="$(ask "Shared token" "$(rand 8)")"
  bp="$(ask "Tunnel port (server listens / client connects)" 3080)"
  if [[ $role == 1 ]]; then
    lp="$(ask "Port to expose on this server (forwarded through the tunnel)" 443)"
    cat > /etc/backhaul/config.toml <<EOF
[server]
bind_addr = "0.0.0.0:${bp}"
transport = "tcp"
token = "${token}"
log_level = "info"
ports = ["${lp}=${lp}"]
EOF
    open_port "$bp" tcp; open_port "$lp" tcp
  else
    sip="$(ask "Backhaul server IP")"
    cat > /etc/backhaul/config.toml <<EOF
[client]
remote_addr = "${sip}:${bp}"
transport = "tcp"
token = "${token}"
log_level = "info"
EOF
  fi
  mk_service backhaul "Backhaul tunnel" "/usr/local/bin/backhaul -c /etc/backhaul/config.toml"
  ok "Token: ${token}"
}

inst_rathole() {
  local pat role token bp sip lp
  if [[ $ARCH == arm64 ]]; then pat='aarch64-unknown-linux-musl\.zip$'
  else pat='x86_64-unknown-linux-gnu\.zip$'; fi
  fetch_release rapiz1/rathole "$pat" || return 1
  install_bin rathole || return 1
  mkdir -p /etc/rathole
  msg "The side with a reachable public IP should be the SERVER."
  role="$(ask "Role: 1) server   2) client" 1)"
  token="$(ask "Shared token" "$(rand 8)")"
  bp="$(ask "Control port" 2333)"
  lp="$(ask "Service port (exposed on server / local port on client)" 443)"
  if [[ $role == 1 ]]; then
    cat > /etc/rathole/config.toml <<EOF
[server]
bind_addr = "0.0.0.0:${bp}"
default_token = "${token}"

[server.services.svc${lp}]
type = "tcp"
bind_addr = "0.0.0.0:${lp}"
EOF
    open_port "$bp" tcp; open_port "$lp" tcp
  else
    sip="$(ask "Rathole server IP")"
    cat > /etc/rathole/config.toml <<EOF
[client]
remote_addr = "${sip}:${bp}"
default_token = "${token}"

[client.services.svc${lp}]
type = "tcp"
local_addr = "127.0.0.1:${lp}"
EOF
  fi
  mk_service rathole "Rathole tunnel" "/usr/local/bin/rathole /etc/rathole/config.toml"
  ok "Token: ${token}"
}

inst_chisel() {
  local role user pass bp sip lp
  run_remote "$URL_CHISEL" || return 1
  command -v chisel >/dev/null 2>&1 || { err "chisel binary not found after install"; return 1; }
  role="$(ask "Role: 1) server   2) client" 1)"
  user="$(ask "Auth user" tunnel)"
  pass="$(ask "Auth password" "$(rand 6)")"
  bp="$(ask "Chisel server port" 8080)"
  if [[ $role == 1 ]]; then
    mk_service chisel-server "Chisel server" \
      "$(command -v chisel) server --port ${bp} --reverse --auth ${user}:${pass}"
    open_port "$bp" tcp
    ok "Server ready.  Auth: ${user}:${pass}"
  else
    sip="$(ask "Chisel server IP")"
    lp="$(ask "Port to expose (same port local and on server)")"
    mk_service chisel-client "Chisel client" \
      "$(command -v chisel) client --auth ${user}:${pass} ${sip}:${bp} R:${lp}:127.0.0.1:${lp}"
  fi
}

inst_cloudflared() {
  if [[ $PM != apt ]]; then warn "This helper supports Debian/Ubuntu only"; return 1; fi
  curl -fsSL -o /tmp/cloudflared.deb \
    "$(mirror_url "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb")" \
    || { err "Download failed"; return 1; }
  dpkg -i /tmp/cloudflared.deb && rm -f /tmp/cloudflared.deb
  local token
  token="$(ask "Cloudflare Tunnel token (from Zero Trust dashboard)")"
  [[ -n $token ]] || { err "Token required"; return 1; }
  cloudflared service install "$token" && ok "cloudflared tunnel service installed"
}

#---------------------------------------------------------------------
#  Server tools
#---------------------------------------------------------------------
ssh_port() {
  local p
  p="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')"
  echo "${p:-22}"
}

inst_bbr() {
  cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null 2>&1
  ok "Congestion control now: $(sysctl -n net.ipv4.tcp_congestion_control)"
}

inst_docker() { ensure_docker && ok "Docker ready"; }

inst_firewall() {
  if [[ $PM != apt ]]; then warn "Firewall helper supports Debian/Ubuntu (ufw) only"; return 1; fi
  pkg_install ufw >/dev/null 2>&1
  local sp extra p
  sp="$(ssh_port)"
  extra="$(ask "Extra ports to allow (space separated, e.g. 8443 2053)" "")"
  ufw allow "${sp}/tcp" >/dev/null
  for p in 80 443 $extra; do ufw allow "$p" >/dev/null; done
  ok "Allowed: SSH ${sp}/tcp, 80, 443 ${extra}"
  warn "Panel ports chosen later by installers are opened automatically when ufw is active."
  if confirm "Enable the firewall now? (SSH port ${sp} is allowed)"; then
    ufw --force enable >/dev/null && ok "ufw enabled"
  fi
}

inst_fail2ban() {
  local sp; sp="$(ssh_port)"
  pkg_install fail2ban >/dev/null 2>&1 || { err "fail2ban install failed"; return 1; }
  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = ${sp}
maxretry = 5
findtime = 10m
bantime = 1h
EOF
  systemctl enable --now fail2ban >/dev/null 2>&1
  systemctl restart fail2ban
  ok "fail2ban protecting SSH (port ${sp}): 5 failures -> 1h ban"
}

inst_swap() {
  if [[ -n "$(swapon --show --noheadings 2>/dev/null)" ]]; then
    ok "Swap already active:"; swapon --show; return 0
  fi
  local size; size="$(ask "Swap size" 1G)"
  fallocate -l "$size" /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null \
    && swapon /swapfile && echo "/swapfile none swap sw 0 0" >> /etc/fstab \
    && ok "Swap ${size} enabled" || err "Swap creation failed"
}

#---------------------------------------------------------------------
#  Status / uninstall
#---------------------------------------------------------------------
show_status() {
  local e u l st f
  local units=("x-ui|3X-UI / X-UI" "marzban|Marzban" "marzneshin|Marzneshin" "pasarguard|PasarGuard"
    "wg-quick@wg0|WireGuard (wg0)" "openvpn-server@server|OpenVPN" "openvpn|OpenVPN" "ipsec|IPsec"
    "xl2tpd|L2TP" "hysteria-server|Hysteria2" "xray|Xray" "sing-box|sing-box"
    "frps|frp server" "frpc|frp client" "backhaul|Backhaul" "rathole|Rathole" "cloudflared|Cloudflare Tunnel"
    "fail2ban|fail2ban")
  echo "${W}=== Installed services ===${N}"
  for e in "${units[@]}"; do
    u="${e%%|*}"; l="${e##*|}"
    if systemctl cat "$u.service" >/dev/null 2>&1; then
      st="$(systemctl is-active "$u.service")"
      if [[ $st == active ]]; then printf "  %-26s ${G}%s${N}\n" "$l" "$st"
      else printf "  %-26s ${R}%s${N}\n" "$l" "$st"; fi
    fi
  done
  for f in /etc/systemd/system/{socat-,gost-,chisel-}*.service; do
    [[ -f $f ]] || continue
    u="$(basename "$f" .service)"; st="$(systemctl is-active "$u.service")"
    printf "  %-26s %s\n" "$u" "$st"
  done
  if command -v docker >/dev/null 2>&1; then
    echo; echo "${W}Docker containers:${N}"
    docker ps --format '  {{.Names}}\t{{.Status}}' 2>/dev/null
  fi
  echo; echo "${W}Listening ports:${N}"
  ss -tulpn 2>/dev/null | awk 'NR==1 || /LISTEN|UNCONN/' | head -40
}

remove_tunnel_service() {
  local units=() f i choice
  for f in /etc/systemd/system/{socat-,gost-,chisel-}*.service \
           /etc/systemd/system/{frps,frpc,backhaul,rathole}.service; do
    [[ -f $f ]] && units+=("$(basename "$f" .service)")
  done
  if [[ ${#units[@]} -eq 0 ]]; then warn "No tunnel services found"; return 0; fi
  for i in "${!units[@]}"; do echo " $((i+1))) ${units[$i]}"; done
  read -rp "Remove which one (number, Enter to cancel): " choice
  [[ $choice =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#units[@]} ]] || return 0
  remove_service "${units[$((choice-1))]}"
}

remove_iptables_rule() {
  iptables -t nat -L PREROUTING -n --line-numbers
  local n; read -rp "Rule number to delete (Enter to cancel): " n
  [[ $n =~ ^[0-9]+$ ]] || return 0
  iptables -t nat -D PREROUTING "$n" && save_iptables && ok "Rule deleted and saved"
}

menu_uninstall() {
  while true; do
    clear
    echo "${W}=== Uninstall / remove ===${N}"
    echo " 1) 3X-UI / X-UI       (x-ui uninstall)"
    echo " 2) Marzban"
    echo " 3) Marzneshin"
    echo " 4) PasarGuard"
    echo " 5) wg-easy            (deletes clients too)"
    echo " 6) Hysteria2"
    echo " 7) Xray-core"
    echo " 8) sing-box"
    echo " 9) A tunnel service   (socat/gost/frp/backhaul/rathole/chisel)"
    echo "10) An iptables forward rule"
    echo " 0) Back"
    echo "(WireGuard / OpenVPN / IKEv2: re-run their installer, it offers removal)"
    read -rp "Select: " c
    case $c in
      1) command -v x-ui >/dev/null && x-ui uninstall || warn "x-ui not found"; pause ;;
      2) command -v marzban >/dev/null && marzban uninstall || warn "marzban not found"; pause ;;
      3) command -v marzneshin >/dev/null && marzneshin uninstall || warn "marzneshin not found"; pause ;;
      4) command -v pasarguard >/dev/null && pasarguard uninstall || warn "pasarguard not found"; pause ;;
      5) if confirm "Remove wg-easy and ALL its clients?"; then
           docker rm -f wg-easy >/dev/null 2>&1; rm -rf /opt/wg-easy; ok "wg-easy removed"; fi; pause ;;
      6) run_remote "$URL_HY2" --remove; rm -rf /etc/hysteria; pause ;;
      7) run_remote "$URL_XRAY" remove; pause ;;
      8) if [[ $PM == apt ]]; then apt-get remove -y sing-box; else warn "Not installed via apt"; fi; pause ;;
      9) remove_tunnel_service; pause ;;
     10) remove_iptables_rule; pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

#=====================================================================
#  Menus
#=====================================================================
menu_v2ray() {
  while true; do
    clear
    echo "${W}=== V2Ray / Xray panels (VMess / VLESS / Trojan / Reality) ===${N}"
    echo " 1) 3X-UI        (MHSanaei - most popular, multi-protocol)"
    echo " 2) X-UI         (alireza0)"
    echo " 3) Marzban      (multi-user, API, Docker)"
    echo " 4) Marzneshin   (multi-node Marzban successor)"
    echo " 5) PasarGuard   (Marzban fork)"
    echo " 6) Hiddify Manager (all-in-one: Reality, Hysteria, TUIC, WireGuard...)"
    echo " 7) Xray-core only (no panel)"
    echo " 8) sing-box only  (no panel, Debian/Ubuntu)"
    echo " 0) Back"
    read -rp "Select: " c
    case $c in
      1) inst_3xui; pause ;;
      2) inst_xui; pause ;;
      3) inst_marzban; pause ;;
      4) inst_marzneshin; pause ;;
      5) inst_pasarguard; pause ;;
      6) inst_hiddify; pause ;;
      7) inst_xray; pause ;;
      8) inst_singbox; pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

menu_wireguard() {
  while true; do
    clear
    echo "${W}=== WireGuard ===${N}"
    echo " 1) wg-easy   (web panel, Docker)"
    echo " 2) WireGuard CLI installer (angristan - add/remove clients from menu)"
    echo " 0) Back"
    read -rp "Select: " c
    case $c in
      1) inst_wgeasy; pause ;;
      2) inst_wireguard; pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

menu_hy2() {
  clear
  echo "${W}=== Hysteria2 / cores ===${N}"
  echo " 1) Hysteria2 server - fully automatic config + client link"
  echo " 2) Xray-core only"
  echo " 3) sing-box only (Debian/Ubuntu)"
  echo " 0) Back"
  read -rp "Select: " c
  case $c in
    1) inst_hysteria2; pause ;;
    2) inst_xray; pause ;;
    3) inst_singbox; pause ;;
    *) ;;
  esac
}

menu_tunnels() {
  while true; do
    clear
    echo "${W}=== Tunnels (optional) ===${N}"
    echo " 1) iptables port forward (TCP+UDP, persistent)"
    echo " 2) socat forward (TCP, systemd service)"
    echo " 3) GOST forward (TCP, systemd service)"
    echo " 4) frp      (reverse tunnel, server/client)"
    echo " 5) Backhaul (reverse tunnel, server/client)"
    echo " 6) Rathole  (reverse tunnel, server/client)"
    echo " 7) Chisel   (reverse tunnel over HTTP, server/client)"
    echo " 8) Cloudflare Tunnel (cloudflared)"
    echo " 0) Back"
    read -rp "Select: " c
    case $c in
      1) inst_iptables; pause ;;
      2) inst_socat; pause ;;
      3) inst_gost; pause ;;
      4) inst_frp; pause ;;
      5) inst_backhaul; pause ;;
      6) inst_rathole; pause ;;
      7) inst_chisel; pause ;;
      8) inst_cloudflared; pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

menu_tools() {
  while true; do
    clear
    echo "${W}=== Server tools ===${N}"
    echo " 1) Enable BBR (faster TCP)"
    echo " 2) Install Docker"
    echo " 3) Firewall (ufw: SSH + 80/443 + extras)"
    echo " 4) fail2ban (SSH brute-force protection)"
    echo " 5) Create swap file"
    echo " 6) Show listening ports"
    echo " 7) Update system packages"
    echo " 0) Back"
    read -rp "Select: " c
    case $c in
      1) inst_bbr; pause ;;
      2) inst_docker; pause ;;
      3) inst_firewall; pause ;;
      4) inst_fail2ban; pause ;;
      5) inst_swap; pause ;;
      6) ss -tulpn; pause ;;
      7) if [[ $PM == apt ]]; then apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
         else "$PM" -y update; fi; pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

main_menu() {
  while true; do
    clear
    echo "${W}=======================================${N}"
    echo "${W}   VPN Panel Auto Installer  v${VERSION}   ${N}"
    echo "${W}=======================================${N}"
    echo "  Server IP: ${SERVER_IP}   Mirror: ${GH_MIRROR:-off}"
    echo
    echo " 1) V2Ray / Xray panels  (3X-UI, Marzban, Hiddify, ...)"
    echo " 2) WireGuard            (wg-easy, CLI)"
    echo " 3) IKEv2 / IPsec / L2TP"
    echo " 4) OpenVPN"
    echo " 5) Hysteria2 / Xray / sing-box cores"
    echo " 6) Tunnels              (iptables, frp, Backhaul, Rathole, ...)"
    echo " 7) Server tools         (BBR, firewall, fail2ban, swap, ...)"
    echo " 8) Status of installed services"
    echo " 9) Uninstall / remove"
    echo " m) GitHub mirror settings"
    echo " u) Update this script"
    echo " 0) Exit"
    echo
    read -rp "Select: " c
    case $c in
      1) menu_v2ray ;;
      2) menu_wireguard ;;
      3) inst_ikev2; pause ;;
      4) inst_openvpn; pause ;;
      5) menu_hy2 ;;
      6) menu_tunnels ;;
      7) menu_tools ;;
      8) show_status; pause ;;
      9) menu_uninstall ;;
      m|M) menu_mirror ;;
      u|U) self_update; pause ;;
      0) echo "Bye."; exit 0 ;;
      *) ;;
    esac
  done
}

#=====================================================================
#  Dispatcher
#=====================================================================
run_target() {
  case "$1" in
    3xui) inst_3xui ;;           xui) inst_xui ;;
    marzban) inst_marzban ;;     marzneshin) inst_marzneshin ;;
    pasarguard) inst_pasarguard ;; hiddify) inst_hiddify ;;
    xray) inst_xray ;;           singbox|sing-box) inst_singbox ;;
    hysteria2|hy2) inst_hysteria2 ;;
    wg-easy|wgeasy) inst_wgeasy ;; wireguard|wg) inst_wireguard ;;
    ikev2|ipsec|l2tp) inst_ikev2 ;; openvpn|ovpn) inst_openvpn ;;
    iptables) inst_iptables ;;   socat) inst_socat ;;
    gost) inst_gost ;;           frp) inst_frp ;;
    backhaul) inst_backhaul ;;   rathole) inst_rathole ;;
    chisel) inst_chisel ;;       cloudflared) inst_cloudflared ;;
    bbr) inst_bbr ;;             docker) inst_docker ;;
    firewall|ufw) inst_firewall ;; fail2ban) inst_fail2ban ;;
    swap) inst_swap ;;
    *) err "Unknown target: $1"; usage; return 1 ;;
  esac
}

run_targets() {
  local arr t
  IFS=',' read -ra arr <<< "$1"
  [[ ${#arr[@]} -gt 0 ]] || { err "No target given"; usage; return 1; }
  for t in "${arr[@]}"; do msg "=== Target: $t ==="; run_target "$t"; done
}

main() {
  parse_args "$@"
  need_root
  detect_system
  [[ -f $CONF ]] && . "$CONF"
  case $MODE in
    mirror) set_mirror "$MIRROR_ARG"; exit 0 ;;
    update) self_update; exit $? ;;
  esac
  install_deps
  [[ -x $BIN ]] || self_install
  case $MODE in
    install) run_targets "$TARGETS" ;;
    status)  show_status ;;
    menu)
      [[ -t 0 ]] || { err "The menu needs a terminal. Run:  bash <(curl -Ls $SELF_URL)"; exit 1; }
      main_menu ;;
  esac
}

main "$@"