# start_menu.gd — 游戏开始界面
# 显示标题与主菜单按钮，负责进入主战斗场景、图鉴界面或退出游戏。
class_name StartMenu
extends Control

const M = "StartMenu"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const ENCYCLOPEDIA_SCENE_PATH := "res://scenes/encyclopedia.tscn"

var storage_overlay: CharacterStorageUI = null
var load_overlay: Control = null
var primary_game_button: Button = null


func _ready() -> void:
	"""创建开始界面UI"""
	_set_full_rect()
	_build_background()
	_build_menu()


func _set_full_rect() -> void:
	"""让开始界面铺满窗口"""
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _build_background() -> void:
	"""创建深色背景"""
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09, 1.0)
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_menu() -> void:
	"""创建居中的标题与按钮列表"""
	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.offset_left = 0.0
	center.offset_top = 0.0
	center.offset_right = 0.0
	center.offset_bottom = 0.0
	add_child(center)

	var menu := VBoxContainer.new()
	menu.custom_minimum_size = Vector2(360, 360)
	menu.add_theme_constant_override("separation", 14)
	center.add_child(menu)

	var title := Label.new()
	title.text = "Paradiso 9"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86, 1.0))
	menu.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, 26)
	menu.add_child(spacer)

	primary_game_button = _create_menu_button(_get_primary_game_button_text(), _on_primary_game_pressed)
	menu.add_child(primary_game_button)
	menu.add_child(_create_menu_button("加载游戏", _on_load_pressed))
	menu.add_child(_create_menu_button("冒险小队", _on_storage_pressed))
	menu.add_child(_create_menu_button("角色图鉴", _on_catalog_pressed))
	menu.add_child(_create_menu_button("游戏设置", _on_settings_pressed))
	menu.add_child(_create_menu_button("退出游戏", _on_quit_pressed))


func _create_menu_button(text: String, callback: Callable) -> Button:
	"""创建统一样式的菜单按钮"""
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	return button


func _get_primary_game_button_text() -> String:
	"""获取主操作按钮显示文本"""
	return "继续游戏" if GameManager.has_any_save_slot() else "开始游戏"


func _refresh_primary_game_button() -> void:
	"""刷新主操作按钮显示状态"""
	if primary_game_button:
		primary_game_button.text = _get_primary_game_button_text()


func _on_primary_game_pressed() -> void:
	"""根据存档状态开始新游戏或继续已有游戏"""
	if GameManager.has_save_slot(GameManager.current_save_id):
		GameManager.load_save(GameManager.current_save_id)
	else:
		GameManager.create_new_save(GameManager.current_save_id)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _on_load_pressed() -> void:
	"""打开存档选择界面"""
	_open_load_overlay()


func _on_catalog_pressed() -> void:
	"""进入角色/敌人图鉴界面"""
	get_tree().change_scene_to_file(ENCYCLOPEDIA_SCENE_PATH)


func _on_storage_pressed() -> void:
	"""打开局外冒险小队养成界面"""
	if storage_overlay and is_instance_valid(storage_overlay):
		storage_overlay.move_to_front()
		return
	storage_overlay = CharacterStorageUI.new()
	storage_overlay.set_return_callback(_close_storage_overlay)
	storage_overlay.z_index = 100
	add_child(storage_overlay)


func _close_storage_overlay() -> void:
	"""关闭冒险小队养成界面"""
	if storage_overlay and is_instance_valid(storage_overlay):
		storage_overlay.queue_free()
	storage_overlay = null


func _open_load_overlay() -> void:
	"""打开三槽位存档选择界面"""
	if load_overlay and is_instance_valid(load_overlay):
		load_overlay.move_to_front()
		return
	if storage_overlay and is_instance_valid(storage_overlay):
		_close_storage_overlay()

	load_overlay = Control.new()
	load_overlay.anchor_left = 0.0
	load_overlay.anchor_top = 0.0
	load_overlay.anchor_right = 1.0
	load_overlay.anchor_bottom = 1.0
	load_overlay.offset_left = 0.0
	load_overlay.offset_top = 0.0
	load_overlay.offset_right = 0.0
	load_overlay.offset_bottom = 0.0
	load_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	load_overlay.z_index = 120
	add_child(load_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.045, 0.96)
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_overlay.add_child(bg)

	var margin := MarginContainer.new()
	margin.anchor_left = 0.0
	margin.anchor_top = 0.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 72.0
	margin.offset_top = 48.0
	margin.offset_right = -72.0
	margin.offset_bottom = -64.0
	load_overlay.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	root.add_child(top_bar)

	var title := Label.new()
	title.text = "加载游戏"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86, 1.0))
	top_bar.add_child(title)

	var back_button := Button.new()
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(112, 42)
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.pressed.connect(_close_load_overlay)
	top_bar.add_child(back_button)

	var slot_box := VBoxContainer.new()
	slot_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot_box.add_theme_constant_override("separation", 12)
	root.add_child(slot_box)

	for save_id in GameManager.get_save_slot_ids():
		slot_box.add_child(_create_save_slot_button(save_id))


func _create_save_slot_button(save_id: String) -> Button:
	"""创建单个存档槽位按钮"""
	var summary := GameManager.get_save_slot_summary(save_id)
	var slot_index := save_id.replace("save", "")
	var current_label := "（当前）" if save_id == GameManager.current_save_id else ""
	var has_save := bool(summary.get("exists", false))
	var button := Button.new()
	if has_save:
		button.text = "存档 %s%s\n金币: %d    角色: %d" % [
			slot_index,
			current_label,
			int(summary.get("gold", 0)),
			int(summary.get("character_count", 0))
		]
	else:
		button.text = "存档 %s%s\n空白" % [
			slot_index,
			current_label
		]
	button.custom_minimum_size = Vector2(520, 88)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(_select_save_slot.bind(save_id))
	return button


func _select_save_slot(save_id: String) -> void:
	"""选择一个存档槽位并返回主菜单"""
	GameManager.switch_save_slot(save_id)
	_refresh_primary_game_button()
	_close_load_overlay()


func _close_load_overlay() -> void:
	"""关闭存档选择界面并返回主菜单"""
	if load_overlay and is_instance_valid(load_overlay):
		load_overlay.queue_free()
	load_overlay = null


func _on_settings_pressed() -> void:
	"""游戏设置入口（待接入具体界面）"""
	Log.i(M, "游戏设置功能待实现")


func _on_quit_pressed() -> void:
	"""退出游戏"""
	GameManager.save_game()
	get_tree().quit()
