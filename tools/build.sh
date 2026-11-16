#!/bin/sh
# Build the signed catalog from catalog.list.
#   tools/build.sh <out_dir>
# Env:
#   RVP_BIN    dir with rvp-pack + rvp-verify
#   SIGN_KEY   release secret key file        SIGN_PUB  release public key file
#   MINISIGN_PW  release key password (piped to minisign; empty = unencrypted key)
#   TRUST_DIR  dir holding keys.json + keys.json.minisig (root-signed)
#   ROOT_PUB   root public key file for the final check (default: trust/root.pub)
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
entries=""
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

    # manifest fields (core manifest is compact JSON; the top-level key comes first)
    man=$tmp/manifest.json
    tar -xzOf "$tmp/c.core" manifest.json >"$man"
    field() { grep -o "\"$1\":\"[^\"]*\"" "$man" | head -1 | sed "s/^\"$1\":\"//; s/\"\$//"; }
    name=$(field name); ver=$(field version)
    [ -n "$name" ] && [ -n "$ver" ] || { echo "$spec: manifest lacks name/version" >&2; exit 1; }
    case "$seen" in *" $name "*) echo "duplicate package $name" >&2; exit 1 ;; esac
    seen="$seen$name "
    rvp=pkgs/$name-$ver.rvp
    "$RVP_BIN/rvp-pack" --from-core "$tmp/c.core" "$out/$rvp" --sig "$tmp/c.minisig" >/dev/null
    "$RVP_BIN/rvp-verify" "$out/$rvp" "$SIGN_PUB"

    # 4. entry = manifest fields + url/size/hash, then meta/<name>.json members (title/subtitle may be overridden there)
    size=$(wc -c <"$out/$rvp" | tr -d ' ')
    meta=$repo/meta/$name.json
    extra=""; ts="\"title\":\"$name\",\"subtitle\":\"$(field description)\","
    if [ -f "$meta" ]; then
        extra=",$(tr -d '\n' <"$meta" | sed 's/^[[:space:]]*{//; s/}[[:space:]]*$//')"
        # ponytail: grep, not a JSON parser; meta keys are flat top-level names
        grep -q '"title"' "$meta" && ts=""
    fi
    [ -n "$entries" ] && entries="$entries,
"
    entries="$entries    { \"name\": \"$name\", \"version\": \"$ver\", ${ts}\"author\": \"$(field author)\", \"category\": \"$(field category)\", \"depends\": \"$(field depends)\", \"conflicts\": \"$(field conflicts)\", \"url\": \"$rvp\", \"size\": $size, \"core_blake2b\": \"$(cat "$tmp/c.hash")\"$extra }"
done <"$list"

printf '{\n  "format": 1,\n  "seq": %s,\n  "generated": "%s",\n  "packages": [\n%s\n  ]\n}\n' "$seq" "$now" "$entries" >"$out/catalog.json"
sign "$out/catalog.json" "$out/catalog.json.minisig" "revised-approved $now"
cp "$TRUST_DIR/keys.json" "$TRUST_DIR/keys.json.minisig" "$out/"

# final checks (fail closed)
minisign -V -p "$root_pub" -m "$out/keys.json" -x "$out/keys.json.minisig" >/dev/null
minisign -V -p "$SIGN_PUB" -m "$out/catalog.json" -x "$out/catalog.json.minisig" >/dev/null
echo "catalog seq $seq: $(grep -c '"core_blake2b"' "$out/catalog.json") packages, all signatures verified"
