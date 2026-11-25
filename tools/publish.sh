#!/bin/sh
# Publish a built catalog (tools/build.sh <out>): upload the signed packages + keys to the dl
# bucket (Cloudflare R2, S3 API), then register each release with the api (POST ci/releases).
#   tools/publish.sh <out_dir>
# Env:
#   API        api base, e.g. https://api.cmu-revised.com/v1      CI_TOKEN  api CI bearer token
#   DL_BASE    public base of the bucket, e.g. https://dl.cmu-revised.com (the api refuses urls outside it)
#   R2_BUCKET, R2_ENDPOINT, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY   for `aws s3 cp`
#   NO_UPLOAD=1  skip the upload (register only: local api test)
#   Needs jq, curl, aws (unless NO_UPLOAD).
# An already registered name@version (409) is skipped: re-running after a partial publish is safe.
set -eu
[ $# -eq 1 ] || { echo "usage: $0 <out_dir>" >&2; exit 2; }
out=$1
: "${API:?}" "${CI_TOKEN:?}" "${DL_BASE:?}"
dl=${DL_BASE%/}

up() { # up <file> <key>
    [ "${NO_UPLOAD-}" = 1 ] && return 0
    aws s3 cp --only-show-errors --endpoint-url "$R2_ENDPOINT" "$1" "s3://$R2_BUCKET/$2"
}

# keys first: a daemon that sees a new release must already find the keys that signed it
up "$out/keys.json" keys.json
up "$out/keys.json.minisig" keys.json.minisig

resp=$(mktemp)
trap 'rm -f "$resp"' EXIT
jq -c '.packages[]' "$out/catalog.json" | while read -r e; do
    name=$(printf '%s' "$e" | jq -r .name)
    ver=$(printf '%s' "$e" | jq -r .version)
    key=pkgs/$name/$ver.rvp
    up "$out/$(printf '%s' "$e" | jq -r .url)" "$key"
    # ponytail: icon / screenshots not sent (no meta uses them yet); upload + prefix DL_BASE when one does
    body=$(printf '%s' "$e" | jq -c --arg u "$dl/$key" '{name, version, url: $u, size, core_blake2b, depends, conflicts,
        targetCMU, devOnly: (.devOnly // false), title, subtitle, category, author,
        description: (.description // ""), permissions: (.permissions // []), changes: (.changes // []), history: (.history // [])} + (if .source then {source} else {} end)')
    code=$(curl -sS -o "$resp" -w '%{http_code}' -X POST -H "authorization: Bearer $CI_TOKEN" \
        -H 'content-type: application/json' --data "$body" "$API/ci/releases")
    case $code in
        201) echo "registered $name $ver" ;;
        409) echo "exists $name $ver" ;;
        *) echo "$name $ver: http $code $(cat "$resp")" >&2; exit 1 ;;
    esac
done
