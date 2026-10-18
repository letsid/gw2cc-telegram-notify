# telegram-notify

A **gw2cc** plugin that messages you through your own Telegram bot when something important happens in game.

## Notifications

| Event | Default | Example |
|---|---|---|
| Character dies | on | `☠️ Charname died on Eternal Battlegrounds (38).` |
| Character is downed | off | `🩸 Charname is downed on …` |
| Commander leaves your map | on | `🗺️ Commander Name.1234 (blue tag) left … (now on …).` |
| Commander goes offline | on | `🔌 Commander Name.1234 (blue tag) went offline.` |
| Commander drops the tag or leaves the squad | on | `🚩 Commander … is no longer leading the squad.` |
| Commander changes | on | `🔄 Commander changed: A (blue tag) → B (pink catmander).` |
| Commander switches tag colour | on | `🎨 Commander A switched to red tag (was blue tag).` |
| Character or account name mentioned in chat | on | `📣 Mentioned ("name") in map by Someone: …` |
| Whisper received | on | `💬 Whisper from Name.1234: …` |
| Inventory full | on | `🎒 Inventory of Charname is full (80/80 slots) on …` |

Every message starts with `[Character name]`, so you can tell which client sent it when you run several.

Mentions are detected for:
- your full character name,
- your account name (`Name.1234`) and the part before the dot (`Name`),
- any extra keywords you add (comma separated).

Only whole words count, so "Ann" does not trigger on "Anna". Combat log channels and your own messages are ignored. Identical messages are merged, and each sender has a 10 second cooldown.

## Installation

1. Download the latest `telegram_notify-vX.Y.Z.zip` from [Releases](../../releases).
2. Extract it into the `plugins` folder of your gw2cc installation so that `plugins/telegram_notify/MetaInfo.tres` exists.
   The folder must be named exactly `telegram_notify`, because the scripts load each other via `res://plugins/telegram_notify/…`.
3. Restart the client and enable the **telegram-notify** plugin.

## Setting up the Telegram bot

1. In Telegram, message [@BotFather](https://t.me/BotFather) and send `/newbot`. Pick a name and copy the **bot token**.
2. Open the chat with your new bot and tap **Start** (or send `/start`).
   A bot can only message you after you have messaged it.
3. In the client, click **TG** in the top bar.
4. Paste the token into **Bot token**.
5. Click **Find chat ID**. The plugin reads your `/start` message and fills in the chat ID.
6. Click **Send test message**. If the test message arrives, you are done.

If "Find chat ID" finds nothing, send the bot another message and try again. You can also look up the chat ID yourself: open `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser and look for `"chat":{"id":…}`.

## Privacy and security

- The plugin only sends messages to `api.telegram.org`, addressed to the chat ID you enter.
- The bot token is stored **in plain text** in the gw2cc config. Do not share the config file.
- If your token has leaked, create a new one with `/revoke` at @BotFather.
- Whispers and chat messages that trigger a notification are also written to the local gw2cc log.

## Notes and limitations

- **Commander** means the leader (role `admin`) of the squad you are in. Without a squad there are no commander notifications.
  A notification is only sent once the state has held for about 3 seconds, so short loading screens do not cause false alarms.
  When you change maps yourself, you get no "left the map" notification.
- **Offline detection:** gw2cc's presence status values are not documented. A status containing "offline" or "invisible", or a missing map, counts as offline. Commander status changes are written to the log (`[commander] … status '…' -> '…'`).
- **Tag colour** is read from the squad data and shown as `<colour> tag` or `<colour> catmander`.
- **Inventory full** uses the client's own "inventory full" check and must hold for about 3 seconds. You get one message per fill; it re-arms once the inventory has free space again.

## Layout

```
telegram_notify/
  MetaInfo.tres          Plugin metadata (product_name telegram-notify)
  Ingame.tscn / .gd      "TG" menu button, starts the client and the watcher
  core/Settings.gd       Config keys (ConfigService section "telegram-notify")
  core/TelegramClient.gd Queue and HTTP calls to the Telegram Bot API
  core/Watcher.gd        Death, commander, chat mentions, whispers, inventory
  ui/Window.gd / .tscn   Settings window
```

## Making a release

1. Bump `version` in `telegram_notify/MetaInfo.tres`, e.g. to `0.2.0`.
2. Commit and create a matching tag:
   ```bash
   git tag v0.2.0
   git push origin main --tags
   ```
3. The workflow [`.github/workflows/release.yml`](.github/workflows/release.yml) checks that the version matches the tag, builds `telegram_notify-v0.2.0.zip` with a SHA-256 checksum and publishes the release.
   You can also run it from **Actions → Release → Run workflow** with a tag.

## License

[MIT](LICENSE)
