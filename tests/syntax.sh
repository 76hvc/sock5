#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
fail=0
for f in install.sh socks5-install.sh socks5-only.sh http-only.sh \
         tools/build.sh tests/selftest.sh tests/dryrun.sh tests/all.sh tests/syntax.sh \
         src/core.sh; do
  if bash -n "$f" 2>/tmp/err; then
    printf 'OK   %s\n' "$f"
  else
    printf 'FAIL %s\n' "$f"
    sed 's/^/       /' /tmp/err
    fail=1
  fi
done
exit $fail
