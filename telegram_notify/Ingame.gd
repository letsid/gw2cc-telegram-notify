extends PluginButton

## Telegram Notify: spawns the Telegram client and the event watcher.

const Settings = preload("res://plugins/telegram_notify/core/Settings.gd")
const TelegramClientScript = preload("res://plugins/telegram_notify/core/TelegramClient.gd")
const WatcherScript = preload("res://plugins/telegram_notify/core/Watcher.gd")

static var _logger := ScopedLogger.create(Settings.PLUGIN_NAME)

var client: Node = null
var _watcher: Node = null
const QUIT_SEND_WAIT_S := 5.0

var _quitting: bool = false
## PluginButton.super() reparents to top_menu, which fires _exit_tree mid-_ready.
var _reparenting: bool = false


func _ready() -> void:
	_reparenting = true
	super()
	_reparenting = false
	client = TelegramClientScript.new()
	client.name = "TelegramClient"
	add_child(client)
	_watcher = WatcherScript.new()
	_watcher.name = "TelegramWatcher"
	_watcher.client = client
	add_child(_watcher)
	client.command_received.connect(_on_command)
	_logger.info("Telegram notify ready (configured=%s)" % client.is_configured())


func _on_command(command: String, _args: String) -> void:
	match command:
		"quit":
			_quit_from_telegram()
		"help", "start":
			client.send(_prefixed("Commands: /quit – close this gw2cc client"))


func _quit_from_telegram() -> void:
	if _quitting:
		return
	if not Settings.get_bool(Settings.ALLOW_QUIT):
		client.send(_prefixed("/quit is disabled in the plugin settings."))
		return
	_quitting = true
	_logger.info("Quit requested via Telegram")
	client.send(_prefixed("👋 Closing gw2cc."))
	# Give the reply a moment to go out before the process ends.
	var deadline: int = Time.get_ticks_msec() + int(QUIT_SEND_WAIT_S * 1000.0)
	while is_inside_tree() and not client.is_idle() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
	if SceneManager.has_method("quit"):
		SceneManager.quit()
	else:
		get_tree().quit(0)


func _prefixed(text: String) -> String:
	var who: String = _watcher._own_character_name() if is_instance_valid(_watcher) else ""
	return ("[%s] %s" % [who, text]) if not who.is_empty() else text


func _exit_tree() -> void:
	if _reparenting:
		return
	if is_instance_valid(_watcher):
		_watcher.queue_free()
	if is_instance_valid(client):
		client.queue_free()
	_watcher = null
	client = null
