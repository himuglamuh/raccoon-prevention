#!/bin/bash

### --- CONFIGURATION --- ###
CLIENT_ID=""
CLIENT_SECRET=""
REFRESH_TOKEN=""
DEVICE_NAME="raccoon-prevention" # change to match if you edited spotifyd.conf device name
CONTEXT_URI="" # your artist/playlist - see readme.md for more details
DEV_ID=""
### --------------------- ###

API="https://api.spotify.com/v1"

RESP=$(curl -s -X POST -u "$CLIENT_ID:$CLIENT_SECRET" \
    -d grant_type=refresh_token \
    -d refresh_token="$REFRESH_TOKEN" \
    https://accounts.spotify.com/api/token)

ACCESS=$(echo "$RESP" | jq -r '.access_token')
[ "$ACCESS" = "null" ] && echo "Token refresh failed" && exit 1

PLAYING=$(curl -s -H "Authorization: Bearer $ACCESS" \
    $API/me/player | jq -r '.is_playing')

if [[ "$PLAYING" != "true" ]]; then
  echo "$(date): Idle detected, starting $CONTEXT_URI on $DEV_ID"
  curl -s -X PUT \
    -H "Authorization: Bearer $ACCESS" \
    -H "Content-Type: application/json" \
    -d '{"device_ids":["'"$DEV_ID"'"],"play":true}' \
    $API/me/player
  sleep 3
  curl -s -X PUT \
    -H "Authorization: Bearer $ACCESS" \
    -H "Content-Type: application/json" \
    -d '{"context_uri": "$CONTEXT_URI"}' \
    "$API/me/player/play?device_id=$DEV_ID"
else
  echo "$(date): Playback active elsewhere, doing nothing."
fi
