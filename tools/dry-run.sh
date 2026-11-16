#!/bin/sh
# Dry-run of tools/build.sh with throwaway root + release keys (generated here, deleted on exit).
#   RVP_BIN=<dir> tools/dry-run.sh <out_dir>
# Nothing it signs is trusted by any real daemon.
set -eu
[ $# -eq 1 ] || { echo "usage: $0 <out_dir>" >&2; exit 2; }
repo=$(cd "$(dirname "$0")/.." && pwd)
k=$(mktemp -d)
trap 'rm -rf "$k"' EXIT
mkdir "$k/trust"
minisign -G -W -p "$k/root.pub" -s "$k/root.key" >/dev/null
minisign -G -W -p "$k/rel.pub" -s "$k/rel.key" >/dev/null
printf '{"format":1,"seq":%s,"keys":["%s"]}\n' "$(date -u +%s)" "$(sed -n 2p "$k/rel.pub")" >"$k/trust/keys.json"
minisign -S -H -s "$k/root.key" -m "$k/trust/keys.json" -x "$k/trust/keys.json.minisig" -t "dry-run" >/dev/null
SIGN_KEY=$k/rel.key SIGN_PUB=$k/rel.pub TRUST_DIR=$k/trust ROOT_PUB=$k/root.pub MINISIGN_PW= \
    "$repo/tools/build.sh" "$1"
