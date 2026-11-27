# App Store Connect listing copy

Paste these into App Store Connect. Do not treat them as already submitted.

## Description

Lumen Voice needs a free desktop companion server on your own computer. The server runs on Windows, Linux, or Mac. The first setup takes about five to ten minutes: start the server, open the pair page it prints, and scan that QR code in the app (you can type the URL and token instead). After that, you talk on your iPhone or Apple Watch and Lumen answers using your hardware.

$2.99 one-time purchase. No subscription.

What the app does:

- You hold a button (or say “Lumen” while the app is open) and speak. Speech is turned into text on the iPhone. The Watch can do the same and hands the question to the phone when it is nearby.
- You choose how answers are produced: paste your own API key (Grok, Claude, Gemini, Groq, or OpenRouter) into the iPhone Keychain; or run the desktop server so the provider key never leaves that computer (or so text goes to local Ollama); or point at a chat URL you already have.
- When Lumen wants to run a command on the computer, it waits. Nothing runs until you tap Approve on the phone or the Watch. You can deny it.
- Chat stays on your devices. The developer of this app does not receive your questions and does not operate the AI.

Demo Mode works on the iPhone with no server and no key. Replies are simulated. Nothing is sent anywhere.

If you are not willing to run a small program on your computer, own-server mode will not work. The API-key path still needs a key you provide. That is the product.

Privacy policy: https://github.com/ouijabored66/lumen-voice/blob/main/PRIVACY.md

## Promotional text

Needs the free desktop server on your computer (Windows, Linux, or Mac). Pair in about 5–10 minutes with a QR code. $2.99 one-time purchase. No subscription.

(157 characters, App Store Connect limit is 170.)

## Keywords

Store name: **Lumen Voice + Watch**. Apple already indexes lumen, voice, and watch from that name, so those words are not repeated below.

Subtitle (proposed, 26 characters): `Private computer assistant`

The public App Store page shows no custom subtitle. The line under the name is the category Productivity, so the 30-character field looks unused. Paste this subtitle only if App Store Connect still has that field empty or filled with something that does not say what the app does.

Keywords (100 characters, no spaces after commas):

```
remote,control,pc,desktop,server,local,speech,talk,command,linux,windows,mac,own,ai,offline,terminal
```

Someone who wants this app searches for a way to talk to their own computer, run it from a phone, or keep an assistant on a private server. The subtitle carries private, computer, and assistant, and the keyword field uses the other 100 characters on the search words the name and subtitle do not already cover.

## What's New (version 1.6.3)

```
New: Pair by QR code. Open the pair page on your desktop server and scan it in the app — no more typing the server URL and token by hand. Manual entry is still there if you prefer it.

New: A guided first-run checklist walks through setup step by step.

Fixed: The same answer could appear twice. It can't now.

Fixed: Long-running tasks no longer end in a false "couldn't reach your server" error. Approved tasks now run in the background and the app checks back for the result.
```
