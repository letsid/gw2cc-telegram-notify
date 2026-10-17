# telegram-notify

Ein Plugin für **gw2cc**, das dir Nachrichten über einen eigenen Telegram-Bot schickt, wenn im Spiel etwas Wichtiges passiert.

## Benachrichtigungen

| Ereignis | Standard | Beispiel |
|---|---|---|
| Charakter stirbt | an | `☠️ Charname died on Eternal Battlegrounds (38).` |
| Charakter ist angeschlagen (downed) | aus | `🩸 Charname is downed on …` |
| Commander verlässt deine Map | an | `🗺️ Commander Name.1234 (blue tag) left … (now on …).` |
| Commander geht offline | an | `🔌 Commander Name.1234 (blue tag) went offline.` |
| Commander gibt den Tag ab oder verlässt den Squad | an | `🚩 Commander … is no longer leading the squad.` |
| Commander wechselt | an | `🔄 Commander changed: A (blue tag) → B (pink catmander).` |
| Commander wechselt die Tag-Farbe | an | `🎨 Commander A switched to red tag (was blue tag).` |
| Charakter- oder Accountname wird im Chat genannt | an | `📣 Mentioned ("name") in map by Someone: …` |
| Flüsternachricht | an | `💬 Whisper from Name.1234: …` |

Jede Nachricht beginnt mit `[Charaktername]`, damit du beim Spielen mit mehreren Clients siehst, von welchem sie kommt.

Erkannt werden Erwähnungen von:
- deinem vollen Charakternamen,
- deinem Accountnamen (`Name.1234`) und dem Teil vor dem Punkt (`Name`),
- frei wählbaren zusätzlichen Stichwörtern (kommagetrennt).

Treffer zählen nur als ganzes Wort, „Ann“ löst also bei „Anna“ nicht aus. Kampflog-Kanäle und eigene Nachrichten werden ignoriert. Gleiche Nachrichten werden zusammengefasst, und pro Absender gilt eine Pause von 10 Sekunden.

## Installation

1. Lade die neueste `telegram_notify-vX.Y.Z.zip` unter [Releases](../../releases) herunter.
2. Entpacke sie in den `plugins`-Ordner deiner gw2cc-Installation, sodass `plugins/telegram_notify/MetaInfo.tres` existiert.
   Der Ordnername muss genau `telegram_notify` lauten, denn die Skripte laden sich über `res://plugins/telegram_notify/…`.
3. Starte den Client neu und aktiviere das Plugin **telegram-notify**.

## Telegram-Bot einrichten

1. Schreibe in Telegram [@BotFather](https://t.me/BotFather) an und sende `/newbot`. Vergib einen Namen und kopiere den **Bot-Token**.
2. Öffne den Chat mit deinem neuen Bot und tippe auf **Start** (oder sende `/start`).
   Ein Bot darf dir erst schreiben, nachdem du ihn angeschrieben hast.
3. Klicke im Client in der oberen Leiste auf **TG**.
4. Füge den Token unter **Bot token** ein.
5. Klicke auf **Find chat ID**. Das Plugin liest deine `/start`-Nachricht und trägt die Chat-ID automatisch ein.
6. Klicke auf **Send test message**. Kommt die Testnachricht an, ist alles eingerichtet.

Findet „Find chat ID“ nichts, schicke dem Bot noch eine Nachricht und versuche es erneut. Die Chat-ID findest du auch selbst, indem du im Browser `https://api.telegram.org/bot<TOKEN>/getUpdates` öffnest und nach `"chat":{"id":…}` suchst.

## Datenschutz und Sicherheit

- Das Plugin schickt Nachrichten nur an `api.telegram.org`, an die Chat-ID, die du einträgst.
- Der Bot-Token wird **im Klartext** in der gw2cc-Konfiguration gespeichert. Gib die Konfigurationsdatei nicht weiter.
- Ist dein Token öffentlich geworden, erzeugst du bei @BotFather mit `/revoke` einen neuen.
- Flüster- und Chatnachrichten, die eine Benachrichtigung auslösen, landen auch im lokalen gw2cc-Log.

## Hinweise und Grenzen

- **Commander:** gemeint ist der Leiter (Rolle `admin`) des Squads, in dem du bist. Ohne Squad gibt es keine Commander-Meldungen.
  Eine Meldung kommt erst, wenn der Zustand rund 3 Sekunden anhält, damit kurze Ladebildschirme keinen Fehlalarm auslösen.
  Wechselst du selbst die Map, gibt es keine „hat die Map verlassen“-Meldung.
- **Offline-Erkennung:** Die Presence-Statuswerte von gw2cc sind nicht dokumentiert. Als offline zählt ein Status mit „offline“ oder „invisible“ oder eine fehlende Map-Angabe. Statuswechsel des Commanders stehen im Log (`[commander] … status '…' -> '…'`).
- **Tag-Farbe:** wird aus den Squad-Daten gelesen und als `<farbe> tag` bzw. `<farbe> catmander` angezeigt.

## Aufbau

```
telegram_notify/
  MetaInfo.tres          Plugin-Metadaten (product_name telegram-notify)
  Ingame.tscn / .gd      Menü-Button "TG", startet Client und Watcher
  core/Settings.gd       Konfigurationsschlüssel (ConfigService-Abschnitt "telegram-notify")
  core/TelegramClient.gd Warteschlange und HTTP-Aufrufe der Telegram Bot API
  core/Watcher.gd        Tod, Commander, Chat-Erwähnungen, Flüstern
  ui/Window.gd / .tscn   Einstellungsfenster
```

## Release erstellen

1. Erhöhe `version` in `telegram_notify/MetaInfo.tres`, z. B. auf `0.2.0`.
2. Committe und lege einen passenden Tag an:
   ```bash
   git tag v0.2.0
   git push origin main --tags
   ```
3. Der Workflow [`.github/workflows/release.yml`](.github/workflows/release.yml) prüft, ob die Version zum Tag passt, baut `telegram_notify-v0.2.0.zip` samt SHA-256-Prüfsumme und veröffentlicht das Release.
   Alternativ startest du ihn unter **Actions → Release → Run workflow** mit einem Tag.

## Lizenz

[MIT](LICENSE)
