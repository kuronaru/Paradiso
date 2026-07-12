# roguelike_relic_select_ui.gd — 肉鸽开局信物选择界面
class_name RoguelikeRelicSelectUI
extends Control

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const AFK_HUB_SCENE_PATH := "res://scenes/afk_hub.tscn"

var relics: Array = []
var selected_index: int = -1
var relic_buttons: Array[Button] = []
var list_box: VBoxContainer = null
var name_label: Label = null
var summary_label: Label = null
var description_label: Label = null
var effect_label: Label = null
var confirm_button: Button = null


func _ready() -> void:
	_set_full_rect()
	_build_ui()
	_load_relics()


func _set_full_rect() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.047, 0.055, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_bottom", 48)
	_fill_parent(margin)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var title := Label.new()
	title.text = "选择开局信物"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "信物会作为本局酒馆被动生效。当前为占位策略，后续可扩展为更复杂的流派。"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.72, 0.73, 0.76, 1.0))
	root.add_child(subtitle)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(410, 420)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.065, 0.066, 0.078, 0.98), Color(0.20, 0.21, 0.25, 1.0)))
	body.add_child(list_panel)

	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left", 10)
	list_margin.add_theme_constant_override("margin_top", 10)
	list_margin.add_theme_constant_override("margin_right", 10)
	list_margin.add_theme_constant_override("margin_bottom", 10)
	list_panel.add_child(list_margin)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	list_margin.add_child(list_box)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.075, 0.075, 0.092, 0.98), Color(0.28, 0.25, 0.18, 1.0)))
	body.add_child(detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 24)
	detail_margin.add_theme_constant_override("margin_top", 24)
	detail_margin.add_theme_constant_override("margin_right", 24)
	detail_margin.add_theme_constant_override("margin_bottom", 24)
	detail_panel.add_child(detail_margin)

	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 16)
	detail_margin.add_child(detail)

	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.38, 1.0))
	detail.add_child(name_label)

	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_font_size_override("font_size", 18)
	summary_label.add_theme_color_override("font_color", Color(0.92, 0.91, 0.86, 1.0))
	detail.add_child(summary_label)

	description_label = Label.new()
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_font_size_override("font_size", 15)
	description_label.add_theme_color_override("font_color", Color(0.78, 0.79, 0.82, 1.0))
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(description_label)

	effect_label = Label.new()
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 15)
	effect_label.add_theme_color_override("font_color", Color(0.68, 0.86, 1.0, 1.0))
	detail.add_child(effect_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)

	var back_button := Button.new()
	back_button.text = "返回大厅"
	back_button.custom_minimum_size = Vector2(140, 44)
	back_button.pressed.connect(_on_back_pressed)
	actions.add_child(back_button)

	confirm_button = Button.new()
	confirm_button.text = "携带信物出发"
	confirm_button.custom_minimum_size = Vector2(180, 44)
	confirm_button.disabled = true
	confirm_button.pressed.connect(_on_confirm_pressed)
	actions.add_child(confirm_button)


func _load_relics() -> void:
	relics = GameManager.get_roguelike_relic_definitions()
	for child in list_box.get_children():
		child.queue_free()
	relic_buttons.clear()
	for relic in relics:
		var data: Dictionary = relic
		var index := relic_buttons.size()
		var button := Button.new()
		button.text = "%s\n%s" % [str(data.get("name", "")), str(data.get("summary", ""))]
		button.custom_minimum_size = Vector2(0, 68)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func(): _on_relic_selected(index))
		list_box.add_child(button)
		relic_buttons.append(button)

	if relics.is_empty():
		_show_empty_state()
		return

	var pending := GameManager.get_pending_roguelike_relic()
	var pending_id := str(pending.get("id", ""))
	selected_index = 0
	for i in range(relics.size()):
		var data: Dictionary = relics[i]
		if str(data.get("id", "")) == pending_id:
			selected_index = i
			break
	_show_relic(selected_index)


func _show_empty_state() -> void:
	selected_index = -1
	confirm_button.disabled = true
	name_label.text = "暂无可选信物"
	summary_label.text = ""
	description_label.text = "请先在 GameManager 中配置肉鸽信物定义。"
	effect_label.text = ""


func _show_relic(index: int) -> void:
	if index < 0 or index >= relics.size():
		_show_empty_state()
		return

	selected_index = index
	var relic: Dictionary = relics[index]
	name_label.text = str(relic.get("name", "未命名信物"))
	summary_label.text = str(relic.get("summary", ""))
	description_label.text = str(relic.get("description", ""))
	effect_label.text = _format_effects(relic.get("modifiers", {}))
	confirm_button.disabled = false
	_update_relic_button_states()


func _update_relic_button_states() -> void:
	for i in range(relic_buttons.size()):
		var button := relic_buttons[i]
		if i == selected_index:
			button.modulate = Color(1.18, 1.10, 0.72, 1.0)
		else:
			button.modulate = Color.WHITE


func _format_effects(modifiers: Dictionary) -> String:
	var lines: Array[String] = []
	if int(modifiers.get("starting_gold_bonus", 0)) != 0:
		lines.append("开局金币 %+d" % int(modifiers["starting_gold_bonus"]))
	if int(modifiers.get("victory_gold_bonus", 0)) != 0:
		lines.append("胜利金币 %+d" % int(modifiers["victory_gold_bonus"]))
	if int(modifiers.get("refresh_cost_delta", 0)) != 0:
		lines.append("刷新费用 %+d" % int(modifiers["refresh_cost_delta"]))
	if int(modifiers.get("hand_limit_bonus", 0)) != 0:
		lines.append("手牌上限 %+d" % int(modifiers["hand_limit_bonus"]))
	if int(modifiers.get("starting_tavern_level_bonus", 0)) != 0:
		lines.append("初始酒馆等级 %+d" % int(modifiers["starting_tavern_level_bonus"]))
	return "效果：" + ("；".join(lines) if not lines.is_empty() else "无数值效果")


func _on_relic_selected(index: int) -> void:
	_show_relic(index)


func _on_confirm_pressed() -> void:
	if selected_index < 0 or selected_index >= relics.size():
		return
	var relic: Dictionary = relics[selected_index]
	if GameManager.set_pending_roguelike_relic(str(relic.get("id", ""))):
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(AFK_HUB_SCENE_PATH)


func _make_panel_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _fill_parent(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
