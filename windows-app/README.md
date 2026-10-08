# 🪟 Cariberry for Windows

The same Cariberry as the Mac app, rebuilt for Windows 10 and 11: the same eight animals drawn the same way, the
same voices and lo-fi music (the audio was rendered by the Mac app's own synthesiser), the same Home / Focus /
Closet / Settings panel, stats scrapbook, sticky notes, study card, XP, berries, badges and habits.

It is an [Electron](https://www.electronjs.org) app. The pet's art and her brain are straight ports of the Swift code
(`src/shared` is `Critter.swift`, `src/engine` is `Pet.swift`), so she behaves the same.

## Install

Download `CariberrySetup.exe` from [`../download/windows`](../download/windows/README.md) and double-click it. It
installs for your account only (no administrator prompt), starts Cariberry, and adds a Start-menu entry. She only
starts with Windows if you turn on **Settings ▸ Her ▸ Start with Windows**.

## Which Windows

| Your PC | Works? |
|---|---|
| Windows 10 and 11 (64-bit), and whatever Windows comes next | yes: `CariberrySetup.exe` |
| Windows 11 or 10 on an ARM chip (Surface Pro X, Snapdragon laptops) | yes: `CariberrySetup.exe` works through Windows' own emulation, or `CariberrySetup-arm64.exe` runs natively |
| Windows 10, 32-bit | yes: `CariberrySetup-32bit.exe` |
| Windows 7, 8, 8.1 | no. The installer says so and stops. Microsoft ended support for them, and so did the engine Cariberry is built on (Electron dropped them in version 23) |

Not sure which you have? **Settings ▸ System ▸ About ▸ System type** says "64-bit" or "32-bit", and "ARM-based" if it is one.

She copes with unusual setups: if PowerShell is blocked by your school or work, she reads the window title instead of the address bar; if the
graphics driver can't draw her (virtual machines, remote desktop), she restarts once and draws in software; if a Windows call fails, that one
feature switches off and the rest keeps working. `Cariberry.exe --diagnose` shows which is which.

## What's different from the Mac, and why

| | Mac | Windows |
|---|---|---|
| Opening the panel | menu bar icon, or right-click her | tray icon (bottom right, by the clock), or right-click her |
| Reading your browser tab | AppleScript, needs a permission | the window title, plus the address bar through Windows UI Automation. No permission needed |
| Other apps | by name | by program name (`code.exe`, `spotify.exe`…) |
| Chat brain | a separate Python program | built in: Ollama, ChatGPT or Gemini, or her own voice with no setup |
| API keys | Keychain | encrypted for your Windows account (DPAPI) in `secrets.json` |
| "Bop to my music" | ScreenCaptureKit (a permission) | system-audio loopback (no permission, no recording indicator) |
| Full-screen apps | pet hidden unless *Above fullscreen apps* is on | the same: she steps aside for a full-screen game or video |
| Hands-free "Hey Cranberry" | optional, you train a wake word | not on Windows. Typing in the chat does everything it does |

Chat commands work on Windows: *"open Spotify"*, *"close Chrome"*, *"open Notion and start my study playlist"*,
*"focus 25"*, *"dance"*. "Study playlist" starts her own lo-fi radio unless you name Spotify.

The **Guard these** section of Settings shows what she can see right now ("👀 Right now she sees: Chrome: instagram.com/reels/…"),
so you can check browser awareness is working.

## Where her things live

`%APPDATA%\Cariberry\`: `pet.json` (her save), `prefs.json` (settings), `rules.json` (what counts as work or a distraction;
**Settings ▸ More options ▸ Edit rules file** opens it), `secrets.json` (encrypted chat keys), and a `Sounds` folder you can create: put
`purr`, `bell` or `click` (.wav, .mp3, .m4a, .ogg or .flac) in it and they replace hers. Uninstalling keeps them. Delete the folder for a fresh start.

If something looks wrong, run `Cariberry.exe --diagnose`. It writes `cariberry-diagnose.txt` to the Desktop showing what she can see.

The tray icon can end up in the "^" overflow: drag it onto the taskbar to keep it visible.

## Build it

You need Node.js 22 or newer. You can build the Windows installers on a Mac or on Windows itself.

```bash
cd windows-app
npm install
npm run dist          # makes the three installers in dist/ and copies them to ../download/windows/
npm run dist -- x64   # just the main one (quicker)
```

The installer isn't code-signed, so Windows SmartScreen shows "Windows protected your PC" the first time:
click **More info ▸ Run anyway**. To remove the warning, sign it with a code-signing certificate
(on Windows, set `CSC_LINK` and `CSC_KEY_PASSWORD` and set `win.signAndEditExecutable` to `true` in `electron-builder.yml`).

### While developing

```bash
npm start             # runs the app (on a Mac too, with the Windows-only parts switched off)
npm test              # engine, rules, chat brain and monitor tests
node dev/serve.mjs    # then open http://localhost:8123/dev/harness.html?page=panel&seed=1
```

The harness runs the real engine in a normal browser tab so the panel (`page=panel`), stats window (`page=stats&seed=stats`)
and cards (`page=cards&kind=mood|note|chat|toast|story`) can be looked at without launching the app. Add `&theme=darkAcademia`
(or any other theme) and `&full=1` to see a whole tab at once.

`CARI_FAKE_ACTIVITY='{"exe":"chrome.exe","name":"Google Chrome","title":"Instagram","browser":true,"url":"instagram.com/reels/x"}' npm start`
pretends that's what is in front, to try the coaching without Windows.

## How it fits together

```
src/main/        the app shell (Electron's main process)
  main.js          windows, tray, files on disk, and the glue between everything
  windows.js       the pet window, panel, stats, cards; where each one goes on screen
  monitor.js       what's in front, every 2 s (and the address bar, through UI Automation)
  win32.js         the few Windows calls she needs, through koffi: foreground window, Ctrl+W, full-screen check
  brain.js chat.js the chat: LLM clients and "open Spotify" style commands
  secrets.js       encrypted API keys           store.js  her JSON files
src/renderer/    the pages
  pet.html/js      the pet window: she is drawn here, and the engine runs here (runtime.js)
  panel/ stats/ cards/   the control panel, the stats window, the floating cards (built on ui/mini.js)
src/engine/      Pet.swift, ported: her moods, needs, XP, rules, dialogue
src/shared/      Critter.swift and the scene, ported: every pixel of her is drawn in code
assets/          her voices and the lo-fi music, rendered by the Mac app (`DesktopPup --render-voices`, `--render-lofi`)
```

Everything is plain JavaScript modules with no build step. She opens no network ports and runs no helper programs, apart from two uses of
PowerShell: one that reads the browser's address bar (only while browser awareness is on and a browser is in front; it exits a minute after
you leave the browser) and one that closes an app when you ask her to in chat.

Third-party code and fonts are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
