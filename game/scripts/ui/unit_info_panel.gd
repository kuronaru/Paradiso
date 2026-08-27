# unit_info_panel.gd — UnitBase 共用悬浮信息面板
class_name UnitInfoPanel
extends CanvasLayer

const PANEL_SIZE := Vector2(280.0, 480.0)
const PANEL_MARGIN := 8.0
const UNIT_SIDE_GAP := 14.0
const REFRESH_INTERVAL := 0.25

var panel: PanelContainer = null
var portrait_panel: PanelContainer = null
var portrait: TextureRect = null
var stats_text: RichTextLabel = null
var synergy_items: VBoxContainer = null
var traits_text: RichTextLabel = null
var skills_text: RichTextLabel = null
var equipment_icon_labels: Array[Label] = []
var equipment_description_labels: Array[Label] = []
var current_unit: UnitBase = null
var recruit_template: ClassTemplate = null
var recruit_star_level: int = 1
var recruit_source: Control = null
var recruit_preview_active: bool = false
var refresh_elapsed: float = 0.0


func _ready() -> void:
	layer = 140
	_build_panel()
	panel.hide()


func _process(delta: float) -> void:
	if not panel or not panel.visible:
		return
	if recruit_preview_active:
		if not is_instance_valid(recruit_source) or not recruit_source.is_visible_in_tree():
			hide_recruit_preview()
			return
	elif not is_instance_valid(current_unit) or not current_unit.is_inside_tree():
		hide_for_unit()
		return
	_position_panel()
	refresh_elapsed += delta
	if refresh_elapsed >= REFRESH_INTERVAL:
		refresh_elapsed = 0.0
		_refresh_stats()


func show_for_unit(unit: UnitBase) -> void:
	if not is_instance_valid(unit):
		return
	current_unit = unit
	recruit_template = null
	recruit_source = null
	recruit_preview_active = false
	refresh_elapsed = 0.0
	_refresh_content()
	_position_panel()
	panel.show()


func show_for_recruit_option(class_data: ClassTemplate, star_level: int, source: Control) -> void:
	if not class_data or not is_instance_valid(source):
		return
	current_unit = null
	recruit_template = class_data
	recruit_star_level = clampi(star_level, 1, 3)
	recruit_source = source
	recruit_preview_active = true
	refresh_elapsed = 0.0
	_refresh_content()
	_position_panel()
	panel.show()


func hide_for_unit(unit: UnitBase = null) -> void:
	if recruit_preview_active:
		return
	if unit and current_unit != unit:
		return
	current_unit = null
	if panel:
		panel.hide()


func hide_recruit_preview(source: Control = null) -> void:
	if not recruit_preview_active:
		return
	if source and recruit_source != source:
		return
	recruit_preview_active = false
	recruit_template = null
	recruit_source = null
	if panel:
		panel.hide()


func is_showing_unit(unit: UnitBase) -> bool:
	return panel != null and panel.visible and not recruit_preview_active and current_unit == unit


func is_showing_recruit_option(source: Control) -> bool:
	return panel != null and panel.visible and recruit_preview_active and recruit_source == source


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "UnitInfoPanel"
	panel.custom_minimum_size = PANEL_SIZE
	panel.size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.025, 0.035, 0.055, 0.97),
		Color(0.34, 0.56, 0.82, 0.95),
		8
	))
	add_child(panel)

	var outer := MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("margin_left", 9)
	outer.add_theme_constant_override("margin_top", 9)
	outer.add_theme_constant_override("margin_right", 9)
	outer.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(outer)

	var columns := VBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override("separation", 6)
	outer.add_child(columns)

	_build_overview_section(columns)
	traits_text = _build_text_section(columns, "TraitsSection", "特质", 90.0)
	skills_text = _build_skills_section(columns, 90.0)
	_build_equipment_section(columns, 102.0)


func _build_overview_section(parent: VBoxContainer) -> void:
	var section := PanelContainer.new()
	section.name = "OverviewSection"
	section.custom_minimum_size = Vector2(0.0, 150.0)
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_theme_stylebox_override("panel", _panel_style(
		Color(0.055, 0.075, 0.105, 0.92),
		Color(0.18, 0.28, 0.42, 0.9),
		5
	))
	parent.add_child(section)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	section.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)

	portrait_panel = PanelContainer.new()
	portrait_panel.name = "PortraitFrame"
	portrait_panel.custom_minimum_size = Vector2(80.0, 0.0)
	portrait_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait_panel)

	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_panel.add_child(portrait)

	stats_text = RichTextLabel.new()
	stats_text.name = "StatsText"
	stats_text.fit_content = false
	stats_text.scroll_active = false
	stats_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_text.add_theme_font_size_override("normal_font_size", 11)
	stats_text.add_theme_color_override("default_color", Color(0.9, 0.93, 0.98))
	stats_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stats_text)

	var synergy_panel := PanelContainer.new()
	synergy_panel.name = "SynergyColumn"
	synergy_panel.custom_minimum_size = Vector2(40.0, 0.0)
	synergy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	row.add_child(synergy_panel)

	var synergy_margin := MarginContainer.new()
	synergy_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_margin.add_theme_constant_override("margin_left", 2)
	synergy_margin.add_theme_constant_override("margin_top", 2)
	synergy_margin.add_theme_constant_override("margin_right", 2)
	synergy_margin.add_theme_constant_override("margin_bottom", 2)
	synergy_panel.add_child(synergy_margin)

	var synergy_scroll := ScrollContainer.new()
	synergy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	synergy_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_margin.add_child(synergy_scroll)

	synergy_items = VBoxContainer.new()
	synergy_items.name = "SynergyItems"
	synergy_items.custom_minimum_size = Vector2(38.0, 0.0)
	synergy_items.add_theme_constant_override("separation", 4)
	synergy_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_scroll.add_child(synergy_items)


func _build_text_section(parent: VBoxContainer, node_name: String, title: String, minimum_height: float) -> RichTextLabel:
	var section := PanelContainer.new()
	section.name = node_name
	section.custom_minimum_size = Vector2(0.0, minimum_height)
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_theme_stylebox_override("panel", _panel_style(
		Color(0.045, 0.06, 0.085, 0.92),
		Color(0.16, 0.24, 0.36, 0.9),
		5
	))
	parent.add_child(section)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	section.add_child(margin)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 3)
	margin.add_child(stack)

	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", Color(0.52, 0.76, 1.0))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(scroll)

	var text_box := RichTextLabel.new()
	text_box.name = "%sText" % title
	text_box.fit_content = true
	text_box.scroll_active = false
	text_box.custom_minimum_size = Vector2(234.0, 0.0)
	text_box.add_theme_font_size_override("normal_font_size", 12)
	text_box.add_theme_color_override("default_color", Color(0.84, 0.87, 0.92))
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(text_box)
	return text_box


func _build_skills_section(parent: VBoxContainer, minimum_height: float) -> RichTextLabel:
	var section := PanelContainer.new()
	section.name = "SkillsSection"
	section.custom_minimum_size = Vector2(0.0, minimum_height)
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_theme_stylebox_override("panel", _panel_style(
		Color(0.045, 0.06, 0.085, 0.92),
		Color(0.16, 0.24, 0.36, 0.9),
		5
	))
	parent.add_child(section)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 5)
	section.add_child(margin)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)

	var heading := Label.new()
	heading.text = "技能"
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", Color(0.52, 0.76, 1.0))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(heading)

	var skill_scroll := ScrollContainer.new()
	skill_scroll.name = "SkillDescriptionScroll"
	skill_scroll.custom_minimum_size = Vector2(0.0, 37.0)
	skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skill_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(skill_scroll)

	var skill_box := RichTextLabel.new()
	skill_box.name = "技能Text"
	skill_box.fit_content = true
	skill_box.scroll_active = false
	skill_box.custom_minimum_size = Vector2(234.0, 0.0)
	skill_box.add_theme_font_size_override("normal_font_size", 11)
	skill_box.add_theme_color_override("default_color", Color(0.84, 0.87, 0.92))
	skill_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_scroll.add_child(skill_box)

	return skill_box


func _build_equipment_section(parent: VBoxContainer, minimum_height: float) -> void:
	var section := PanelContainer.new()
	section.name = "EquipmentSection"
	section.custom_minimum_size = Vector2(0.0, minimum_height)
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_theme_stylebox_override("panel", _panel_style(
		Color(0.045, 0.06, 0.085, 0.92),
		Color(0.34, 0.48, 0.66, 0.95),
		5
	))
	parent.add_child(section)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	section.add_child(margin)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)

	var heading := Label.new()
	heading.name = "EquipmentTitle"
	heading.text = "装备"
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", Color(0.62, 0.8, 1.0))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(heading)

	for equipment_index in range(2):
		_build_equipment_row(stack, equipment_index)


func _build_equipment_row(parent: VBoxContainer, index: int) -> void:
	var row := HBoxContainer.new()
	row.name = "EquipmentRow%d" % (index + 1)
	row.custom_minimum_size = Vector2(0.0, 34.0)
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var icon := PanelContainer.new()
	icon.name = "EquipmentIcon"
	icon.custom_minimum_size = Vector2(34.0, 34.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_stylebox_override("panel", _panel_style(
		Color(0.08, 0.1, 0.14, 0.95),
		Color(0.25, 0.32, 0.44, 0.9),
		3
	))
	row.add_child(icon)

	var icon_label := Label.new()
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 10)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(icon_label)
	equipment_icon_labels.append(icon_label)

	var description_panel := PanelContainer.new()
	description_panel.name = "EquipmentDescription"
	description_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.035, 0.045, 0.065, 0.9),
		Color(0.13, 0.19, 0.28, 0.8),
		3
	))
	row.add_child(description_panel)

	var description := Label.new()
	description.clip_text = true
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size", 9)
	description.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_panel.add_child(description)
	equipment_description_labels.append(description)


func _refresh_content() -> void:
	_refresh_stats()
	_refresh_portrait()
	_refresh_synergies()
	_refresh_traits()
	_refresh_skills()
	_refresh_equipment()


func _refresh_stats() -> void:
	if not stats_text:
		return
	var ct := _content_template()
	if not ct and not is_instance_valid(current_unit):
		return
	var level := _content_level()
	var star_level := _content_star_level()
	var hp := current_unit.current_hp if is_instance_valid(current_unit) else _scaled_stat(ct.base_hp, level)
	var max_hp := current_unit.max_hp if is_instance_valid(current_unit) else hp
	var attack_value := current_unit.attack if is_instance_valid(current_unit) else _scaled_stat(ct.base_atk, level)
	var defense_value := current_unit.defense if is_instance_valid(current_unit) else _scaled_stat(ct.base_def, level)
	var attack_speed_value := current_unit.attack_speed if is_instance_valid(current_unit) else ct.attack_speed
	var move_speed_value := current_unit.move_speed if is_instance_valid(current_unit) else ct.move_speed
	var attack_range_value := current_unit.attack_range if is_instance_valid(current_unit) else ct.attack_range
	var team_name := ("我方" if current_unit.team == "player" else "敌方") if is_instance_valid(current_unit) else "招募"
	stats_text.text = "\n".join([
		"%s" % _unit_display_name(),
		"%s · Lv.%d · %d星" % [team_name, level, star_level],
		"生命  %d / %d" % [hp, max_hp],
		"攻击  %d" % attack_value,
		"防御  %d" % defense_value,
		"攻速  %.2f/秒" % attack_speed_value,
		"移速  %.2f格/秒" % move_speed_value,
		"范围  %.1f格" % attack_range_value,
	])


func _refresh_portrait() -> void:
	var ct := _content_template()
	if not ct and not is_instance_valid(current_unit):
		return
	var visual_id := current_unit.visual_id if is_instance_valid(current_unit) else ct.visual_id
	var unit_color := current_unit.color if is_instance_valid(current_unit) else ClassDefinitions.get_template_color(ct.class_id)
	portrait.texture = _visual_portrait_texture(visual_id)
	portrait.modulate = Color.WHITE
	portrait_panel.add_theme_stylebox_override("panel", _panel_style(
		unit_color.darkened(0.62),
		unit_color.lightened(0.18),
		4
	))


func _refresh_synergies() -> void:
	if not synergy_items:
		return
	for child in synergy_items.get_children():
		child.queue_free()
	var synergy_ids := _content_synergy_ids()
	if synergy_ids.is_empty():
		var empty := Label.new()
		empty.text = "无羁绊"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 10)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		synergy_items.add_child(empty)
		return
	for synergy_id in synergy_ids:
		_add_synergy_item(str(synergy_id))


func _add_synergy_item(synergy_id: String) -> void:
	var data: Dictionary = DataRegistry.get_synergy(synergy_id)
	var display_name := str(data.get("display_name", synergy_id))
	var short_name := str(data.get("short_name", display_name.left(1)))
	var item := VBoxContainer.new()
	item.alignment = BoxContainer.ALIGNMENT_CENTER
	item.add_theme_constant_override("separation", 1)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_items.add_child(item)

	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(34.0, 34.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_color := _synergy_color(synergy_id)
	icon.add_theme_stylebox_override("panel", _panel_style(icon_color.darkened(0.35), icon_color, 4))
	item.add_child(icon)

	var glyph := Label.new()
	glyph.text = short_name.left(2)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 13)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(glyph)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(38.0, 15.0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(name_label)


func _refresh_traits() -> void:
	if not traits_text:
		return
	var lines: Array[String] = []
	var ct := _content_template()
	if ct:
		for trait_id in ct.auto_trait_ids:
			var trait_data: Dictionary = DataRegistry.get_auto_trait(str(trait_id))
			var display_name := str(trait_data.get("display_name", trait_id))
			var description := str(trait_data.get("description", "暂无描述"))
			lines.append("【%s】\n%s" % [display_name, description])
	traits_text.text = "\n\n".join(lines) if not lines.is_empty() else "无特质"


func _refresh_skills() -> void:
	if not skills_text:
		return
	var skill_ids: Array = []
	var ct := _content_template()
	if ct:
		skill_ids = ct.skill_ids
	elif is_instance_valid(current_unit) and current_unit is EnemyUnit:
		skill_ids = (current_unit as EnemyUnit).spawn_template.get("skills", [])
	var lines: Array[String] = []
	for raw_skill in skill_ids:
		var skill_id := str(raw_skill.get("skill_id", "")) if raw_skill is Dictionary else str(raw_skill)
		if skill_id == "":
			continue
		var skill := SkillData.get_skill(skill_id)
		if skill:
			lines.append("【%s】 冷却 %.1fs\n%s" % [skill.skill_name, skill.cooldown, skill.description])
		elif raw_skill is Dictionary:
			lines.append("【%s】\n%s" % [skill_id, str(raw_skill.get("description", "暂无描述"))])
	skills_text.text = "\n\n".join(lines) if not lines.is_empty() else "无技能"


func _refresh_equipment() -> void:
	var equipment_ids := _content_equipment_ids()
	for index in range(equipment_description_labels.size()):
		var icon_label := equipment_icon_labels[index]
		var description_label := equipment_description_labels[index]
		if index >= equipment_ids.size():
			icon_label.text = "+"
			description_label.text = "空装备槽"
			continue
		var equipment_id := str(equipment_ids[index])
		var equipment: Dictionary = DataRegistry.get_autochess_equipment(equipment_id)
		var display_name := str(equipment.get("display_name", equipment_id))
		icon_label.text = display_name.left(2)
		description_label.text = "%s：%s" % [display_name, str(equipment.get("description", "暂无描述"))]


func _position_panel() -> void:
	if not panel:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_x := PANEL_MARGIN
	if recruit_preview_active and is_instance_valid(recruit_source):
		panel_x = recruit_source.get_global_rect().get_center().x - PANEL_SIZE.x * 0.5
	elif is_instance_valid(current_unit):
		var unit_screen := current_unit.get_global_transform_with_canvas() * current_unit.billboard_screen_offset
		var side_offset := current_unit.unit_radius + UNIT_SIDE_GAP
		panel_x = unit_screen.x + side_offset
		if unit_screen.x >= viewport_size.x * 0.5:
			panel_x = unit_screen.x - side_offset - PANEL_SIZE.x
	else:
		return
	panel_x = clampf(panel_x, PANEL_MARGIN, maxf(PANEL_MARGIN, viewport_size.x - PANEL_SIZE.x - PANEL_MARGIN))

	var recruit_top := viewport_size.y - RecruitUI.PANEL_HEIGHT - 8.0
	var grid := BattleManager.grid as GridSystem
	if grid:
		recruit_top = grid.get_recruit_panel_top_y()
	var panel_y := recruit_top - PANEL_SIZE.y - PANEL_MARGIN
	panel_y = clampf(panel_y, PANEL_MARGIN, maxf(PANEL_MARGIN, viewport_size.y - PANEL_SIZE.y - PANEL_MARGIN))
	panel.position = Vector2(panel_x, panel_y)
	panel.size = PANEL_SIZE


func _unit_display_name() -> String:
	if is_instance_valid(current_unit) and current_unit.unit_name != "":
		return current_unit.unit_name
	var ct := _content_template()
	if ct:
		return ct.job_name
	return "未知单位"


func _visual_portrait_texture(visual_id: String) -> Texture2D:
	if visual_id == "":
		return null
	var config: UnitVisualConfig = ArtRegistry.get_unit_visual_config(visual_id)
	if not config:
		return null
	if config.texture:
		return config.texture
	if config.sprite_frames:
		var animation := config.idle_animation
		if animation == "" or not config.sprite_frames.has_animation(animation):
			var names := config.sprite_frames.get_animation_names()
			animation = str(names[0]) if not names.is_empty() else ""
		if animation != "" and config.sprite_frames.get_frame_count(animation) > 0:
			return config.sprite_frames.get_frame_texture(animation, 0)
	return null


func _content_template() -> ClassTemplate:
	if recruit_preview_active:
		return recruit_template
	if is_instance_valid(current_unit):
		return current_unit.class_template
	return null


func _content_level() -> int:
	if recruit_preview_active and recruit_template:
		return GameManager.get_effective_level_for_star(recruit_template.class_id, recruit_star_level)
	return current_unit.level if is_instance_valid(current_unit) else 1


func _content_star_level() -> int:
	if recruit_preview_active:
		return recruit_star_level
	if is_instance_valid(current_unit):
		if current_unit is HeroUnit:
			return (current_unit as HeroUnit).star_level
		return int(current_unit.get_meta("star_level", 1))
	return 1


func _content_equipment_ids() -> Array:
	if recruit_preview_active:
		return []
	if is_instance_valid(current_unit):
		if current_unit is HeroUnit:
			return (current_unit as HeroUnit).run_card_data.get("equipment_ids", [])
		return current_unit.get_meta("equipment_ids", [])
	return []


func _content_synergy_ids() -> Array[String]:
	var result: Array[String] = []
	var ct := _content_template()
	if not ct:
		return result
	result.assign(ct.autochess_synergy_ids)
	if result.is_empty():
		if ct.class_group != "":
			result.append("main_%s" % ct.class_group)
		for tag in ct.stat_tags:
			result.append("stat_%s" % str(tag).to_lower())
		for tag in ct.alignment_tags:
			result.append("alignment_%s" % str(tag).to_lower())
		for tag in ct.trait_tags:
			result.append("trait_%s" % str(tag).to_lower())
	if _content_star_level() >= 2 and "trait_advanced" not in result:
		result.append("trait_advanced")
	var equipment_ids := _content_equipment_ids()
	if SynergyManager and SynergyManager.has_method("get_equipment_main_synergy_ids"):
		for synergy_id in SynergyManager.get_equipment_main_synergy_ids(equipment_ids):
			if str(synergy_id) not in result:
				result.append(str(synergy_id))
	return result


func _scaled_stat(base_value: int, level: int) -> int:
	return int(round(float(base_value) * (1.0 + float(maxi(level, 1) - 1) * 0.05)))


func _synergy_color(synergy_id: String) -> Color:
	if synergy_id.begins_with("main_"):
		return Color(0.82, 0.46, 0.22)
	if synergy_id.begins_with("stat_"):
		return Color(0.28, 0.58, 0.9)
	if synergy_id.begins_with("alignment_"):
		return Color(0.64, 0.42, 0.82)
	return Color(0.32, 0.72, 0.52)


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style
