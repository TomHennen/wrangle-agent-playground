# wrangle-agent-playground — PR #622 validation harness

Reusable end-to-end harness validating TomHennen/wrangle PR #622 (zizmor +
wrangle-lint flipped to `delivery: image`; zizmor wired online via the new
`github-token` scan input) on real GitHub Actions runners. `actions/scan` is
pinned at PR #622's head SHA, so the run exercises #622's catalog, run.sh docker
path, and github-token -> WRANGLE_EXTRA_GITHUB_TOKEN forwarding.

## Layout
- `main` — clean baseline: scan is green. Proves container dispatch (osv/zizmor/
  wrangle-lint each via `docker run` of their pinned ghcr image), zizmor online,
  SARIF upload, and the clean-passes gating case.
- `wrangle-622-findings` — planted findings: a vulnerable `requirements.txt`
  (osv), an unpinned + known-vulnerable action (zizmor, incl. the online-only
  `known-vulnerable-actions` audit), and a missing dependabot config
  (wrangle-lint). Scan is red.

## Re-validate (one dispatch each)
```
gh workflow run wrangle-validate.yml                                    # clean -> green
gh workflow run wrangle-validate.yml --ref wrangle-622-findings         # findings -> red (gating)
```

### Online A/B (proves the github-token reaches zizmor's container)
Run the findings branch online vs offline and diff zizmor's findings: the
online-only `known-vulnerable-actions` audit fires only when the token is
forwarded.
```
gh workflow run wrangle-validate.yml --ref wrangle-622-findings                   # online: known-vulnerable-actions present
gh workflow run wrangle-validate.yml --ref wrangle-622-findings -f online=false   # offline: that finding absent
```

The pre-suppression history also shows the A/B directly on `main`: the online
run failed on zizmor's online `ref-version-mismatch` audit while the offline run
of the same files passed. The harness now suppresses that one false positive
(the harness pin has no released version tag) via `.github/zizmor.yml`.
