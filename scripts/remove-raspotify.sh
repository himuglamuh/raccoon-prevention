#!/usr/bin/env bash
# remove-raspotify.sh — fully remove raspotify.
#
# This project uses the Chromium web-player kiosk (see start-spot.sh), so the
# raspotify package/daemon is not needed. Audio on this setup is PipeWire/Pulse,
# not ALSA, so removing raspotify is safe. Idempotent.
set -euo pipefail

echo "Disabling and purging raspotify..."
sudo systemctl disable --now raspotify.service 2>/dev/null || true
sudo apt-get purge -y raspotify 2>/dev/null || true

echo "Removing leftover data/config..."
sudo rm -rf \
  /etc/systemd/system/raspotify.service.d \
  /var/cache/raspotify \
  /var/lib/raspotify \
  /etc/raspotify

echo "Removing apt source + signing key..."
sudo rm -f \
  /etc/apt/sources.list.d/raspotify.list \
  /usr/share/keyrings/raspotify_key.asc

sudo systemctl daemon-reload
sudo systemctl reset-failed raspotify.service 2>/dev/null || true

echo "raspotify removed."
