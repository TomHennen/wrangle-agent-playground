#!/bin/bash
# demo.sh — run wrangle-attest over a known input set and print what comes out.
set -uo pipefail
# globbing is used to walk the demo's own fixture dirs; no external input

WA=/tmp/wrangle-attest
D="$(mktemp -d)"
cd "$D" || exit 1

hr() { printf '\n────────────────────────────────────────────────────────────\n%s\n────────────────────────────────────────────────────────────\n' "$1"; }
run() { printf '\n$ %s\n' "$*"; "$@"; printf '   [exit %s]\n' "$?"; }

hr "0. The input"
mkdir -p dist metadata/sbom metadata/osv
printf 'example binary payload v0.1.0 linux/amd64\n'  > dist/example_0.1.0_linux_amd64.tar.gz
printf 'example binary payload v0.1.0 darwin/arm64\n' > dist/example_0.1.0_darwin_arm64.tar.gz

printf '{"spdxVersion":"SPDX-2.3","name":"example","packages":[]}\n' > metadata/sbom/sbom.spdx.json
printf '{"predicate-type":"https://spdx.dev/Document","result-file":"sbom.spdx.json","tool":{"name":"syft","version":"1.20.0"}}\n' \
    > metadata/sbom/wrangle_attestation_metadata.json

printf '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"osv-scanner","version":"2.4.0"}},"results":[]}]}\n' > metadata/osv/output.sarif
printf '{"predicate-type":"https://github.com/TomHennen/wrangle/attestation/scan/v1","result-file":"output.sarif","tool":{"name":"osv-scanner","version":"2.4.0"},"result":"clean"}\n' \
    > metadata/osv/wrangle_attestation_metadata.json

# Two dist files (the engine self-digests them) + one container image digest.
{
    printf 'dist/example_0.1.0_linux_amd64.tar.gz\n'
    printf 'dist/example_0.1.0_darwin_arm64.tar.gz\n'
    printf 'sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08\n'
} > subjects.txt

# Stand-in for the build's SLSA provenance bundle (copied verbatim into every bundle).
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json","dsseEnvelope":{"payloadType":"application/vnd.in-toto+json","payload":"eyJfdHlwZSI6Imh0dHBzOi8vaW4tdG90by5pby9TdGF0ZW1lbnQvdjEiLCJwcmVkaWNhdGVUeXBlIjoiaHR0cHM6Ly9zbHNhLmRldi9wcm92ZW5hbmNlL3YxIiwic3ViamVjdCI6W119"}}\n' \
    > provenance.jsonl

printf 'subjects.txt:\n'; sed 's/^/  /' subjects.txt
printf '\nmetadata roots:\n'; find metadata -type f | sort | sed 's/^/  /'

hr "1. assemble — sign every subject's metadata, build one bundle per artifact"
printf '\n(signs against public-good Sigstore; each signature writes a public Rekor transparency-log entry)\n'
run "$WA" assemble \
    --metadata-root metadata/sbom \
    --metadata-root metadata/osv \
    --subjects-file subjects.txt \
    --provenance provenance.jsonl \
    --sign \
    --bundle-dir bundles \
    --statements-out statements.jsonl

hr "2. What came out"
printf '\nbundles/\n'
for b in bundles/*; do printf '  %s  (%s statements)\n' "$(basename "$b")" "$(wc -l < "$b")"; done

printf '\nEach bundle, decoded — predicateType + subject digest per statement:\n'
for b in bundles/*; do
    printf '\n  %s\n' "$(basename "$b")"
    while IFS= read -r line; do
        payload="$(printf '%s' "$line" | jq -r '.dsseEnvelope.payload' 2>/dev/null | base64 -d 2>/dev/null)"
        pt="$(printf '%s' "$payload" | jq -r '.predicateType // "?"' 2>/dev/null)"
        subj="$(printf '%s' "$payload" | jq -r '(.subject[0].digest.sha256 // "-")[0:16]' 2>/dev/null)"
        printf '    %-58s subject sha256:%s…\n' "$pt" "$subj"
    done < "$b"
done

printf '\nstatements.jsonl: %s newly signed statements (the lines pushed to the attestation store)\n' "$(wc -l < statements.jsonl)"

hr "3. Sign a VSA and append it to a bundle"
printf '{"_type":"https://in-toto.io/Statement/v1","predicateType":"https://slsa.dev/verification_summary/v1","subject":[{"digest":{"sha256":"'"$(sha256sum dist/example_0.1.0_linux_amd64.tar.gz | cut -d" " -f1)"'"}}],"predicate":{"verificationResult":"PASSED"}}\n' > vsa.json
run "$WA" --sign --statement vsa.json --out vsa.jsonl
run "$WA" --sign --statement vsa.json --append bundles/example_0.1.0_linux_amd64.tar.gz.intoto.jsonl --out vsa2.jsonl

printf '\nbundle after append:\n'
b=bundles/example_0.1.0_linux_amd64.tar.gz.intoto.jsonl
while IFS= read -r line; do
    payload="$(printf '%s' "$line" | jq -r '.dsseEnvelope.payload' 2>/dev/null | base64 -d 2>/dev/null)"
    printf '    %s\n' "$(printf '%s' "$payload" | jq -r '.predicateType // "?"' 2>/dev/null)"
done < "$b"

hr "4. Fail-closed behaviour"
printf 'sha512:%0128d\n' 0 > bad-algo.txt
run "$WA" assemble --metadata-root metadata/sbom --subjects-file bad-algo.txt --provenance provenance.jsonl --sign --bundle-dir b2 --statements-out s2.jsonl

{ printf 'dist/example_0.1.0_linux_amd64.tar.gz\n'; printf 'dist/example_0.1.0_linux_amd64.tar.gz\n'; } > dup.txt
run "$WA" assemble --metadata-root metadata/sbom --subjects-file dup.txt --provenance provenance.jsonl --sign --bundle-dir b3 --statements-out s3.jsonl

run "$WA" assemble --metadata-root metadata/sbom --subjects-file subjects.txt --sign --bundle-dir b4 --statements-out s4.jsonl

printf '{"hello":"world"}\n' > not-a-statement.json
run "$WA" --sign --statement not-a-statement.json --out nope.jsonl

hr "done"
