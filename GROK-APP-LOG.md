# GROK-APP-LOG — Lumen Voice app work (Grok, 2026-11-26)

Repo: `~/src/lumen-voice`. Assignment from `GROK-APP-BRIEF.md`.
Do not touch `~/bayouos`.

## Update 1 — bug fixes (`fix/app-bugs-20261126`, aec1092)

### Sanity review (`git diff main...fix/app-bugs-20261126`)

Reviewed the 7-file diff against local `main` (5f49b8d). Matches `FIX-LOG.md`:

- Duplicate result bubbles: per-action `approving` set + `deliveredResults` set in `LumenModel.approve` / `watch`. Views and Watch relay untouched.
- False "Couldn't reach": `Queue.approve` returns `running` immediately and finishes on a daemon thread; `run_command` takes `timeout=` (approved tasks use `APPROVE_TIMEOUT` 600s). Client POST timeout 30s falls through to poll; first status GET is the genuine unreachable check; then 4s × 150 (~10 min). "Couldn't reach" prefix and "Couldn't approve that." fallback unchanged.
- Tests in `desktop/check_actions.py` wait via `_settled`.
- Version 1.6.1 build 5 in `ios/project.yml`, `project.pbxproj`, `ios/LumenApp/Info.plist`.
- Prior desktop wording / journalctl / `_log_line` edits are in this commit (already in the tree when Muse Code fixed the bugs).

Note: local `main` is behind `origin/main` (origin has 1.6.2 build 5/6 and later Watch/App Store commits). This branch is based on local `main` as the brief asked. Reconcile with origin is Dylan's call when merging.

Small issue found and fixed (see next commit): `watch` used the first status GET only as a reachability probe and then always slept 4s before reading a terminal status. A fast task that was already `done` on that first GET waited an extra 4 seconds. The first GET now delivers a terminal result immediately. Comment on `actionStatus` claimed a 404 still decoded; the code requires HTTP 200, so 404 is treated as unreachable/miss and the comment was corrected.

No other problems in the diff.
