# recruit_ui.gd - 酒馆招募界面
class_name RecruitUI
extends Control

const PANEL_MARGIN := 16.0
const PANEL_HEIGHT := 136.0
const CELL_SPACING := 8.0
const CELL_MARGIN := 7
const OPTION_SLOT_COUNT := 5
const LAYOUT_TWEEN_TIME := 0.22

signal recruit_purchased
signal recruit_skipped

var roguelike_manager: RoguelikeManager = null
var option_buttons: Array[Button] = []
var option_icons: Array[ColorRect] = []
var option_name_labels: Array[Label] = []
var option_synergy_labels: Array[Label] = []
var option_price_labels: Array[Label] = []
var skip_btn: Button
var freeze_btn: Button
var refresh_btn: Button
var upgrade_btn: Button
var gold_label: Label
var title_label: Label
var panel_container: PanelContainer
var content_margin: MarginContainer
var shop_row: HBoxContainer
var layout_tween: Tween = null
var last_prepare_layout: bool = true
var cached_viewport_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var tree := get_tree()
	if tree:
		var nodes := tree.get_nodes_in_group("roguelike_manager")
		if nodes.size() > 0:
			roguelike_manager = nodes[0]
			roguelike_manager.recruit_phase_started.connect(_show)
	if not GameManager.party_changed.is_connected(_on_party_changed):
		GameManager.party_changed.connect(_on_party_changed)
	if not GameManager.run_gold_changed.is_connected(_on_run_gold_changed):
		GameManager.run_gold_changed.connect(_on_run_gold_changed)
	if not GameManager.run_round_changed.is_connected(_on_run_round_changed):
		GameManager.run_round_changed.connect(_on_run_round_changed)

	_setup_ui()
	hide()


func _setup_ui() -> void:
	cached_viewport_size = get_viewport_rect().size
	size = Vector2(cached_viewport_size.x - PANEL_MARGIN * 2.0, PANEL_HEIGHT)
	position = Vector2(PANEL_MARGIN, _prepare_y())
	z_index = 90

	panel_container = PanelContainer.new()
	panel_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(panel_container)
	panel_container.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.045, 0.035, 0.055, 0.96),
		Color(0.18, 0.15, 0.22, 1.0)
	))
	add_child(panel_container)

	content_margin = MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 10)
	content_margin.add_theme_constant_override("margin_top", 10)
	content_margin.add_theme_constant_override("margin_right", 10)
	content_margin.add_theme_constant_override("margin_bottom", 10)
	panel_container.add_child(content_margin)

	shop_row = HBoxContainer.new()
	shop_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_row.add_theme_constant_override("separation", int(CELL_SPACING))
	content_margin.add_child(shop_row)

	_create_info_cell()
	_create_control_cell()
	for i in range(OPTION_SLOT_COUNT):
		_create_option_card(i)
	_create_refresh_cell()

	skip_btn = Button.new()
	skip_btn.visible = false
	skip_btn.pressed.connect(_on_skip)
	add_child(skip_btn)


func _create_info_cell() -> void:
	var cell := _create_cell_panel()
	shop_row.add_child(cell)

	var stack := _create_cell_stack(cell)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER

	title_label = Label.new()
	title_label.text = "酒馆等级 Lv.1"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(title_label)

	gold_label = Label.new()
	gold_label.text = "金币 0"
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.24))
	gold_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(gold_label)


func _create_control_cell() -> void:
	var cell := _create_cell_panel()
	shop_row.add_child(cell)

	var stack := _create_cell_stack(cell)
	stack.add_theme_constant_override("separation", 8)

	freeze_btn = _create_command_button("冻结酒馆")
	freeze_btn.pressed.connect(_on_freeze_pressed)
	stack.add_child(freeze_btn)

	upgrade_btn = _create_command_button("升级酒馆\n5 金币")
	upgrade_btn.pressed.connect(_on_upgrade_pressed)
	stack.add_child(upgrade_btn)


func _create_option_card(index: int) -> void:
	var button := Button.new()
	_setup_equal_cell(button)
	button.text = ""
	button.clip_contents = true
	button.pressed.connect(func(): _on_purchase(index))
	_apply_button_style(button, Color(0.10, 0.11, 0.15, 0.98), Color(0.30, 0.34, 0.44, 1.0))
	shop_row.add_child(button)
	option_buttons.append(button)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(margin)
	margin.add_theme_constant_override("margin_left", CELL_MARGIN)
	margin.add_theme_constant_override("margin_top", CELL_MARGIN)
	margin.add_theme_constant_override("margin_right", CELL_MARGIN)
	margin.add_theme_constant_override("margin_bottom", CELL_MARGIN)
	button.add_child(margin)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(0, 36)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	option_icons.append(icon)

	var name_label := _create_card_label(13)
	name_label.custom_minimum_size = Vector2(0, 18)
	stack.add_child(name_label)
	option_name_labels.append(name_label)

	var synergy_label := _create_card_label(11)
	synergy_label.custom_minimum_size = Vector2(0, 18)
	stack.add_child(synergy_label)
	option_synergy_labels.append(synergy_label)

	var price_label := _create_card_label(11)
	price_label.custom_minimum_size = Vector2(0, 18)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.32))
	stack.add_child(price_label)
	option_price_labels.append(price_label)


func _create_refresh_cell() -> void:
	refresh_btn = Button.new()
	_setup_equal_cell(refresh_btn)
	refresh_btn.text = "刷新商店\n1 金币"
	refresh_btn.add_theme_font_size_override("font_size", 15)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	_apply_button_style(refresh_btn, Color(0.13, 0.10, 0.16, 0.98), Color(0.40, 0.33, 0.50, 1.0))
	shop_row.add_child(refresh_btn)


func _create_cell_panel() -> PanelContainer:
	var cell := PanelContainer.new()
	_setup_equal_cell(cell)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.085, 0.08, 0.105, 0.96),
		Color(0.23, 0.22, 0.28, 1.0)
	))
	return cell


func _create_cell_stack(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(margin)
	margin.add_theme_constant_override("margin_left", CELL_MARGIN)
	margin.add_theme_constant_override("margin_top", CELL_MARGIN)
	margin.add_theme_constant_override("margin_right", CELL_MARGIN)
	margin.add_theme_constant_override("margin_bottom", CELL_MARGIN)
	parent.add_child(margin)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	return stack


func _create_command_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	_apply_button_style(button, Color(0.12, 0.115, 0.145, 0.98), Color(0.33, 0.31, 0.40, 1.0))
	return button


func _create_card_label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86, 1.0))
	return label


func _show() -> void:
	_refresh()
	show()
	last_prepare_layout = _is_prepare_layout()
	_apply_stage_layout(false)


func _refresh() -> void:
	if not roguelike_manager:
		return

	var recruit_system := roguelike_manager.recruit_system
	var options := recruit_system.get_current_options()
	var active_gold := GameManager.get_active_gold()
	title_label.text = "酒馆等级 Lv.%d" % recruit_system.tavern_level
	gold_label.text = "金币 %d" % active_gold

	freeze_btn.text = "解冻酒馆" if recruit_system.is_frozen else "冻结酒馆"
	freeze_btn.disabled = not _is_prepare_layout()
	freeze_btn.tooltip_text = "保留当前商店到下一次招募阶段"

	refresh_btn.text = "刷新商店\n%d 金币" % recruit_system.get_refresh_cost()
	refresh_btn.disabled = active_gold < recruit_system.get_refresh_cost() or not _is_prepare_layout()

	if recruit_system.is_max_level():
		upgrade_btn.text = "酒馆已满级"
		upgrade_btn.disabled = true
	else:
		var upgrade_cost := recruit_system.get_upgrade_cost()
		upgrade_btn.text = "升级酒馆\n%d 金币" % upgrade_cost
		upgrade_btn.disabled = active_gold < upgrade_cost or not _is_prepare_layout()

	for i in range(option_buttons.size()):
		if i < options.size():
			_refresh_option_card(i, options[i], active_gold)
		else:
			_refresh_empty_option_card(i)


func _refresh_option_card(index: int, option, active_gold: int) -> void:
	var ct := ClassDefinitions.get_template(option.class_id)
	option_icons[index].color = ClassDefinitions.get_template_color(ct.class_id)
	option_name_labels[index].text = ct.job_name
	option_synergy_labels[index].text = _get_synergy_line(ct)
	option_price_labels[index].text = "%d 金币  酒馆Lv.%d" % [option.cost, option.shop_level]
	option_buttons[index].tooltip_text = option.tavern_passive
	option_buttons[index].disabled = (
		active_gold < option.cost
		or not GameManager.can_add_to_party()
		or not _is_prepare_layout()
	)
	option_buttons[index].visible = true
	option_buttons[index].modulate = Color.WHITE


func _refresh_empty_option_card(index: int) -> void:
	option_icons[index].color = Color(0.08, 0.08, 0.09, 0.85)
	option_name_labels[index].text = "空"
	option_synergy_labels[index].text = ""
	option_price_labels[index].text = ""
	option_buttons[index].tooltip_text = ""
	option_buttons[index].disabled = true
	option_buttons[index].visible = true
	option_buttons[index].modulate = Color(0.82, 0.82, 0.82, 1.0)


func _get_synergy_line(ct: ClassTemplate) -> String:
	var tags: Array[String] = []
	if ct.class_group != "":
		tags.append(_main_group_label(ct.class_group))
	for tag in ct.stat_tags:
		tags.append(_stat_label(str(tag)))
	for tag in ct.alignment_tags:
		tags.append(_alignment_label(str(tag)))
	return " / ".join(tags)


func _main_group_label(class_group: String) -> String:
	match class_group:
		"anmarit":
			return "安马里特"
		"laferida":
			return "拉费里达"
		"naka":
			return "纳卡"
	return ClassDefinitions.get_class_group_label(class_group)


func _stat_label(tag: String) -> String:
	match tag:
		"STR":
			return "力"
		"DEX":
			return "敏"
		"CON":
			return "体"
		"INT":
			return "智"
		"WIS":
			return "感"
		"CHA":
			return "魅"
	return tag.left(1)


func _alignment_label(tag: String) -> String:
	match tag:
		"LAWFUL":
			return "守"
		"CHAOTIC":
			return "混"
		"GOOD":
			return "善"
		"EVIL":
			return "邪"
		"NEUTRAL":
			return "中"
	return tag.left(1)


func _on_purchase(index: int) -> void:
	if roguelike_manager:
		if roguelike_manager.purchase_recruit(index):
			_refresh()
			recruit_purchased.emit()


func _on_freeze_pressed() -> void:
	if roguelike_manager:
		roguelike_manager.recruit_system.toggle_frozen()
		_refresh()


func _on_refresh_pressed() -> void:
	if roguelike_manager and roguelike_manager.refresh_recruit_options():
		_refresh()


func _on_upgrade_pressed() -> void:
	if roguelike_manager and roguelike_manager.upgrade_tavern():
		_refresh()


func _on_skip() -> void:
	if roguelike_manager:
		roguelike_manager.skip_recruit()
	recruit_skipped.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size != cached_viewport_size:
		_rebuild_for_viewport(viewport_size)
	var wants_prepare := _is_prepare_layout()
	if wants_prepare != last_prepare_layout:
		last_prepare_layout = wants_prepare
		_apply_stage_layout(true)


func _is_prepare_layout() -> bool:
	return GameManager.is_roguelike_run and BattleManager.state == BattleManager.BattleState.PREPARING


func _apply_stage_layout(animated: bool) -> void:
	var target_y := _prepare_y() if _is_prepare_layout() else _hidden_y()
	if layout_tween and layout_tween.is_valid():
		layout_tween.kill()
	if animated and is_inside_tree():
		layout_tween = create_tween()
		layout_tween.tween_property(self, "position:y", target_y, LAYOUT_TWEEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		position.y = target_y


func _prepare_y() -> float:
	return get_viewport_rect().size.y - PANEL_HEIGHT - 8.0


func _hidden_y() -> float:
	return get_viewport_rect().size.y + 12.0


func _rebuild_for_viewport(viewport_size: Vector2) -> void:
	cached_viewport_size = viewport_size
	size = Vector2(viewport_size.x - PANEL_MARGIN * 2.0, PANEL_HEIGHT)
	position.x = PANEL_MARGIN
	_apply_stage_layout(false)
	_refresh()


func _on_party_changed(_party: Array) -> void:
	_refresh()


func _on_run_gold_changed(_gold: int) -> void:
	_refresh()


func _on_run_round_changed(_round: int, _max_rounds: int) -> void:
	_refresh()


func _setup_equal_cell(control: Control) -> void:
	control.custom_minimum_size = Vector2(0, 0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _apply_button_style(button: Button, bg_color: Color, border_color: Color) -> void:
	button.add_theme_stylebox_override("normal", _make_panel_style(bg_color, border_color))
	button.add_theme_stylebox_override("hover", _make_panel_style(bg_color.lightened(0.08), border_color.lightened(0.10)))
	button.add_theme_stylebox_override("pressed", _make_panel_style(bg_color.darkened(0.08), border_color))
	button.add_theme_stylebox_override("disabled", _make_panel_style(bg_color.darkened(0.18), border_color.darkened(0.16)))


func _make_panel_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
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
