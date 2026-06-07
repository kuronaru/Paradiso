# recruit_ui.gd — 酒馆招募界面
class_name RecruitUI
extends Control

const M = "RecruitUI"
const PANEL_MARGIN := 16.0
const PANEL_HEIGHT := 112.0
const PANEL_GAP := 14.0
const LEFT_PANEL_WIDTH := 150.0
const RIGHT_PANEL_WIDTH := 126.0
const CARD_SPACING := 14.0
const LAYOUT_TWEEN_TIME := 0.22

signal recruit_purchased
signal recruit_skipped

var roguelike_manager: RoguelikeManager = null
var option_buttons: Array[Button] = []
var skip_btn: Button
var refresh_btn: Button
var upgrade_btn: Button
var gold_label: Label
var status_label: Label
var title_label: Label
var panel_container: PanelContainer
var content_margin: MarginContainer
var shop_row: HBoxContainer
var options_row: HBoxContainer
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
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.035, 0.055, 0.96)
	panel_style.border_color = Color(0.18, 0.15, 0.22, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_container.add_theme_stylebox_override("panel", panel_style)
	add_child(panel_container)

	content_margin = MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 12)
	content_margin.add_theme_constant_override("margin_top", 10)
	content_margin.add_theme_constant_override("margin_right", 12)
	content_margin.add_theme_constant_override("margin_bottom", 10)
	panel_container.add_child(content_margin)

	shop_row = HBoxContainer.new()
	shop_row.add_theme_constant_override("separation", int(PANEL_GAP))
	content_margin.add_child(shop_row)

	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(LEFT_PANEL_WIDTH, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_theme_constant_override("separation", 4)
	shop_row.add_child(left_panel)

	title_label = Label.new()
	title_label.text = "酒馆 Lv.1"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_panel.add_child(title_label)

	gold_label = Label.new()
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 12)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	left_panel.add_child(gold_label)

	status_label = Label.new()
	status_label.visible = false
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.9))
	left_panel.add_child(status_label)

	upgrade_btn = Button.new()
	upgrade_btn.text = "升级 5 金币"
	upgrade_btn.custom_minimum_size = Vector2(0, 34)
	upgrade_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	upgrade_btn.add_theme_font_size_override("font_size", 12)
	upgrade_btn.pressed.connect(_on_upgrade_pressed)
	left_panel.add_child(upgrade_btn)

	options_row = HBoxContainer.new()
	options_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_row.add_theme_constant_override("separation", int(CARD_SPACING))
	shop_row.add_child(options_row)
	for i in range(5):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 76)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.clip_contents = true
		btn.add_theme_font_size_override("font_size", 11)
		var idx := i
		btn.pressed.connect(func(): _on_purchase(idx))
		options_row.add_child(btn)
		option_buttons.append(btn)

	var right_panel := VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(RIGHT_PANEL_WIDTH, 0)
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_row.add_child(right_panel)

	refresh_btn = Button.new()
	refresh_btn.text = "刷新商店\n1 金币"
	refresh_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	refresh_btn.add_theme_font_size_override("font_size", 13)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	right_panel.add_child(refresh_btn)

	skip_btn = Button.new()
	skip_btn.visible = false
	skip_btn.pressed.connect(_on_skip)
	add_child(skip_btn)


func _show() -> void:
	_refresh()
	show()
	last_prepare_layout = _is_prepare_layout()
	_apply_stage_layout(false)


func _refresh() -> void:
	if not roguelike_manager:
		return

	var options := roguelike_manager.recruit_system.get_current_options()
	var recruit_system := roguelike_manager.recruit_system
	var active_gold := GameManager.get_active_gold()
	var deployed_count := _get_deployed_count()
	title_label.text = "酒馆 Lv.%d" % recruit_system.tavern_level
	gold_label.text = "金币 %d" % active_gold
	status_label.text = "第 %d/%d 回合 | 手牌 %d/%d | 部署 %d/%d" % [
		GameManager.current_run_round,
		GameManager.max_run_rounds,
		GameManager.party.size(),
		GameManager.ROGUELIKE_MAX_HAND_CARDS,
		deployed_count,
		GameManager.ROGUELIKE_MAX_DEPLOYED_UNITS
	]

	refresh_btn.text = "刷新商店\n%d 金币" % recruit_system.get_refresh_cost()
	refresh_btn.disabled = active_gold < recruit_system.get_refresh_cost() or not _is_prepare_layout()

	if recruit_system.is_max_level():
		upgrade_btn.text = "酒馆已满级"
		upgrade_btn.disabled = true
	else:
		var upgrade_cost := recruit_system.get_upgrade_cost()
		upgrade_btn.text = "升级 %d 金币" % upgrade_cost
		upgrade_btn.disabled = active_gold < upgrade_cost or not _is_prepare_layout()

	for i in range(option_buttons.size()):
		if i < options.size():
			var opt = options[i]
			var ct := ClassDefinitions.get_template(opt.class_id)
			option_buttons[i].text = "%s\n%d星 商店Lv.%d\n%s\n%d 金币" % [
				ct.job_name,
				opt.level,
				opt.shop_level,
				_get_synergy_line(ct),
				opt.cost
			]
			option_buttons[i].tooltip_text = opt.tavern_passive
			option_buttons[i].disabled = active_gold < opt.cost or not GameManager.can_add_to_party() or not _is_prepare_layout()
			option_buttons[i].visible = true
		else:
			option_buttons[i].text = "空"
			option_buttons[i].tooltip_text = ""
			option_buttons[i].disabled = true
			option_buttons[i].visible = true


func _get_synergy_line(ct: ClassTemplate) -> String:
	var tags: Array[String] = []
	if ct.class_group != "":
		tags.append(_main_group_label(ct.class_group))
	for tag in ct.stat_tags:
		tags.append(str(tag))
	for tag in ct.alignment_tags:
		tags.append(_alignment_label(str(tag)))
	return "羁绊: %s" % " / ".join(tags)


func _main_group_label(class_group: String) -> String:
	match class_group:
		"fighter":
			return "战士"
		"ranger":
			return "游侠"
		"wizard":
			return "法师"
		"cleric":
			return "牧师"
		"rogue":
			return "游荡者"
	return class_group


func _alignment_label(tag: String) -> String:
	match tag:
		"LAWFUL":
			return "守序"
		"CHAOTIC":
			return "混沌"
		"GOOD":
			return "善良"
		"EVIL":
			return "邪恶"
		"NEUTRAL":
			return "中立"
	return tag


func _on_purchase(index: int) -> void:
	if roguelike_manager:
		if roguelike_manager.purchase_recruit(index):
			_refresh()
			recruit_purchased.emit()


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


func _get_deployed_count() -> int:
	var tree := get_tree()
	if not tree:
		return 0
	var nodes := tree.get_nodes_in_group("deployment_system")
	if nodes.size() > 0 and nodes[0] is DeploymentSystem:
		return (nodes[0] as DeploymentSystem).get_deployed_count()
	return 0


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


func _fill_parent(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
