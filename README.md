# Keep Sound Alive

A tiny macOS menu-bar app that stops your Bluetooth speakers and headphones from
falling asleep when nothing's playing — by quietly playing something.

## The problem

My soundbar and my AirPods Max kept *disconnecting on me*. Not because anything
was wrong — because nothing was **playing**. Bluetooth audio devices drop the
connection after a minute or two of silence to save power. Usually that's fine.
But:

- I wear the AirPods Max **just for noise cancelling** — no music — and a few
  minutes in, they'd quietly disconnect and ANC would stop.
- My soundbar would nod off between things, so the first second of the next video
  got swallowed while it woke back up and re-handshook.

The fix the internet suggests is "just play a silent audio file on a loop." That
works, but juggling a hidden media player is clunky. So this is that idea, done
properly: a menu-bar switch that plays a **continuous, inaudible tone** to keep
the current output device awake, and gets out of your way.

## What it does

- Plays a **20 Hz sine at very low volume** to whatever your current output device
  is. 20 Hz sits at the very bottom of human hearing — you won't hear it — but
  it's real, low-frequency signal, which is what keeps the route open. (An
  *ultrasonic* tone seems cleverer, but Bluetooth codecs roll off high
  frequencies, so the device never really "hears" it. Low and slow wins.)
- **Follows your output device.** Switch from the soundbar to AirPods mid-session
  and the tone moves with you.
- **Self-heals.** Bluetooth routes renegotiate constantly; if a hiccup ever stops
  the tone, a watchdog restarts it within a few seconds.
- **Turns itself off.** Each "keep awake" request has a timer (8h by default), so
  it never runs forever by accident.
- **Stays out of the way.** No Dock icon, no window — just a menu-bar toggle.

## Install

Requires **macOS 15+**. Build from source:

```sh
git clone https://github.com/dchersey/keep-sound-alive.git
cd keep-sound-alive
./build_app.sh          # builds, signs, installs to /Applications, opens it
```

`build_app.sh` code-signs with your local Apple Development identity; override or
skip with `SIGN_IDENTITY="..." ./build_app.sh` (empty string = unsigned).

## Using it

Click the menu-bar icon → **Turn on**. That's it. The icon shows on/off; the panel
shows how long the current hold lasts. **Launch at Login** is in the menu (and the
app adds itself there on first run, so it just works after a reboot).

## Automating it (control endpoint + CLI)

Keep Sound Alive runs a tiny **localhost-only** HTTP control endpoint on
`127.0.0.1:4500`, so other tools can switch it on and off. State is a **stack of
holds** — audio plays while at least one hold exists:

| Request | Effect |
| --- | --- |
| `POST /on` `{"minutes": 480}` | push a hold (optional duration, default 8h) |
| `POST /off` | pop a hold |
| `GET /status` | `{ "on": bool, "holds": N, "next_expiry": epoch \| null }` |

There's a CLI wrapper too:

```sh
bin/keepalive on            # push a hold (8h)
bin/keepalive on 120        # push a 2h hold
bin/keepalive off           # pop a hold
bin/keepalive status
```

**Why a stack instead of a simple on/off?** So independent things can ask for it
without stepping on each other. If you flip it on manually *and* a script turns it
on, that's two holds — when the script pops its hold, yours stays. Each caller just
pushes when it needs the device awake and pops when it's done; nobody has to track
who else wants it. (It's how I wire it to another app of mine that turns it on
during a session and off afterward, without ever clobbering a manual toggle.)

## Tuning

The tone lives in `Sources/KeepAlive/KeepAliveEngine.swift`:

```swift
let amplitude: Float = 0.05   // louder if a device ignores it; quieter if you feel it
let frequency = 20.0          // raise toward 30–40 Hz if 20 Hz rumbles your sub
```

If a device is stubborn, nudge the amplitude up; if you can faintly feel 20 Hz on a
subwoofer, nudge the frequency up (staying low enough to survive codec roll-off).

## Limitations

- It can't keep a device awake while your **Mac is asleep** — there's no audio to
  play then. It's for "Mac awake, nothing playing."
- A few subwoofers reproduce 20 Hz strongly enough to *feel*; see Tuning.

## Credits

Inspired by needing this for an [AirPods ANC auto-switcher](https://github.com/dchersey/noise-defense),
and by Tomasz Szynalski's [Online Tone Generator](https://www.szynalski.com/tone-generator/),
which is what made me realize a low-frequency tone keeps these devices awake.

## License

MIT — see [LICENSE](LICENSE).
