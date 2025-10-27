# raccoon-prevention
Auto-play Spotify if you're not listening to it elsewhere. Great for keeping raccoons out of sheds.

# Get Started

> [!NOTE]
> This has only been tested on a Raspberry Pi 5 running Raspberry Pi OS (64-bit).

> [!WARNING]
> These steps and scripts involve storing your Spotify credentials and tokens in plain text files **which is a bad idea**. Be aware of the security implications.

## Clone this repo

`git clone https://github.com/himuglamuh/raccoon-prevention.git && cd raccoon-prevention`

## Install pre-requisites:

```bash
sudo apt install python3 spotifyd curl jq
pip install spotipy
```

> [!NOTE]
> `spotifyd` might not be available in all package repositories. If it's not available, you can follow the instructions here to install it:
> 
> ```bash
> wget https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-aarch64-slim.tar.gz # for Raspberry Pi (ARM 64-bit)
> tar -xvzf spotifyd-linux-aarch64-slim.tar.gz
> sudo mv spotifyd /usr/local/bin/spotifyd
> sudo chmod +x /usr/local/bin/spotifyd
> ```

## Setup Spotify Developer Account + App

- Create a Spotify Developer account and create an app to get your `CLIENT_ID` and `CLIENT_SECRET`: [https://developer.spotify.com/dashboard/](https://developer.spotify.com/dashboard/)
- Set your Redirect URI in the Spotify Developer Dashboard to `http://127.0.0.1:8888/callback` (do not use `localhost`, Spotify will complain you're not using HTTPS)

## Configure `spotifyd`

- Copy `spotifyd.conf` from this repo to `~/.config/spotifyd/spotifyd.conf`
- Replace `username` and `password` with your Spotify account credentials
- You may need to edit the sound devices in the config file depending on your setup
- Copy `spotifyd.service` to `/etc/systemd/system/spotifyd.service` (replace `YOUR_USER` with your actual username)
- Copy `spotifyd-auto-resume.service` to `/etc/systemd/system/spotifyd-auto-resume.service` (replace `YOUR_USER` with your actual username)
- Copy `spotifyd-auto-resume.timer` to `/etc/systemd/system/spotifyd-auto-resume.timer`

## Get your Spotify token

- Edit `get_spotify_token.py` and replace `CLIENT_ID` and `CLIENT_SECRET` with your app credentials.

`python3 get_spotify_token.py` (log in to Spotify in your browser when prompted and accept the permissions)

- This returns both an access token and a refresh token. Copy both of these for the next steps.

## Get your device ID

` curl -s -H "Authorization: Bearer $ACCESS_TOKEN" https://api.spotify.com/v1/me/player/devices | jq .`

- Copy the `id` for your device (it should be named `raccoon-prevention` unless you changed it in `spotifyd.conf`)

> [!TIP]
> Sometimes you'll see the `raccoon-prevention` device listed on your phone when you look for other playback devices in Spotify, but not in the results returned by the API. If that happens, use your phone to start playback on the `raccoon-prevention` device, then run the above `curl` command again and you should see it.

## Setup the raccoon-prevention service script

- Copy `spotifyd-auto-resume.sh` to `/usr/local/bin/spotifyd-auto-resume.sh`
- Edit `/usr/local/bin/spotifyd-auto-resume.sh` and replace the following placeholders:
  - `CLIENT_ID` - the client ID from your Spotify Developer app
  - `CLIENT_SECRET` - the client secret from your Spotify Developer app
  - `REFRESH_TOKEN` - the refresh token (not the access token) you got from `get_spotify_token.py`
  - `DEVICE_NAME` - `raccoon-prevention` unless you changed it in `spotifyd.conf`
  - `CONTEXT_URI` - the URI of the playlist/album/track you want to play when resuming (find this by clicking "share" in Spotify on what you'd like to play and examining the URI)
    - Example for a playlist: `spotify:playlist:ID_HERE`
    - Example for an album: `spotify:album:ID_HERE`
    - Example for a track: `spotify:track:ID_HERE`
    - Example for an artist: `spotify:artist:ID_HERE`
  - `DEV_ID` - the device ID you got from the previous step

> [!CAUTION]
> You're storing secrets in plaintext files. This is a Bad Idea ™️. Be aware of the security implications.

## Enable and start the services

```
sudo systemctl daemon-reload
sudo systemctl enable --now spotifyd.service
sudo systemctl enable --now spotifyd-auto-resume.service
sudo systemctl enable --now spotifyd-auto-resume.timer
```
