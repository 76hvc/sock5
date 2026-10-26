#!/usr/bin/env bash
#
# socks5-install.sh — gost SOCKS5 + HTTP 代理一键部署脚本
#
# 运行后自动生成：随机用户名 / 随机密码 / 未被占用的随机端口，
# 同时开 SOCKS5 与 HTTP 代理，并直接输出两条可用连接串。
#
# 用法:
#   bash socks5-install.sh                 # 全自动：随机账号 + 随机空闲端口（SOCKS5 + HTTP）
#   bash socks5-install.sh --port 1080     # 指定 SOCKS5 端口
#   bash socks5-install.sh --http-port 8080
#   bash socks5-install.sh --no-http       # 只开 SOCKS5
#   bash socks5-install.sh --user u --pass p
#   bash socks5-install.sh --status        # 查看当前状态
#   bash socks5-install.sh --url           # 只打印连接串
#   bash socks5-install.sh --uninstall     # 卸载
#
# 支持: Debian / Ubuntu / CentOS / RHEL / Rocky / Alma / Fedora / Arch
# 架构: amd64 / arm64 / armv7 / armv6 / 386
#
set -euo pipefail

# ------------------------------------------------------------------ 常量
SERVICE_NAME="gost-socks5"
BIN_PATH="/usr/local/bin/gost"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
STATE_PATH="/etc/${SERVICE_NAME}.env"
PORT_MIN=20000
PORT_MAX=65000
FALLBACK_VER="3.3.1"

# ------------------------------------------------------------------ 输出
if [ -t 1 ]; then
  CR=$'\033[0m'; CG=$'\033[32m'; CY=$'\033[33m'; CC=$'\033[36m'; CE=$'\033[31m'; CB=$'\033[1m'
else
  CR=""; CG=""; CY=""; CC=""; CE=""; CB=""
fi
info() { printf '%s[*]%s %s\n' "$CC" "$CR" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$CG" "$CR" "$*"; }
warn() { printf '%s[!]%s %s\n' "$CY" "$CR" "$*"; }
die()  { printf '%s[x]%s %s\n' "$CE" "$CR" "$*" >&2; exit 1; }
hr()   { printf '%s%s%s\n' "$CC" "--------------------------------------------------------------" "$CR"; }

usage() {
  cat <<'EOT'
socks5-install.sh — gost SOCKS5 + HTTP 代理一键部署

运行后自动生成随机用户名、随机密码、未被占用的随机端口，
同时开 SOCKS5 与 HTTP 代理，并直接输出两条连接串。

用法:
  bash socks5-install.sh                 全自动：随机账号 + 随机空闲端口（双协议）
  bash socks5-install.sh --port 1080     指定 SOCKS5 端口（账号仍随机）
  bash socks5-install.sh --http-port 8080  指定 HTTP 代理端口
  bash socks5-install.sh --no-http       只开 SOCKS5，不开 HTTP
  bash socks5-install.sh --user u --pass p
  bash socks5-install.sh --status        查看当前状态 / 两条连接串
  bash socks5-install.sh --url           只打印连接串
  bash socks5-install.sh --uninstall     卸载（服务 + 二进制 + 凭据）

环境变量:
  GITHUB_MIRROR   自定义 gost 下载加速前缀，例如 https://ghfast.top/

支持: Debian / Ubuntu / CentOS / RHEL / Rocky / Alma / Fedora / Arch
架构: amd64 / arm64 / armv7 / armv6 / 386
EOT
  exit 0
}

# ------------------------------------------------------------------ 参数
WANT_PORT=""; WANT_HTTP_PORT=""; WANT_USER=""; WANT_PASS=""
ACTION="install"; ENABLE_HTTP=1
while [ $# -gt 0 ]; do
  case "$1" in
    --port)                WANT_PORT="${2:-}"; shift 2 ;;
    --port=*)              WANT_PORT="${1#*=}"; shift ;;
    --http-port)           WANT_HTTP_PORT="${2:-}"; shift 2 ;;
    --http-port=*)         WANT_HTTP_PORT="${1#*=}"; shift ;;
    --no-http|--socks-only) ENABLE_HTTP=0; shift ;;
    --user)                WANT_USER="${2:-}"; shift 2 ;;
    --user=*)              WANT_USER="${1#*=}"; shift ;;
    --pass|--password)     WANT_PASS="${2:-}"; shift 2 ;;
    --pass=*|--password=*) WANT_PASS="${1#*=}"; shift ;;
    --uninstall|uninstall) ACTION="uninstall"; shift ;;
    --status|status)       ACTION="status"; shift ;;
    --url|url)             ACTION="url"; shift ;;
    -h|--help|help)        usage ;;
    *) die "未知参数: $1  （用 --help 看用法）" ;;
  esac
done

# ------------------------------------------------------------------ 随机生成
rand_user() {
  local s=""
  s=$(openssl rand -base64 18 2>/dev/null | tr -dc 'a-z0-9' | cut -c1-8 || true)
  [ -n "$s" ] || s=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-8)
  printf 's5%s' "$s"
}

rand_pass() {
  local s=""
  s=$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-20 || true)
  [ -n "$s" ] || s=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-20)
  printf '%s' "$s"
}

# ------------------------------------------------------------------ 端口检测
# 惰性探测一次，选一个可用后端，避免每条命令都重试慢路径。
#   python  —— 真实 bind 测试，最准（同时测 IPv4/IPv6）
#   ss      —— 解析监听表，快
#   netstat —— 老系统兜底
#   lsof    —— 再兜底
#   bash    —— /dev/tcp 连一下，能连上就算占用
PORT_BACKEND=""

init_port_backend() {
  [ -n "$PORT_BACKEND" ] && return 0
  PORT_BACKEND="none"

  if command -v python3 >/dev/null 2>&1; then
    if timeout 5 python3 -c 'import socket' >/dev/null 2>&1; then
      PORT_BACKEND="python"
      return 0
    fi
  fi
  if command -v ss >/dev/null 2>&1 && ss -lnt >/dev/null 2>&1; then
    PORT_BACKEND="ss"
    return 0
  fi
  if command -v netstat >/dev/null 2>&1 && netstat -lnt >/dev/null 2>&1; then
    PORT_BACKEND="netstat"
    return 0
  fi
  if command -v lsof >/dev/null 2>&1; then
    PORT_BACKEND="lsof"
    return 0
  fi
  PORT_BACKEND="bash"
}

port_free() {
  local p="$1"
  init_port_backend

  case "$PORT_BACKEND" in
    python)
      if timeout 5 python3 - "$p" >/dev/null 2>&1 <<'PY'
import socket, sys
port = int(sys.argv[1])
try:
    s4 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s4.bind(("0.0.0.0", port))
    s4.close()
except OSError:
    sys.exit(1)
try:
    s6 = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    s6.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    s6.bind(("::", port))
    s6.close()
except OSError:
    pass          # 无 IPv6 栈不算占用
sys.exit(0)
PY
      then
        return 0
      fi
      return 1
      ;;
    ss)
      if ss -lntu 2>/dev/null | awk 'NR>1{print $5}' | grep -qE "[:.]${p}$"; then
        return 1
      fi
      return 0
      ;;
    netstat)
      if netstat -lntu 2>/dev/null | awk 'NR>2{print $4}' | grep -qE "[:.]${p}$"; then
        return 1
      fi
      return 0
      ;;
    lsof)
      if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
        return 1
      fi
      return 0
      ;;
    *)
      if (exec 3<>/dev/tcp/127.0.0.1/"$p") >/dev/null 2>&1; then
        return 1
      fi
      return 0
      ;;
  esac
}

# pick_port [已占用的端口列表]
# 排除列表用来避免 SOCKS5 和 HTTP 挑到同一个端口（两者都还没真正监听，检测不到）。
pick_port() {
  local exclude="${1:-}" span seed p i
  span=$(( PORT_MAX - PORT_MIN ))
  seed=$(( (RANDOM * 32768 + RANDOM) % span ))
  for (( i = 1; i <= 500; i++ )); do
    p=$(( PORT_MIN + (seed + i) % span ))
    case " ${exclude} " in *" ${p} "*) continue ;; esac
    if port_free "$p"; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# ------------------------------------------------------------------ 系统探测
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)   echo "amd64" ;;
    aarch64|arm64)  echo "arm64" ;;
    armv7l|armv7)   echo "armv7" ;;
    armv6l|armv6)   echo "armv6" ;;
    i386|i686)      echo "386" ;;
    *)              uname -m ;;
  esac
}

ensure_deps() {
  local missing=""
  for c in curl tar; do
    command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
  done
  [ -z "$missing" ] && return 0

  info "安装依赖:$missing"
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing >/dev/null 2>&1 || die "依赖安装失败:$missing"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q $missing >/dev/null 2>&1 || die "依赖安装失败:$missing"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q $missing >/dev/null 2>&1 || die "依赖安装失败:$missing"
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache $missing >/dev/null 2>&1 || die "依赖安装失败:$missing"
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm $missing >/dev/null 2>&1 || die "依赖安装失败:$missing"
  else
    die "无法自动安装依赖:$missing"
  fi
}

# ------------------------------------------------------------------ gost 安装
latest_version() {
  local v=""
  if command -v curl >/dev/null 2>&1; then
    v=$(curl -fsSL --max-time 20 https://api.github.com/repos/go-gost/gost/releases/latest 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' \
        | head -n1 || true)
  fi
  case "$v" in
    ''|*[!0-9.]*) v="$FALLBACK_VER" ;;
  esac
  printf '%s' "$v"
}

fetch_url() {
  local url="$1" out="$2" m
  # 自定义镜像优先
  if [ -n "${GITHUB_MIRROR:-}" ]; then
    m="${GITHUB_MIRROR%/}"
    curl -fsSL --max-time 180 -o "$out" "${m}/${url}" 2>/dev/null && return 0
    warn "自定义镜像 ${GITHUB_MIRROR} 失败，回退直连..."
  fi
  curl -fsSL --max-time 180 -o "$out" "$url" 2>/dev/null && return 0
  warn "GitHub 直连失败，尝试加速镜像..."
  curl -fsSL --max-time 180 -o "$out" "https://ghfast.top/${url}" 2>/dev/null && return 0
  curl -fsSL --max-time 180 -o "$out" "https://gh-proxy.com/${url}" 2>/dev/null && return 0
  curl -fsSL --max-time 180 -o "$out" "https://ghproxy.net/${url}" 2>/dev/null && return 0
  return 1
}

install_gost() {
  if [ -x "$BIN_PATH" ] && "$BIN_PATH" -V >/dev/null 2>&1; then
    ok "已安装 gost: $("$BIN_PATH" -V 2>&1 | head -n1)"
    return 0
  fi
  if command -v gost >/dev/null 2>&1 && gost -V >/dev/null 2>&1; then
    local p; p=$(command -v gost)
    install -m 755 "$p" "$BIN_PATH"
    ok "复用已有 gost: $("$BIN_PATH" -V 2>&1 | head -n1)"
    return 0
  fi

  local arch ver url tmp
  arch=$(detect_arch)
  ver=$(latest_version)
  url="https://github.com/go-gost/gost/releases/download/v${ver}/gost_${ver}_linux_${arch}.tar.gz"
  tmp=$(mktemp -d)

  info "下载 gost v${ver} (linux/${arch})"
  fetch_url "$url" "${tmp}/gost.tar.gz" || die "gost 下载失败，请检查网络或手动上传二进制到 ${BIN_PATH}"

  tar -xzf "${tmp}/gost.tar.gz" -C "$tmp" gost 2>/dev/null \
    || tar -xzf "${tmp}/gost.tar.gz" -C "$tmp" 2>/dev/null \
    || die "gost 解压失败"

  [ -f "${tmp}/gost" ] || die "压缩包内未找到 gost 可执行文件"
  install -m 755 "${tmp}/gost" "$BIN_PATH"
  rm -rf "$tmp"
  ok "gost 已安装: $("$BIN_PATH" -V 2>&1 | head -n1)"
}

# ------------------------------------------------------------------ 公网 IP
public_ip() {
  local ip=""
  local u
  for u in https://api.ipify.org https://ifconfig.me/ip https://ipinfo.io/ip https://api.ip.sb/ip; do
    ip=$(curl -fsS --max-time 6 "$u" 2>/dev/null | tr -d '[:space:]' || true)
    case "$ip" in
      '') continue ;;
      *[!0-9a-fA-F:.]*) continue ;;
    esac
    printf '%s' "$ip"
    return 0
  done
  ip=$(curl -fsS --max-time 4 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null | tr -d '[:space:]' || true)
  case "$ip" in
    ''|*[!0-9a-fA-F:.]*) ip="<你的服务器公网IP>" ;;
  esac
  printf '%s' "$ip"
}

# ------------------------------------------------------------------ 状态文件
save_state() {
  umask 077
  cat >"$STATE_PATH" <<EOF
S5_USER=${S5_USER}
S5_PASS=${S5_PASS}
S5_PORT=${S5_PORT}
S5_HTTP_PORT=${S5_HTTP_PORT:-}
S5_SERVICE=${SERVICE_NAME}
EOF
  chmod 600 "$STATE_PATH"
}

load_state() {
  [ -f "$STATE_PATH" ] || return 1
  # 先清空，避免读到上一次运行残留的值（尤其是旧版状态文件没有 S5_HTTP_PORT）
  S5_USER=""; S5_PASS=""; S5_PORT=""; S5_HTTP_PORT=""; S5_SERVICE=""
  # shellcheck disable=SC1090
  . "$STATE_PATH"
  S5_HTTP_PORT="${S5_HTTP_PORT:-}"
  [ -n "${S5_USER:-}" ] && [ -n "${S5_PASS:-}" ] && [ -n "${S5_PORT:-}" ]
}

# ------------------------------------------------------------------ 防火墙
open_firewall() {
  local p="$1"
  [ -n "$p" ] || return 0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
    ufw allow "${p}/tcp" >/dev/null 2>&1 && ok "ufw 已放行 ${p}/tcp" || warn "ufw 放行 ${p}/tcp 失败"
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    ok "firewalld 已放行 ${p}/tcp"
  fi
  if command -v iptables >/dev/null 2>&1; then
    if ! iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null; then
      iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || true
    fi
  fi
}

# ------------------------------------------------------------------ 自检
# 返回出口 IP；失败返回空
self_test_socks() {
  local out=""
  out=$(curl -fsS --max-time 12 \
        -x "socks5h://${S5_USER}:${S5_PASS}@127.0.0.1:${S5_PORT}" \
        https://api.ipify.org 2>/dev/null || true)
  case "$out" in
    ''|*[!0-9a-fA-F:.]*) return 1 ;;
    *) printf '%s' "$out"; return 0 ;;
  esac
}

self_test_http() {
  local out=""
  out=$(curl -fsS --max-time 12 \
        -x "http://${S5_USER}:${S5_PASS}@127.0.0.1:${S5_HTTP_PORT}" \
        https://api.ipify.org 2>/dev/null || true)
  case "$out" in
    ''|*[!0-9a-fA-F:.]*) return 1 ;;
    *) printf '%s' "$out"; return 0 ;;
  esac
}

# ------------------------------------------------------------------ 输出结果
print_result() {
  local ip; ip=$(public_ip)
  local s_url="socks5h://${S5_USER}:${S5_PASS}@${ip}:${S5_PORT}"
  local s_uri="socks5://${S5_USER}:${S5_PASS}@${ip}:${S5_PORT}"
  local h_url=""

  if [ -n "${S5_HTTP_PORT:-}" ]; then
    h_url="http://${S5_USER}:${S5_PASS}@${ip}:${S5_HTTP_PORT}"
  fi

  echo
  hr
  if [ -n "$h_url" ]; then
    printf '%s  代理部署完成（SOCKS5 + HTTP）%s\n' "$CB" "$CR"
  else
    printf '%s  SOCKS5 部署完成%s\n' "$CB" "$CR"
  fi
  hr
  printf '  主机 (Host)   : %s%s%s\n' "$CG" "$ip" "$CR"
  printf '  用户 (User)   : %s%s%s\n' "$CG" "$S5_USER" "$CR"
  printf '  密码 (Pass)   : %s%s%s\n' "$CG" "$S5_PASS" "$CR"
  echo
  printf '  ── SOCKS5 ──────────────────────────────────\n'
  printf '  端口 (Port)   : %s%s%s\n' "$CG" "$S5_PORT" "$CR"
  printf '  连接串 (推荐) : %s%s%s\n' "$CB" "$s_url" "$CR"
  printf '  连接串 (兼容) : %s\n' "$s_uri"
  if [ -n "$h_url" ]; then
    echo
    printf '  ── HTTP ────────────────────────────────────\n'
    printf '  端口 (Port)   : %s%s%s\n' "$CG" "$S5_HTTP_PORT" "$CR"
    printf '  连接串        : %s%s%s\n' "$CB" "$h_url" "$CR"
  fi
  echo
  printf '  本地测试      : curl -x %s https://ipinfo.io/ip\n' "$s_url"
  if [ -n "$h_url" ]; then
    printf '                : curl -x %s https://ipinfo.io/ip\n' "$h_url"
  fi
  printf '  查看状态      : bash %s --status\n' "$0"
  printf '  卸载          : bash %s --uninstall\n' "$0"
  hr
  local ports="$S5_PORT"
  if [ -n "$S5_HTTP_PORT" ]; then
    ports="${ports}, ${S5_HTTP_PORT}"
  fi
  warn "端口 ${ports} 需在云厂商安全组 / 面板防火墙放行对应 TCP"
  warn "账号密码保存在 ${STATE_PATH} (600)，仅 root 可读"
  echo
}

# ------------------------------------------------------------------ 动作
do_status() {
  load_state || die "未找到 ${STATE_PATH}，看起来还没安装过"
  echo
  hr
  printf '%s  代理当前状态%s\n' "$CB" "$CR"
  hr
  printf '  服务状态 : %s\n' "$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo unknown)"
  printf '  开机自启 : %s\n' "$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo unknown)"
  printf '  用户名   : %s\n' "$S5_USER"
  printf '  密码     : %s\n' "$S5_PASS"
  printf '  SOCKS5   : %s\n' "$S5_PORT"
  printf '  HTTP     : %s\n' "${S5_HTTP_PORT:-（未启用）}"
  echo
  printf '  监听明细 :\n'
  local found=0
  for p in "$S5_PORT" ${S5_HTTP_PORT:+"$S5_HTTP_PORT"}; do
    if ss -lntp 2>/dev/null | grep -qE "[:.]${p}\b"; then
      ss -lntp 2>/dev/null | grep -E "[:.]${p}\b" | sed 's/^/    /'
      found=1
    fi
  done
  [ "$found" -eq 1 ] || echo "    (未在监听)"
  echo
  local act=0 n
  for p in "$S5_PORT" ${S5_HTTP_PORT:+"$S5_HTTP_PORT"}; do
    n=$(ss -tn state established 2>/dev/null | grep -c ":${p}" || true)
    act=$(( act + ${n:-0} ))
  done
  printf '  活跃连接 : %s\n' "$act"
  echo
  printf '  最近日志 :\n'
  journalctl -u "$SERVICE_NAME" -n 8 --no-pager 2>/dev/null | sed 's/^/    /' || true
  hr
  print_result
}

do_url() {
  load_state || die "未找到 ${STATE_PATH}，看起来还没安装过"
  local ip; ip=$(public_ip)
  printf 'socks5h://%s:%s@%s:%s\n' "$S5_USER" "$S5_PASS" "$ip" "$S5_PORT"
  if [ -n "${S5_HTTP_PORT:-}" ]; then
    printf 'http://%s:%s@%s:%s\n' "$S5_USER" "$S5_PASS" "$ip" "$S5_HTTP_PORT"
  fi
}

do_uninstall() {
  info "卸载 ${SERVICE_NAME}"
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$UNIT_PATH"
  systemctl daemon-reload 2>/dev/null || true
  rm -f "$BIN_PATH" "$STATE_PATH"
  ok "已卸载（systemd 服务、二进制、状态文件均已清理）"
  exit 0
}

# ------------------------------------------------------------------ 校验端口参数
validate_port() {
  local val="$1" name="$2"
  case "$val" in
    ''|*[!0-9]*) die "${name} 必须是数字: ${val}" ;;
  esac
  [ "$val" -ge 1 ] && [ "$val" -le 65535 ] || die "${name} 超出范围 (1-65535): ${val}"
  if ! port_free "$val"; then
    die "端口 ${val} 已被占用，换一个或去掉 ${name} 让脚本自动挑"
  fi
}

# ------------------------------------------------------------------ 主流程
main() {
  [ "$(id -u)" -eq 0 ] || die "需要 root 权限，请执行: sudo -i 后再运行"

  case "$ACTION" in
    uninstall) do_uninstall ;;
    status)    do_status ;;
    url)       do_url ;;
  esac

  command -v systemctl >/dev/null 2>&1 || die "当前系统没有 systemd，无法托管服务"

  ensure_deps
  install_gost

  # ---- 端口 1：SOCKS5
  if [ -n "$WANT_PORT" ]; then
    validate_port "$WANT_PORT" "--port"
    S5_PORT="$WANT_PORT"
    ok "SOCKS5 使用指定端口: ${S5_PORT}"
  else
    S5_PORT=$(pick_port) || die "在 ${PORT_MIN}-${PORT_MAX} 范围内找不到空闲端口"
    ok "SOCKS5 自动分配空闲端口: ${S5_PORT}"
  fi

  # ---- 端口 2：HTTP（必须避开 SOCKS5 端口，此时两者都还没监听）
  S5_HTTP_PORT=""
  if [ "$ENABLE_HTTP" -eq 1 ]; then
    if [ -n "$WANT_HTTP_PORT" ]; then
      if [ "$WANT_HTTP_PORT" = "$S5_PORT" ]; then
        die "--http-port 不能与 SOCKS5 端口相同 (${S5_PORT})"
      fi
      validate_port "$WANT_HTTP_PORT" "--http-port"
      S5_HTTP_PORT="$WANT_HTTP_PORT"
      ok "HTTP 使用指定端口: ${S5_HTTP_PORT}"
    else
      S5_HTTP_PORT=$(pick_port "$S5_PORT") || die "找不到可用的 HTTP 端口"
      ok "HTTP 自动分配空闲端口: ${S5_HTTP_PORT}"
    fi
  else
    info "按 --no-http 只启用 SOCKS5"
  fi

  # ---- 账号（两种协议共用一套凭据）
  S5_USER="${WANT_USER:-$(rand_user)}"
  S5_PASS="${WANT_PASS:-$(rand_pass)}"
  case "${S5_USER}${S5_PASS}" in
    *[@:/?#\ ]*) die "用户名/密码不能包含 @ : / ? # 或空格（会破坏 URL 解析）" ;;
  esac
  [ ${#S5_USER} -ge 3 ] || die "用户名至少 3 位"
  [ ${#S5_PASS} -ge 8 ] || die "密码至少 8 位"
  ok "生成凭据: ${S5_USER} / ${S5_PASS}"

  # ---- 写 systemd unit
  local listen_args="-L socks5://${S5_USER}:${S5_PASS}@:${S5_PORT}"
  if [ -n "$S5_HTTP_PORT" ]; then
    listen_args="${listen_args} -L http://${S5_USER}:${S5_PASS}@:${S5_HTTP_PORT}"
  fi

  info "写入 ${UNIT_PATH}"
  cat >"$UNIT_PATH" <<EOF
[Unit]
Description=gost SOCKS5 + HTTP proxy (auto-generated by socks5-install.sh)
Documentation=https://gost.run
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_PATH} ${listen_args}
Restart=always
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

  # ---- 启动
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
  systemctl restart "$SERVICE_NAME"
  sleep 1

  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    warn "服务启动失败，最后 20 行日志:"
    journalctl -u "$SERVICE_NAME" -n 20 --no-pager 2>/dev/null || true
    die "部署失败"
  fi
  ok "服务已启动并设为开机自启"

  # ---- 监听确认
  local p listen_ok
  for p in "$S5_PORT" ${S5_HTTP_PORT:+"$S5_HTTP_PORT"}; do
    listen_ok=""
    for _ in 1 2 3 4 5; do
      if ss -lnt 2>/dev/null | grep -qE "[:.]${p}\b"; then listen_ok=1; break; fi
      sleep 1
    done
    if [ -n "$listen_ok" ]; then
      ok "端口 ${p} 已在监听"
    else
      warn "端口 ${p} 暂未在监听，请用 --status 复查"
    fi
  done

  # ---- 防火墙
  open_firewall "$S5_PORT"
  [ -n "$S5_HTTP_PORT" ] && open_firewall "$S5_HTTP_PORT"

  # ---- 保存
  save_state
  ok "凭据已保存到 ${STATE_PATH}"

  # ---- 自检
  local egress=""
  if egress=$(self_test_socks); then
    ok "SOCKS5 自检通过，出口 IP: ${egress}"
  else
    warn "SOCKS5 自检未拿到结果（服务器无外网或出口受限时正常）"
  fi
  if [ -n "$S5_HTTP_PORT" ]; then
    if egress=$(self_test_http); then
      ok "HTTP 自检通过，出口 IP: ${egress}"
    else
      warn "HTTP 自检未拿到结果（服务器无外网或出口受限时正常）"
    fi
  fi

  print_result
}

main "$@"
