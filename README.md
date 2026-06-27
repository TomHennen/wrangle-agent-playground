# wrangle-agent-playground — PR #622 validation harness

Reusable end-to-end harness validating TomHennen/wrangle PR #622 (zizmor +
wrangle-lint flipped to `delivery: image`; zizmor wired online via
`github-token`) on real GitHub Actions runners.

## Layout
- `main` — **clean baseline**: scan is green (no findings). Proves container
  dispatch, zizmor online, SARIF upload, and the clean-passes gating case.
- `wrangle-622-findings` — planted findings (osv vuln dep, zizmor unpinned +
  known-vulnerable action, wrangle-lint missing dependabot config). Scan is red.

## Re-validate (one dispatch)
```
gh workflow run wrangle-validate.yml                     # online (default)
gh workflow run wrangle-validate.yml -f online=false     # offline A/B (zizmor token dropped)
gh workflow run wrangle-validate.yml --ref wrangle-622-findings   # gating: red
```

The harness pins `actions/scan` at PR #622's head SHA. Bump that pin to
re-target a different ref.
