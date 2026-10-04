# Notifications

ROA offers optional macOS and Telegram notifications for important session and
service events. Both channels start disabled. Ordinary ON/OFF commands are silent.
The menu app must be running to observe events; the power service keeps enforcing
timers and guards independently. Notifications are best-effort, not a monitoring
or guaranteed-delivery service.

## macOS

Open **Notifications…** and enable macOS notifications. Approve the native macOS
permission request. If permission was denied, change it under **System Settings
→ Notifications → ROA**. Focus settings and macOS notification preferences can
suppress banners or sounds.

## Telegram

1. In Telegram, open the official [@BotFather](https://t.me/BotFather), send
   `/newbot` and choose a display name and a unique username ending in `bot`.
   Keep its token private. Do not paste it into an issue, chat, screenshot or Git.
2. Open your new bot's chat and press **Start** or send `/start`. A bot cannot
   initiate a private conversation before you contact it.
3. Find your numeric chat ID from the bot's incoming update. The example below
   prompts privately for the token, contacts only Telegram and prints numeric IDs.
   It requires Python 3 and a recent message to your new bot. Use your own bot;
   do not reuse one managed by another application with a webhook.

   ```sh
   python3 - <<'PY'
   import getpass
   import json
   import re
   import urllib.request

   token = getpass.getpass("Telegram bot token (hidden): ").strip()
   if not re.fullmatch(r"[0-9]+:[A-Za-z0-9_-]+", token):
       raise SystemExit("Invalid token format")
   request = urllib.request.Request(
       "https://api.telegram.org/bot" + token + "/getUpdates",
       data=b'{"timeout":0,"limit":20}',
       headers={"Content-Type": "application/json"}, method="POST")
   class NoRedirect(urllib.request.HTTPRedirectHandler):
       def redirect_request(self, req, fp, code, msg, headers, newurl):
           return None

   try:
       opener = urllib.request.build_opener(NoRedirect())
       with opener.open(request, timeout=10) as response:
           raw = response.read(65537)
       if len(raw) > 65536:
           raise ValueError()
       payload = json.loads(raw)
       if payload.get("ok") is not True:
           raise ValueError()
       ids = {item["message"]["chat"]["id"] for item in payload["result"]
              if "message" in item}
       for chat_id in sorted(ids):
           print("Chat ID:", chat_id)
       if not ids:
           print("No messages found. Send /start to your bot, then retry.")
   except Exception:
       raise SystemExit("Could not read updates. Check the token and connection.")
   PY
   ```

4. In ROA's **Notifications…**, enter the token and numeric chat ID. Save your
   settings and use the test action to verify delivery. Enable Telegram alerts
   explicitly. Bot tokens are saved in the macOS Keychain, not preferences.

For a group, add the bot and send it a command; the update contains a negative
group chat ID. Choose a private chat if you do not want others to see alerts.
If the token is exposed, revoke it through BotFather and replace it in ROA.
The **Forget Telegram Credentials** action removes the saved credential; uninstall also
attempts to delete ROA's own Keychain item.

## Privacy and delivery limits

Telegram delivery sends short ROA event text and any included battery value to
`api.telegram.org`, using your bot and the chat you configure. It never sends
diagnostics, local file paths, account names, running processes or logs. Telegram
and the chat's members can see those messages. No Revion Tech server is involved.
Disabling Telegram prevents future automatic sends; previously delivered messages
remain in Telegram until deleted there.

Repeated identical states are deduplicated, with at most one event alert per
30 seconds across the channels. Startup does not replay historical alerts. There is no persistent retry queue; offline messages may be lost. A sleep
transition can happen before a network request finishes. App crashes, revoked
permissions, invalid credentials, rate limits and unavailable networks can prevent
delivery. Use **Status & Diagnostics…** for the current locally confirmed state.

Protocol details: [Telegram Bot API](https://core.telegram.org/bots/api#sendmessage)
and [bot creation](https://core.telegram.org/bots/features#botfather).
