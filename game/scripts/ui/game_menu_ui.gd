# game_menu_ui.gd — 游戏内菜单UI
# 显示右上角快捷按钮，并管理暂停菜单。
class_name GameMenuUI
extends Control

const M = "GameMenu"
const START_MENU_PATH := "res://scenes/start_menu.tscn"
const ENCYCLOPEDIA_SCENE_PATH := "res://scenes/encyclopedia.tscn"

var pause_overlay: Control = null
var pause_shortcut_button: Button = null
var encyclopedia_overlay: EncyclopediaUI = null


func _ready() -> void:
	"""创建游戏内菜单UI"""
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_full_rect()
	_build_pause_overlay()
	_build_top_buttons()


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


func _build_top_buttons() -> void:
	"""创建右上角从左到右排列的游戏内按钮"""
	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.anchor_top = 0.0
	bar.anchor_bottom = 0.0
	bar.offset_left = -354.0
	bar.offset_right = -16.0
	bar.offset_top = 16.0
	bar.offset_bottom = 54.0
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.process_mode = Node.PROCESS_MODE_ALWAYS
	bar.z_index = 100
	add_child(bar)

	bar.add_child(_create_top_button("角色仓库", _on_storage_pressed))
	bar.add_child(_create_top_button("角色图鉴", _on_catalog_pressed))

	pause_shortcut_button = _create_top_button("暂停", _on_pause_shortcut_pressed)
	bar.add_child(pause_shortcut_button)


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


func _create_top_button(text: String, callback: Callable) -> Button:
	"""创建右上角快捷按钮"""
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(104, 38)
	button.add_theme_font_size_override("font_size", 15)
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.pressed.connect(callback)
	return button


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


func _set_paused(paused: bool) -> void:
	"""切换游戏暂停状态和暂停菜单显示"""
	get_tree().paused = paused
	pause_overlay.visible = paused
	if pause_shortcut_button:
		pause_shortcut_button.text = "继续" if paused else "暂停"


func _on_storage_pressed() -> void:
	"""角色仓库入口（待接入具体界面）"""
	Log.i(M, "角色仓库功能待实现")


func _on_catalog_pressed() -> void:
	"""进入角色/敌人图鉴界面"""
	_open_encyclopedia_overlay()


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


func _close_encyclopedia_overlay() -> void:
	"""关闭游戏内图鉴覆盖层，保持打开前的游戏暂停/运行状态"""
	if encyclopedia_overlay and is_instance_valid(encyclopedia_overlay):
		encyclopedia_overlay.queue_free()
	encyclopedia_overlay = null


func _on_pause_shortcut_pressed() -> void:
	"""右上角暂停/继续快捷按钮"""
	_set_paused(not get_tree().paused)


func _on_continue_pressed() -> void:
	"""继续游戏"""
	_set_paused(false)


func _on_settings_pressed() -> void:
	"""游戏设置入口（待后续功能接口接入）"""
	pass


func _on_return_menu_pressed() -> void:
	"""返回开始菜单"""
	_set_paused(false)
	get_tree().change_scene_to_file(START_MENU_PATH)


func _on_quit_pressed() -> void:
	"""退出游戏"""
	_set_paused(false)
	get_tree().quit()
