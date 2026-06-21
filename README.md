# wrangle-agent-playground

Throwaway scaffold for e2e-testing pending [wrangle](https://github.com/TomHennen/wrangle)
PRs against unmerged code. Nothing here is permanent.

It is a minimal Python consumer of wrangle's reusable build workflow
(`build_and_publish_python.yml`), mirroring the python build type in
`TomHennen/wrangle-test`. The build is verified against the **provenance**
policy tier (`policies/wrangle-provenance-python-v1.hjson`), the simplest
guaranteed-green baseline — the default tier needs all three scan tools
configured.

## Layout

- `python/` — a trivial buildable package (`add()`) plus one pytest test.
- `.github/workflows/e2e.yml` — calls wrangle's reusable Python workflow.

## E2e-testing a pending wrangle PR

1. In `.github/workflows/e2e.yml`, edit the single `uses:` ref:

   ```yaml
   uses: TomHennen/wrangle/.github/workflows/build_and_publish_python.yml@main
   ```

   Change `@main` to the PR's branch name, e.g.
   `@my-feature-branch`. That one line is the only edit point.

2. The wrangle PR must carry its **bootstrap pins** so the nested
   `verify_release` / `verify` / `attest_provenance` composites resolve to
   the PR's code, not main. (See wrangle's `docs/e2e_testing.md`.)

3. Commit and push (or run the `e2e` workflow via `workflow_dispatch`),
   then read the run:

   ```sh
   gh run list --repo TomHennen/wrangle-agent-playground --workflow e2e.yml
   gh run watch <run-id> --repo TomHennen/wrangle-agent-playground
   ```

Keyless signing works on this public repo via ambient GitHub OIDC — no
secrets needed. The signing identity is wrangle's reusable workflow, not
this caller, so the wrangle policy's `wrangle-builder` identity matches.
