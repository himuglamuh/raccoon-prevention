# raccoon-prevention

Auto-play Spotify on a headless Raspberry Pi whenever nothing else is playing —
great for keeping raccoons out of sheds, or just keeping a room sounding lived-in.

This is the **Chromium web-player kiosk** design: a Pi runs the Spotify Web
Player full-screen in Chromium (which registers as a Spotify Connect device
named `Web Player (Chrome)`), and a small dependency-free Python CLI keeps it
healthy, playing, and re-authorized.

> [!NOTE]
> Tested on a Raspberry Pi 5 running Debian 12 (Bookworm) with a Wayland
> (labwc) session and PipeWire audio.

## Why this exists / what's different

Earlier versions stored a Spotify **client secret** and a long-lived **refresh
token** in plaintext across several bash scripts (some world-readable). That is
exactly what you should not do. This rewrite:

- Uses the **PKCE** OAuth flow, so the tooling never needs a client *secret*.
- Keeps every secret **out of this repo** and out of the scripts, in one
  `0600` file under `~/.config/spotify-auto/` (this is a public repo).
- Stores the refresh token in one place and **rotates it atomically** (Spotify
  rotates the refresh token on every refresh; concurrent refreshes are
  serialized with a lock so they can't invalidate each other).
- Handles Spotify's **6-month refresh-token expiry** gracefully: it warns you
  before the wall, and on `invalid_grant` it drops a sentinel + alerts you
  (log, desktop `notify-send`, Telegram) instead of silently going quiet.
- Runs as a normal **user systemd timer** (no root cron, no `sudo`).

## Architecture

```
chromium kiosk (start-spot.sh)  ── Spotify Web Player, DevTools on 127.0.0.1:9222
        ▲   ▲                       registers Connect device "Web Player (Chrome)"
        │   │
spotify-kiosk.service             keeps the browser running (Restart=on-failure)
spotify-kiosk-watchdog.timer  ──▶ spotify-auto watchdog     (restart if wedged)
spotify-kiosk-nightly-restart ──▶ restart at 04:00          (preventive)
spotify-auto-resume.timer     ──▶ spotify-auto auto-resume  (play if idle, 4 min)
spotify-auto-tokencheck.timer ──▶ spotify-auto status --alert (daily; 6-mo wall)
spotify-auto-bot.service      ──▶ spotify-auto bot          (optional; Telegram commands)

secrets/state: ~/.config/spotify-auto/{config.env, token.json, auth-needed, ...}
```

`spotify-auto` is one Python 3 standard-library script (no pip installs):

| Subcommand | What it does |
|---|---|
| `reauth` | Interactive PKCE (re-)authorization. `--remote` authorizes from your phone via Tailscale Serve HTTPS. |
| `token` | Print a valid access token (refresh + rotate under lock; cached until ~60 s before expiry). |
| `status` | Token/device health; `--probe` queries Spotify live; `--alert` fires the 6-month-wall reminder. |
| `now-playing` | Print `Artist — Title` (used by `now-playing`/`marq-playing`). |
| `auto-resume` | If the kiosk is idle, start the configured context (+ repeat). Random-volume heartbeat when already playing. |
| `watchdog` | Probe DevTools + Connect-device presence; restart the kiosk after 3 consecutive failures. |
| `notify` | Send an alert; `--setup` configures Telegram; `--test` sends a test. |
| `bot` | Run the Telegram command bot (long-poll); control the kiosk from your phone. |

## Install

```bash
git clone https://github.com/himuglamuh/raccoon-prevention.git
cd raccoon-prevention
./install.sh            # symlinks bin/ + systemd units, creates config.env
```

`install.sh` symlinks (so `git pull` updates everything live):

- `bin/{spotify-auto,now-playing,marq-playing}` and `scripts/start-spot.sh` → `~/bin/`
- `systemd/*.{service,timer}` → `~/.config/systemd/user/`
- a starter `~/.config/spotify-auto/config.env` (0600) if none exists

Then follow **[docs/SETUP.md](docs/SETUP.md)**:

1. Create a Spotify app (PKCE), register both redirect URIs.
2. Fill in `~/.config/spotify-auto/config.env`.
3. `spotify-auto reauth` (on the Pi) or `spotify-auto reauth --remote` (phone).
4. `spotify-auto notify --setup` (optional Telegram alerts).
5. `./install.sh --enable` to enable + start the kiosk and timers.
6. `spotify-auto status --probe` to confirm.

## Control from Telegram (optional)

The same bot used for alerts can also take **commands**, so you can drive the Pi
from your phone. Enable it after `spotify-auto notify --setup`:

```bash
systemctl --user enable --now spotify-auto-bot.service   # ./install.sh --enable does this for you
```

Then message your bot:

| Command | What it does |
|---|---|
| `/status` | Token / device health (general). |
| `/status detailed` | Live probe: device list, kiosk presence, current track. |
| `/nowplaying` | What's playing right now. |
| `/resume` | Play the configured context if the kiosk is idle. |
| `/restart` | Restart the kiosk service. |
| `/reauth` | Re-authorize Spotify — the bot sends you a Tailscale link to approve. |
| `/health` | Quick liveness check. |
| `/log` | Tail the `spotify-auto` log (optional line count, e.g. `/log 40`). |
| `/help` | List commands. |

It uses Telegram **long-polling** (no public webhook / open port). **Only
`TELEGRAM_CHAT_ID` is authorized**; messages from any other chat are ignored.

## The 6-month wall (important)

Starting 2026, a Spotify refresh token **expires 6 months after you authorize**,
and refreshing it does **not** extend that. So periodic manual re-auth is
mandatory — there is no way around it. This tooling makes that survivable:

- `spotify-auto-tokencheck.timer` warns you (Telegram/desktop) ~14 days out.
- On `invalid_grant`, a `auth-needed` sentinel is written and you're alerted;
  playback tooling backs off cleanly instead of erroring in a loop.
- Recover any time with `spotify-auto reauth` (or `--remote` from your phone).

## Security

No secrets live in this repo. See **[docs/SECURITY.md](docs/SECURITY.md)** for
the model, file permissions, and what to do if a token leaks (short version:
Spotify account → **Apps → Remove Access**, then `spotify-auto reauth`).

## Not using raspotify?

Correct — this design plays through the browser, not a native daemon. If you
have a leftover raspotify install, `scripts/remove-raspotify.sh` removes it
cleanly (safe here because audio is PipeWire/Pulse, not ALSA).

## License

MIT — see [LICENSE](LICENSE).
