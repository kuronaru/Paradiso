# start_menu.gd — 游戏开始界面
# 显示标题与主菜单按钮，负责进入主战斗场景或退出游戏。
class_name StartMenu
extends Control

const M = "StartMenu"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"


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

	menu.add_child(_create_menu_button("开始游戏", _on_start_pressed))
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


func _on_start_pressed() -> void:
	"""进入主战斗场景"""
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _on_catalog_pressed() -> void:
	"""角色图鉴入口（待接入具体界面）"""
	Log.i(M, "角色图鉴功能待实现")


func _on_settings_pressed() -> void:
	"""游戏设置入口（待接入具体界面）"""
	Log.i(M, "游戏设置功能待实现")


func _on_quit_pressed() -> void:
	"""退出游戏"""
	get_tree().quit()
