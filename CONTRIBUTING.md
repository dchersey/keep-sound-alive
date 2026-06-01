# Contributing

Thanks for your interest! This is a small, focused utility — the goal is to keep
it simple and reliable, not to grow features.

## Build & test

```sh
swift build            # build
swift test             # run the unit tests (HoldStack)
./build_app.sh --here  # build the .app bundle without installing
./build_app.sh         # build, sign, and install to /Applications
```

Requires macOS 15+ and a recent Swift toolchain (Swift 6 / Xcode 16).

## Layout

- `Sources/KeepAliveCore/` — the pure, testable hold-stack model (no AppKit/AVFoundation).
- `Sources/KeepAlive/` — the menu-bar app: audio engine, control server, menu.
  - `KeepAliveEngine.swift` — the inaudible tone (tune frequency/amplitude here).
  - `ControlServer.swift` — the localhost HTTP control endpoint.
  - `HoldStack` logic lives in Core so it can be unit-tested without a GUI.

## Guidelines

- Keep `KeepAliveCore` free of UI/audio imports so it stays unit-testable.
- Add or update tests in `Tests/KeepAliveCoreTests/` for any logic change; CI runs
  `swift build` + `swift test` on macOS.
- Keep the control endpoint **localhost-only** and generic — it shouldn't know
  about any particular caller.

## Reporting issues

Please include your macOS version, the device that's disconnecting (speaker /
headphones / model), and any lines from `~/Library/Logs/keep-alive.log`.
