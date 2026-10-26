#!/usr/bin/env bash
# 干跑测试：stub 掉 systemd / 网络 / root，只验证生成的 systemd unit 是否正确
# 用法: bash tests/dryrun.sh
set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0
check() { if [ "$1" = "0" ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; FAIL=$((FAIL+1)); fi; }

dryrun() {
  local src="$1" extra="$2" expect="$3" notexpect="$4" label="$5"
  local tmp; tmp=$(mktemp -d)
  local code="$tmp/unit.service"
  local statef="$tmp/state.env"
  local script="$tmp/s.sh"

  sed 's/^main "\$@"$//' "$src" > "$script"

  (
    set --
    # shellcheck disable=SC1090
    source "$script" >/dev/null 2>&1
    set +e

    UNIT_PATH="$code"
    STATE_PATH="$statef"
    LEGACY_UNIT_PATH="$tmp/none-legacy.service"
    LEGACY_STATE_PATH="$tmp/none-legacy.env"

    # ---- stubs
    id() { echo 0; }
    install_gost() { :; }
    ensure_deps() { :; }
    open_firewall() { :; }
    save_state() {
      printf 'S5_PROTO=%s S5_SOCKS_PORT=%s S5_HTTP_PORT=%s\n' \
        "$S5_PROTO" "$S5_SOCKS_PORT" "$S5_HTTP_PORT" > "$STATE_PATH"
    }
    public_ip() { echo "1.2.3.4"; }
    self_test_socks() { echo "1.2.3.4"; }
    self_test_http()  { echo "1.2.3.4"; }
    sleep() { :; }
    journalctl() { :; }
    systemctl() {
      if [ "$1" = "is-active" ] && [ "$2" = "--quiet" ]; then return 0; fi
      if [ "$1" = "is-active" ]; then echo active; return 0; fi
      return 0
    }
    ss() {
      local p
      for p in ${S5_SOCKS_PORT:+"$S5_SOCKS_PORT"} ${S5_HTTP_PORT:+"$S5_HTTP_PORT"}; do
        echo "LISTEN 0 4096 *:${p} *:*"
      done
    }

    # shellcheck disable=SC2086
    eval "set -- $extra"
    PROTO="$PROTO_DEFAULT"
    WANT_PORT=""; WANT_HTTP_PORT=""; WANT_USER="testuser"; WANT_PASS="testpass123"; ACTION="install"
    while [ $# -gt 0 ]; do
      case "$1" in
        --proto)     PROTO="$2"; shift 2 ;;
        --port)      WANT_PORT="$2"; shift 2 ;;
        --http-port) WANT_HTTP_PORT="$2"; shift 2 ;;
        --no-http)   PROTO="socks5"; shift ;;
        *)           shift ;;
      esac
    done
    # 与脚本参数解析后的归一化保持一致：http 单协议模式下 --port 即 HTTP 端口
    if [ "$PROTO" = "http" ] && [ -n "$WANT_PORT" ] && [ -z "$WANT_HTTP_PORT" ]; then
      WANT_HTTP_PORT="$WANT_PORT"
      WANT_PORT=""
    fi

    main >/dev/null 2>&1
  )

  local exec_line state
  exec_line=$(grep '^ExecStart=' "$code" 2>/dev/null)
  state=$(tr -s '\n' ' ' < "$statef" 2>/dev/null)

  echo "--- $label ---"
  echo "  ${exec_line#ExecStart=}"
  echo "  $state"
  if printf '%s' "$exec_line" | grep -qE -e "$expect"; then
    check 0 "ExecStart 匹配预期"
  else
    check 1 "ExecStart 匹配预期（期望正则: $expect）"
  fi
  if [ -n "$notexpect" ]; then
    if printf '%s' "$exec_line" | grep -qE -e "$notexpect"; then
      check 1 "不应出现 $notexpect"
    else
      check 0 "不应出现 $notexpect"
    fi
  fi
  rm -rf "$tmp"
}

S5RE='-L socks5://testuser:testpass123@:[0-9]+'
HRE='-L http://testuser:testpass123@:[0-9]+'

dryrun "$ROOT/socks5-install.sh" "" "$S5RE $HRE" "" "both 默认"
dryrun "$ROOT/socks5-install.sh" "--proto socks5" "$S5RE\$" "http://" "both 脚本 --proto socks5"
dryrun "$ROOT/socks5-install.sh" "--proto http" "$HRE\$" "socks5://" "both 脚本 --proto http"
dryrun "$ROOT/socks5-install.sh" "--no-http" "$S5RE\$" "http://" "both 脚本 --no-http"
dryrun "$ROOT/socks5-only.sh" "" "$S5RE\$" "http://" "socks5-only 默认"
dryrun "$ROOT/http-only.sh" "" "$HRE\$" "socks5://" "http-only 默认"
dryrun "$ROOT/socks5-install.sh" "--port 1080 --http-port 8080" \
       '-L socks5://testuser:testpass123@:1080 -L http://testuser:testpass123@:8080' "" "both 指定双端口"
dryrun "$ROOT/http-only.sh" "--port 9090" '-L http://testuser:testpass123@:9090$' "socks5://" "http-only --port 视为 HTTP 端口"
dryrun "$ROOT/socks5-only.sh" "--port 1080" '-L socks5://testuser:testpass123@:1080$' "http://" "socks5-only --port"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "干跑全部通过"
  exit 0
else
  echo "干跑失败 $FAIL 项"
  exit 1
fi
