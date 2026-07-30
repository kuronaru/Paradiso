# multiplayer_lobby.gd — LAN / 直连联机大厅
class_name MultiplayerLobby
extends Control

const AFK_HUB_SCENE_PATH := "res://scenes/afk_hub.tscn"
const RELIC_SELECT_SCENE_PATH := "res://scenes/roguelike_relic_select.tscn"
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_PORT := 24567
const MIN_PLAYERS := 2
const MAX_PLAYERS := 4

const COLOR_TEXT := Color(0.94, 0.94, 0.96, 1.0)
const COLOR_MUTED := Color(0.62, 0.66, 0.73, 1.0)
const COLOR_GOLD := Color(1.0, 0.79, 0.30, 1.0)
const COLOR_READY := Color(0.43, 0.91, 0.61, 1.0)
const COLOR_WARNING := Color(1.0, 0.63, 0.30, 1.0)
const COLOR_ERROR := Color(1.0, 0.38, 0.38, 1.0)

var multiplayer_manager: Node = null
var players_snapshot: Array = []
var connection_status := "offline"
var scene_transitioning := false

var nickname_input: LineEdit = null
var address_input: LineEdit = null
var port_input: LineEdit = null
var host_button: Button = null
var join_button: Button = null
var ready_button: Button = null
var start_button: Button = null
var leave_button: Button = null
var status_label: Label = null
var role_label: Label = null
var player_count_label: Label = null
var player_list: VBoxContainer = null
var hint_label: Label = null


func _ready() -> void:
	_set_full_rect()
	_build_ui()
	multiplayer_manager = get_node_or_null("/root/MultiplayerRunManager")
	_connect_manager_signals()
	_refresh_from_manager()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_leave_pressed()
		get_viewport().set_input_as_handled()


func _set_full_rect() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.025, 0.030, 0.043, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(background)
	add_child(background)

	var accent := ColorRect.new()
	accent.color = Color(0.16, 0.30, 0.43, 0.25)
	accent.anchor_left = 0.0
	accent.anchor_top = 0.0
	accent.anchor_right = 1.0
	accent.anchor_bottom = 0.0
	accent.offset_bottom = 164.0
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(accent)

	var page_margin := MarginContainer.new()
	page_margin.add_theme_constant_override("margin_left", 48)
	page_margin.add_theme_constant_override("margin_top", 28)
	page_margin.add_theme_constant_override("margin_right", 48)
	page_margin.add_theme_constant_override("margin_bottom", 32)
	_fill_parent(page_margin)
	add_child(page_margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	page_margin.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	page.add_child(header)

	var heading_stack := VBoxContainer.new()
	heading_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_stack.add_theme_constant_override("separation", 3)
	header.add_child(heading_stack)

	var title := Label.new()
	title.text = "联机大厅"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	heading_stack.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "通过局域网或 IP 地址直连，支持 2～4 名玩家协同迎敌"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.70, 0.76, 0.84, 1.0))
	heading_stack.add_child(subtitle)

	var status_panel := PanelContainer.new()
	status_panel.custom_minimum_size = Vector2(310, 58)
	status_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.055, 0.070, 0.092, 0.96), Color(0.18, 0.30, 0.42, 1.0), 8)
	)
	header.add_child(status_panel)

	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 14)
	status_margin.add_theme_constant_override("margin_top", 8)
	status_margin.add_theme_constant_override("margin_right", 14)
	status_margin.add_theme_constant_override("margin_bottom", 8)
	status_panel.add_child(status_margin)

	var status_stack := VBoxContainer.new()
	status_stack.add_theme_constant_override("separation", 2)
	status_margin.add_child(status_stack)

	status_label = Label.new()
	status_label.text = "● 未连接"
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	status_stack.add_child(status_label)

	role_label = Label.new()
	role_label.text = "可创建房间或加入已有房间"
	role_label.add_theme_font_size_override("font_size", 12)
	role_label.add_theme_color_override("font_color", COLOR_MUTED)
	status_stack.add_child(role_label)

	var connection_panel := PanelContainer.new()
	connection_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.045, 0.051, 0.068, 0.98), Color(0.14, 0.17, 0.23, 1.0), 10)
	)
	page.add_child(connection_panel)

	var connection_margin := MarginContainer.new()
	connection_margin.add_theme_constant_override("margin_left", 18)
	connection_margin.add_theme_constant_override("margin_top", 14)
	connection_margin.add_theme_constant_override("margin_right", 18)
	connection_margin.add_theme_constant_override("margin_bottom", 14)
	connection_panel.add_child(connection_margin)

	var connection_row := HBoxContainer.new()
	connection_row.add_theme_constant_override("separation", 12)
	connection_margin.add_child(connection_row)

	nickname_input = _make_labeled_input(connection_row, "昵称", "输入昵称", 170.0)
	nickname_input.max_length = 18
	nickname_input.text = "玩家%03d" % randi_range(1, 999)

	address_input = _make_labeled_input(connection_row, "主机地址", "例如 192.168.1.10", 220.0)
	address_input.text = DEFAULT_ADDRESS

	port_input = _make_labeled_input(connection_row, "端口", "1～65535", 110.0)
	port_input.max_length = 5
	port_input.text = str(DEFAULT_PORT)

	var action_spacer := Control.new()
	action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection_row.add_child(action_spacer)

	host_button = _make_action_button("创建房间", Color(0.17, 0.43, 0.62, 1.0))
	host_button.tooltip_text = "在本机创建最多 4 人的 LAN 房间"
	host_button.pressed.connect(_on_host_pressed)
	connection_row.add_child(host_button)

	join_button = _make_action_button("加入房间", Color(0.26, 0.48, 0.35, 1.0))
	join_button.tooltip_text = "通过主机 IP 地址和端口直连"
	join_button.pressed.connect(_on_join_pressed)
	connection_row.add_child(join_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	page.add_child(body)

	var roster_panel := PanelContainer.new()
	roster_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.045, 0.049, 0.063, 0.98), Color(0.15, 0.17, 0.22, 1.0), 10)
	)
	body.add_child(roster_panel)

	var roster_margin := MarginContainer.new()
	roster_margin.add_theme_constant_override("margin_left", 20)
	roster_margin.add_theme_constant_override("margin_top", 18)
	roster_margin.add_theme_constant_override("margin_right", 20)
	roster_margin.add_theme_constant_override("margin_bottom", 18)
	roster_panel.add_child(roster_margin)

	var roster_stack := VBoxContainer.new()
	roster_stack.add_theme_constant_override("separation", 12)
	roster_margin.add_child(roster_stack)

	var roster_header := HBoxContainer.new()
	roster_stack.add_child(roster_header)

	var roster_title := Label.new()
	roster_title.text = "房间玩家"
	roster_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_title.add_theme_font_size_override("font_size", 21)
	roster_title.add_theme_color_override("font_color", COLOR_TEXT)
	roster_header.add_child(roster_title)

	player_count_label = Label.new()
	player_count_label.text = "0 / 4"
	player_count_label.add_theme_font_size_override("font_size", 14)
	player_count_label.add_theme_color_override("font_color", COLOR_MUTED)
	roster_header.add_child(player_count_label)

	var separator := HSeparator.new()
	separator.modulate = Color(0.28, 0.31, 0.38, 0.6)
	roster_stack.add_child(separator)

	player_list = VBoxContainer.new()
	player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_list.add_theme_constant_override("separation", 9)
	roster_stack.add_child(player_list)

	var side_panel := PanelContainer.new()
	side_panel.custom_minimum_size = Vector2(330, 0)
	side_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.055, 0.057, 0.072, 0.98), Color(0.20, 0.18, 0.13, 1.0), 10)
	)
	body.add_child(side_panel)

	var side_margin := MarginContainer.new()
	side_margin.add_theme_constant_override("margin_left", 20)
	side_margin.add_theme_constant_override("margin_top", 18)
	side_margin.add_theme_constant_override("margin_right", 20)
	side_margin.add_theme_constant_override("margin_bottom", 18)
	side_panel.add_child(side_margin)

	var side_stack := VBoxContainer.new()
	side_stack.add_theme_constant_override("separation", 12)
	side_margin.add_child(side_stack)

	var ready_title := Label.new()
	ready_title.text = "出发准备"
	ready_title.add_theme_font_size_override("font_size", 21)
	ready_title.add_theme_color_override("font_color", COLOR_GOLD)
	side_stack.add_child(ready_title)

	hint_label = Label.new()
	hint_label.text = "创建或加入房间后即可准备。至少 2 名玩家，且所有玩家准备完毕，房主才能开始。"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", COLOR_MUTED)
	side_stack.add_child(hint_label)

	var side_spacer := Control.new()
	side_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_stack.add_child(side_spacer)

	ready_button = _make_action_button("准备", Color(0.23, 0.53, 0.35, 1.0))
	ready_button.custom_minimum_size.y = 46.0
	ready_button.pressed.connect(_on_ready_pressed)
	side_stack.add_child(ready_button)

	start_button = _make_action_button("等待房主开始", Color(0.63, 0.43, 0.13, 1.0))
	start_button.custom_minimum_size.y = 50.0
	start_button.pressed.connect(_on_start_pressed)
	side_stack.add_child(start_button)

	leave_button = _make_action_button("离开并返回大厅", Color(0.34, 0.20, 0.22, 1.0))
	leave_button.custom_minimum_size.y = 40.0
	leave_button.pressed.connect(_on_leave_pressed)
	side_stack.add_child(leave_button)


func _make_labeled_input(parent: HBoxContainer, label_text: String, placeholder: String, width: float) -> LineEdit:
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = width
	stack.add_theme_constant_override("separation", 4)
	parent.add_child(stack)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	stack.add_child(label)

	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.custom_minimum_size = Vector2(width, 35)
	input.add_theme_font_size_override("font_size", 14)
	input.add_theme_color_override("font_color", COLOR_TEXT)
	input.add_theme_color_override("font_placeholder_color", Color(0.42, 0.45, 0.51, 1.0))
	input.add_theme_stylebox_override(
		"normal",
		_make_panel_style(Color(0.075, 0.082, 0.105, 1.0), Color(0.18, 0.21, 0.28, 1.0), 6)
	)
	input.add_theme_stylebox_override(
		"focus",
		_make_panel_style(Color(0.085, 0.095, 0.125, 1.0), Color(0.30, 0.57, 0.78, 1.0), 6)
	)
	stack.add_child(input)
	return input


func _make_action_button(text_value: String, background_color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(128, 38)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.47, 0.52, 1.0))
	button.add_theme_stylebox_override("normal", _make_panel_style(background_color, background_color.lightened(0.18), 7))
	button.add_theme_stylebox_override("hover", _make_panel_style(background_color.lightened(0.09), background_color.lightened(0.28), 7))
	button.add_theme_stylebox_override("pressed", _make_panel_style(background_color.darkened(0.10), background_color.lightened(0.12), 7))
	button.add_theme_stylebox_override("disabled", _make_panel_style(Color(0.12, 0.13, 0.16, 0.9), Color(0.20, 0.21, 0.24, 0.9), 7))
	return button


func _make_panel_style(background_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _fill_parent(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _connect_manager_signals() -> void:
	if not multiplayer_manager:
		return
	_connect_manager_signal("lobby_updated", Callable(self, "_on_lobby_updated"))
	_connect_manager_signal("connection_status_changed", Callable(self, "_on_connection_status_changed"))
	_connect_manager_signal("run_start_requested", Callable(self, "_on_run_start_requested"))
	_connect_manager_signal("session_ended", Callable(self, "_on_session_ended"))


func _connect_manager_signal(signal_name: StringName, callback: Callable) -> void:
	if multiplayer_manager.has_signal(signal_name) and not multiplayer_manager.is_connected(signal_name, callback):
		multiplayer_manager.connect(signal_name, callback)


func _refresh_from_manager() -> void:
	if not multiplayer_manager:
		connection_status = "error"
		players_snapshot.clear()
		_refresh_ui("联机服务未初始化，请确认 MultiplayerRunManager 已配置为 Autoload。")
		return

	var snapshot = multiplayer_manager.call("get_players_snapshot")
	players_snapshot = snapshot.duplicate(true) if snapshot is Array else []
	_refresh_ui()


func _on_host_pressed() -> void:
	if not multiplayer_manager:
		return
	var nickname := _validated_nickname()
	var port := _validated_port()
	if nickname == "" or port <= 0:
		return

	_set_connection_message("正在创建房间……", COLOR_WARNING)
	var result := int(multiplayer_manager.call("host_session", port, nickname))
	if result != OK:
		connection_status = "error"
		_refresh_ui("创建房间失败，错误码 %d。" % result)
		return
	_refresh_from_manager()


func _on_join_pressed() -> void:
	if not multiplayer_manager:
		return
	var nickname := _validated_nickname()
	var address := address_input.text.strip_edges()
	var port := _validated_port()
	if nickname == "" or port <= 0:
		return
	if address == "":
		_refresh_ui("请输入房主地址，例如 192.168.1.10。")
		address_input.grab_focus()
		return

	_set_connection_message("正在连接 %s:%d ……" % [address, port], COLOR_WARNING)
	var result := int(multiplayer_manager.call("join_session", address, port, nickname))
	if result != OK:
		connection_status = "error"
		_refresh_ui("加入房间失败，错误码 %d。" % result)
		return
	_refresh_from_manager()


func _on_ready_pressed() -> void:
	if not multiplayer_manager or not _manager_is_active() or not _has_local_player():
		return
	multiplayer_manager.call("set_local_ready", not _is_local_ready())
	_refresh_from_manager()


func _on_start_pressed() -> void:
	if not multiplayer_manager or not _is_local_host():
		return
	if not _can_host_start():
		_refresh_ui("需要 2～4 名已连接玩家，且所有玩家都已准备。")
		return
	if not bool(multiplayer_manager.call("start_session_run")):
		_refresh_ui("暂时无法开始，请检查所有玩家的连接与准备状态。")


func _on_leave_pressed() -> void:
	if scene_transitioning:
		return
	scene_transitioning = true
	if multiplayer_manager and multiplayer_manager.has_method("leave_session"):
		multiplayer_manager.call("leave_session")
	_change_scene(AFK_HUB_SCENE_PATH)


func _on_lobby_updated(players: Array = []) -> void:
	players_snapshot = players.duplicate(true)
	_refresh_ui()


func _on_connection_status_changed(status: String = "") -> void:
	if status != "":
		connection_status = status
	_refresh_from_manager()


func _on_run_start_requested() -> void:
	if scene_transitioning:
		return
	scene_transitioning = true
	_change_scene(RELIC_SELECT_SCENE_PATH)


func _on_session_ended(reason: String = "") -> void:
	if scene_transitioning:
		return
	scene_transitioning = true
	if reason != "":
		connection_status = "offline"
	_change_scene(AFK_HUB_SCENE_PATH)


func _change_scene(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		scene_transitioning = false
		connection_status = "error"
		_refresh_ui("无法打开场景：%s（错误码 %d）" % [scene_path, error])


func _validated_nickname() -> String:
	var nickname := nickname_input.text.strip_edges()
	if nickname == "":
		_refresh_ui("请输入昵称。")
		nickname_input.grab_focus()
		return ""
	nickname_input.text = nickname
	return nickname


func _validated_port() -> int:
	var raw := port_input.text.strip_edges()
	if not raw.is_valid_int():
		_refresh_ui("端口必须是 1～65535 的整数。")
		port_input.grab_focus()
		return -1
	var port := int(raw)
	if port < 1 or port > 65535:
		_refresh_ui("端口必须位于 1～65535。")
		port_input.grab_focus()
		return -1
	return port


func _manager_is_active() -> bool:
	return (
		multiplayer_manager != null
		and multiplayer_manager.has_method("is_session_active")
		and bool(multiplayer_manager.call("is_session_active"))
	)


func _local_player_id() -> int:
	if not multiplayer_manager or not multiplayer_manager.has_method("get_local_player_id"):
		return 0
	return int(multiplayer_manager.call("get_local_player_id"))


func _is_local_host() -> bool:
	return _manager_is_active() and _local_player_id() == 1


func _is_local_ready() -> bool:
	var local_id := _local_player_id()
	for value in players_snapshot:
		if value is Dictionary and int(value.get("peer_id", 0)) == local_id:
			return bool(value.get("ready", false))
	return false


func _has_local_player() -> bool:
	var local_id := _local_player_id()
	for value in players_snapshot:
		if value is Dictionary and int(value.get("peer_id", 0)) == local_id:
			return true
	return false


func _can_host_start() -> bool:
	if not _is_local_host():
		return false
	if players_snapshot.size() < MIN_PLAYERS or players_snapshot.size() > MAX_PLAYERS:
		return false
	for value in players_snapshot:
		if not (value is Dictionary):
			return false
		if not bool(value.get("connected", false)) or not bool(value.get("ready", false)):
			return false
	return multiplayer_manager.has_method("can_start_run") and bool(multiplayer_manager.call("can_start_run"))


func _refresh_ui(message_override: String = "") -> void:
	var active := _manager_is_active()
	var local_host := _is_local_host()
	var local_ready := _is_local_ready()

	nickname_input.editable = not active
	address_input.editable = not active
	port_input.editable = not active
	host_button.disabled = multiplayer_manager == null or active or connection_status in ["connecting", "hosting"]
	join_button.disabled = multiplayer_manager == null or active or connection_status in ["connecting", "hosting"]
	ready_button.disabled = not active or not _has_local_player() or connection_status in ["connecting", "running"]
	ready_button.text = "取消准备" if local_ready else "准备"

	if local_host:
		start_button.text = "开始肉鸽"
		start_button.disabled = not _can_host_start()
	else:
		start_button.text = "等待房主开始"
		start_button.disabled = true

	leave_button.text = "离开房间并返回" if active else "返回 AFK 大厅"
	leave_button.disabled = scene_transitioning

	_refresh_status(message_override)
	_refresh_player_list()


func _refresh_status(message_override: String = "") -> void:
	if message_override != "":
		_set_connection_message(message_override, COLOR_ERROR if connection_status == "error" else COLOR_WARNING)
	elif not multiplayer_manager:
		_set_connection_message("● 联机服务不可用", COLOR_ERROR)
	else:
		var status_text := _localized_status(connection_status)
		var color := _status_color(connection_status)
		_set_connection_message("● %s" % status_text, color)

	if _is_local_host():
		role_label.text = "你是房主 · 端口 %d · 最多 4 人" % _validated_port_without_message()
	elif _manager_is_active():
		role_label.text = "你是房间成员 · 等待所有玩家准备"
	else:
		role_label.text = "可创建房间或加入已有房间"


func _set_connection_message(message: String, color: Color) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color)


func _localized_status(status: String) -> String:
	match status:
		"hosting":
			return "房间已创建，等待玩家加入"
		"connecting":
			return "正在连接房主"
		"connected":
			return "已连接"
		"lobby":
			return "房间连接正常"
		"running":
			return "游戏即将开始"
		"error":
			return "连接发生错误"
		_:
			return "未连接"


func _status_color(status: String) -> Color:
	match status:
		"hosting", "connected", "lobby":
			return COLOR_READY
		"connecting", "running":
			return COLOR_WARNING
		"error":
			return COLOR_ERROR
		_:
			return COLOR_MUTED


func _validated_port_without_message() -> int:
	var raw := port_input.text.strip_edges()
	if raw.is_valid_int():
		return clampi(int(raw), 1, 65535)
	return DEFAULT_PORT


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

	player_count_label.text = "%d / %d · 至少 %d 人" % [players_snapshot.size(), MAX_PLAYERS, MIN_PLAYERS]
	player_count_label.add_theme_color_override(
		"font_color",
		COLOR_READY if players_snapshot.size() >= MIN_PLAYERS else COLOR_MUTED
	)

	if players_snapshot.is_empty():
		var empty := Label.new()
		empty.text = "尚未加入房间\n创建房间，或输入房主地址进行直连。"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", COLOR_MUTED)
		player_list.add_child(empty)
	else:
		for value in players_snapshot:
			if value is Dictionary:
				player_list.add_child(_build_player_row(value))

	var waiting_slots := maxi(0, MAX_PLAYERS - players_snapshot.size())
	for index in range(waiting_slots):
		player_list.add_child(_build_waiting_row(players_snapshot.size() + index + 1))

	if not _manager_is_active():
		hint_label.text = "先创建房间或加入房间。LAN 玩家可输入主机的局域网 IP；同机测试可使用 127.0.0.1。"
	elif players_snapshot.size() < MIN_PLAYERS:
		hint_label.text = "还需要至少 %d 名玩家加入。" % (MIN_PLAYERS - players_snapshot.size())
	elif _can_host_start():
		hint_label.text = "所有玩家均已准备，可以开始肉鸽。"
	elif _is_local_host():
		hint_label.text = "等待所有玩家准备。房主也需要点击准备。"
	else:
		hint_label.text = "准备后等待房主开始。"


func _build_player_row(player: Dictionary) -> Control:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size.y = 66.0
	var connected := bool(player.get("connected", false))
	var ready := bool(player.get("ready", false))
	var eliminated := bool(player.get("eliminated", false))
	var local := int(player.get("peer_id", 0)) == _local_player_id()
	var border := Color(0.28, 0.58, 0.42, 1.0) if ready else Color(0.19, 0.22, 0.28, 1.0)
	row_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.066, 0.071, 0.089, 0.98), border, 8)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_panel.add_child(row)

	var seat := Label.new()
	seat.custom_minimum_size.x = 42.0
	seat.text = "%d" % int(player.get("seat", 0))
	seat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seat.add_theme_font_size_override("font_size", 22)
	seat.add_theme_color_override("font_color", COLOR_GOLD)
	row.add_child(seat)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 2)
	row.add_child(identity)

	var display_name := str(player.get("display_name", "玩家"))
	var tags: Array[String] = []
	if int(player.get("peer_id", 0)) == 1:
		tags.append("房主")
	if local:
		tags.append("我")
	var name_label := Label.new()
	name_label.text = display_name + ("  [%s]" % " · ".join(tags) if not tags.is_empty() else "")
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	identity.add_child(name_label)

	var connection_label := Label.new()
	connection_label.text = "已连接" if connected else "连接已断开"
	connection_label.add_theme_font_size_override("font_size", 12)
	connection_label.add_theme_color_override("font_color", COLOR_MUTED if connected else COLOR_ERROR)
	identity.add_child(connection_label)

	var life_label := Label.new()
	var life := int(player.get("life", 0))
	var max_life := int(player.get("max_life", 0))
	life_label.text = "生命 %d/%d" % [life, max_life] if max_life > 0 else ""
	life_label.custom_minimum_size.x = 86.0
	life_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	life_label.add_theme_font_size_override("font_size", 12)
	life_label.add_theme_color_override("font_color", COLOR_MUTED)
	row.add_child(life_label)

	var readiness := Label.new()
	readiness.custom_minimum_size.x = 90.0
	readiness.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if eliminated:
		readiness.text = "已淘汰"
		readiness.add_theme_color_override("font_color", COLOR_ERROR)
	elif ready:
		readiness.text = "✓ 已准备"
		readiness.add_theme_color_override("font_color", COLOR_READY)
	else:
		readiness.text = "未准备"
		readiness.add_theme_color_override("font_color", COLOR_WARNING)
	readiness.add_theme_font_size_override("font_size", 14)
	row.add_child(readiness)
	return row_panel


func _build_waiting_row(seat_index: int) -> Control:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size.y = 52.0
	row_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.046, 0.050, 0.062, 0.68), Color(0.12, 0.14, 0.18, 0.8), 8)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_panel.add_child(row)

	var seat := Label.new()
	seat.custom_minimum_size.x = 42.0
	seat.text = str(seat_index)
	seat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seat.add_theme_color_override("font_color", Color(0.34, 0.37, 0.43, 1.0))
	row.add_child(seat)

	var waiting := Label.new()
	waiting.text = "等待玩家加入……"
	waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	waiting.add_theme_font_size_override("font_size", 14)
	waiting.add_theme_color_override("font_color", Color(0.40, 0.43, 0.49, 1.0))
	row.add_child(waiting)
	return row_panel
