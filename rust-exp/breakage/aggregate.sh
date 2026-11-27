#!/usr/bin/env bash
# Usage: aggregate.sh <dir-with-result-*/result.json> <out-dir>
set -uo pipefail
IN="${1:?}"; OUT="${2:?}"; mkdir -p "$OUT"
jq -s 'sort_by(.name)' "$IN"/*/result.json >"$OUT/summary.json"
jq -r '
def st($r; $s): ($r.steps[]? | select(.step==$s)) as $x
  | if $x.status=="pass" then "pass"
    elif $x.status=="n/a" then "-"
    elif $x.status=="timeout" then "TIMEOUT"
    else ($x.status|sub("fail-";"FAIL-")) + " (" + $x.cause + ")" end;
"| project | tag | lock | build | test-compile | test-run | package |",
"|---|---|---|---|---|---|---|",
(.[] | . as $r | "| \(.name) | \(.tag) | \(if .lock_committed then "yes" else "no" end) | \(st($r;"build")) | \(st($r;"testc")) | \(st($r;"testr")) | \(st($r;"pkg")) |"),
"",
"online-phase failures: " + ([.[] | select(.online_rc!=0) | .name] | join(", ")),
"",
"## totals per phase",
(["build","testc","testr","pkg"][] as $s
  | "\($s): " + ([.[] | .steps[]? | select(.step==$s) | .status] | group_by(.) | map("\(.[0])=\(length)") | join(", "))),
"",
"## sandbox-caused (fail-sandbox / fail-partial-sandbox) by cause",
([.[] | .name as $n | .steps[]? | select(.status|startswith("fail-sandbox") or startswith("fail-partial")) | "\(.cause)"] | group_by(.) | map("\(.[0])=\(length)") | join(", ")),
"",
"## pre-existing by cause",
([.[] | .steps[]? | select(.status=="fail-preexisting") | .cause] | group_by(.) | map("\(.[0])=\(length)") | join(", ")),
"",
"## projects with sandbox-caused failures",
(.[] | . as $r | [.steps[]? | select(.status|startswith("fail-sandbox") or startswith("fail-partial")) | "\(.step):\(.cause)" + (if (.sandbox_only_failed_tests|length)>0 then " [\(.sandbox_only_failed_tests|length) tests e.g. \(.sandbox_only_failed_tests[0:3]|join("; "))]" else "" end)] | select(length>0) | "- \($r.name): " + join(", "))
' "$OUT/summary.json" >"$OUT/summary.md"
cat "$OUT/summary.md"
printf '\n## tails of sandbox-caused failures\n'
jq -r '.[] | .name as $n | .steps[]? | select(.status|startswith("fail-sandbox") or startswith("fail-partial")) | "### \($n) \(.step) (\(.cause))\n```\n\(.tail)\n```"' "$OUT/summary.json" | tee -a "$OUT/summary.md"
