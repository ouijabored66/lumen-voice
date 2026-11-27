# SETUP-FIX-LOG — setup-friction update (branch `feat/setup-friction-20261126`)

Based on `fix/app-bugs-20261126`. Version **1.6.2** build **6**.

## Pairing payload

QR and copyable text on `GET /pair` (no auth) encode compact JSON:

```json
{"lumen":1,"urls":["http://<lan-ip>:<port>", "..."],"token":"<server token>"}
```

- `lumen` is `1` so the app ignores unrelated QR codes.
- `urls` is every non-loopback address `lan_ips()` found (Tailscale `100.x` included when present). The phone tries them in order against `GET /health` and keeps the first that answers.
- `token` is the existing `desktop/config.json` server token (or `LUMEN_TOKEN`). The provider key is never in the payload or the HTML.
- The iPhone parser also accepts `{"url":"...","token":"..."}` and `lumenvoice://pair?url=...&token=...` (repeated `url=` allowed).

QR is drawn **on this computer** with vendored Nayuki `desktop/qrcodegen.py` (MIT) via `desktop/qr.py`. No third-party QR web API. If drawing fails, the page still shows copyable URL(s) and token.

`GET /health` stays Bearer-authed. After the scan, the app stores URL + token (Keychain `server.token`, same as typing) then tests `/health`, then `/api/status` for the assistant name.

## Files changed

- `desktop/qrcodegen.py` — vendored encoder (Nayuki).
- `desktop/qr.py` — matrix + SVG helpers.
- `desktop/server.py` — `public_urls`, `pairing_payload`, unauthenticated `GET /pair` HTML page, startup print of `/pair` URLs. Other routes still require the token.
- `desktop/check_pair.py` — QR finder-pattern check, pair page without auth, health 401/200, provider key not leaked.
- `ios/LumenApp/Sources/LumenApp/Pairing.swift` — parse payload; `PairingOutcome`.
- `ios/LumenApp/Sources/LumenApp/PairScanner.swift` — AVFoundation QR scan + `PairScanButton`.
- `ios/LumenApp/Sources/LumenApp/LumenModel.swift` — `applyPairing` (Keychain + `/health`).
- `ios/LumenApp/Sources/LumenApp/OnboardingView.swift` — skippable 4-step checklist (start server, QR or manual, connection test, try a command). Demo Mode button kept.
- `ios/LumenApp/Sources/LumenApp/SettingsView.swift` — Scan QR in own-server mode; manual URL+token still there.
- `ios/LumenApp/Sources/LumenApp/ContentView.swift` — `lumenvoice://pair` opens the same apply path.
- Camera usage string in `ios/LumenApp/Info.plist`, `ios/Xcode/LumenVoice-Info.plist`, `ios/project.yml`. New Swift files in `project.pbxproj`.
- `docs/app-store-listing.md` — description **and** promotional text, de-scammed, for Dylan to paste.
- `README.md` — pair-page / scan steps (including Windows).
- Version: `1.6.1` build `5` → `1.6.2` build `6` (`project.yml`, `project.pbxproj`, `LumenApp/Info.plist`).

## Build / submission

- `python3 desktop/check_pair.py` → `ok`
- `python3 desktop/check_actions.py` → `ok`
- Live after `systemctl --user restart lumen-server`: `GET /pair` HTTP 200 HTML with inline SVG; `GET /health` 401 without token, 200 with token. Port from config (8790 on this host).
- No Swift toolchain on this host. iOS changes got a review pass and brace-balance check.
- xtool cannot archive/upload (SDK not installed; no upload subcommand). `gh` is not installed.
- `git push origin feat/setup-friction-20261126` — see GROK-APP-LOG.md; HTTPS prompts are disabled here.

## What remains for Dylan

1. Push the branch if the push from this session failed (same GitHub login as Update 1).
2. Actions → **App Store** → Run workflow on `feat/setup-friction-20261126` (version 1.6.2 build 6) → TestFlight.
3. App Store Connect: paste `docs/app-store-listing.md` (description + promotional text), then submit the TestFlight build for review.

Manual URL+token entry is unchanged as the fallback. Demo Mode still works from onboarding and Settings.
