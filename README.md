# Keep Sound Alive

A tiny macOS menu-bar utility that keeps a Bluetooth audio device (AirPods Max, a
soundbar, …) from idle-disconnecting, by playing a continuous **inaudible** tone
(~-70 dB, near-ultrasonic) to the current default output.

It's fully generic — it knows nothing about any particular caller. State is a
**LIFO stack of holds**, each with its own expiry timer (8h default). Audio plays
while the stack is non-empty:

- the menu toggle pushes/pops a manual hold;
- external apps push/pop holds over a localhost control endpoint;
- a hold also drops off when its timer expires.

So callers are stateless: push when you start needing it, pop when you're done. If
two holds coexist, popping one leaves the other.

## Control endpoint (localhost `127.0.0.1:4041`)

    POST /on   {"minutes": 480}  -> push a hold   -> {"ok":true,"holds":N}
    POST /off                    -> pop a hold     -> {"ok":true,"holds":N}
    GET  /status                 -> {"on":bool,"holds":N,"next_expiry":epoch|null}

CLI wrapper: `bin/keepalive on [minutes] | off | status`.

## Build

    ./build_app.sh            # build + install to /Applications, then `open` it
    swift test                # unit tests (HoldStack)

Requires macOS 15+. The app is a signed `LSUIElement` agent (no Dock icon).
