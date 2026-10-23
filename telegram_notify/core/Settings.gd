extends RefCounted

## Config keys and accessors for telegram-notify (ConfigService section = product_name).

const PLUGIN_NAME: String = "telegram-notify"

const TOKEN := "bot_token"
const CHAT_ID := "chat_id"
const ON_DEATH := "on_death"
const ON_DOWNED := "on_downed"
const ON_COMMANDER := "on_commander"
const ON_COMMANDER_CHANGE := "on_commander_change"
const ON_MENTION := "on_mention"
const ON_WHISPER := "on_whisper"
const ON_INVENTORY_FULL := "on_inventory_full"
const ALLOW_QUIT := "allow_quit_command"
const KEYWORDS := "extra_keywords"

const DEFAULTS: Dictionary = {
	TOKEN: "",
	CHAT_ID: "",
	ON_DEATH: true,
	ON_DOWNED: false,
	ON_COMMANDER: true,
	ON_COMMANDER_CHANGE: true,
	ON_MENTION: true,
	ON_WHISPER: true,
	ON_INVENTORY_FULL: true,
	ALLOW_QUIT: true,
	KEYWORDS: "",
}


static func get_bool(key: String) -> bool:
	return bool(ConfigService.get_value(PLUGIN_NAME, key, DEFAULTS.get(key, false)))


static func get_string(key: String) -> String:
	return str(ConfigService.get_value(PLUGIN_NAME, key, DEFAULTS.get(key, ""))).strip_edges()


static func set_value(key: String, value: Variant) -> void:
	ConfigService.set_value(PLUGIN_NAME, key, value)


## Comma-separated extra keywords, lowercased, empty entries dropped.
static func keywords() -> PackedStringArray:
	var out := PackedStringArray()
	for part in get_string(KEYWORDS).split(","):
		var word: String = part.strip_edges().to_lower()
		if word.length() >= 2:
			out.append(word)
	return out
