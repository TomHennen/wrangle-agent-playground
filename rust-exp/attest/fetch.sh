#!/usr/bin/env bash
# usage: fetch.sh <label> <url> [token]
label=$1; url=$2; tok=${3:-}
args=(-s -o "/tmp/body.$label" -D "/tmp/hdr.$label" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
[[ -n $tok ]] && args+=(-H "Authorization: Bearer $tok")
curl "${args[@]}" "$url"
echo "== $label: $(head -1 /tmp/hdr.$label | tr -d '\r')"
grep -i '^x-ratelimit' /tmp/hdr.$label | tr -d '\r'
echo "n_attestations=$(jq '.attestations|length' /tmp/body.$label 2>/dev/null) inline_bundle=$(jq '[.attestations[]?|has("bundle") and .bundle!=null]|all' /tmp/body.$label 2>/dev/null) has_bundle_url=$(jq '[.attestations[]?|.bundle_url!=null]|any' /tmp/body.$label 2>/dev/null)"
jq -c 'select(.message!=null)|{message}' /tmp/body.$label 2>/dev/null
