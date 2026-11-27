# FIX-LOG — Lumen Voice app bugs (branch `fix/app-bugs-20261126`)

## Root causes

### Bug 1 — duplicate result bubbles
- `LumenModel.approve(_:)` sets the action to `.running` then `await watch(action)`,
  and `watch(_:)` appends one lumen message when the task reaches a terminal status.
- Nothing stops two `approve`/`watch` runs for the same action id: double-tapping
  Approve, or approving from the phone and the Watch at the same time (notification
  action → `respondToWatch` → `approve`, plus the in-app button → `approve`), starts
  two `watch` loops, and each appends its own result bubble.
- Retrying approve after the task already finished also re-enters `watch`, which
  immediately sees a terminal status and appends the result text again.
- `ContentView` renders `model.messages` as-is (`ForEach`), and `WatchSync` only
  reads messages — so the fix belongs at the model source, not the view.
- Phone model holds one copy; the Watch keeps its own `WatchEntry` history via
  `WatchModel.decideAction` (one copy per device surface — legitimate, untouched).

### Bug 2 — false "Couldn't reach your server to approve that"
- `Queue.approve()` in `desktop/actions.py` ran the command synchronously inside the
  HTTP handler, so `POST /api/action/<id>/approve` blocked for the whole task.
- `LumenModel.approve` used a 15 s timeout on that POST, so any task longer than ~15 s
  threw `URLError.timedOut`, and every timeout was reported as
  "Couldn't reach \<server> to approve that." — even though the server kept running
  the command to completion (proven 2026-11-26: an apt upgrade reported unreachable
  had run and finished).
- Additionally `run_command` capped every command at `RUN_TIMEOUT` (12 s), so long
  tasks could never actually complete server-side either.

## Files changed
- `desktop/actions.py` — `Queue.approve` now marks the item `running` and runs the
  command on a background thread, returning the `running` detail immediately (HTTP 200,
  same shape as before). `run_command` gained a `timeout` parameter (default 12 s);
  approved tasks run with `APPROVE_TIMEOUT` (600 s) to match the client's poll cap.
  `GET /api/action/<id>` (already in `desktop/server.py`, unchanged) is the poll
  endpoint: backward-compatible, no new endpoint needed.
- `desktop/check_actions.py` — approve assertions now wait for the background task to
  settle via a small poll helper (same terminal-state assertions as before).
- `ios/LumenApp/Sources/LumenApp/LumenModel.swift` — `approve` guards concurrent
  runs per action id (`approving` set) and treats an approve-POST timeout as "maybe
  still running, go poll" instead of failure; `watch` first does one quick status GET
  (unreachable there → the genuine "Couldn't reach … to approve that."), then polls
  every 4 s up to ~10 min (150 rounds). Result bubbles are appended once per action
  id (`deliveredResults` set). Wording kept: "Couldn't reach …" prefix and
  "Couldn't approve that." fallback unchanged, so `WatchSync`'s string checks still match.
- Version bump: `ios/project.yml` (`MARKETING_VERSION` 1.6 → 1.6.1,
  `CURRENT_PROJECT_VERSION` 4 → 5), generated `ios/LumenVoice.xcodeproj/project.pbxproj`
  (same two values, both targets), `ios/LumenApp/Info.plist` (`CFBundleShortVersionString`
  1.6 → 1.6.1, `CFBundleVersion` 4 → 5). Xcode `*-Info.plist` files use
  `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`, so they follow automatically.

## Build / submission
- No Swift toolchain on this host (`which swift xcodegen` → empty), so the Swift
  changes got a careful review pass plus a bracket-balance check (all balanced) instead
  of a compile. `desktop/check_actions.py` passes, and a live in-process probe of
  `desktop/server.py` + `actions.Queue` verified: approve POST → HTTP 200 `running`
  in 0.00 s (no longer blocks), GET poll → `running` → `done` with result
  `all-done` and spoken `Done. all-done`; unknown id → 404.
- xtool (`~/.local/bin/xtool`, v1.24.0) does run after `--appimage-extract` (FUSE is
  unavailable in this sandbox, so the AppImage can't mount directly), and
  `xtool auth status` shows signed in (Apple ID dylanpreed1995@gmail.com,
  Team 34X2T5QXVU, token valid to 22/11/2027).
- BLOCKER — could not build or submit, stopping per the brief (no guessing):
  1. `xtool sdk status` → "Not installed", and `xtool sdk install` needs a local
     `Xcode.xip`, `Xcode.app`, or `darwin.xtoolsdk` path. None exists anywhere on this
     host (searched `/home/dylanr`, `/opt`, `/usr/local`). No iOS build is possible
     with xtool here without that SDK file.
  2. xtool 1.24 has no App Store/TestFlight upload subcommand at all (subcommands are
     only setup/auth/sdk/new/dev/ds/devices/install/uninstall/launch). The repo's real
     ship path is the manual GitHub Actions workflow
     `.github/workflows/app-store.yml` (macOS runner: xcodebuild archive + altool
     upload to TestFlight with the `ASC_*` secrets).
- Next step for Dylan (exact): either drop an `Xcode.xip` on this host and run
  `xtool sdk install <path>` (then `cd ios/LumenApp && xtool dev build -c release -s -i`),
  or — simpler and the repo's supported route — commit this branch and run the
  "App Store" workflow by hand from the Actions tab; it archives `ios/LumenVoice.xcodeproj`
  (scheme LumenVoice, version now 1.6.1 build 5) and uploads to TestFlight. No push was
  made from here per the brief; the branch is ready locally.

## Final summary
- Bug 1 (duplicate bubbles): root cause was concurrent/retried `approve` calls each
  starting a `watch` loop that appended its own result message. Fixed at the model
  source with a per-action `approving` guard and a `deliveredResults` set; views and
  Watch relay untouched (Watch keeps its own legitimate per-device copy).
- Bug 2 (false "Couldn't reach"): root cause was a blocking approve POST (server ran
  the whole task in the request handler) combined with a 15 s client timeout, plus a
  12 s server-side run cap. Fixed by running approved tasks on a server background
  thread (HTTP 200 `running` immediately, same JSON shape — old app compatible),
  raising the approved-task cap to 600 s, and making the app submit-then-poll
  (4 s cadence, ~10 min cap) with "Couldn't reach …" reserved for a genuinely
  unreachable server. `WatchSync`'s `"Couldn't reach"` prefix and
  `"Couldn't approve that."` checks still match; no new server endpoint was needed
  (`GET /api/action/<id>` already serves status/result).
- Version bumped 1.6 (build 4) → 1.6.1 (build 5) in `ios/project.yml`, the generated
  `project.pbxproj`, and `ios/LumenApp/Info.plist`.
- Verified: `desktop/check_actions.py` passes; live approve→poll probe passes.
- NOT done: iOS compile, xtool build, App Store submission — blocked as detailed
  above. Branch `fix/app-bugs-20261126` holds all changes, unpushed.
- Note: this branch also carries Dylan's prior uncommitted `desktop/` edits
  (assistant INSTRUCTION wording, summarize budget 10/20, journalctl `--since -24h`,
  `_log_line` filter + matching `check_actions.py` updates) — they were already in the
  working tree and are untouched by this fix.
