extends Node

## Watches death, squad commander, chat mentions and whispers and forwards them to Telegram.

const Settings = preload("res://plugins/telegram_notify/core/Settings.gd")

const POLL_MS := 1000
## Commander state must hold for this many polls before we report it (loading screens, presence lag).
const COMMANDER_CONFIRM_POLLS := 3
const DEDUPE_MS := 3000
const MENTION_COOLDOWN_MS := 10000
## Combat log channels (ChatManager CHAT_CHANNEL_COMBAT .. COMBAT_OUT_STRIKE) are never scanned.
const COMBAT_CHANNEL_MAX := 11
const CHANNEL_WHISPER := 42
## Inventory must be full (or not full again) for this many polls before the state flips.
const INVENTORY_CONFIRM_POLLS := 3

static var _logger := ScopedLogger.create(Settings.PLUGIN_NAME)

var client: Node = null

var _next_poll_ms: int = 0
var _dead_state: int = HealthBar.DEAD_STATE_ALIVE
var _recent: Dictionary = {}
var _mention_cooldown: Dictionary = {}

var _cmd_id: String = ""
var _cmd_name: String = ""
var _cmd_map: int = 0
var _cmd_online: bool = true
var _cmd_status: String = ""
var _cmd_pending: String = ""
var _cmd_pending_polls: int = 0
var _own_map: int = 0
var _inv_full: bool = false
var _inv_flip_polls: int = 0
var _cmd_tag: int = 0
## After a confirmed "gone" the next commander in the same squad is reported as a change.
var _announce_next: bool = false


func _exit_tree() -> void:
	_disconnect_all()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now < _next_poll_ms:
		return
	_next_poll_ms = now + POLL_MS
	_ensure_connections()
	_poll_death()
	_poll_commander()
	_poll_inventory()
	_prune(now)


# ---------------------------------------------------------------- signals

func _ensure_connections() -> void:
	if Manager.chat and not Manager.chat.message_received.is_connected(_on_chat):
		Manager.chat.message_received.connect(_on_chat)
	if Manager.channel and not Manager.channel.message_received.is_connected(_on_channel_msg):
		Manager.channel.message_received.connect(_on_channel_msg)
	# Presence status_changed is not used: in the client it emits 1 argument, not the documented 2.
	if Manager.presence and not Manager.presence.whisper_received.is_connected(_on_whisper):
		Manager.presence.whisper_received.connect(_on_whisper)


func _disconnect_all() -> void:
	if Manager.chat and Manager.chat.message_received.is_connected(_on_chat):
		Manager.chat.message_received.disconnect(_on_chat)
	if Manager.channel and Manager.channel.message_received.is_connected(_on_channel_msg):
		Manager.channel.message_received.disconnect(_on_channel_msg)
	if Manager.presence and Manager.presence.whisper_received.is_connected(_on_whisper):
		Manager.presence.whisper_received.disconnect(_on_whisper)


func _on_whisper(user: User, alias: String, msg: String) -> void:
	_handle_whisper(alias if not alias.is_empty() else _user_name(user), msg)


func _on_chat(channel: int, speaker: String, speaker_user: User, msg: String) -> void:
	if channel <= COMBAT_CHANNEL_MAX:
		return
	if channel == CHANNEL_WHISPER:
		_handle_whisper(speaker if not speaker.is_empty() else _user_name(speaker_user), msg, speaker_user)
		return
	_handle_mention(_channel_label(channel), speaker, speaker_user, msg)


func _on_channel_msg(channel: Channel, user: User, alias: String, msg: String) -> void:
	var label: String = str(channel.channel_name) if channel else "channel"
	_handle_mention(label, alias, user, msg)


# ---------------------------------------------------------------- whispers / mentions

func _handle_whisper(from: String, msg: String, user: User = null) -> void:
	if not Settings.get_bool(Settings.ON_WHISPER) or _is_own(from, user):
		return
	if _is_duplicate("w|" + msg):
		return
	_notify("💬 Whisper from %s:\n%s" % [from, msg])


func _handle_mention(where: String, speaker: String, user: User, msg: String) -> void:
	if not Settings.get_bool(Settings.ON_MENTION) or msg.is_empty() or _is_own(speaker, user):
		return
	var hit: String = _find_mention(msg)
	if hit.is_empty():
		return
	if _is_duplicate("m|" + speaker + "|" + msg):
		return
	var now: int = Time.get_ticks_msec()
	if now < int(_mention_cooldown.get(speaker, 0)):
		return
	_mention_cooldown[speaker] = now + MENTION_COOLDOWN_MS
	_notify("📣 Mentioned (\"%s\") in %s by %s:\n%s" % [hit, where, speaker, msg])


## Returns the matched name/keyword, or "" if the message does not mention us.
func _find_mention(msg: String) -> String:
	var lower: String = msg.to_lower()
	for word in _mention_words():
		if _contains_word(lower, word):
			return word
	return ""


func _mention_words() -> PackedStringArray:
	var words := PackedStringArray()
	var char_name: String = _own_character_name().to_lower()
	if char_name.length() >= 3:
		words.append(char_name)
	var account: String = _own_account_name().to_lower()
	if account.length() >= 3:
		words.append(account)
		var short: String = account.get_slice(".", 0)
		if short != account and short.length() >= 3:
			words.append(short)
	words.append_array(Settings.keywords())
	return words


## Substring match that rejects hits glued to other letters/digits ("Ann" in "Anna").
static func _contains_word(haystack: String, needle: String) -> bool:
	var from: int = 0
	while true:
		var idx: int = haystack.find(needle, from)
		if idx < 0:
			return false
		var end: int = idx + needle.length()
		var left_ok: bool = idx == 0 or not _is_word_char(haystack.unicode_at(idx - 1))
		var right_ok: bool = end >= haystack.length() or not _is_word_char(haystack.unicode_at(end))
		if left_ok and right_ok:
			return true
		from = idx + 1
	return false


static func _is_word_char(code: int) -> bool:
	var c: String = char(code)
	return c.is_valid_identifier() or c.is_valid_int() or code > 127


# ---------------------------------------------------------------- death

func _poll_death() -> void:
	var cc: AgentChar = Manager.agent.controlled_character if Manager.agent else null
	if not cc or cc.health_bar == null:
		_dead_state = HealthBar.DEAD_STATE_ALIVE
		return
	var state: int = int(cc.health_bar.dead_state)
	if state == _dead_state:
		return
	var previous: int = _dead_state
	_dead_state = state
	if state == HealthBar.DEAD_STATE_DEAD and Settings.get_bool(Settings.ON_DEATH):
		_notify("☠️ %s died on %s." % [_own_character_name(), _map_text(_current_map())])
	elif state == HealthBar.DEAD_STATE_DOWNED and previous == HealthBar.DEAD_STATE_ALIVE and Settings.get_bool(Settings.ON_DOWNED):
		_notify("🩸 %s is downed on %s." % [_own_character_name(), _map_text(_current_map())])


# ---------------------------------------------------------------- inventory

func _poll_inventory() -> void:
	var inv: InventoryLocation = _inventory()
	if inv == null:
		_inv_flip_polls = 0
		return
	var full: bool = inv.is_full()
	if full == _inv_full:
		_inv_flip_polls = 0
		return
	_inv_flip_polls += 1
	if _inv_flip_polls < INVENTORY_CONFIRM_POLLS:
		return
	_inv_flip_polls = 0
	_inv_full = full
	_logger.info("[inventory] full=%s (%s)" % [full, _slot_text(inv)])
	if full and Settings.get_bool(Settings.ON_INVENTORY_FULL):
		_notify("🎒 Inventory of %s is full (%s) on %s." % [_own_character_name(), _slot_text(inv), _map_text(_current_map())])


static func _inventory() -> InventoryLocation:
	var cc: AgentChar = Manager.agent.controlled_character if Manager.agent else null
	if not cc or not cc.has_component(ItemStorage):
		return null
	var locations: Array = cc.item_storage.item_locations
	if locations.size() <= InventoryLocation.LOCATION_INVENTORY:
		return null
	var loc: Variant = locations[InventoryLocation.LOCATION_INVENTORY]
	return loc as InventoryLocation if loc is InventoryLocation else null


## "used/max slots"; max_size may include slots of empty bag positions.
static func _slot_text(inv: InventoryLocation) -> String:
	var used: int = 0
	for item in inv.items.values():
		if item != null:
			used += 1
	return "%d/%d slots" % [used, int(inv.max_size)]


# ---------------------------------------------------------------- commander

func _poll_commander() -> void:
	var own_map: int = _current_map()
	if own_map != _own_map:
		# Our own map change: re-baseline, never report the commander as "left".
		_own_map = own_map
		_reset_commander()
		_announce_next = false
	if own_map == 0 or not Manager.squad or not Manager.squad.squad:
		_reset_commander()
		_announce_next = false
		return
	var leader: ChannelMember = Manager.squad.get_squad_leader()
	var user: User = leader.user if leader else null
	if user == null:
		if not _cmd_id.is_empty():
			_confirm("gone", "🚩 Commander %s is no longer leading the squad (tag dropped or left)." % _cmd_label())
		return
	var id: String = str(user.user_id).to_upper()
	var map_id: int = int(user.app_data.get("x_M", 0)) if user.app_data else 0
	var status: String = str(user.status)
	var online: bool = _is_online(user, map_id)
	var tag: int = _tag_id()
	if id != _cmd_id:
		_logger.info("[commander] tracking %s (map %d, status '%s', tag %d '%s', SI='%s')" % [
			_user_name(user), map_id, status, tag, _tag_text(tag), _raw_tag_guid()])
		var previous: String = _cmd_label()
		if (not _cmd_id.is_empty() or _announce_next) and Settings.get_bool(Settings.ON_COMMANDER_CHANGE):
			if previous.is_empty():
				_notify("🔄 New commander: %s (%s)." % [_user_name(user), _tag_text(tag)])
			else:
				_notify("🔄 Commander changed: %s → %s (%s)." % [previous, _user_name(user), _tag_text(tag)])
		_announce_next = false
		_cmd_tag = tag
		_cmd_id = id
		_cmd_name = _user_name(user)
		_cmd_map = map_id
		_cmd_online = online
		_cmd_status = status
		_clear_pending()
		return
	if tag > 0 and tag != _cmd_tag:
		if _cmd_tag > 0 and Settings.get_bool(Settings.ON_COMMANDER_CHANGE):
			_notify("🎨 Commander %s switched to %s (was %s)." % [_cmd_name, _tag_text(tag), _tag_text(_cmd_tag)])
		_cmd_tag = tag
	if status != _cmd_status:
		_logger.info("[commander] %s status '%s' -> '%s', x_M=%d" % [_cmd_name, _cmd_status, status, map_id])
		_cmd_status = status
	if not Settings.get_bool(Settings.ON_COMMANDER):
		_cmd_map = map_id
		_cmd_online = online
		_clear_pending()
		return
	if _cmd_online and not online:
		if _confirm("offline", "🔌 Commander %s went offline." % _cmd_label()):
			_cmd_online = false
		return
	if not _cmd_online and online:
		_cmd_online = true
		_cmd_map = map_id
		_clear_pending()
		return
	if online and map_id != 0 and map_id != _cmd_map:
		if _cmd_map == own_map:
			if _confirm("map:%d" % map_id, "🗺️ Commander %s left %s (now on %s)." % [_cmd_label(), _map_text(own_map), _map_text(map_id)]):
				_cmd_map = map_id
			return
		_cmd_map = map_id
	_clear_pending()


## Reports only after the same condition held for COMMANDER_CONFIRM_POLLS polls. Returns true once sent.
func _confirm(key: String, text: String) -> bool:
	if key != _cmd_pending:
		_cmd_pending = key
		_cmd_pending_polls = 0
	_cmd_pending_polls += 1
	if _cmd_pending_polls < COMMANDER_CONFIRM_POLLS:
		return false
	if Settings.get_bool(Settings.ON_COMMANDER):
		_notify(text)
	if key == "gone":
		_reset_commander()
		_announce_next = true
	_clear_pending()
	return true


func _clear_pending() -> void:
	_cmd_pending = ""
	_cmd_pending_polls = 0


func _reset_commander() -> void:
	_cmd_id = ""
	_cmd_name = ""
	_cmd_map = 0
	_cmd_online = true
	_cmd_status = ""
	_cmd_tag = 0
	_clear_pending()


## Commander name plus tag colour, or "" when nobody is tracked.
func _cmd_label() -> String:
	if _cmd_name.is_empty():
		return ""
	return "%s (%s)" % [_cmd_name, _tag_text(_cmd_tag)] if _cmd_tag > 0 else _cmd_name


## SquadConstants.CommanderIcon of the current squad tag; 0 if unknown.
static func _tag_id() -> int:
	if not Manager.squad or not Manager.squad.squad:
		return 0
	var id: int = int(Manager.squad.get_current_tag_icon_id())
	if id > 0:
		return id
	# SquadManager matches the GUID case-sensitively; retry upper-case.
	var raw: String = _raw_tag_guid().to_upper()
	if raw.is_empty():
		return 0
	var script: Script = Manager.squad.get_script()
	var guids: Variant = script.get_script_constant_map().get("_SELECTED_ICON_GUID") if script else null
	if guids is Array:
		return maxi(0, (guids as Array).find(raw))
	return 0


static func _raw_tag_guid() -> String:
	if not Manager.squad or not Manager.squad.squad:
		return ""
	var data: Dictionary = Manager.squad.squad.channel.app_data
	return str(data.get("SI", ""))


## "blue tag" / "pink catmander"; "no tag" for 0.
static func _tag_text(tag: int) -> String:
	if tag <= 0:
		return "no tag"
	var key: Variant = SquadConstants.CommanderIcon.find_key(tag)
	if key == null:
		return "tag %d" % tag
	var parts: PackedStringArray = str(key).to_lower().split("_icon_")
	if parts.size() != 2:
		return str(key).to_lower()
	var kind: String = "catmander" if parts[0] == "catmander" else "tag"
	return "%s %s" % [parts[1], kind]


## Presence status strings are not documented; anything offline-like or a missing map counts as offline.
static func _is_online(user: User, map_id: int) -> bool:
	var status: String = str(user.status).to_lower()
	if status.contains("offline") or status.contains("invisible"):
		return false
	return map_id != 0


# ---------------------------------------------------------------- helpers

func _notify(text: String) -> void:
	var who: String = _own_character_name()
	var line: String = ("[%s] %s" % [who, text]) if not who.is_empty() else text
	_logger.info("[notify] " + line.replace("\n", " | "))
	if client and client.has_method("send"):
		client.send(line)


func _is_own(name: String, user: User) -> bool:
	var own_user: Variant = Manager.presence.get("own_user") if Manager.presence else null
	if user != null and own_user != null and user == own_user:
		return true
	var lower: String = name.strip_edges().to_lower()
	if lower.is_empty():
		return false
	return lower == _own_character_name().to_lower() or lower == _own_account_name().to_lower()


func _is_duplicate(key: String) -> bool:
	var now: int = Time.get_ticks_msec()
	if now < int(_recent.get(key, 0)):
		return true
	_recent[key] = now + DEDUPE_MS
	return false


func _prune(now: int) -> void:
	for key in _recent.keys():
		if now >= int(_recent[key]):
			_recent.erase(key)
	for key in _mention_cooldown.keys():
		if now >= int(_mention_cooldown[key]):
			_mention_cooldown.erase(key)


func _own_character_name() -> String:
	var cc: AgentChar = Manager.agent.controlled_character if Manager.agent else null
	return AgentUtils.get_agent_name(cc) if cc else ""


func _own_account_name() -> String:
	var own_user: Variant = Manager.presence.get("own_user") if Manager.presence else null
	return str(own_user.user_name) if own_user is User else ""


static func _user_name(user: User) -> String:
	return str(user.user_name) if user else "?"


static func _current_map() -> int:
	if not Manager.mission:
		return 0
	return int(Manager.mission.get_map_id())


static func _map_text(map_id: int) -> String:
	if map_id == 0:
		return "unknown map"
	var def: MapDef = MapUtils.get_map_def(map_id)
	if def and not str(def.map_name).is_empty():
		return "%s (%d)" % [def.map_name, map_id]
	return "map %d" % map_id


static func _channel_label(channel: int) -> String:
	match channel:
		16, 17: return "guild"
		18, 19, 20, 21, 22, 23: return "guild"
		34: return "LFG"
		35: return "say"
		36: return "map"
		37: return "party"
		38: return "squad"
		40: return "team"
	return "chat %d" % channel
