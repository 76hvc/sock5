#!/usr/bin/env bash
# 逻辑自测：只测纯函数，不碰 systemd
# 用法: bash tests/selftest.sh [被测算脚本]
set +e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/socks5-install.sh}"

[ -f "$SRC" ] || { echo "找不到 $SRC"; exit 1; }

TMP="$(mktemp)"
sed 's/^main "\$@"$//' "$SRC" > "$TMP"
set --   # 清空位置参数，否则 source 的脚本会把 "$1" 当成自己的命令行参数并报未知参数
# shellcheck disable=SC1090
source "$TMP" >/dev/null 2>&1
set +e   # 脚本里 source 时开了 set -euo pipefail，测试要关掉
rm -f "$TMP"

FAIL=0
check() { if [ "$1" = "0" ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; FAIL=$((FAIL+1)); fi; }

echo "== $SRC =="
echo "  PROTO_DEFAULT=$PROTO_DEFAULT"

echo "--- rand ---"
u=$(rand_user); p=$(rand_pass)
[ "${#u}" -eq 10 ] && check 0 "用户名长度 ${#u}" || check 1 "用户名长度 ${#u}"
[ "${#p}" -eq 20 ] && check 0 "密码长度 ${#p}" || check 1 "密码长度 ${#p}"
case "$u$p" in *[!A-Za-z0-9]*) check 1 "凭据只含字母数字" ;; *) check 0 "凭据只含字母数字" ;; esac
case "$u" in s5*) check 0 "用户名 s5 前缀" ;; *) check 1 "用户名 s5 前缀" ;; esac
[ "$(rand_pass)" != "$(rand_pass)" ] && check 0 "密码每次不同" || check 1 "密码每次不同"

echo "--- backend ---"
init_port_backend
echo "  PORT_BACKEND=${PORT_BACKEND}"
[ "$PORT_BACKEND" != "none" ] && check 0 "有可用探测后端" || check 1 "有可用探测后端"

echo "--- pick_port 排除逻辑 ---"
a=$(pick_port); b=$(pick_port "$a"); c=$(pick_port "$a $b")
echo "  $a / $b / $c"
if [ "$a" != "$b" ] && [ "$b" != "$c" ] && [ "$a" != "$c" ]; then
  check 0 "三个端口互不相同"
else
  check 1 "三个端口互不相同"
fi
for x in "$a" "$b" "$c"; do
  [ "$x" -ge "$PORT_MIN" ] && [ "$x" -le "$PORT_MAX" ] && check 0 "端口 $x 在范围内" || check 1 "端口 $x 在范围内"
done

echo "--- validate_port ---"
( validate_port 50000 "--port" ) >/dev/null 2>&1; check $? "50000 通过"
( validate_port abc "--port" ) >/dev/null 2>&1; [ $? -ne 0 ] && check 0 "abc 被拒" || check 1 "abc 被拒"
( validate_port 99999 "--port" ) >/dev/null 2>&1; [ $? -ne 0 ] && check 0 "99999 被拒" || check 1 "99999 被拒"
( validate_port 0 "--port" ) >/dev/null 2>&1; [ $? -ne 0 ] && check 0 "0 被拒" || check 1 "0 被拒"

echo "--- 状态文件往返 ---"
S5_PROTO="$PROTO_DEFAULT"; S5_USER="$u"; S5_PASS="$p"
S5_SOCKS_PORT="$a"; S5_HTTP_PORT="$b"
SAVED_STATE="$STATE_PATH"
STATE_PATH="$(mktemp)"
save_state
perm=$(stat -c '%a' "$STATE_PATH" 2>/dev/null || echo "n/a")
[ "$perm" = "600" ] && check 0 "状态文件权限 600" || check 1 "状态文件权限 600 (实际 $perm)"
grep -q "^S5_HTTP_PORT=$b$" "$STATE_PATH" && check 0 "HTTP 端口已落盘" || check 1 "HTTP 端口已落盘"
grep -q "^S5_PORT=$a$" "$STATE_PATH" && check 0 "兼容字段 S5_PORT 已落盘" || check 1 "兼容字段 S5_PORT 已落盘"

S5_PROTO=""; S5_USER=""; S5_PASS=""; S5_SOCKS_PORT=""; S5_HTTP_PORT=""; S5_PORT=""
load_state && check 0 "load_state 成功" || check 1 "load_state 成功"
[ "$S5_USER" = "$u" ] && check 0 "用户名还原" || check 1 "用户名还原"
[ "$S5_SOCKS_PORT" = "$a" ] && check 0 "SOCKS 端口还原" || check 1 "SOCKS 端口还原"
[ "$S5_HTTP_PORT" = "$b" ] && check 0 "HTTP 端口还原" || check 1 "HTTP 端口还原"

echo "--- 旧版状态文件（无 S5_SOCKS_PORT / S5_HTTP_PORT / S5_PROTO） ---"
LEGACY_STATE_PATH="$(mktemp)"
printf 'S5_USER=old\nS5_PASS=oldpass123\nS5_PORT=3333\nS5_SERVICE=gost-socks5\n' > "$LEGACY_STATE_PATH"
STATE_PATH="/nonexistent/path.env"
S5_PROTO=""; S5_USER=""; S5_PASS=""; S5_SOCKS_PORT=""; S5_HTTP_PORT=""; S5_PORT=""; S5_SERVICE=""
load_state && check 0 "旧格式可读" || check 1 "旧格式可读"
[ "$S5_SOCKS_PORT" = "3333" ] && check 0 "S5_PORT 映射到 S5_SOCKS_PORT" || check 1 "S5_PORT 映射到 S5_SOCKS_PORT"
[ -z "$S5_HTTP_PORT" ] && check 0 "HTTP 端口为空（未启用）" || check 1 "HTTP 端口为空（未启用）"
[ "$S5_PROTO" = "socks5" ] && check 0 "PROTO 推导为 socks5" || check 1 "PROTO 推导为 socks5"

STATE_PATH="$SAVED_STATE"
rm -f "$LEGACY_STATE_PATH"

echo "--- do_url 输出行数 ---"
STATE_PATH="$(mktemp)"
S5_PROTO=both; S5_USER="$u"; S5_PASS="$p"; S5_SOCKS_PORT="$a"; S5_HTTP_PORT="$b"
save_state
public_ip() { echo "1.2.3.4"; }
out=$(do_url)
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
[ "$lines" = "2" ] && check 0 "both 模式输出 2 行" || check 1 "both 模式输出 2 行 (实际 $lines)"
echo "$out" | grep -q "^socks5h://" && check 0 "含 socks5h 行" || check 1 "含 socks5h 行"
echo "$out" | grep -q "^http://" && check 0 "含 http 行" || check 1 "含 http 行"

S5_HTTP_PORT=""
save_state
out=$(do_url)
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
[ "$lines" = "1" ] && check 0 "socks5 模式输出 1 行" || check 1 "socks5 模式输出 1 行 (实际 $lines)"

S5_SOCKS_PORT=""; S5_HTTP_PORT="$b"
save_state
out=$(do_url)
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
[ "$lines" = "1" ] && check 0 "http 模式输出 1 行" || check 1 "http 模式输出 1 行 (实际 $lines)"
echo "$out" | grep -q "^http://" && check 0 "http 模式只输出 http 行" || check 1 "http 模式只输出 http 行"

rm -f "$STATE_PATH"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "全部通过"
  exit 0
else
  echo "失败 $FAIL 项"
  exit 1
fi
