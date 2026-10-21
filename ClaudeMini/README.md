# Claude Mini

A small floating Claude window for macOS. Press **⌘L** anywhere to open it, and press **Esc** or **⌘L** again to hide it.

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
| ⌘L | Open / hide (works from any app) |
| Esc | Hide |
| ⌘N | New chat |
| ⌘E | Chat history |
| ⌘R | Reload |
| ⌘= / ⌘- / ⌘0 | Bigger / smaller / reset text |

## Changing the shortcut

⌘L is also the "go to address bar" shortcut in browsers. Claude Mini takes it over everywhere while it's running. To use something else, such as **⌥Space**, edit `Sources/ClaudeMini/Config.swift`:

```swift
static let hotKeyCode = UInt32(kVK_Space)
static let hotKeyModifiers = UInt32(optionKey)
static let hotKeyLabel = "⌥Space"
```

Then run `./build.sh install` again.

## Notes

- Apps that use a locked-down kiosk mode (for example Safe Exam Browser) block every other window, so Claude Mini can't appear over them by design.
- Your sign-in is stored in WebKit's normal data store for this app (`~/Library/WebKit/com.calebnash.ClaudeMini`).
