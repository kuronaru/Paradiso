# afk_hub_ui.gd — AFK模式局外大厅
# 进入存档后的默认界面，承载放置爬塔展示和其他功能模块入口。
class_name AfkHubUI
extends Control

const M = "AfkHub"
const START_MENU_SCENE_PATH := "res://scenes/start_menu.tscn"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const MAX_DISPLAY_PARTY := 5
const MOCK_TOWER_FLOOR := 1

var storage_overlay: CharacterStorageUI = null
var encyclopedia_overlay: EncyclopediaUI = null
var settings_overlay: SettingsUI = null
var equipment_overlay: Control = null

var save_label: Label = null
var gold_label: Label = null
var party_box: HBoxContainer = null
var power_label: Label = null
var synergy_label: Label = null
var tower_label: Label = null
var reward_label: Label = null
var status_label: Label = null

var panel_style: StyleBoxFlat = null
var stage_style: StyleBoxFlat = null
var rail_style: StyleBoxFlat = null


## 创建AFK大厅界面。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_active_save()
	_build_styles()
	_set_full_rect()
	_build_background()
	_build_layout()
	_connect_game_manager_signals()
	_refresh_all()


## 确保从场景直接启动时也有可用存档。
func _ensure_active_save() -> void:
	if GameManager.has_active_save:
		return
	if GameManager.has_any_save_slot():
		GameManager.load_save(GameManager.get_continue_save_id())
	else:
		GameManager.create_new_save(GameManager.current_save_id)


## 让大厅铺满窗口。
func _set_full_rect() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP


## 创建全局样式。
func _build_styles() -> void:
	panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.105, 0.125, 0.96)
	panel_style.border_color = Color(0.22, 0.25, 0.29, 1.0)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_left = 12
	panel_style.content_margin_top = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_bottom = 12

	stage_style = panel_style.duplicate()
	stage_style.bg_color = Color(0.055, 0.065, 0.08, 0.98)
	stage_style.border_color = Color(0.36, 0.32, 0.22, 1.0)

	rail_style = panel_style.duplicate()
	rail_style.bg_color = Color(0.075, 0.085, 0.105, 0.98)


## 创建背景。
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.042, 0.052, 1.0)
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


## 创建主布局。
func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.anchor_left = 0.0
	margin.anchor_top = 0.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	root.add_child(_build_top_bar())

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	body.add_child(_build_center_stage())
	body.add_child(_build_right_panel())

	root.add_child(_build_bottom_bar())


## 创建顶部资源栏。
func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1, 58)
	panel.add_theme_stylebox_override("panel", rail_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var title := Label.new()
	title.text = "九重天堂"
	title.custom_minimum_size = Vector2(220, 1)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.76, 1.0))
	row.add_child(title)

	save_label = Label.new()
	save_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	save_label.add_theme_font_size_override("font_size", 16)
	row.add_child(save_label)

	gold_label = Label.new()
	gold_label.custom_minimum_size = Vector2(150, 1)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_font_size_override("font_size", 17)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.28, 1.0))
	row.add_child(gold_label)

	row.add_child(_create_small_button("游戏设置", _open_settings_overlay))
	row.add_child(_create_small_button("主菜单", _return_to_start_menu))
	return panel


## 创建中心战斗舞台占位。
func _build_center_stage() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", stage_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	root.add_child(title_row)

	var title := Label.new()
	title.text = "静默之塔"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.94, 0.88, 0.68, 1.0))
	title_row.add_child(title)

	status_label = Label.new()
	status_label.text = "战斗模拟待机"
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.74, 0.82, 0.9, 1.0))
	title_row.add_child(status_label)

	var stage_area := PanelContainer.new()
	stage_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_area.add_theme_stylebox_override("panel", _make_flat_style(Color(0.045, 0.054, 0.067, 1.0), Color(0.18, 0.2, 0.24, 1.0)))
	root.add_child(stage_area)

	var stage_margin := MarginContainer.new()
	stage_margin.add_theme_constant_override("margin_left", 12)
	stage_margin.add_theme_constant_override("margin_top", 12)
	stage_margin.add_theme_constant_override("margin_right", 12)
	stage_margin.add_theme_constant_override("margin_bottom", 12)
	stage_area.add_child(stage_margin)

	var lane := HBoxContainer.new()
	lane.add_theme_constant_override("separation", 12)
	stage_margin.add_child(lane)

	var party_panel := _create_stage_side_panel("冒险小队")
	party_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lane.add_child(party_panel)

	party_box = HBoxContainer.new()
	party_box.add_theme_constant_override("separation", 10)
	var party_content := party_panel.find_child("Content", true, false) as VBoxContainer
	party_content.add_child(party_box)

	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(96, 1)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 10)
	lane.add_child(middle)

	var mid_spacer_a := Control.new()
	mid_spacer_a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(mid_spacer_a)

	var sigil := Label.new()
	sigil.text = "VS"
	sigil.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sigil.add_theme_font_size_override("font_size", 34)
	sigil.add_theme_color_override("font_color", Color(0.9, 0.72, 0.38, 1.0))
	middle.add_child(sigil)

	var tower_hint := Label.new()
	tower_hint.text = "战斗动画\n待接入"
	tower_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tower_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tower_hint.add_theme_font_size_override("font_size", 14)
	tower_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78, 1.0))
	middle.add_child(tower_hint)

	var mid_spacer_b := Control.new()
	mid_spacer_b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(mid_spacer_b)

	var tower_panel := _create_stage_side_panel("塔层敌影")
	tower_panel.custom_minimum_size = Vector2(190, 1)
	lane.add_child(tower_panel)
	var tower_content := tower_panel.find_child("Content", true, false) as VBoxContainer
	_populate_enemy_placeholders(tower_content)

	return panel


## 创建右侧塔层信息面板。
func _build_right_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(252, 1)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", rail_style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "远征状态"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	tower_label = Label.new()
	tower_label.add_theme_font_size_override("font_size", 18)
	box.add_child(tower_label)

	power_label = Label.new()
	power_label.add_theme_font_size_override("font_size", 18)
	power_label.add_theme_color_override("font_color", Color(0.6, 0.86, 1.0, 1.0))
	box.add_child(power_label)

	synergy_label = Label.new()
	synergy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	synergy_label.add_theme_font_size_override("font_size", 15)
	box.add_child(synergy_label)

	var separator := HSeparator.new()
	box.add_child(separator)

	reward_label = Label.new()
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_label.add_theme_font_size_override("font_size", 15)
	box.add_child(reward_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	box.add_child(_create_nav_button("领取挂机收益", _claim_idle_rewards))
	box.add_child(_create_nav_button("挑战本层", _preview_tower_challenge))
	return panel


## 创建底部状态栏。
func _build_bottom_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1, 70)
	panel.add_theme_stylebox_override("panel", rail_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var note := Label.new()
	note.text = "中心舞台用于后续播放小队爬塔战斗表现。"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8, 1.0))
	row.add_child(note)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)

	actions.add_child(_create_action_button("英雄养成", _open_storage_overlay))
	actions.add_child(_create_action_button("装备背包", _open_equipment_overlay))
	actions.add_child(_create_action_button("角色图鉴", _open_encyclopedia_overlay))
	actions.add_child(_create_action_button("肉鸽模式", _enter_roguelike_mode))
	return panel


## 创建舞台两侧分区。
func _create_stage_side_panel(title_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_flat_style(Color(0.07, 0.08, 0.1, 0.96), Color(0.17, 0.19, 0.23, 1.0)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	box.add_child(title)
	return panel


## 填充敌影占位。
func _populate_enemy_placeholders(container: VBoxContainer) -> void:
	for i in range(3):
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(1, 54)
		row.add_theme_constant_override("separation", 10)
		container.add_child(row)

		var marker := ColorRect.new()
		marker.custom_minimum_size = Vector2(42, 42)
		marker.color = Color(0.45 + i * 0.08, 0.18, 0.16, 1.0)
		row.add_child(marker)

		var text := Label.new()
		text.text = "第%d波 敌影" % (i + 1)
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.add_theme_font_size_override("font_size", 15)
		row.add_child(text)


## 连接全局状态变化。
func _connect_game_manager_signals() -> void:
	if not GameManager.gold_changed.is_connected(_on_gold_changed):
		GameManager.gold_changed.connect(_on_gold_changed)
	if not GameManager.owned_characters_changed.is_connected(_on_owned_characters_changed):
		GameManager.owned_characters_changed.connect(_on_owned_characters_changed)
	if not GameManager.save_slot_changed.is_connected(_on_save_slot_changed):
		GameManager.save_slot_changed.connect(_on_save_slot_changed)


## 刷新整个大厅显示。
func _refresh_all() -> void:
	_refresh_top_bar()
	_refresh_party_cards()
	_refresh_status_panel()


## 刷新资源和存档信息。
func _refresh_top_bar() -> void:
	if save_label:
		save_label.text = "当前存档: %s" % GameManager.current_save_id
	if gold_label:
		gold_label.text = "金币: %d" % GameManager.gold


## 刷新中心小队卡。
func _refresh_party_cards() -> void:
	if not party_box:
		return
	for child in party_box.get_children():
		child.queue_free()

	var party := _get_display_party()
	for i in range(MAX_DISPLAY_PARTY):
		if i < party.size():
			var card: Dictionary = party[i]
			party_box.add_child(_create_hero_card(card))
		else:
			party_box.add_child(_create_empty_hero_slot())


## 刷新右侧战力和奖励信息。
func _refresh_status_panel() -> void:
	var team_power := _calculate_team_power()
	var required_power := _get_required_power(MOCK_TOWER_FLOOR)
	var reward_gold := _get_preview_reward_gold(MOCK_TOWER_FLOOR)

	if tower_label:
		tower_label.text = "静默之塔 第%d层\n推荐战力: %d" % [MOCK_TOWER_FLOOR, required_power]
	if power_label:
		power_label.text = "小队战力: %d" % team_power
	if synergy_label:
		synergy_label.text = "羁绊概览:\n%s" % _format_synergy_summary()
	if reward_label:
		reward_label.text = "预计挂机收益:\n金币 +%d / 小时\n装备掉落: 低概率\n重铸材料: 未开放" % reward_gold
	if status_label:
		status_label.text = "可挑战" if team_power >= required_power else "战力不足"


## 获取当前展示的小队。
func _get_display_party() -> Array:
	var result: Array = []
	for card in GameManager.owned_characters:
		if result.size() >= MAX_DISPLAY_PARTY:
			break
		if card is Dictionary:
			result.append(card.duplicate(true))
	if not result.is_empty():
		return result

	for class_id in ClassDefinitions.get_all_class_ids():
		if result.size() >= MAX_DISPLAY_PARTY:
			break
		result.append({
			"class_id": class_id,
			"level": 1
		})
	return result


## 创建英雄卡牌占位。
func _create_hero_card(card_data: Dictionary) -> Control:
	var class_id := ClassDefinitions.canonicalize_class_id(str(card_data.get("class_id", ClassDefinitions.FALLBACK_CLASS_ID)))
	var level := int(card_data.get("level", 1))
	var ct := ClassDefinitions.get_template(class_id)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(92, 148)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_flat_style(Color(0.105, 0.12, 0.145, 1.0), ClassDefinitions.get_template_color(class_id)))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(1, 58)
	portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait.color = ClassDefinitions.get_template_color(class_id)
	box.add_child(portrait)

	var name := Label.new()
	name.text = ct.job_name
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_font_size_override("font_size", 14)
	box.add_child(name)

	var meta := Label.new()
	meta.text = "Lv.%d\n%s" % [level, ClassDefinitions.get_class_group_label(ct.class_group)]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", Color(0.76, 0.8, 0.86, 1.0))
	box.add_child(meta)
	return panel


## 创建空英雄槽位。
func _create_empty_hero_slot() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(92, 148)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_flat_style(Color(0.07, 0.078, 0.095, 1.0), Color(0.16, 0.18, 0.22, 1.0)))

	var label := Label.new()
	label.text = "空位"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.62, 1.0))
	panel.add_child(label)
	return panel


## 计算展示小队总战力。
func _calculate_team_power() -> int:
	var total := 0
	for card in _get_display_party():
		var class_id := ClassDefinitions.canonicalize_class_id(str(card.get("class_id", ClassDefinitions.FALLBACK_CLASS_ID)))
		var level := int(card.get("level", 1))
		total += _calculate_character_power(ClassDefinitions.get_template(class_id), level)
	return total


## 计算单名英雄的AFK展示战力。
func _calculate_character_power(ct: ClassTemplate, level: int) -> int:
	var level_scale := 1.0 + float(maxi(1, level) - 1) * 0.05
	var base_power := float(ct.base_hp) * 0.08 + float(ct.base_atk) * 5.0 + float(ct.base_def) * 2.0 + ct.attack_speed * 20.0
	return int(round(base_power * level_scale))


## 格式化羁绊概览。
func _format_synergy_summary() -> String:
	var group_counts: Dictionary = {}
	for card in _get_display_party():
		var class_id := ClassDefinitions.canonicalize_class_id(str(card.get("class_id", ClassDefinitions.FALLBACK_CLASS_ID)))
		var ct := ClassDefinitions.get_template(class_id)
		group_counts[ct.class_group] = int(group_counts.get(ct.class_group, 0)) + 1

	var parts: Array[String] = []
	for group in group_counts.keys():
		parts.append("%s x%d" % [ClassDefinitions.get_class_group_label(str(group)), int(group_counts[group])])
	return "无" if parts.is_empty() else "，".join(parts)


## 获取当前层推荐战力。
func _get_required_power(floor: int) -> int:
	return 420 + maxi(0, floor - 1) * 120


## 获取预览挂机金币收益。
func _get_preview_reward_gold(floor: int) -> int:
	return 18 + maxi(0, floor - 1) * 4


## 创建左侧导航按钮。
func _create_nav_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(1, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(callback)
	return button


## 创建底部功能入口按钮。
func _create_action_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(112, 44)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	return button


## 创建顶部小按钮。
func _create_small_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(104, 36)
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(callback)
	return button


## 创建基础面板样式。
func _make_flat_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 10
	style.content_margin_top = 10
	style.content_margin_right = 10
	style.content_margin_bottom = 10
	return style


## 打开英雄养成覆盖层。
func _open_storage_overlay() -> void:
	if storage_overlay and is_instance_valid(storage_overlay):
		storage_overlay.move_to_front()
		return
	storage_overlay = CharacterStorageUI.new()
	storage_overlay.set_return_callback(_close_storage_overlay)
	storage_overlay.z_index = 100
	add_child(storage_overlay)


## 关闭英雄养成覆盖层。
func _close_storage_overlay() -> void:
	if storage_overlay and is_instance_valid(storage_overlay):
		storage_overlay.queue_free()
	storage_overlay = null
	_refresh_all()


## 打开装备背包占位。
func _open_equipment_overlay() -> void:
	if equipment_overlay and is_instance_valid(equipment_overlay):
		equipment_overlay.move_to_front()
		return
	equipment_overlay = _create_equipment_placeholder()
	equipment_overlay.z_index = 110
	add_child(equipment_overlay)


## 创建装备背包占位界面。
func _create_equipment_placeholder() -> Control:
	var overlay := Control.new()
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.024, 0.03, 0.86)
	dim.anchor_left = 0.0
	dim.anchor_top = 0.0
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 420)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)

	var title := Label.new()
	title.text = "装备背包"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	top.add_child(title)

	top.add_child(_create_small_button("返回", _close_equipment_overlay))

	var desc := Label.new()
	desc.text = "装备系统尚未接入数据。当前界面预留职业武器、单特殊词条和重铸入口。"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 16)
	root.add_child(desc)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	root.add_child(list)
	list.add_child(_create_equipment_row("战士武器", "特殊词条: 连锁反应", "重铸未开放"))
	list.add_child(_create_equipment_row("游侠武器", "特殊词条: 穿透箭矢", "重铸未开放"))
	list.add_child(_create_equipment_row("牧师圣器", "特殊词条: 溢出护盾", "重铸未开放"))
	return overlay


## 创建装备占位行。
func _create_equipment_row(name_text: String, affix_text: String, action_text: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(1, 54)
	row.add_theme_constant_override("separation", 10)

	var marker := ColorRect.new()
	marker.custom_minimum_size = Vector2(46, 46)
	marker.color = Color(0.34, 0.42, 0.55, 1.0)
	row.add_child(marker)

	var info := Label.new()
	info.text = "%s\n%s" % [name_text, affix_text]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 15)
	row.add_child(info)

	var button := Button.new()
	button.text = action_text
	button.custom_minimum_size = Vector2(128, 38)
	button.disabled = true
	row.add_child(button)
	return row


## 关闭装备背包占位。
func _close_equipment_overlay() -> void:
	if equipment_overlay and is_instance_valid(equipment_overlay):
		equipment_overlay.queue_free()
	equipment_overlay = null


## 打开图鉴覆盖层。
func _open_encyclopedia_overlay() -> void:
	if encyclopedia_overlay and is_instance_valid(encyclopedia_overlay):
		encyclopedia_overlay.move_to_front()
		return
	encyclopedia_overlay = EncyclopediaUI.new()
	encyclopedia_overlay.set_return_callback(_close_encyclopedia_overlay)
	encyclopedia_overlay.z_index = 120
	add_child(encyclopedia_overlay)


## 关闭图鉴覆盖层。
func _close_encyclopedia_overlay() -> void:
	if encyclopedia_overlay and is_instance_valid(encyclopedia_overlay):
		encyclopedia_overlay.queue_free()
	encyclopedia_overlay = null


## 打开设置覆盖层。
func _open_settings_overlay() -> void:
	if settings_overlay and is_instance_valid(settings_overlay):
		settings_overlay.move_to_front()
		return
	settings_overlay = SettingsUI.new()
	settings_overlay.set_return_callback(_close_settings_overlay)
	settings_overlay.z_index = 130
	add_child(settings_overlay)


## 关闭设置覆盖层。
func _close_settings_overlay() -> void:
	if settings_overlay and is_instance_valid(settings_overlay):
		settings_overlay.queue_free()
	settings_overlay = null


## 进入自走棋肉鸽模式。
func _enter_roguelike_mode() -> void:
	GameManager.save_game()
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


## 返回主菜单。
func _return_to_start_menu() -> void:
	GameManager.save_game()
	get_tree().change_scene_to_file(START_MENU_SCENE_PATH)


## 领取挂机收益占位。
func _claim_idle_rewards() -> void:
	status_label.text = "挂机收益结算待接入"


## 挑战本层占位。
func _preview_tower_challenge() -> void:
	status_label.text = "战斗动画待接入"


func _on_gold_changed(_gold: int) -> void:
	_refresh_top_bar()
	_refresh_status_panel()


func _on_owned_characters_changed(_characters: Array) -> void:
	_refresh_party_cards()
	_refresh_status_panel()


func _on_save_slot_changed(_save_id: String) -> void:
	_refresh_top_bar()
