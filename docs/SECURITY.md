# Security model

## Principles

1. **No secrets in the repo.** This is a public repository. Every secret lives
   only in `~/.config/spotify-auto/` on the device, never in tracked files.
   `.gitignore` defensively blocks `config.env`, `token.json`, etc. in case one
   is ever copied into the tree.
2. **No client secret in the tooling.** Authorization uses the OAuth **PKCE**
   flow, which proves possession of a one-time code verifier instead of a
   shared secret. The tooling only ever needs the **Client ID** (not sensitive)
   and a user refresh token.
3. **Least privilege.** Everything runs as your normal user via
   `systemd --user`. No root cron, no `sudo` in the hot path.

## What's stored, and where

| File (`~/.config/spotify-auto/`) | Mode | Contents |
|---|---|---|
| `config.env` | `0600` | Client ID, redirect URIs, context URI, Telegram token/chat, marquee target |
| `token.json` | `0600` | Refresh token, cached access token + expiry, `authorized_at`, scope |
| `auth-needed` | `0600` | Sentinel: present ⇒ a human must re-authorize |
| `alert-state.json` | `0600` | Per-alert throttle timestamps |
| `bot-offset.json` | `0600` | Telegram bot: last processed `update_id` (no secrets) |
| `.lock` | `0600` | flock target serializing token refresh/rotation |

The directory itself is `0700`. Access tokens are short-lived (~1 h) and cached
to avoid unnecessary refreshes; the refresh token is the sensitive item.

## Token handling

- **Atomic writes:** `token.json` is written to a temp file in the same
  directory and `os.replace`d, so a crash can't leave a half-written token.
- **Locked rotation:** Spotify rotates the refresh token on every refresh. All
  refreshes happen under an exclusive `flock`, and the token file is re-read
  inside the lock, so two concurrent timers can't refresh in parallel and
  invalidate each other's refresh token.
- **Access-token caching:** a cached access token is reused until ~60 s before
  expiry, minimizing how often the refresh token is rotated.

## The 6-month wall

Spotify expires a refresh token **6 months after authorization**; refreshing
does **not** extend it. This is a hard limit — periodic manual re-auth is
unavoidable. Mitigations here:

- `spotify-auto status --alert` (daily timer) warns ~14 days before expiry.
- On `invalid_grant`, the tooling writes the `auth-needed` sentinel and alerts
  you; playback commands fail soft (exit non-zero, no crash loop).
- `spotify-auto reauth` / `--remote` restores service in under a minute.

## If a token or secret leaks

1. **Revoke app access** (kills all refresh/access tokens for the app):
   Spotify account → <https://www.spotify.com/account/apps/> → **Remove Access**.
2. **Rotate the client secret** in the Spotify dashboard. The PKCE tooling does
   not use the secret, but rotating retires any previously-leaked secret.
3. **Re-authorize:** `spotify-auto reauth`. This mints a brand-new refresh
   token; the old one is already dead from step 1.
4. If the leak was in git history, treat the credential as compromised forever —
   revocation (step 1) is what actually protects you, not history rewriting.

## Re-auth callback exposure

`reauth` runs a localhost-only HTTP server on `127.0.0.1`. `--remote` exposes it
via Tailscale **Serve** (tailnet-private, TLS-terminated by Tailscale) — never
Tailscale Funnel, so the callback is never reachable from the public internet.
The OAuth `state` parameter is validated on the callback to prevent CSRF.

## Telegram command bot (`spotify-auto bot`)

The optional command bot lets you control the kiosk from Telegram. Its exposure
is deliberately minimal:

- **Outbound only / no open port.** It uses Telegram **long-polling**
  (`getUpdates` over HTTPS to `api.telegram.org`); it never opens an inbound
  port and never sets a webhook. Nothing on the Pi is reachable from outside.
- **Single-chat allowlist.** Every update is checked against
  `TELEGRAM_CHAT_ID`; messages from any other chat id are logged and dropped.
  Anyone who finds the bot's username can message it, but only you can command
  it.
- **`/reauth` is powerful but contained.** It runs `reauth --remote`, which
  briefly uses Tailscale Serve (see above) and sends the approval link **only**
  to the allowlisted chat. Completing it still requires logging into your
  Spotify account on the device you open the link with.
- **Bot token is a secret.** It lives in `config.env` (`0600`) like the rest.
  If it leaks, revoke/rotate it via **@BotFather** (`/revoke`) and update
  `config.env`.
- Only one re-auth runs at a time (guarded by a lock); a restart of the service
  never replays old commands (the processed `update_id` offset is persisted to
  `bot-offset.json`).
