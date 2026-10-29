# Samsung TV Remote for Mac

A small native menu bar remote for Samsung TVs.

<img src="docs/remote.png" width="288" alt="Samsung TV Remote with navigation, volume and playback controls">

## Keyboard shortcuts

While the remote is open:

| Key | Action |
| --- | --- |
| <kbd>↑</kbd> <kbd>↓</kbd> <kbd>←</kbd> <kbd>→</kbd> | Navigate |
| <kbd>Return</kbd> | OK |
| <kbd>Backspace</kbd> | Back |
| <kbd>Space</kbd> | Play / pause |
| <kbd>+</kbd> / <kbd>−</kbd> | Adjust volume |
| <kbd>H</kbd> | Home |
| <kbd>M</kbd> | TV menu |
| <kbd>I</kbd> | Inputs |
| <kbd>U</kbd> | Mute |

## Install

Requires macOS 14 or later and a Samsung Tizen TV on the same network.

[Download the app](https://github.com/alken01/samsung-tv-remote-mac/releases/latest/download/Samsung-TV-Remote.zip), unzip it and move Samsung TV Remote to Applications.

To build from source:

```sh
scripts/build-app.sh
```

Copy `build/Samsung TV Remote.app` to Applications and open it.
