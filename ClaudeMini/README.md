# Claude Mini

Small floating windows for macOS, each with its own shortcut. Press the shortcut anywhere to open the window, and press **Esc** or the same shortcut to hide it.

| Shortcut | Window |
|---|---|
| **⌥L** (Option+L) | Claude |
| **⌥M** (Option+M) | Web: a mini browser with an address bar. The ↗ button opens the current page in Google Chrome. |
| **⌥N** (Option+N) | Roblox (roblox.com). **Play** launches the Roblox app, because games can't run inside a web page. |

```
┌──────────────────────────────────┐
│ ‹  ▤          Claude        ✎  ✕ │  ← drag here to move
├──────────────────────────────────┤
│                                  │
│   How can I help you today?      │
│                                  │
│ ┌──────────────────────────────┐ │
│ │ Ask anything… ▌              │ │  ← cursor is already here
│ │ +              Opus 5.5 ▾  ↑ │ │  ← model switcher
│ └──────────────────────────────┘ │
└──────────────────────────────────┘
   ‹ back   ▤ chats   ✎ new chat   ✕ hide
```

- **Your real Claude account.** The window is claude.ai, so you get the newest models, the model picker, your full chat history, projects, and file uploads. It doesn't need an API key or separate billing.
- **Stays out of the way.** The window floats over the app you're in (including full-screen apps) without switching to another app, minimizing anything, or leaving full screen.
- **Ready to type.** The message box is focused as soon as the window opens.
- **Instant.** The page stays loaded in the background, so opening the window is just showing it.
- **Utility app.** It has no Dock icon, just a ✦ icon in the menu bar.

## Install

You need macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
cd ClaudeMini
./build.sh install      # builds, copies to /Applications, and launches
```

On first launch the window opens so you can sign in. You stay signed in after that.

To start it automatically, open the ✦ menu bar icon and choose **Launch at Login**.

### Signing in

- **Email (recommended):** Enter your email. If you get a code, type it into the window. If you only get a link, right-click it in the email, choose **Copy Link**, then pick **✦ → Sign In with Link from Clipboard**.
- **Google:** Google sometimes blocks sign-in inside embedded windows. If it does, use email instead. It signs you into the same account.

## Shortcuts

| Keys | Action |
|---|---|
| ⌥L / ⌥M / ⌥N | Open / hide Claude / Web / Roblox (works from any app) |
| Esc | Hide |
| ⌘N | New chat (Claude) or home page (Web, Roblox) |
| ⌘E | Chat history (Claude) |
| ⌘L | Jump to the address bar (Web) |
| ⌘[ / ⌘] | Back / forward |
| ⌘R | Reload |
| ⌘= / ⌘- / ⌘0 | Bigger / smaller / reset text |

## Changing the shortcut

Each window's shortcut is set in `Sources/ClaudeMini/Config.swift`. For example, to open Claude with **⌥Space**, change these three values in `static let claude`:

```swift
hotKeyCode: UInt32(kVK_Space), hotKeyModifiers: UInt32(optionKey), hotKeyLabel: "⌥Space",
```

Then run `./build.sh install` again. While Claude Mini is running, ⌥L, ⌥M and ⌥N open their windows instead of typing "¬", "µ" or the ˜ accent.

## Troubleshooting

**See what happens when you press the shortcut.** Run this in Terminal, press ⌥L, and watch the output:

```bash
log stream --level info --predicate 'subsystem == "com.calebnash.ClaudeMini"'
```

A working press looks like this:

```
hotkey  Hotkey event received
hotkey  Hotkey handler running; frontmost=com.apple.Safari secureInput=false
window  Show requested over com.apple.Safari: visible=true key=true onActiveSpace=true ...
window  Confirmed on screen: visible=true key=true onActiveSpace=true occlusionVisible=true ...
```

| What you see | What it means |
|---|---|
| A beep and **no** `Hotkey event received` | The keystroke never reached Claude Mini. macOS gave it to the frontmost app, which didn't use it and beeped. That's what happens in lockdown or kiosk apps (Safe Exam Browser, exam.net's locked mode, some games or remote-desktop apps) that take over the keyboard. Claude Mini can't and won't override that. Use it in a normal app or window instead. |
| `Registration ... RegisterEventHotKey=-9878` at launch | Another app already uses ⌥L. Pick a different shortcut (see above). |
| `Not on screen` then `Presentation blocked` | The shortcut worked, but the app in front kept other windows off the screen. The ✦ icon turns into ⚠︎ for a few seconds so you know it didn't open. |
| `Message box not found` | The page hasn't loaded yet or you're signed out. Press ⌘R. |

**✦ → Copy Diagnostics** copies the current state (shortcut registered, secure input, frontmost app, window level and visibility) so you can paste it into a bug report.

The shortcut uses Carbon's `RegisterEventHotKey`, so it needs **no** Accessibility or Input Monitoring permission.

## Notes

- Apps that use a locked-down kiosk mode (for example Safe Exam Browser) block every other window, so Claude Mini can't appear over them by design.
- Your sign-in is stored in WebKit's normal data store for this app (`~/Library/WebKit/com.calebnash.ClaudeMini`).
