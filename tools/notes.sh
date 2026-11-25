#!/bin/sh
# Change notes of one release, from git.
#   tools/notes.sh <owner/repo> <tag>
# Prints {"changes": [...], "history": [{"version", "changes"}, ...]}: for every tag of the same channel
# (dev/v* or v*) up to <tag>, the commit subjects since the previous tag. "changes" is <tag>'s own,
# "history" the older versions'. Chores, CI, docs, tests and merges are left out.
# Needs gh (GH_TOKEN) and jq. A GitHub error gives empty notes: notes never fail a build.
set -u
[ $# -eq 2 ] || { echo "usage: $0 <owner/repo> <tag>" >&2; exit 2; }
repo=$1 tag=$2
case "$tag" in dev/v*) pre=dev/v ;; *) pre=v ;; esac
cur=${tag#"$pre"}

subjects() { # subjects <from_tag> <to_tag>
    gh api "repos/$repo/compare/$1...$2" --jq '.commits[].commit.message | split("\n")[0]' 2>/dev/null \
        | grep -Ev '^(Merge |(chore|ci|docs|test|tests|style|build|release)(\([^)]*\))?!?:)' \
        | sed -E 's/^[a-z]+(\([^)]*\))?!?: *//; s/; *[a-z0-9-]+ v?[0-9][0-9.]*$//' \
        | awk 'NF { print toupper(substr($0, 1, 1)) substr($0, 2) }' | cut -c1-200 | head -20
}

out=$(mktemp)
trap 'rm -f "$out"' EXIT
prev=
for v in $(gh api "repos/$repo/tags" --paginate --jq '.[].name' 2>/dev/null | grep "^$pre[0-9]" | sed "s#^$pre##" | sort -V); do
    if [ -z "$prev" ]; then notes='First release.'; else notes=$(subjects "$pre$prev" "$pre$v"); fi
    [ -n "$notes" ] || notes='Maintenance release.'
    printf '%s\n' "$notes" | jq -Rsc --arg v "$v" '{version: $v, changes: (split("\n") | map(select(length > 0)))}' >>"$out"
    prev=$v
    [ "$v" = "$cur" ] && break
done
# the tag itself missing from the list (GitHub error) = no notes at all
jq -sc --arg v "$cur" 'if (last.version? // "") == $v then {changes: last.changes, history: .[:-1]}
    else {changes: [], history: []} end' "$out"
