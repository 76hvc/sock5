#!/usr/bin/env bash
# 本地跑全部检查：语法 → 逻辑 → 干跑
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FAIL=0

echo "########## 1. 语法 ##########"
bash tests/syntax.sh || FAIL=1

echo
echo "########## 2. 逻辑自测 ##########"
for f in socks5-install.sh socks5-only.sh http-only.sh; do
  printf '\n--- %s ---\n' "$f"
  if bash tests/selftest.sh "$f" >/tmp/selftest.log 2>&1; then
    echo "  PASS"
  else
    echo "  FAIL"
    tail -n 15 /tmp/selftest.log | sed 's/^/    /'
    FAIL=1
  fi
done

echo
echo "########## 3. 干跑（systemd unit 生成） ##########"
if bash tests/dryrun.sh >/tmp/dryrun.log 2>&1; then
  echo "  PASS"
else
  echo "  FAIL"
  tail -n 20 /tmp/dryrun.log | sed 's/^/    /'
  FAIL=1
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "===== 全部通过 ====="
  exit 0
else
  echo "===== 有失败项 ====="
  exit 1
fi
