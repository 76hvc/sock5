#!/usr/bin/env bash
#
# 从 src/core.sh 生成三个自包含单文件脚本。
#   socks5-install.sh  双协议（SOCKS5 + HTTP）
#   socks5-only.sh     仅 SOCKS5
#   http-only.sh       仅 HTTP
#
set -euo pipefail

cd "$(dirname "$0")/.."

[ -f src/core.sh ] || { echo "找不到 src/core.sh" >&2; exit 1; }

gen() {
  local out="$1" proto="$2" title="$3"
  {
    printf '#!/usr/bin/env bash\n'
    printf '#\n'
    printf '# %s\n' "$title"
    printf '#\n'
    printf '# 本文件由 tools/build.sh 从 src/core.sh 生成，改逻辑请改 src/core.sh 后重新构建。\n'
    printf '#\n'
    printf 'PROTO_DEFAULT="%s"\n' "$proto"
    printf '\n'
    cat src/core.sh
  } > "$out"
  chmod +x "$out"
  printf '  built %-20s proto=%s\n' "$out" "$proto"
}

echo "building..."
gen socks5-install.sh both   "gost SOCKS5 + HTTP 双协议代理一键部署脚本"
gen socks5-only.sh    socks5 "gost SOCKS5 单协议代理一键部署脚本"
gen http-only.sh      http   "gost HTTP 代理一键部署脚本"
echo "done."
