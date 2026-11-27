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

Committed on this branch as `19a6111` (`Deliver approve results on the first status poll.`).

### Push

`git push origin fix/app-bugs-20261126` failed:

```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
```

No credential workarounds attempted. Branch is local only: `19a6111` on top of `aec1092`.

### Dylan — ship Update 1 (1.6.1 build 5) to TestFlight

`gh` is not installed. xtool cannot upload (no iOS SDK on this host; xtool 1.24 has no App Store upload command). The ship path is the manual GitHub Actions workflow.

1. From a machine that is logged into GitHub (this repo: `https://github.com/ouijabored66/lumen-voice`):
   ```
   cd ~/src/lumen-voice
   git checkout fix/app-bugs-20261126
   git push -u origin fix/app-bugs-20261126
   ```
   If HTTPS still prompts, use SSH (`git remote set-url origin git@github.com:ouijabored66/lumen-voice.git`) or GitHub Desktop / the website to publish the branch.
2. GitHub → **Actions** tab → workflow **App Store** → **Run workflow**.
3. Branch dropdown: `fix/app-bugs-20261126` → **Run workflow**.
4. Wait for the macOS job to archive `ios/LumenVoice.xcodeproj` (scheme `LumenVoice`, version **1.6.1** build **5**) and `xcrun altool --upload-app` to TestFlight. Secrets required: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`.
5. App Store Connect → TestFlight: wait for processing, then submit that build for App Store review when you want it public.

**Update 1 status: code shipped to branch, awaiting Dylan's workflow run.**

### Server restart

`systemctl --user restart lumen-server` succeeded. Unit active, PID 709138, `python3 ~/src/lumen-voice/desktop/server.py`.

`GET /health` on the configured port **8790** (not 8787 — 8787 is a different process, `watch-relay/1.0`):

- No token → HTTP 401 `{"error": "unauthorized"}` (`Server: LumenDesktop/1.0`)
- With the saved Bearer token → HTTP 200 `{"ok": true, "os": "linux"}` (`X-Server-OS: linux`)

The async approve path from this branch is the live desktop server.

---

## Update 2 — setup-friction (`feat/setup-friction-20261126`)

Full writeup: `SETUP-FIX-LOG.md`. Headline:

- Pairing payload is local JSON `{"lumen":1,"urls":[...],"token":"..."}` in a QR drawn on the desktop with vendored Nayuki (`desktop/qrcodegen.py`). `GET /pair` is unauthenticated HTML; token never goes to a web QR API; provider key is not on that page.
- iOS: Scan QR in onboarding (4-step checklist, skippable, Demo Mode kept) and Settings; Keychain storage; `/health` connection test; manual URL+token fallback.
- `docs/app-store-listing.md` has description **and** promotional text (151 characters), de-scammed, for Dylan to paste. Not submitted to App Store Connect from here.
- Version **1.6.2** build **6**.
- Verified: `desktop/check_pair.py` and `desktop/check_actions.py` pass. After restart, live `GET /pair` is 200 with SVG; `GET /health` 401/200 as before.
- iOS not compiled (no Swift / xtool SDK). Push / Actions / listing paste are Dylan's, same path as Update 1.

### Dylan — ship Update 2 (1.6.2 build 6) to TestFlight

1. From a machine that is logged into GitHub:
   ```
   cd ~/src/lumen-voice
   git checkout feat/setup-friction-20261126
   git push -u origin feat/setup-friction-20261126
   ```
   If HTTPS still prompts, use SSH (`git remote set-url origin git@github.com:ouijabored66/lumen-voice.git`) or GitHub Desktop / the website to publish the branch.
2. GitHub → **Actions** tab → workflow **App Store** → **Run workflow**.
3. Branch dropdown: `feat/setup-friction-20261126` → **Run workflow**.
4. Wait for the macOS job to archive `ios/LumenVoice.xcodeproj` (scheme `LumenVoice`, version **1.6.2** build **6**) and upload to TestFlight. Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`.
5. App Store Connect: paste **Description** and **Promotional text** from `docs/app-store-listing.md`, then submit that TestFlight build for review when you want it public.

`git push origin feat/setup-friction-20261126` failed with the same auth error as Update 1:

```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
```

No credential workarounds attempted. Branch is local: `4d09c0a` on `feat/setup-friction-20261126`.

**Update 2 status: code shipped to branch, awaiting Dylan's workflow run.** Also paste listing text; that is not done from this host.
