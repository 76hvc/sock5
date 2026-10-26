#!/usr/bin/env bash
#
# install.sh — 统一入口 / 交互菜单
#
# 本地运行（git clone 后）优先用同目录下的脚本；
# 通过 curl | bash 运行时自动从 GitHub 下载对应脚本。
#
# 用法:
#   bash install.sh             交互菜单
#   bash install.sh both        直接装 SOCKS5 + HTTP
#   bash install.sh socks5      只装 SOCKS5
#   bash install.sh http        只装 HTTP
#   bash install.sh status      查看状态
#   bash install.sh url         打印连接串
#   bash install.sh uninstall   卸载
#
set -euo pipefail

BASE_URL="${SOCK5_BASE_URL:-https://raw.githubusercontent.com/76hvc/sock5/main}"

# 定位脚本所在目录（curl | bash 时为空）
SELF_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -t 1 ]; then
  CR=$'\033[0m'; CG=$'\033[32m'; CY=$'\033[33m'; CC=$'\033[36m'; CB=$'\033[1m'
else
  CR=""; CG=""; CY=""; CC=""; CB=""
fi

file_for() {
  case "$1" in
    both)   printf 'socks5-install.sh' ;;
    socks5) printf 'socks5-only.sh' ;;
    http)   printf 'http-only.sh' ;;
    *)      printf '' ;;
  esac
}

run_proto() {
  local proto="$1"; shift
  local name; name=$(file_for "$proto")
  [ -n "$name" ] || { echo "未知协议: $proto" >&2; exit 1; }

  if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/$name" ]; then
    bash "$SELF_DIR/$name" "$@"
    return
  fi

  local tmp; tmp=$(mktemp)
  printf '%s[*]%s 下载 %s\n' "$CC" "$CR" "$name"
  if ! curl -fsSL --max-time 60 "$BASE_URL/$name" -o "$tmp"; then
    rm -f "$tmp"
    printf '%s[x]%s 下载失败: %s/%s\n' "$CY" "$CR" "$BASE_URL" "$name" >&2
    exit 1
  fi
  local rc=0
  bash "$tmp" "$@" || rc=$?
  rm -f "$tmp"
  return $rc
}

ask() {
  local prompt="$1" def="$2" ans=""
  if [ -r /dev/tty ]; then
    printf '%s' "$prompt" > /dev/tty
    read -r ans < /dev/tty || ans=""
  else
    printf '%s' "$prompt"
    read -r ans || ans=""
  fi
  printf '%s' "${ans:-$def}"
}

menu() {
  cat <<EOF

${CB}代理一键部署${CR}
${CC}--------------------------------------------------------------${CR}
  1) SOCKS5 + HTTP  两个一起装（推荐）
  2) 仅 SOCKS5
  3) 仅 HTTP
  4) 查看当前状态
  5) 打印连接串
  6) 卸载
  0) 退出
${CC}--------------------------------------------------------------${CR}
EOF
  local choice; choice=$(ask "请选择 [1]: " "1")
  case "$choice" in
    1) run_proto both ;;
    2) run_proto socks5 ;;
    3) run_proto http ;;
    4) run_proto both --status ;;
    5) run_proto both --url ;;
    6) run_proto both --uninstall ;;
    0|q|Q) exit 0 ;;
    *) printf '%s[x]%s 无效选项: %s\n' "$CY" "$CR" "$choice" >&2; exit 1 ;;
  esac
}

case "${1:-}" in
  '')        menu ;;
  both|all)  shift; run_proto both "$@" ;;
  socks5|socks|s5) shift; run_proto socks5 "$@" ;;
  http|https) shift; run_proto http "$@" ;;
  status)    shift; run_proto both --status "$@" ;;
  url)       shift; run_proto both --url "$@" ;;
  uninstall|remove) shift; run_proto both --uninstall "$@" ;;
  -h|--help|help)
    cat <<'EOT'
install.sh — 统一入口 / 交互菜单

用法:
  bash install.sh             交互菜单
  bash install.sh both        直接装 SOCKS5 + HTTP
  bash install.sh socks5      只装 SOCKS5
  bash install.sh http        只装 HTTP
  bash install.sh status      查看状态
  bash install.sh url         打印连接串
  bash install.sh uninstall   卸载

环境变量:
  SOCK5_BASE_URL   脚本下载源，默认 GitHub raw
EOT
    exit 0
    ;;
  *)
    printf '%s[x]%s 未知子命令: %s\n' "$CY" "$CR" "$1" >&2
    printf '可用: both | socks5 | http | status | url | uninstall\n' >&2
    exit 1
    ;;
esac
