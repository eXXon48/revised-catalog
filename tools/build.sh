#!/bin/sh
# Build the signed catalog from catalog.list.
#   tools/build.sh <out_dir>
# Env:
#   RVP_BIN    dir with rvp-pack + rvp-verify
#   SIGN_KEY   release secret key file        SIGN_PUB  release public key file
#   MINISIGN_PW  release key password (piped to minisign; empty = unencrypted key)
#   TRUST_DIR  dir holding keys.json + keys.json.minisig (root-signed)
#   ROOT_PUB   root public key file for the final check (default: trust/root.pub)
#   Needs jq, minisign, tar.
#   GH_TOKEN   for `gh release download`
# Output: <out>/{catalog.json,catalog.json.minisig,keys.json,keys.json.minisig,pkgs/*.rvp}
# Any failed check aborts (set -e); nothing is half-published because CI only uploads on success.
set -eu
[ $# -eq 1 ] || { echo "usage: $0 <out_dir>" >&2; exit 2; }
out=$1
repo=$(cd "$(dirname "$0")/.." && pwd)
: "${RVP_BIN:?}" "${SIGN_KEY:?}" "${SIGN_PUB:?}" "${TRUST_DIR:?}"
pw=${MINISIGN_PW-}
root_pub=${ROOT_PUB:-$repo/trust/root.pub}
list=$repo/catalog.list

sign() { # sign <file> <sigfile> <trusted comment>
    printf '%s\n' "$pw" | minisign -S -H -s "$SIGN_KEY" -m "$1" -x "$2" -t "$3" >/dev/null
}

rm -rf "$out"
mkdir -p "$out/pkgs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
seq=$(date -u +%s)
allow='["title","subtitle","description","icon","screenshots","permissions","changes"]'
: >"$tmp/entries.jsonl"
seen=" "

while read -r spec sha rest; do
    case "$spec" in ''|'#'*) continue ;; esac
    [ -z "$rest" ] || { echo "bad catalog.list line: $spec $sha $rest" >&2; exit 1; }
    case "$spec" in */*@*) ;; *) echo "bad spec (want owner/repo@tag): $spec" >&2; exit 1 ;; esac
    case "$sha" in
        *[!0-9a-f]*|'') echo "bad sha256 for $spec" >&2; exit 1 ;;
    esac
    [ ${#sha} -eq 64 ] || { echo "bad sha256 length for $spec" >&2; exit 1; }
    gh_repo=${spec%@*}; tag=${spec#*@}
    echo "== $spec"

    # 1. download: exactly one .rvp
    dl=$tmp/dl; rm -rf "$dl"; mkdir -p "$dl"
    gh release download "$tag" -R "$gh_repo" -p '*.rvp' -D "$dl"
    set -- "$dl"/*.rvp
    [ $# -eq 1 ] && [ -f "$1" ] || { echo "$spec: want exactly one .rvp asset, got $#" >&2; exit 1; }
    in=$1

    # 2. hash pinned in catalog.list
    printf '%s  %s\n' "$sha" "$in" | sha256sum -c -

    # 3. strip any signature, sign the core, re-wrap, verify
    "$RVP_BIN/rvp-pack" --extract-core "$in" "$tmp/c.core" >"$tmp/c.hash"
    sign "$tmp/c.core" "$tmp/c.minisig" "revised-approved $now"

    # manifest (compact JSON inside the core) -> base entry; jq builds everything, nothing is hand-assembled
    tar -xzOf "$tmp/c.core" manifest.json >"$tmp/manifest.json"
    name=$(jq -er '.name | strings' "$tmp/manifest.json")
    ver=$(jq -er '.version | strings' "$tmp/manifest.json")
    case "$seen" in *" $name "*) echo "duplicate package $name" >&2; exit 1 ;; esac
    seen="$seen$name "
    rvp=pkgs/$name-$ver.rvp
    "$RVP_BIN/rvp-pack" --from-core "$tmp/c.core" "$out/$rvp" --sig "$tmp/c.minisig" >/dev/null
    "$RVP_BIN/rvp-verify" "$out/$rvp" "$SIGN_PUB"

    # entry = manifest fields + url/size/hash, then allowlisted meta/<name>.json overrides
    size=$(wc -c <"$out/$rvp" | tr -d ' ')
    jq -c --arg url "$rvp" --argjson size "$size" --arg h "$(cat "$tmp/c.hash")" '{
        name, version, title: .name, subtitle: (.description // ""), author: (.author // ""),
        category: (.category // ""), depends: (.depends // ""), conflicts: (.conflicts // ""),
        url: $url, size: $size, core_blake2b: $h}' "$tmp/manifest.json" >"$tmp/base.json"
    meta=$repo/meta/$name.json
    if [ -f "$meta" ]; then
        jq -e --argjson ok "$allow" 'type == "object" and ((keys - $ok) | length == 0)' "$meta" >/dev/null \
            || { echo "$meta: must be a JSON object using only: $allow" >&2; exit 1; }
        jq -cs '.[0] * .[1]' "$tmp/base.json" "$meta" >>"$tmp/entries.jsonl"
    else
        cat "$tmp/base.json" >>"$tmp/entries.jsonl"
    fi
done <"$list"

jq -s --argjson seq "$seq" --arg g "$now" '{format: 1, seq: $seq, generated: $g, packages: .}' "$tmp/entries.jsonl" >"$out/catalog.json"
jq -e . "$out/catalog.json" >/dev/null
sign "$out/catalog.json" "$out/catalog.json.minisig" "revised-approved $now"
cp "$TRUST_DIR/keys.json" "$TRUST_DIR/keys.json.minisig" "$out/"

# final checks (fail closed)
minisign -V -p "$root_pub" -m "$out/keys.json" -x "$out/keys.json.minisig" >/dev/null
minisign -V -p "$SIGN_PUB" -m "$out/catalog.json" -x "$out/catalog.json.minisig" >/dev/null
echo "catalog seq $seq: $(jq ".packages | length" "$out/catalog.json") packages, all signatures verified"
