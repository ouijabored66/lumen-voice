# Lumen Voice

App Store: https://apps.apple.com/app/id6836863521

Source: https://github.com/ouijabored66/lumen-voice

A free iPhone and Apple Watch voice app. You talk on the device. Lumen answers with one of three connections:

- **Your API key.** One key, stored in the iOS Keychain. The app detects Grok (`xai-`), Claude (`sk-ant-`), Gemini (`AIza`), Groq (`gsk_`), or OpenRouter (`sk-or-`) and shows "Connected to …". The screen shows only the last four characters. A plain OpenAI key (`sk-` that is not `sk-ant-` or `sk-or-`) is not detected. For that, use Cloud / custom provider and the provider's chat URL.
- **Your own server.** `python3 desktop/server.py` forwards text. The provider key stays on that computer, or text goes to Ollama. The default port is **8787**. Set `LUMEN_PORT` to use another port. `python3 server/server.py` is the older text server on port **4100** (it also reads `LUMEN_PORT`).
- **Cloud / custom provider.** A local or cloud chat address. Auto tries the local URL first. A cloud address uses the same one key.

Speech uses Apple's on-device Speech and `AVSpeechSynthesizer`. Recordings stay in memory and are discarded. Nothing in this repo uploads dictation or plays a WAV from a server.

There is no subscription.

## Install

Get it on the App Store: https://apps.apple.com/app/id6836863521

### First launch

The first screen says "How should Lumen think?"

- To try it with no key and no server: close that screen, tap the sliders button at the top, and turn on Demo Mode under "Try it without a server". You get sample replies. Nothing is sent off the phone.
- To use your own key: tap Use your API key, paste a Grok, Claude, Gemini, Groq, or OpenRouter key, and tap Save and connect. When it works you see "Connected to …", and the screen shows only the last four characters of the key.

## Desktop server

```bash
python3 desktop/server.py
```

On first run it writes `desktop/config.json` (gitignored) with a random token and prints that token plus the LAN URL. In the iPhone app choose **Run your own server** and enter them.

The listen port is `8787` unless `desktop/config.json` or the environment says otherwise:

```bash
LUMEN_PORT=8787 LUMEN_PROVIDER_KEY=… python3 desktop/server.py
```

`LUMEN_PROVIDER_KEY` is the assistant key on that computer (`xai-` Grok, `sk-ant-` Claude, `AIza` Gemini, `gsk_` Groq, `sk-or-` OpenRouter). The same value can be `provider_key` inside `desktop/config.json`. With no key, text goes to Ollama at `http://127.0.0.1:11434` (model `llama3.2`, or `LUMEN_OLLAMA_MODEL`).

On the same network, publish the server with Tailscale Serve so the phone uses HTTPS:

```bash
tailscale serve --bg --https=443 http://127.0.0.1:8787
```

Use the port you actually started (`LUMEN_PORT`, otherwise 8787). Don't put the server on the open internet without HTTPS.

`server/server.py` listens on `127.0.0.1:4100` and speaks the same text API. It does not take audio. The unit `linux/systemd/lumen.service` is that older server (it expects `~/lumen/server.py`). The desktop server unit is `linux/systemd/lumen-server.service`.

### PC task approvals

Approve and Deny work only when the iPhone is in **Run your own server** mode and is talking to `desktop/server.py`. They do not run in API key mode or Cloud / custom provider mode.

The server proposes a shell command and does not run it. Nothing runs until you tap Approve. Deny drops it. A pending command expires after about 10 minutes. Approval still goes through the phone, including when you tap Approve on the Watch. After it runs, the reply is a short spoken summary with the key numbers. The full output stays under Details. A command that prints output and then exits with an error still counts as done, with a note.

On Linux the command runs in the POSIX shell (`df -h` for disk space). On Windows it runs in PowerShell, not in cmd (`Get-PSDrive -PSProvider FileSystem` for disk space). The server tells the assistant which shell this computer uses. Status responses send `X-Server-OS: linux` or `X-Server-OS: windows`, and the app lights that system.

### Phone without the Tailscale app

Tailscale Funnel gives the phone a public HTTPS address, so the phone does not need the Tailscale app:

```bash
tailscale funnel --bg --https=8443 http://127.0.0.1:8787
```

That address is on the open internet. The token is the only protection. Turn it off with:

```bash
tailscale funnel --https=8443 off
```

### Keep the desktop server running (Linux)

Clone the repo to `~/lumen-voice` (the `main` branch). Then:

```bash
mkdir -p ~/.config/systemd/user
cp linux/systemd/lumen-server.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now lumen-server.service
```

`ExecStart` is `/usr/bin/python3 %h/lumen-voice/desktop/server.py` and `Restart=on-failure`. `loginctl enable-linger "$USER"` keeps it up when you are logged out. Put `LUMEN_PORT` and `LUMEN_PROVIDER_KEY` in `~/.config/environment.d/lumen.conf` or in `desktop/config.json` if you do not want them only in the shell that started the process.

## Windows

This runs the small server on your Windows computer so the iPhone can use it. The phone and the computer need to be on the same Wi-Fi. Leave the server window open, or the phone cannot reach it.

1. Open PowerShell. Click Start, type `PowerShell`, and click Windows PowerShell. A blue window opens.
2. Install Python. Open [python.org/downloads/windows](https://www.python.org/downloads/windows/) and download Python 3.12. Run the installer. On the first screen, check **Add python.exe to PATH**, then click **Install Now**. When it finishes, close the blue window, open PowerShell again, type `python --version`, and press Enter. You should see `Python 3.12`. If it says Python was not found, the PATH box was not checked. Run the installer again and check it.
3. Download Lumen. Open [github.com/ouijabored66/lumen-voice](https://github.com/ouijabored66/lumen-voice). Click the green **Code** button, then **Download ZIP**. In your Downloads folder, right-click the zip, click **Extract All**, then **Extract**. You get a folder named `lumen-voice-main`.
4. Start the server. In the blue window, type `cd` and a space. Drag the `lumen-voice-main` folder onto the window, then press Enter. Type `python desktop\server.py` and press Enter. Leave this window open. Closing it stops the server.
5. Read the address and the token. The window prints `Lumen desktop server`, then lines like this:

   ```text
   In the iPhone app choose Run your own server and enter:

     URL    http://…:8787
     Token  (a long random string)
   ```

   The numbers after `http://` are your computer's address. Use a line that does not say `127.0.0.1`. The token is the line that starts with `Token`. The first run also saves both in `desktop\config.json`, inside the folder you unzipped.
6. Type them into the iPhone. Open Lumen. On the screen that says "How should Lumen think?", tap **Run your own server**. You will see **Your server**, a box that says `https://…`, and **Server token**. Paste the URL into the box and the token into Server token. Tap **Save and connect**. If you already closed that screen, tap the sliders button at the top. The screen title is Settings. Set **Connection** to **Run your own server**, fill in the same two lines, and tap **Save and connect**. When it works, that row says Online or In use.
7. Allow the firewall prompt. Windows may show a window that says it blocked some features of Python. Check **Private networks**. Leave **Public networks** unchecked. Click **Allow access**. If you click Cancel, the phone on your Wi-Fi cannot connect.
8. Keep it running when you sign in. You only need to do this after the window has printed a URL once. Click Start, type `Task Scheduler`, and open it. Click **Create Basic Task**. Name it `Lumen Desktop Server` and click Next. Choose **When I log on**, then Next. Choose **Start a program**, then Next. In Program/script, click Browse and choose `python.exe` (the same Python from step 2). In Add arguments, type `desktop\server.py`. In Start in, paste the path of the `lumen-voice-main` folder. Click Next, then Finish. After the next sign-in you will not see the blue window. The address and token stay the ones already printed.

With no provider key, the server sends text to Ollama on this PC if Ollama is already running. Adding a key is in Advanced, below.

### Advanced

The default port is **8787**. To use another port, or to give the server a provider key, set them in the same PowerShell window before you start the server. A key set only in that window is forgotten when you close it. For the sign-in task, put `port` and `provider_key` in `desktop\config.json` instead.

```powershell
$env:LUMEN_PORT = "8787"
$env:LUMEN_PROVIDER_KEY = "paste-the-provider-key"
python desktop\server.py
```

`LUMEN_PROVIDER_KEY` is `xai-` Grok, `sk-ant-` Claude, `AIza` Gemini, `gsk_` Groq, or `sk-or-` OpenRouter.

The same sign-in task can be registered from PowerShell. Environment variables from one window are not copied into the task.

```powershell
$repo = (Resolve-Path .).Path
$py = (Get-Command python).Source
$action = New-ScheduledTaskAction -Execute $py -Argument "desktop\server.py" -WorkingDirectory $repo
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
Register-ScheduledTask -TaskName "Lumen Desktop Server" -Action $action -Trigger $trigger -Force
```

`windows/Setup-Lumen-Windows.ps1` does not start `desktop/server.py`. It installs the older text server (`server/server.py`, port 4100). It looks for an `app` folder with `server.py` next to the script, installs Python 3.12 with winget if it is missing, copies that folder to `%LOCALAPPDATA%\Lumen`, and registers a scheduled task named "Lumen Server" that starts at startup and at sign-in. If Tailscale is installed it also runs `tailscale serve` on port 443. Windows blocks scripts by default. This command applies Bypass only to that process:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\Setup-Lumen-Windows.ps1
```

Remove that task and turn Serve off with `-Uninstall`. The copied files stay in `%LOCALAPPDATA%\Lumen`.

Tailscale Serve keeps the desktop server on your tailnet. The phone needs the Tailscale app:

```powershell
tailscale serve --bg --https=443 http://127.0.0.1:8787
```

Funnel is for a phone that does not have the Tailscale app. That address is public and protected only by the token:

```powershell
tailscale funnel --bg --https=8443 http://127.0.0.1:8787
tailscale funnel --https=8443 off
```

Approved PC commands on Windows run in PowerShell (`powershell.exe -NoProfile -NonInteractive -Command`), not in cmd and not in bash. A command such as `Get-PSDrive -PSProvider FileSystem` or `Get-ChildItem` fits. `df` does not. The app shows Windows when the server sends `X-Server-OS: windows`.

## Cloud / custom server troubleshooting

**Won't save the password/key.** On the main API Key screen only Grok, Claude, Gemini, Groq, or OpenRouter keys are accepted. For your own relay, choose Cloud / custom provider, enter the Cloud URL, paste the password into its API key field, and tap Save key. It shows Key saved, then tests the connection. Any non-empty password is sent as Authorization: Bearer.

**The assistant sent an empty reply.** The server took longer than the app waited, the app retried `/api/ask`, and got a voice-clip-style NDJSON answer. The server's `/api/ask` must accept JSON `{"text":"..."}` and return one JSON object `{"say":"..."}` like `/api/text`, and should reuse an identical in-flight question. Newer builds wait up to 120s.

## iPhone and Watch

Bundle IDs:

- `ouijabored66.lumenvoice`
- `ouijabored66.lumenvoice.watchkitapp`

Marketing version **1.6**.

The Watch works on its own once Cloud is set up on the iPhone, even when that app is closed or the phone is away. It needs Wi-Fi or cellular. It records with its microphone. Nearby, that recording goes to the iPhone. On its own, the Watch turns the recording into text, then asks. If the iPhone does not answer in about 5 seconds, the Watch switches to Direct.

Tapping the complication starts that recording and speaks the reply on the Watch. Text chat stays on the screen. The keyboard appears only when you tap the text field.

Replies can take up to about 2 minutes. The Watch stays awake while it shows "Lumen is answering" and retries once if a request fails. Status shows "Via iPhone" or "Direct".

When a task needs a yes or no, the Watch shows Approve and Deny. That only works in Run your own server mode, with `desktop/server.py` running. The tap goes to the iPhone, which talks to that computer. If the iPhone is out of reach, the request stays waiting. API key mode and Cloud / custom provider mode do not propose or run PC commands.

### Hands-free

Settings → Hands-free → *Say "Lumen" to talk*. Recognition stays on the iPhone, and only while the app is open on screen. Say "Lumen", wait for the buzz, then speak.

Siri: "Hey Siri, Ask Lumen".

### Talk button

Tap Talk to record. Tap again to send.
