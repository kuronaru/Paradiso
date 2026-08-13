# game_menu_ui.gd — 游戏内菜单UI
# 显示右上角快捷按钮，并管理暂停菜单。
class_name GameMenuUI
extends Control

const M = "GameMenu"
const START_MENU_PATH := "res://scenes/start_menu.tscn"
const AFK_HUB_PATH := "res://scenes/afk_hub.tscn"
const ENCYCLOPEDIA_SCENE_PATH := "res://scenes/encyclopedia.tscn"

var pause_overlay: Control = null
var pause_shortcut_button: Button = null
var encyclopedia_overlay: EncyclopediaUI = null
var settings_overlay: SettingsUI = null
var run_end_overlay: Control = null
var run_end_title: Label = null
var run_end_detail: Label = null
var run_end_stay_button: Button = null
var run_end_return_button: Button = null


## 创建游戏内菜单UI
func _ready() -> void:
	"""创建游戏内菜单UI"""
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_full_rect()
	_build_pause_overlay()
	_build_run_end_overlay()
	_build_top_buttons()
	_connect_roguelike_manager()


## 让菜单UI铺满窗口，便于放置右上角按钮和居中暂停菜单
func _set_full_rect() -> void:
	"""让菜单UI铺满窗口，便于放置右上角按钮和居中暂停菜单"""
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 创建右上角从左到右排列的游戏内按钮
func _build_top_buttons() -> void:
	"""创建右上角从左到右排列的游戏内按钮"""
	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.anchor_top = 0.0
	bar.anchor_bottom = 0.0
	bar.offset_left = -242.0
	bar.offset_right = -16.0
	bar.offset_top = 16.0
	bar.offset_bottom = 54.0
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.process_mode = Node.PROCESS_MODE_ALWAYS
	bar.z_index = 100
	add_child(bar)

	bar.add_child(_create_top_button("英雄图鉴", _on_catalog_pressed))

	pause_shortcut_button = _create_top_button("暂停", _on_pause_shortcut_pressed)
	bar.add_child(pause_shortcut_button)


## 创建暂停时显示在画面中央的菜单
func _build_pause_overlay() -> void:
	"""创建暂停时显示在画面中央的菜单"""
	pause_overlay = Control.new()
	pause_overlay.visible = false
	pause_overlay.anchor_left = 0.0
	pause_overlay.anchor_top = 0.0
	pause_overlay.anchor_right = 1.0
	pause_overlay.anchor_bottom = 1.0
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.z_index = 10
	add_child(pause_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.anchor_left = 0.0
	dim.anchor_top = 0.0
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(center)

	var menu := VBoxContainer.new()
	menu.custom_minimum_size = Vector2(280, 226)
	menu.add_theme_constant_override("separation", 12)
	menu.mouse_filter = Control.MOUSE_FILTER_PASS
	center.add_child(menu)

	menu.add_child(_create_pause_button("继续游戏", _on_continue_pressed))
	menu.add_child(_create_pause_button("游戏设置", _on_settings_pressed))
	menu.add_child(_create_pause_button("返回菜单", _on_return_menu_pressed))
	menu.add_child(_create_pause_button("退出游戏", _on_quit_pressed))


## 创建肉鸽结算遮罩，确保生命归零或最终胜利后有明确的退出路径。
func _build_run_end_overlay() -> void:
	run_end_overlay = Control.new()
	run_end_overlay.visible = false
	run_end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	run_end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	run_end_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	run_end_overlay.z_index = 320
	add_child(run_end_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.018, 0.026, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	run_end_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	run_end_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 260)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.060, 0.078, 0.98)
	panel_style.border_color = Color(0.35, 0.31, 0.20, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	margin.add_child(stack)

	run_end_title = Label.new()
	run_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	run_end_title.add_theme_font_size_override("font_size", 32)
	stack.add_child(run_end_title)

	run_end_detail = Label.new()
	run_end_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	run_end_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	run_end_detail.add_theme_font_size_override("font_size", 15)
	run_end_detail.add_theme_color_override("font_color", Color(0.78, 0.80, 0.85, 1.0))
	run_end_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(run_end_detail)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	stack.add_child(actions)

	run_end_stay_button = _create_pause_button("留在房间", _on_run_end_stay_pressed)
	run_end_stay_button.custom_minimum_size.x = 170
	actions.add_child(run_end_stay_button)

	run_end_return_button = _create_pause_button("返回 AFK 大厅", _on_run_end_return_pressed)
	run_end_return_button.custom_minimum_size.x = 190
	actions.add_child(run_end_return_button)


func _connect_roguelike_manager() -> void:
	var managers := get_tree().get_nodes_in_group("roguelike_manager")
	if managers.is_empty():
		call_deferred("_connect_roguelike_manager")
		return
	var manager := managers[0] as RoguelikeManager
	if manager and not manager.run_ended.is_connected(_on_run_ended):
		manager.run_ended.connect(_on_run_ended)


func _on_run_ended(victory: bool) -> void:
	_set_paused(false)
	var online := _is_online_session()
	var host := _is_online_host()
	run_end_title.text = "冒险完成" if victory else "冒险失败"
	run_end_title.add_theme_color_override(
		"font_color",
		Color(1.0, 0.82, 0.32, 1.0) if victory else Color(1.0, 0.38, 0.38, 1.0)
	)
	if victory:
		run_end_detail.text = "全部回合已经完成。"
	elif online and host:
		run_end_detail.text = "玩家生命已归零，你已被淘汰。房主可留在房间维持其他玩家的战斗；返回大厅将结束整个房间。"
	elif online:
		run_end_detail.text = "玩家生命已归零，你已被淘汰。你可以留在房间等待，或离开当前联机房间。"
	else:
		run_end_detail.text = "玩家生命已归零，本次冒险结束。"
	run_end_stay_button.visible = online and not victory
	run_end_return_button.text = (
		"结束房间并返回" if online and host
		else ("离开房间并返回" if online else "返回 AFK 大厅")
	)
	run_end_overlay.visible = true


func _on_run_end_stay_pressed() -> void:
	if run_end_overlay:
		run_end_overlay.visible = false


func _on_run_end_return_pressed() -> void:
	if run_end_overlay:
		run_end_overlay.visible = false
	var coordinator := get_tree().root.get_node_or_null("MultiplayerRunManager")
	if coordinator and coordinator.has_method("leave_session"):
		coordinator.leave_session()
	GameManager.save_game()
	get_tree().change_scene_to_file(AFK_HUB_PATH)


func _is_online_host() -> bool:
	if not _is_online_session():
		return false
	var coordinator := get_tree().root.get_node_or_null("MultiplayerRunManager")
	return (
		coordinator.has_method("get_local_player_id")
		and int(coordinator.call("get_local_player_id")) == 1
	)


## 创建右上角快捷按钮
func _create_top_button(text: String, callback: Callable) -> Button:
	"""创建右上角快捷按钮"""
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(104, 38)
	button.add_theme_font_size_override("font_size", 15)
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.pressed.connect(callback)
	return button


## 创建暂停菜单按钮
func _create_pause_button(text: String, callback: Callable) -> Button:
	"""创建暂停菜单按钮"""
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 44)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 18)
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.pressed.connect(callback)
	return button


## 切换游戏暂停状态和暂停菜单显示
func _set_paused(paused: bool) -> void:
	"""切换游戏暂停状态和暂停菜单显示"""
	if not _is_online_session():
		get_tree().paused = paused
	pause_overlay.visible = paused
	if pause_shortcut_button:
		pause_shortcut_button.text = "关闭" if paused and _is_online_session() else ("继续" if paused else "暂停")


func _is_online_session() -> bool:
	var coordinator := get_tree().root.get_node_or_null("MultiplayerRunManager")
	return coordinator and coordinator.has_method("is_session_active") and coordinator.is_session_active()


## 进入角色/敌人图鉴界面
func _on_catalog_pressed() -> void:
	"""进入角色/敌人图鉴界面"""
	_open_encyclopedia_overlay()


## 在游戏内以覆盖层打开图鉴，不切换场景也不改变暂停状态
func _open_encyclopedia_overlay() -> void:
	"""在游戏内以覆盖层打开图鉴，不切换场景也不改变暂停状态"""
	if encyclopedia_overlay and is_instance_valid(encyclopedia_overlay):
		encyclopedia_overlay.move_to_front()
		return

	var scene := load(ENCYCLOPEDIA_SCENE_PATH) as PackedScene
	if not scene:
		return

	encyclopedia_overlay = scene.instantiate() as EncyclopediaUI
	encyclopedia_overlay.set_return_callback(_close_encyclopedia_overlay)
	encyclopedia_overlay.z_index = 200
	encyclopedia_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(encyclopedia_overlay)


## 关闭游戏内图鉴覆盖层，保持打开前的游戏暂停/运行状态
func _close_encyclopedia_overlay() -> void:
	"""关闭游戏内图鉴覆盖层，保持打开前的游戏暂停/运行状态"""
	if encyclopedia_overlay and is_instance_valid(encyclopedia_overlay):
		encyclopedia_overlay.queue_free()
	encyclopedia_overlay = null


## 右上角暂停/继续快捷按钮
func _on_pause_shortcut_pressed() -> void:
	"""右上角暂停/继续快捷按钮"""
	_set_paused(not pause_overlay.visible if _is_online_session() else not get_tree().paused)


## 继续游戏
func _on_continue_pressed() -> void:
	"""继续游戏"""
	_set_paused(false)


## 打开游戏设置界面
func _on_settings_pressed() -> void:
	"""打开游戏设置界面"""
	_open_settings_overlay()


## 在游戏内打开设置覆盖层，保持当前暂停状态
func _open_settings_overlay() -> void:
	"""在游戏内打开设置覆盖层，保持当前暂停状态"""
	if settings_overlay and is_instance_valid(settings_overlay):
		settings_overlay.move_to_front()
		return
	settings_overlay = SettingsUI.new()
	settings_overlay.set_return_callback(_close_settings_overlay)
	settings_overlay.z_index = 260
	settings_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(settings_overlay)


## 关闭游戏内设置覆盖层
func _close_settings_overlay() -> void:
	"""关闭游戏内设置覆盖层"""
	if settings_overlay and is_instance_valid(settings_overlay):
		settings_overlay.queue_free()
	settings_overlay = null


## 返回开始菜单
func _on_return_menu_pressed() -> void:
	"""返回开始菜单"""
	_set_paused(false)
	var coordinator := get_tree().root.get_node_or_null("MultiplayerRunManager")
	if coordinator and coordinator.has_method("leave_session"):
		coordinator.leave_session()
	get_tree().change_scene_to_file(START_MENU_PATH)


## 退出游戏
func _on_quit_pressed() -> void:
	"""退出游戏"""
	_set_paused(false)
	var coordinator := get_tree().root.get_node_or_null("MultiplayerRunManager")
	if coordinator and coordinator.has_method("leave_session"):
		coordinator.leave_session()
	get_tree().quit()
