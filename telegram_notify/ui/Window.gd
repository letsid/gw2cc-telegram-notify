extends Window

## Settings: bot token, chat id, event toggles, test message.

const Settings = preload("res://plugins/telegram_notify/core/Settings.gd")

var _token_edit: LineEdit
var _chat_edit: LineEdit
var _keywords_edit: LineEdit
var _status_label: Label


func _enter_tree() -> void:
	ConfigUtils.restore_window_state(self, Settings.PLUGIN_NAME, "window")


func _exit_tree() -> void:
	ConfigUtils.save_window_state(self, Settings.PLUGIN_NAME, "window")


func _ready() -> void:
	close_requested.connect(hide)
	min_size = Vector2i(380, 460)
	_build_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and _token_edit:
		_load_fields()
		var client: Node = _client()
		if client:
			_status_label.text = "Status: " + str(client.last_status)
			if not client.status_changed.is_connected(_on_status):
				client.status_changed.connect(_on_status)
			if not client.chat_id_found.is_connected(_on_chat_id_found):
				client.chat_id_found.connect(_on_chat_id_found)


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	scroll.add_child(margin)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	_section(vb, "Telegram bot")
	_hint(vb, "Create a bot with @BotFather, paste its token, send /start to the bot, then press \"Find chat ID\".")
	_token_edit = _add_line(vb, "Bot token", "123456:ABC-DEF...")
	_token_edit.secret = true
	_token_edit.text_submitted.connect(func(_t: String) -> void: _save_fields())
	_token_edit.focus_exited.connect(_save_fields)
	_chat_edit = _add_line(vb, "Chat ID", "e.g. 123456789")
	_chat_edit.text_submitted.connect(func(_t: String) -> void: _save_fields())
	_chat_edit.focus_exited.connect(_save_fields)

	var row := HBoxContainer.new()
	vb.add_child(row)
	var find_btn := Button.new()
	find_btn.text = "Find chat ID"
	find_btn.pressed.connect(_on_find_chat_id)
	row.add_child(find_btn)
	var test_btn := Button.new()
	test_btn.text = "Send test message"
	test_btn.pressed.connect(_on_test)
	row.add_child(test_btn)

	_section(vb, "Notify on")
	_add_bool(vb, Settings.ON_DEATH, "Character dies")
	_add_bool(vb, Settings.ON_DOWNED, "Character is downed")
	_add_bool(vb, Settings.ON_COMMANDER, "Squad commander leaves the map / goes offline / drops tag")
	_add_bool(vb, Settings.ON_COMMANDER_CHANGE, "Squad commander changes / switches tag colour")
	_add_bool(vb, Settings.ON_MENTION, "Character or account name mentioned in chat")
	_add_bool(vb, Settings.ON_WHISPER, "Whisper received")
	_add_bool(vb, Settings.ON_INVENTORY_FULL, "Inventory full")
	_keywords_edit = _add_line(vb, "Extra keywords (comma separated)", "e.g. nickname, guild tag")
	_keywords_edit.text_submitted.connect(func(_t: String) -> void: _save_fields())
	_keywords_edit.focus_exited.connect(_save_fields)

	_section(vb, "Bot commands")
	_add_bool(vb, Settings.ALLOW_QUIT, "Allow /quit (closes the client)")
	_hint(vb, "Commands are only accepted from the chat ID above. With several clients on one bot only one of them receives commands.")

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = "Status: idle"
	vb.add_child(_status_label)
	_load_fields()


func _load_fields() -> void:
	_token_edit.text = Settings.get_string(Settings.TOKEN)
	_chat_edit.text = Settings.get_string(Settings.CHAT_ID)
	_keywords_edit.text = Settings.get_string(Settings.KEYWORDS)


func _save_fields() -> void:
	Settings.set_value(Settings.TOKEN, _token_edit.text.strip_edges())
	Settings.set_value(Settings.CHAT_ID, _chat_edit.text.strip_edges())
	Settings.set_value(Settings.KEYWORDS, _keywords_edit.text.strip_edges())


func _on_find_chat_id() -> void:
	_save_fields()
	var client: Node = _client()
	if client:
		client.fetch_chat_id()


func _on_test() -> void:
	_save_fields()
	var client: Node = _client()
	if not client:
		_status_label.text = "Status: plugin not running"
		return
	client.send("✅ gw2cc telegram-notify test message")


func _on_status(text: String) -> void:
	_status_label.text = "Status: " + text


func _on_chat_id_found(chat_id: String) -> void:
	_chat_edit.text = chat_id
	_save_fields()


func _client() -> Node:
	var owner_button: Node = get_parent()
	if owner_button and "client" in owner_button and is_instance_valid(owner_button.client):
		return owner_button.client
	return null


func _section(parent: Container, title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)
	parent.add_child(HSeparator.new())


func _hint(parent: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(label)


func _add_line(parent: Container, title: String, placeholder: String) -> LineEdit:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	return edit


func _add_bool(parent: Container, key: String, title: String) -> void:
	var box := CheckBox.new()
	box.text = title
	box.button_pressed = Settings.get_bool(key)
	box.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	parent.add_child(box)
