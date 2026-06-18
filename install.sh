#!/usr/bin/env bash
# install.sh — symlink the spotify-auto tooling and systemd user units into
# place. Symlinks (not copies) so `git pull` updates everything live.
#
#   ./install.sh            link files, create config, daemon-reload
#   ./install.sh --enable   also enable + start the kiosk and timers
#
# Secrets are NOT touched here; they live in ~/.config/spotify-auto/config.env.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN_DIR="${HOME}/bin"
UNIT_DIR="${HOME}/.config/systemd/user"
CFG_DIR="${SPOTIFY_AUTO_CONFIG_DIR:-${HOME}/.config/spotify-auto}"

mkdir -p "$BIN_DIR" "$UNIT_DIR" "$CFG_DIR"
chmod 700 "$CFG_DIR"

link() { ln -sfn "$1" "$2"; printf '  %s -> %s\n' "$2" "$1"; }

echo "Linking executables into $BIN_DIR:"
for f in spotify-auto now-playing marq-playing; do
  chmod +x "$REPO_DIR/bin/$f"
  link "$REPO_DIR/bin/$f" "$BIN_DIR/$f"
done
chmod +x "$REPO_DIR/scripts/start-spot.sh"
link "$REPO_DIR/scripts/start-spot.sh" "$BIN_DIR/start-spot.sh"

echo "Linking systemd user units into $UNIT_DIR:"
shopt -s nullglob
for u in "$REPO_DIR"/systemd/*.service "$REPO_DIR"/systemd/*.timer; do
  link "$u" "$UNIT_DIR/$(basename "$u")"
done
shopt -u nullglob

if [ ! -f "$CFG_DIR/config.env" ]; then
  install -m 600 "$REPO_DIR/config/config.env.example" "$CFG_DIR/config.env"
  echo "Created $CFG_DIR/config.env  (EDIT: CLIENT_ID, CONTEXT_URI, redirect URIs...)"
else
  echo "Keeping existing $CFG_DIR/config.env"
fi

systemctl --user daemon-reload
echo "systemctl --user daemon-reload done."

if [ "${1:-}" = "--enable" ]; then
  systemctl --user enable --now \
    spotify-kiosk.service \
    spotify-kiosk-watchdog.timer \
    spotify-kiosk-nightly-restart.timer \
    spotify-auto-resume.timer \
    spotify-auto-tokencheck.timer
  echo "Enabled + started kiosk service and all timers."
  # The Telegram command bot is optional; only enable it once a bot token and
  # chat id are configured (spotify-auto notify --setup).
  if grep -q '^TELEGRAM_BOT_TOKEN=.\+' "$CFG_DIR/config.env" 2>/dev/null \
     && grep -q '^TELEGRAM_CHAT_ID=.\+' "$CFG_DIR/config.env" 2>/dev/null; then
    systemctl --user enable --now spotify-auto-bot.service
    echo "Enabled + started spotify-auto-bot.service (Telegram is configured)."
  else
    echo "Skipping spotify-auto-bot.service (Telegram not configured yet)."
    echo "  After 'spotify-auto notify --setup', run:"
    echo "    systemctl --user enable --now spotify-auto-bot.service"
  fi
fi

cat <<EOF

Next steps:
  1. Edit    $CFG_DIR/config.env   (CLIENT_ID, CONTEXT_URI, REMOTE_REDIRECT_URI)
  2. Authorize:
       spotify-auto reauth             # on the Pi (loopback browser), or
       spotify-auto reauth --remote    # from your phone via Tailscale Serve
  3. Alerts  (optional):  spotify-auto notify --setup
  4. Enable  (cutover):   ./install.sh --enable
  5. Verify:              spotify-auto status --probe

The same Telegram bot can also take commands (status, reauth, restart...):
  after 'notify --setup', '--enable' starts spotify-auto-bot.service; then
  message your bot /help. Only TELEGRAM_CHAT_ID is allowed to command it.

Tip: enable lingering so user timers run without an active login:
       sudo loginctl enable-linger "$USER"
EOF
