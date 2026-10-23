extends Node

## Sends queued messages to the Telegram Bot API and long-polls getUpdates for commands.

const Settings = preload("res://plugins/telegram_notify/core/Settings.gd")

const API_BASE := "https://api.telegram.org/bot"
const MAX_QUEUE := 20
const MAX_TEXT := 3500
const POLL_TIMEOUT_S := 25
const RETRY_S := 5.0
## HTTP 409: another client polls the same bot.
const CONFLICT_RETRY_S := 30.0
const IDLE_RETRY_S := 5.0

signal status_changed(text: String)
signal chat_id_found(chat_id: String)
## A bot command such as "quit" (lowercase, no slash, no @botname) from the configured chat.
signal command_received(command: String, args: String)

static var _logger := ScopedLogger.create(Settings.PLUGIN_NAME)

var last_status: String = "idle"

var _http: HTTPRequest
var _queue: Array[String] = []
var _busy: bool = false

var _poll_http: HTTPRequest
var _stopped: bool = false
var _polled_token: String = ""
## -1 until the backlog was skipped once for the current token.
var _offset: int = -1
var _last_chat_id: String = ""
var _want_chat_id: bool = false
var _conflict_logged: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_poll_http = HTTPRequest.new()
	_poll_http.timeout = POLL_TIMEOUT_S + 10.0
	add_child(_poll_http)
	_poll_loop()


func _exit_tree() -> void:
	_stopped = true
	_queue.clear()
	if is_instance_valid(_http):
		_http.cancel_request()
	if is_instance_valid(_poll_http):
		_poll_http.cancel_request()


func is_configured() -> bool:
	return not Settings.get_string(Settings.TOKEN).is_empty() and not Settings.get_string(Settings.CHAT_ID).is_empty()


func send(text: String) -> void:
	if not is_configured():
		_set_status("not configured, dropped: " + text.left(60))
		return
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append(text.left(MAX_TEXT))
	_pump()


func is_idle() -> bool:
	return not _busy and _queue.is_empty()


## Reports the chat id of the newest message the bot received (from the poller).
func fetch_chat_id() -> void:
	if Settings.get_string(Settings.TOKEN).is_empty():
		_set_status("enter the bot token first")
		return
	if not _last_chat_id.is_empty():
		_report_chat_id(_last_chat_id)
		return
	_want_chat_id = true
	_set_status("waiting: send any message to your bot in Telegram")


func _report_chat_id(chat_id: String) -> void:
	_want_chat_id = false
	_set_status("chat id found: " + chat_id)
	chat_id_found.emit(chat_id)


# ---------------------------------------------------------------- sending

func _pump() -> void:
	if _busy or _queue.is_empty() or not is_instance_valid(_http):
		return
	var token: String = Settings.get_string(Settings.TOKEN)
	var chat_id: String = Settings.get_string(Settings.CHAT_ID)
	if token.is_empty() or chat_id.is_empty():
		_queue.clear()
		return
	var text: String = _queue.pop_front()
	var body: String = JSON.stringify({"chat_id": chat_id, "text": text, "disable_web_page_preview": true})
	var headers := PackedStringArray(["Content-Type: application/json"])
	_busy = true
	var err: int = _http.request(API_BASE + token + "/sendMessage", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		_set_status("send request failed (%d)" % err)
		return
	var completed: Array = await _http.request_completed
	_busy = false
	var parsed: Variant = _parse(completed)
	if parsed is Dictionary and parsed.get("ok", false):
		_set_status("sent: " + text.left(60))
	else:
		_set_status("send failed: %s" % _describe(completed, parsed))
	_pump()


# ---------------------------------------------------------------- receiving

func _poll_loop() -> void:
	while not _stopped:
		var token: String = Settings.get_string(Settings.TOKEN)
		if token.is_empty():
			if not await _sleep(IDLE_RETRY_S):
				return
			continue
		if token != _polled_token:
			_polled_token = token
			_offset = -1
			_last_chat_id = ""
		var delay: float = await _poll_once(token)
		if _stopped:
			return
		if delay > 0.0 and not await _sleep(delay):
			return


## One getUpdates call. Returns seconds to wait before the next call (0 = poll again now).
func _poll_once(token: String) -> float:
	var skipping: bool = _offset < 0
	# First call per token only fetches the newest update, so old commands never run after a restart.
	var query: String = "?offset=-1&timeout=0" if skipping else "?offset=%d&timeout=%d" % [_offset, POLL_TIMEOUT_S]
	var err: int = _poll_http.request(API_BASE + token + "/getUpdates" + query)
	if err != OK:
		return RETRY_S
	var completed: Array = await _poll_http.request_completed
	if _stopped:
		return 0.0
	var parsed: Variant = _parse(completed)
	if completed.size() >= 2 and int(completed[1]) == 409:
		if not _conflict_logged:
			_conflict_logged = true
			_set_status("commands disabled here: another client polls this bot (use one bot per client)")
		return CONFLICT_RETRY_S
	if not parsed is Dictionary or not parsed.get("ok", false):
		_logger.info("[telegram] getUpdates failed: %s" % _describe(completed, parsed))
		return RETRY_S
	_conflict_logged = false
	var updates: Array = parsed.get("result", [])
	if skipping:
		_offset = 0
	for update in updates:
		if not update is Dictionary:
			continue
		_offset = maxi(_offset, int(update.get("update_id", 0)) + 1)
		_handle_update(update, skipping)
	return 0.0


func _handle_update(update: Dictionary, backlog: bool) -> void:
	var msg: Variant = update.get("message", update.get("channel_post", null))
	if not msg is Dictionary or not msg.get("chat") is Dictionary:
		return
	var chat_id: String = str(int(msg["chat"].get("id", 0)))
	if chat_id == "0":
		return
	_last_chat_id = chat_id
	if _want_chat_id:
		_report_chat_id(chat_id)
	if backlog or chat_id != Settings.get_string(Settings.CHAT_ID):
		return
	var text: String = str(msg.get("text", "")).strip_edges()
	if text.is_empty():
		return
	var word: String = text.get_slice(" ", 0).to_lower()
	var args: String = text.substr(word.length()).strip_edges()
	if word.begins_with("/"):
		word = word.substr(1)
	word = word.get_slice("@", 0)
	if word.is_empty():
		return
	_logger.info("[telegram] command '%s'" % word)
	command_received.emit(word, args)


## Returns false if the plugin was unloaded while waiting.
func _sleep(seconds: float) -> bool:
	if _stopped or not is_inside_tree():
		return false
	await get_tree().create_timer(seconds).timeout
	return not _stopped and is_inside_tree()


# ---------------------------------------------------------------- helpers

func _parse(completed: Array) -> Variant:
	if completed.size() < 4 or int(completed[0]) != HTTPRequest.RESULT_SUCCESS:
		return null
	var body: PackedByteArray = completed[3]
	return JSON.parse_string(body.get_string_from_utf8())


func _describe(completed: Array, parsed: Variant) -> String:
	if parsed is Dictionary and parsed.has("description"):
		return str(parsed["description"])
	if completed.size() >= 2:
		return "result=%d http=%d" % [int(completed[0]), int(completed[1])]
	return "no response"


func _set_status(text: String) -> void:
	last_status = text
	_logger.info("[telegram] " + text)
	status_changed.emit(text)
