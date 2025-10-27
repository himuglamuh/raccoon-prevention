import requests, urllib.parse, http.server, threading, webbrowser

CLIENT_ID     = ""
CLIENT_SECRET = ""
REDIRECT_URI  = "http://127.0.0.1:8888/callback"
SCOPES        = "user-read-playback-state user-modify-playback-state streaming"

AUTH_URL  = "https://accounts.spotify.com/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"

params = {
    "client_id": CLIENT_ID,
    "response_type": "code",
    "redirect_uri": REDIRECT_URI,
    "scope": SCOPES,
}
url = f"{AUTH_URL}?{urllib.parse.urlencode(params)}"

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        code = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)["code"][0]
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"You can close this tab.")
        data = {
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": REDIRECT_URI,
        }
        r = requests.post(TOKEN_URL, data=data, auth=(CLIENT_ID, CLIENT_SECRET))
        print("\nToken response:\n", r.json())
        threading.Thread(target=self.server.shutdown).start()

server = http.server.HTTPServer(("127.0.0.1", 8888), Handler)
threading.Thread(target=lambda: webbrowser.open(url)).start()
server.serve_forever()
