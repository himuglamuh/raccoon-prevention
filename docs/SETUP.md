# Setup

Step-by-step setup for the Chromium web-player kiosk + `spotify-auto`.

Prerequisites: a Raspberry Pi (or any Linux box) with a graphical session
running Chromium, `python3`, and `systemd --user`. For `--remote` re-auth and
remote alerts you'll also want Tailscale.

---

## 1. Spotify app (PKCE — no client secret)

1. Go to <https://developer.spotify.com/dashboard> → **Create app**.
2. Note the **Client ID**. You do **not** need the client secret for this
   tooling (PKCE doesn't use one).
3. Under the app's **Redirect URIs**, add **both**, verbatim:
   - `http://127.0.0.1:8080/callback` — local re-auth on the Pi.
     (Use `127.0.0.1`, not `localhost`; Spotify requires the loopback IP.)
   - `https://<your-pi>.<your-tailnet>.ts.net/callback` — remote re-auth from
     your phone via Tailscale Serve.
4. Save.

> The redirect URIs must match what's in `config.env` character-for-character,
> including the port and `/callback` path.

---

## 2. Tailscale (for `--remote` re-auth and off-LAN alerts)

1. Install Tailscale on the Pi and `tailscale up`.
2. Enable **MagicDNS** and **HTTPS certificates** in the Tailscale admin console.
3. Confirm your Pi's tailnet name, e.g. `your-pi.your-tailnet.ts.net`.

`spotify-auto reauth --remote` runs `tailscale serve --bg <port>` for you to
expose the local callback over HTTPS, then `tailscale serve reset` to tear it
down. (If `tailscale serve` needs root on your setup, it retries with `sudo`.)

This uses Tailscale **Serve** (private, tailnet-only), not Funnel — the callback
is never exposed to the public internet.

---

## 3. Install the tooling

```bash
git clone https://github.com/himuglamuh/raccoon-prevention.git
cd raccoon-prevention
./install.sh
```

This symlinks the executables and units and creates a starter
`~/.config/spotify-auto/config.env`.

---

## 4. Configure

Edit `~/.config/spotify-auto/config.env` (it's `0600`; keep it that way):

```ini
CLIENT_ID=<your client id>
REDIRECT_URI=http://127.0.0.1:8080/callback
REMOTE_REDIRECT_URI=https://your-pi.your-tailnet.ts.net/callback
REMOTE_LISTEN_PORT=8080
CONTEXT_URI=spotify:playlist:<id>
DEVICE_NAME="Web Player (Chrome)"
```

Get `CONTEXT_URI` from the Spotify app: right-click a playlist/album/artist →
**Share → Copy Spotify URI**.

---

## 5. Authorize

On the Pi (a browser there will hit the loopback redirect):

```bash
spotify-auto reauth
```

…or from your phone / another tailnet device:

```bash
spotify-auto reauth --remote
# open the printed URL on your phone, approve, done
```

Either way the refresh token is written to `~/.config/spotify-auto/token.json`
(`0600`) with the authorization timestamp used for the 6-month-wall reminder.

Verify:

```bash
spotify-auto status --probe
```

You should see your refresh token stored, the 6-month-wall date, and — if the
kiosk is up — `kiosk dev: present`.

---

## 6. Telegram alerts (optional)

```bash
spotify-auto notify --setup
```

Create a bot via **@BotFather** (`/newbot`) and paste its token, then send the
bot any message so it can auto-detect your chat id. Test it:

```bash
spotify-auto notify --test
```

---

## 7. Enable everything (cutover)

```bash
./install.sh --enable
```

This enables + starts:

- `spotify-kiosk.service` (the browser)
- `spotify-kiosk-watchdog.timer` (every 5 min)
- `spotify-kiosk-nightly-restart.timer` (04:00)
- `spotify-auto-resume.timer` (every 4 min)
- `spotify-auto-tokencheck.timer` (daily)

So the timers run even when you're not logged in:

```bash
sudo loginctl enable-linger "$USER"
```

---

## 8. Verify

```bash
systemctl --user list-timers 'spotify*'
journalctl --user -u spotify-auto-resume.service -n 20 --no-pager
tail -f ~/.local/state/spotify-auto.log
```

Leave the Pi idle for ~4 minutes; `auto-resume` should start your context on
the kiosk. Pausing and waiting should make it resume.

---

## Migrating from the old root-cron / raspotify setup

1. Remove raspotify if present: `scripts/remove-raspotify.sh`.
2. Remove the old root cron entry and script:
   ```bash
   sudo crontab -l | grep -v spotifyd-auto-resume | sudo crontab -
   sudo rm -f /usr/local/bin/spotifyd-auto-resume.sh*
   ```
3. **Revoke the old leaked credentials**: Spotify account →
   <https://www.spotify.com/account/apps/> → **Remove Access** for the app,
   then `spotify-auto reauth` to mint a fresh PKCE token. Rotate the client
   secret in the dashboard too (the new tooling won't use it, but the old
   leaked one should die). See [SECURITY.md](SECURITY.md).
