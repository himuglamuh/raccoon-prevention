#!/usr/bin/env bash
# Launch Chromium in kiosk mode pointing at Spotify Web Player.
# Uses an isolated user-data-dir so the kiosk profile never accumulates
# restored tabs from interactive Chromium sessions.
#
# Backups of previous versions live in ~/backups/spotify-kiosk-*/

set -u

URL="https://open.spotify.com"
PROFILE_DIR="${HOME}/.local/share/spotify-kiosk-profile"
LOG="${HOME}/.local/state/spotify-kiosk.log"

mkdir -p "$(dirname "$LOG")" "$PROFILE_DIR"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

# 1. Wait for the Wayland compositor (labwc) to be up. Without this the
#    service can race the graphical session at boot and Chromium crashes,
#    which then loops via systemd Restart=.
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  export WAYLAND_DISPLAY="wayland-1"
fi
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

for i in $(seq 1 60); do
  if [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; then
    break
  fi
  # Try common alternates
  for alt in wayland-0 wayland-1 wayland-2; do
    if [ -S "${XDG_RUNTIME_DIR}/${alt}" ]; then
      export WAYLAND_DISPLAY="$alt"
      break 2
    fi
  done
  sleep 1
done

if [ ! -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; then
  log "FATAL: no wayland socket after 60s under ${XDG_RUNTIME_DIR}"
  exit 1
fi
log "using WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"

# 1b. Import the user dbus + desktop env so chromium portals work and
#     we don't spam "Failed to connect to the bus" errors. The user
#     systemd manager always knows DBUS_SESSION_BUS_ADDRESS.
eval "$(systemctl --user show-environment 2>/dev/null \
        | grep -E '^(DBUS_SESSION_BUS_ADDRESS|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|WAYLAND_DISPLAY)=' \
        | sed 's/^/export /')"

# 1c. Bail out if a kiosk chromium is already running against this profile.
#     This prevents accidental second-window-of-tabs if systemd ever
#     double-triggers the unit.
if pgrep -f "chromium.*--user-data-dir=${PROFILE_DIR}" >/dev/null 2>&1; then
  log "kiosk chromium already running, exiting cleanly"
  exit 0
fi

# 2. Clear stale Singleton* locks from a prior crash. These cause new
#    launches to either attach to a dead instance or open extra windows.
for f in SingletonLock SingletonCookie SingletonSocket; do
  rm -f "${PROFILE_DIR}/${f}"
done

# 3. Suppress the "Chrome didn't shut down correctly. Restore?" bubble and
#    prevent session restore from re-opening every previously-open tab.
PREF="${PROFILE_DIR}/Default/Preferences"
if [ -f "$PREF" ]; then
  # Force exit_type=Normal and exited_cleanly=true via a tiny python edit
  # (jq isn't guaranteed present; python3 is on Raspberry Pi OS).
  python3 - "$PREF" <<'PY' 2>>"$LOG" || log "WARN: could not normalize Preferences"
import json, sys
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
prof = d.setdefault("profile", {})
prof["exit_type"] = "Normal"
prof["exited_cleanly"] = True
# Force "open a specific page" with just our URL, disable restore.
ssn = d.setdefault("session", {})
ssn["restore_on_startup"] = 4
ssn["startup_urls"] = ["https://open.spotify.com"]
with open(p, "w") as f:
    json.dump(d, f)
PY
fi

# 4. Wipe the kiosk profile's Sessions/Tabs files so nothing is restored.
rm -f "${PROFILE_DIR}/Default/Sessions/"Session_* \
      "${PROFILE_DIR}/Default/Sessions/"Tabs_* 2>/dev/null || true

log "launching chromium kiosk -> ${URL}"

# 5. Launch. --kiosk implies fullscreen; do not also pass --start-fullscreen.
#    --user-data-dir isolates from the user's regular Chromium profile so a
#    crash-restore there can never inject tabs here.
#    --remote-debugging-* enables the watchdog to probe responsiveness via
#    http://127.0.0.1:9222/json/version. Bound to loopback only.
exec chromium-browser \
  --kiosk "$URL" \
  --user-data-dir="$PROFILE_DIR" \
  --no-first-run \
  --no-default-browser-check \
  --disable-features=TranslateUI,InfiniteSessionRestore \
  --hide-crash-restore-bubble \
  --disable-session-crashed-bubble \
  --noerrdialogs \
  --disable-infobars \
  --autoplay-policy=no-user-gesture-required \
  --disable-component-update \
  --disable-background-networking \
  --disable-background-timer-throttling \
  --disable-backgrounding-occluded-windows \
  --disable-renderer-backgrounding \
  --ozone-platform=wayland \
  --remote-debugging-port=9222 \
  --remote-debugging-address=127.0.0.1 \
  --remote-allow-origins=http://127.0.0.1:9222 \
  >>"$LOG" 2>&1
