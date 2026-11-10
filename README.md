# Kilit

A small macOS app that locks the physical keyboard, mouse and trackpad while letting software keep working. I built it so an AI agent (like Claude with computer use) can keep clicking and switching apps on my Mac while nobody else can touch it. It unlocks with Touch ID.

It also has a second mode similar to iPhone's Guided Access: it keeps the Mac inside one app until you enter a PIN.

## How it works

macOS lets an app watch every input event through an *event tap* (`CGEvent.tapCreate`). Each event carries the process ID of whoever sent it:

| Where the event came from | `eventSourceUnixProcessID` |
|---|---|
| Real keyboard / mouse / trackpad | `0` |
| A program posting events (e.g. an AI agent) | that program's PID |

In lock mode, Kilit drops every event whose source PID is `0` and lets everything else through. I checked this on my Mac with a test script before building on it.

When a physical key or click is blocked, Kilit asks for Touch ID (`LocalAuthentication`). A backup PIN can also be typed blind and confirmed with Enter, because Kilit still reads the keys it blocks.

### Modes

- **Keyboard + mouse lock:** physical input is blocked and synthetic input passes. Unlock with Touch ID or the PIN.
- **Single app (Guided Access style):** hides other apps and blocks ⌘Tab, ⌘Q, ⌘H, Spotlight, Mission Control and similar shortcuts. If you leave the app, it brings you back. Press Esc three times quickly, then enter the PIN. There is an optional time limit.

## Build

Needs macOS 14+ and the Xcode command line tools (`swiftc`).

```bash
./derle.sh
open Kilit.app
```

On first launch, give Kilit Accessibility permission in **System Settings → Privacy & Security → Accessibility**. Event taps don't work without it.

## Limits

- If Kilit crashes, input is no longer blocked. This is on purpose, so you can never get permanently locked out. Holding the power button always works too.
- While the Touch ID prompt is open, it can take focus for a few seconds.
- The app is ad-hoc signed, not notarized. On another Mac, open it with right-click → Open.

## Files

- `main.swift`: the whole app (AppKit + SwiftUI)
- `derle.sh`: build script that creates and signs `Kilit.app`
