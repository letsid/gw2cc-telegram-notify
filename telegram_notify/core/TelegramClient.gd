extends Node

## Sends queued messages to the Telegram Bot API, one request at a time.

const Settings = preload("res://plugins/telegram_notify/core/Settings.gd")

const API_BASE := "https://api.telegram.org/bot"
const MAX_QUEUE := 20
const MAX_TEXT := 3500

signal status_changed(text: String)
signal chat_id_found(chat_id: String)

static var _logger := ScopedLogger.create(Settings.PLUGIN_NAME)

var last_status: String = "idle"

var _http: HTTPRequest
var _queue: Array[String] = []
var _busy: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)


func _exit_tree() -> void:
	_queue.clear()
	if is_instance_valid(_http):
		_http.cancel_request()


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


## Reads getUpdates and reports the chat id of the newest message sent to the bot.
func fetch_chat_id() -> void:
	var token: String = Settings.get_string(Settings.TOKEN)
	if token.is_empty():
		_set_status("enter the bot token first")
		return
	if _busy:
		_set_status("busy, try again in a moment")
		return
	_busy = true
	var err: int = _http.request(API_BASE + token + "/getUpdates")
	if err != OK:
		_busy = false
		_set_status("getUpdates request failed (%d)" % err)
		return
	var completed: Array = await _http.request_completed
	_busy = false
	var parsed: Variant = _parse(completed)
	if not parsed is Dictionary or not parsed.get("ok", false):
		_set_status("getUpdates failed: %s" % _describe(completed, parsed))
		_pump()
		return
	var found: String = ""
	for update in parsed.get("result", []):
		if not update is Dictionary:
			continue
		var msg: Variant = update.get("message", update.get("channel_post", null))
		if msg is Dictionary and msg.get("chat") is Dictionary:
			found = str(int(msg["chat"].get("id", 0)))
	if found.is_empty() or found == "0":
		_set_status("no message found: write /start to your bot in Telegram, then retry")
	else:
		_set_status("chat id found: " + found)
		chat_id_found.emit(found)
	_pump()


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
