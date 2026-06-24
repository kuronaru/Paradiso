# settings_ui.gd — 游戏设置界面
# 在主菜单和暂停菜单中复用，直接读写全局设置配置。
class_name SettingsUI
extends Control

const M = "SettingsUI"

var return_callback: Callable = Callable()


## 创建游戏设置界面
func _ready() -> void:
	"""创建游戏设置界面"""
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_full_rect()
	_build_ui()


## 设置返回按钮回调
func set_return_callback(callback: Callable) -> void:
	"""设置返回按钮回调"""
	return_callback = callback


## 让设置界面铺满窗口
func _set_full_rect() -> void:
	"""让设置界面铺满窗口"""
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP


## 创建设置面板和设置项
func _build_ui() -> void:
	"""创建设置面板和设置项"""
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.82)
	dim.anchor_left = 0.0
	dim.anchor_top = 0.0
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 500)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 12)
	root.add_child(title_bar)

	var title := Label.new()
	title.text = "游戏设置"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title_bar.add_child(title)

	var back_button := Button.new()
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(108, 40)
	back_button.add_theme_font_size_override("font_size", 17)
	back_button.process_mode = Node.PROCESS_MODE_ALWAYS
	back_button.pressed.connect(_on_return_pressed)
	title_bar.add_child(back_button)

	var list := VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	root.add_child(list)

	list.add_child(_create_slider_row("主音量", SettingsManager.master_volume, SettingsManager.set_master_volume))
	list.add_child(_create_slider_row("音乐音量", SettingsManager.music_volume, SettingsManager.set_music_volume))
	list.add_child(_create_slider_row("音效音量", SettingsManager.sfx_volume, SettingsManager.set_sfx_volume))
	list.add_child(_create_check_row("静音", SettingsManager.muted, SettingsManager.set_muted))
	list.add_child(_create_check_row("全屏显示", SettingsManager.fullscreen, SettingsManager.set_fullscreen))
	list.add_child(_create_check_row("垂直同步", SettingsManager.vsync_enabled, SettingsManager.set_vsync_enabled))
	list.add_child(_create_check_row("显示伤害数字", SettingsManager.show_floating_numbers, SettingsManager.set_show_floating_numbers))


## 创建百分比滑动设置项
func _create_slider_row(text: String, value: float, setter: Callable) -> Control:
	"""创建百分比滑动设置项"""
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(1, 42)
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(110, 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = round(clampf(value, 0.0, 1.0) * 100.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.process_mode = Node.PROCESS_MODE_ALWAYS
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = "%d%%" % int(slider.value)
	value_label.custom_minimum_size = Vector2(56, 1)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 16)
	row.add_child(value_label)

	slider.value_changed.connect(func(next_value: float) -> void:
		value_label.text = "%d%%" % int(next_value)
		setter.call(next_value / 100.0)
	)
	return row


## 创建开关设置项
func _create_check_row(text: String, value: bool, setter: Callable) -> Control:
	"""创建开关设置项"""
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(1, 40)
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)

	var checkbox := CheckBox.new()
	checkbox.button_pressed = value
	checkbox.process_mode = Node.PROCESS_MODE_ALWAYS
	checkbox.toggled.connect(func(pressed: bool) -> void:
		setter.call(pressed)
	)
	row.add_child(checkbox)
	return row


## 返回打开设置前的界面
func _on_return_pressed() -> void:
	"""返回打开设置前的界面"""
	SettingsManager.save_settings()
	if return_callback.is_valid():
		return_callback.call()
	else:
		queue_free()
