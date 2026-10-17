extends PluginButton

## Telegram Notify: spawns the Telegram client and the event watcher.

const Settings = preload("res://plugins/telegram_notify/core/Settings.gd")
const TelegramClientScript = preload("res://plugins/telegram_notify/core/TelegramClient.gd")
const WatcherScript = preload("res://plugins/telegram_notify/core/Watcher.gd")

static var _logger := ScopedLogger.create(Settings.PLUGIN_NAME)

var client: Node = null
var _watcher: Node = null
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
	_logger.info("Telegram notify ready (configured=%s)" % client.is_configured())


func _exit_tree() -> void:
	if _reparenting:
		return
	if is_instance_valid(_watcher):
		_watcher.queue_free()
	if is_instance_valid(client):
		client.queue_free()
	_watcher = null
	client = null
