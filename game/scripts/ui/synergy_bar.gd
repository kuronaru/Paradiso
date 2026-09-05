# synergy_bar.gd — 顶部羁绊栏
class_name SynergyBar
extends Control

const M = "SynergyBar"
const NUMBER_COLOR := "#72d7ff"
const SYNERGY_COLOR := "#f0bd55"
const ACTIVE_HERO_COLOR := "#82e6aa"
const INACTIVE_HERO_COLOR := "#8895a8"

@export var panel_width: float = 560.0
@export var icon_size: float = 50.0
@export var icon_spacing: float = 8.0
@export var top_margin: float = 8.0
@export var progress_lamp_height: float = 6.0
@export var progress_lamp_gap: float = 3.0
@export var progress_lamp_width_shrink: float = 3.0

var summaries: Array[Dictionary] = []
var icon_items: Array[Control] = []
var detail_panel: PanelContainer = null
var detail_label: RichTextLabel = null
var selected_synergy_id: String = ""
var synergy_buttons: Dictionary = {}


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	z_index = 2000
	size = Vector2(panel_width, 120.0)
	_reposition()
	_setup_detail_panel()
	if SynergyManager and not SynergyManager.synergy_changed.is_connected(_on_synergy_changed):
		SynergyManager.synergy_changed.connect(_on_synergy_changed)
		_on_synergy_changed(SynergyManager.get_synergy_summary())


## 响应 Godot 通知并刷新相关状态。
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reposition()


## 处理reposition逻辑。
func _reposition() -> void:
	var viewport_size := get_viewport_rect().size
	position = Vector2((viewport_size.x - panel_width) * 0.5, top_margin)


## 初始化详情panel。
func _setup_detail_panel() -> void:
	detail_panel = PanelContainer.new()
	detail_panel.name = "SynergyDetailPanel"
	detail_panel.visible = false
	detail_panel.custom_minimum_size = Vector2(panel_width, 318.0)
	detail_panel.size = Vector2(panel_width, 318.0)
	detail_panel.position = Vector2(0, _get_item_height() + icon_spacing + 6.0)
	detail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	detail_panel.add_theme_stylebox_override("panel", _create_detail_outer_style())
	add_child(detail_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.name = "DetailOuterMargin"
	outer_margin.add_theme_constant_override("margin_left", 8)
	outer_margin.add_theme_constant_override("margin_top", 8)
	outer_margin.add_theme_constant_override("margin_right", 8)
	outer_margin.add_theme_constant_override("margin_bottom", 8)
	detail_panel.add_child(outer_margin)

	var inner_panel := PanelContainer.new()
	inner_panel.name = "DetailInnerPanel"
	inner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_panel.add_theme_stylebox_override("panel", _create_detail_inner_style())
	outer_margin.add_child(inner_panel)

	var text_margin := MarginContainer.new()
	text_margin.name = "DetailTextMargin"
	text_margin.add_theme_constant_override("margin_left", 14)
	text_margin.add_theme_constant_override("margin_top", 10)
	text_margin.add_theme_constant_override("margin_right", 14)
	text_margin.add_theme_constant_override("margin_bottom", 10)
	inner_panel.add_child(text_margin)

	detail_label = RichTextLabel.new()
	detail_label.name = "SynergyDetailText"
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.scroll_following = false
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("normal_font_size", 14)
	detail_label.add_theme_font_size_override("bold_font_size", 14)
	detail_label.add_theme_color_override("default_color", Color(0.92, 0.96, 1.0))
	detail_label.add_theme_constant_override("line_separation", 5)
	detail_label.custom_minimum_size = Vector2(panel_width - 60.0, 270.0)
	text_margin.add_child(detail_label)


func _create_detail_outer_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.085, 0.97)
	style.border_color = Color(0.28, 0.70, 0.92, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
	style.shadow_size = 8
	return style


func _create_detail_inner_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.095, 0.13, 0.94)
	style.border_color = Color(0.76, 0.57, 0.25, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


## 处理羁绊变化回调。
func _on_synergy_changed(next_summaries: Array) -> void:
	summaries.clear()
	for raw_summary in next_summaries:
		if raw_summary is Dictionary:
			summaries.append(raw_summary.duplicate(true))
	summaries.sort_custom(_sort_summaries_for_display)
	_refresh_icons()
	_refresh_detail()


## 刷新图标。
func _refresh_icons() -> void:
	for item in icon_items:
		if is_instance_valid(item):
			item.queue_free()
	icon_items.clear()
	synergy_buttons.clear()

	if summaries.is_empty():
		detail_panel.visible = false
		return

	var item_height := _get_item_height()
	var max_per_row: int = maxi(1, int(floor(panel_width / (icon_size + icon_spacing))))
	var row_count: int = int(ceil(float(summaries.size()) / float(max_per_row)))
	size.y = float(row_count) * (item_height + icon_spacing) + detail_panel.size.y + 18.0

	for i in range(summaries.size()):
		var summary: Dictionary = summaries[i]
		var row: int = int(float(i) / max_per_row)
		var col: int = i % max_per_row
		var row_items: int = mini(max_per_row, summaries.size() - row * max_per_row)
		var row_width: float = float(row_items) * icon_size + float(row_items - 1) * icon_spacing
		var start_x: float = (panel_width - row_width) * 0.5

		var item := Control.new()
		item.size = Vector2(icon_size, item_height)
		item.position = Vector2(start_x + float(col) * (icon_size + icon_spacing), float(row) * (item_height + icon_spacing))
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(item)
		icon_items.append(item)

		_add_progress_lamps(item, summary)

		var btn := Button.new()
		btn.size = Vector2(icon_size, icon_size)
		btn.position = Vector2(0.0, progress_lamp_height + progress_lamp_gap)
		btn.text = "%s\n%d" % [str(summary.get("short_name", "?")), int(summary.get("layer", 0))]
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.tooltip_text = "%s %d/%d · %d层" % [
			str(summary.get("display_name", "")),
			int(summary.get("count", 0)),
			int(summary.get("max_threshold", 0)),
			int(summary.get("layer", 0))
		]
		_apply_icon_style(btn, bool(summary.get("is_active", false)))

		var synergy_id := str(summary.get("id", ""))
		btn.pressed.connect(func(): _toggle_detail(synergy_id))
		item.add_child(btn)
		synergy_buttons[synergy_id] = btn

	detail_panel.position.y = float(row_count) * (item_height + icon_spacing) + 6.0


## 获取条目height。
func _get_item_height() -> float:
	return progress_lamp_height + progress_lamp_gap + icon_size


## 处理添加进度进度灯逻辑。
func _add_progress_lamps(parent: Control, summary: Dictionary) -> void:
	var count: int = maxi(0, int(summary.get("count", 0)))
	var lamp_count: int = maxi(1, int(summary.get("activation_count", 1)))
	var gap: float = 3.0
	var lamp_total_width: float = maxf(1.0, icon_size - progress_lamp_width_shrink)
	var lamp_width: float = (lamp_total_width - gap * float(lamp_count - 1)) / float(lamp_count)
	var start_x: float = (icon_size - lamp_total_width) * 0.5

	for i in range(lamp_count):
		var lamp := Panel.new()
		lamp.size = Vector2(lamp_width, progress_lamp_height)
		lamp.position = Vector2(start_x + float(i) * (lamp_width + gap), 0.0)
		var required_count: int = i + 1
		var is_lit: bool = count >= required_count
		lamp.add_theme_stylebox_override("panel", _create_progress_lamp_style(is_lit))
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(lamp)


## 创建进度lamp样式。
func _create_progress_lamp_style(is_lit: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.75, 1.0, 0.95) if is_lit else Color(0.24, 0.26, 0.30, 0.85)
	var radius := int(ceil(progress_lamp_height * 0.4))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


## 应用图标样式。
func _apply_icon_style(btn: Button, is_active: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.68, 1.0, 0.92) if is_active else Color(0.28, 0.30, 0.34, 0.82)
	normal.border_color = Color(0.78, 0.93, 1.0, 0.95) if is_active else Color(0.55, 0.58, 0.64, 0.75)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("disabled", normal)


## 按显示优先级排序羁绊摘要。
func _sort_summaries_for_display(a: Dictionary, b: Dictionary) -> bool:
	var a_active := bool(a.get("is_active", false))
	var b_active := bool(b.get("is_active", false))
	if a_active != b_active:
		return a_active
	if int(a.get("layer", 0)) != int(b.get("layer", 0)):
		return int(a.get("layer", 0)) > int(b.get("layer", 0))
	var a_main := int(a.get("type", 0)) == 0
	var b_main := int(b.get("type", 0)) == 0
	if a_main != b_main:
		return a_main
	return int(a.get("order", 0)) < int(b.get("order", 0))


## 切换详情。
func _toggle_detail(synergy_id: String) -> void:
	if selected_synergy_id == synergy_id and detail_panel.visible:
		selected_synergy_id = ""
		detail_panel.visible = false
		return
	selected_synergy_id = synergy_id
	_refresh_detail()


func _input(event: InputEvent) -> void:
	if not detail_panel or not detail_panel.visible:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if detail_panel.get_global_rect().has_point(mouse_event.position):
		return
	var selected_button = synergy_buttons.get(selected_synergy_id)
	if selected_button is Control and is_instance_valid(selected_button) \
			and (selected_button as Control).get_global_rect().has_point(mouse_event.position):
		return
	_hide_detail()


func _hide_detail() -> void:
	selected_synergy_id = ""
	if detail_panel:
		detail_panel.visible = false


## 刷新详情。
func _refresh_detail() -> void:
	if selected_synergy_id == "":
		return
	for summary in summaries:
		if str(summary.get("id", "")) == selected_synergy_id:
			detail_label.text = _format_detail_rich(summary)
			detail_panel.visible = true
			return
	detail_panel.visible = false
	selected_synergy_id = ""


## 格式化详情富文本。
func _format_detail_rich(summary: Dictionary) -> String:
	var count: int = int(summary.get("count", 0))
	var activation_count: int = maxi(1, int(summary.get("activation_count", 1)))
	var display_name := str(summary.get("display_name", ""))
	return "[left][font_size=22][b]%s[/b][/font_size]   [color=%s][b]%d层[/b][/color]\n[color=#aab8ca]已激活人数：[/color][b]%d/%d[/b]\n[color=#44647e]━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n%s\n[color=#44647e]━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n[font_size=15][b]英雄：[/b][/font_size]\n%s[/left]" % [
		_bbcode_escape(display_name),
		NUMBER_COLOR,
		int(summary.get("layer", 0)),
		count,
		activation_count,
		_format_effect_paragraphs(summary),
		_format_hero_roster(summary)
	]


func _format_effect_paragraphs(summary: Dictionary) -> String:
	var synergy_id := str(summary.get("id", ""))
	var data: Dictionary = DataRegistry.get_synergy(synergy_id)
	var templates = data.get("detail_descriptions", [])
	if not templates is Array or templates.is_empty():
		return _format_generic_description(summary)
	var lines: PackedStringArray = []
	for raw_template in templates:
		if not raw_template is Dictionary:
			continue
		var template: Dictionary = raw_template
		var text := str(template.get("text", ""))
		text = text.replace("【某羁绊】", "[color=%s]【%s】[/color]" % [
			SYNERGY_COLOR, _bbcode_escape(str(summary.get("display_name", "")))
		])
		text = _replace_detail_numeric_placeholders(
			text, template.get("values", []), summary, data
		)
		var threshold := int(template.get("threshold", 0))
		var line_color := "#edf5ff" if int(summary.get("count", 0)) >= threshold else "#8995a5"
		lines.append("[color=%s]%s[/color]" % [line_color, text])
	return "\n\n".join(lines)


func _replace_detail_numeric_placeholders(
	description: String,
	value_specs: Variant,
	summary: Dictionary,
	data: Dictionary
) -> String:
	var pattern := RegEx.new()
	pattern.compile("\\[\\+?X\\]")
	var matches := pattern.search_all(description)
	if matches.is_empty():
		return description
	var specs: Array = value_specs if value_specs is Array else []
	var result := ""
	var cursor := 0
	for index in range(matches.size()):
		var regex_match := matches[index] as RegExMatch
		result += description.substr(cursor, regex_match.get_start() - cursor)
		var token := regex_match.get_string()
		var value := _resolve_detail_value(specs[index] if index < specs.size() else {}, summary, data)
		var number_text := _format_number(value)
		if token == "[+X]" and value >= 0.0:
			number_text = "+" + number_text
		result += "[color=%s][b]%s[/b][/color]" % [NUMBER_COLOR, number_text]
		cursor = regex_match.get_end()
	result += description.substr(cursor)
	return result


func _resolve_detail_value(spec: Variant, summary: Dictionary, data: Dictionary) -> float:
	if spec is float or spec is int:
		return float(spec)
	if not spec is Dictionary:
		return 0.0
	var descriptor: Dictionary = spec
	var value := 0.0
	match str(descriptor.get("source", "fixed")):
		"modifier":
			value = _modifier_current_value(
				data.get("scalable_modifiers", []), str(descriptor.get("key", "")), int(summary.get("layer", 0))
			)
		"effect":
			value = _effect_current_value(
				data.get("main_effect", {}), str(descriptor.get("key", "")), int(summary.get("layer", 0))
			)
		_:
			value = float(descriptor.get("value", 0.0))
	match str(descriptor.get("format", "number")):
		"percent":
			value *= 100.0
		"bonus_percent":
			value = (value - 1.0) * 100.0
	return value


func _modifier_current_value(modifiers: Variant, stat: String, layer: int) -> float:
	if modifiers is Array:
		for raw_modifier in modifiers:
			if raw_modifier is Dictionary and str(raw_modifier.get("stat", "")) == stat:
				return _scaled_value(raw_modifier, layer)
	return 0.0


func _effect_current_value(main_effect: Variant, key: String, layer: int) -> float:
	if not main_effect is Dictionary:
		return 0.0
	var configured = main_effect.get(key, 0.0)
	return _scaled_value(configured, layer) if configured is Dictionary else float(configured)


func _scaled_value(configured: Dictionary, layer: int) -> float:
	var value := float(configured.get("base", configured.get("value", configured.get("fallback", 0.0))))
	value += float(layer) * float(configured.get("per_layer", 0.0))
	if configured.has("max_value"):
		value = minf(value, float(configured.get("max_value")))
	if configured.has("min_value"):
		value = maxf(value, float(configured.get("min_value")))
	return value


func _format_generic_description(summary: Dictionary) -> String:
	var display_name := str(summary.get("display_name", ""))
	var description := _highlight_literal_numbers(_bbcode_escape(str(summary.get("description", ""))))
	var thresholds: Array = summary.get("thresholds", [])
	for raw_threshold in thresholds:
		var threshold := int(raw_threshold)
		description = description.replace(
			"%d人时" % threshold,
			"<在场[color=%s][b]%d[/b][/color]名不同[color=%s]【%s】[/color]英雄>" % [
				NUMBER_COLOR, threshold, SYNERGY_COLOR, _bbcode_escape(display_name)
			]
		)
		description = description.replace(
			"%d人：" % threshold,
			"<在场[color=%s][b]%d[/b][/color]名不同[color=%s]【%s】[/color]英雄>" % [
				NUMBER_COLOR, threshold, SYNERGY_COLOR, _bbcode_escape(display_name)
			]
		)
	description = description.replace("；", "\n\n").replace("。", "。\n\n").strip_edges()
	var current_values := _format_effect_lines(summary)
	if "暂无数值项" not in current_values:
		description += "\n\n[color=#aab8ca]当前效果：[/color]" + current_values.trim_prefix("当前层数数值：")
	return description


func _highlight_literal_numbers(value: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("(?<![A-Za-z_])[-+]?\\d+(?:\\.\\d+)?%?")
	var matches := pattern.search_all(value)
	if matches.is_empty():
		return value
	var result := ""
	var cursor := 0
	for regex_match in matches:
		result += value.substr(cursor, regex_match.get_start() - cursor)
		result += "[color=%s][b]%s[/b][/color]" % [NUMBER_COLOR, regex_match.get_string()]
		cursor = regex_match.get_end()
	result += value.substr(cursor)
	return result


func _format_hero_roster(summary: Dictionary) -> String:
	var synergy_id := str(summary.get("id", ""))
	var active_names: Dictionary = {}
	for member in summary.get("members", []):
		active_names[str(member)] = true
	var all_names: PackedStringArray = []
	if DataRegistry and DataRegistry.has_method("get_all_autochess_hero_ids"):
		for hero_id in DataRegistry.get_all_autochess_hero_ids():
			var hero_data: Dictionary = DataRegistry.get_autochess_hero(str(hero_id))
			var owned_synergies: Array = hero_data.get("autochess_synergy_ids", [])
			if synergy_id != "trait_advanced" and synergy_id not in owned_synergies:
				continue
			var template := ClassDefinitions.get_template(str(hero_id))
			var hero_name := template.job_name if template else str(hero_id)
			if hero_name not in all_names:
				all_names.append(hero_name)
	for active_name in active_names.keys():
		if str(active_name) not in all_names:
			all_names.append(str(active_name))
	if all_names.is_empty():
		return "[color=%s]暂无[/color]" % INACTIVE_HERO_COLOR
	var rendered: PackedStringArray = []
	for hero_name in all_names:
		var color := ACTIVE_HERO_COLOR if active_names.has(hero_name) else INACTIVE_HERO_COLOR
		var weight_open := "[b]" if active_names.has(hero_name) else ""
		var weight_close := "[/b]" if active_names.has(hero_name) else ""
		rendered.append("[color=%s]%s%s%s[/color]" % [
			color, weight_open, _bbcode_escape(hero_name), weight_close
		])
	return "  ·  ".join(rendered)


## 格式化effect文本行。
func _format_effect_lines(summary: Dictionary) -> String:
	var active_tier: int = int(summary.get("active_tier", 0))
	var layer: int = int(summary.get("layer", 0))
	var lines: PackedStringArray = []
	var scalable_modifiers: Array = summary.get("scalable_modifiers", [])
	for modifier_value in scalable_modifiers:
		if not (modifier_value is Dictionary):
			continue
		var modifier: Dictionary = modifier_value
		lines.append(_format_scalable_modifier_line(modifier, active_tier, layer))

	var fixed_modifiers: Array = summary.get("fixed_modifiers", [])
	for modifier_value in fixed_modifiers:
		if not (modifier_value is Dictionary):
			continue
		var modifier: Dictionary = modifier_value
		lines.append(_format_fixed_modifier_line(modifier, active_tier))

	if lines.is_empty():
		return "[color=#8d98a8]当前层数暂无数值项。[/color]"
	return "当前层数数值：" + "  ".join(lines)


## 格式化可缩放修正文本行。
func _format_scalable_modifier_line(modifier: Dictionary, active_tier: int, layer: int) -> String:
	var min_tier: int = int(modifier.get("min_tier", 0))
	var stat: String = str(modifier.get("stat", ""))
	var base: float = float(modifier.get("base", 0.0))
	var per_layer: float = float(modifier.get("per_layer", 0.0))
	var max_value: float = float(modifier.get("max_value", base))
	var value: float = minf(base + float(layer) * per_layer, max_value)
	return "%s %s %s" % [
		_format_tier_tag(min_tier, active_tier),
		_stat_display_name(stat),
		_format_modifier_value(stat, value)
	]


## 格式化固定修正文本行。
func _format_fixed_modifier_line(modifier: Dictionary, active_tier: int) -> String:
	var min_tier: int = int(modifier.get("min_tier", 0))
	var stat: String = str(modifier.get("stat", ""))
	var value: float = float(modifier.get("value", 0.0))
	return "%s %s %s" % [
		_format_tier_tag(min_tier, active_tier),
		_stat_display_name(stat),
		_format_modifier_value(stat, value)
	]


## 格式化档位标签。
func _format_tier_tag(min_tier: int, active_tier: int) -> String:
	if active_tier >= min_tier:
		return "[color=#9df7b5]已生效[/color]"
	return "[color=#8d98a8]%d人解锁[/color]" % min_tier


## 格式化修正值。
func _format_modifier_value(stat: String, value: float) -> String:
	var text: String = ""
	if _is_multiplier_stat(stat):
		text = _format_percent(value - 1.0)
	elif _is_fraction_stat(stat):
		text = _format_percent(value)
	elif stat == "deploy_cost_discount":
		text = _format_percent(-value)
	elif stat == "victory_gold_multiplier":
		text = _format_percent(value - 1.0)
	elif stat == "max_dp_bonus":
		text = "+%d" % int(round(value))
	elif stat == "search_range_bonus":
		text = "+%s" % _format_number(value)
	elif stat in ["trench_counter_duration", "poem_cooldown_seconds"]:
		text = "+%s秒" % _format_number(value)
	else:
		text = "+%s" % _format_number(value)
	return "[color=#ffd166][b]%s[/b][/color]" % text


## 格式化percent。
func _format_percent(value: float) -> String:
	var _sign: String = "+" if value >= 0.0 else ""
	return "%s%s%%" % [_sign, _format_number(value * 100.0)]


## 格式化数值。
func _format_number(value: float) -> String:
	var rounded: float = snappedf(value, 0.1)
	if is_equal_approx(rounded, round(rounded)):
		return "%d" % int(round(rounded))
	return "%.1f" % rounded


## 判断multiplier属性状态。
func _is_multiplier_stat(stat: String) -> bool:
	return stat in [
		"max_hp_multiplier",
		"attack_multiplier",
		"defense_multiplier",
		"attack_speed_multiplier",
		"move_speed_multiplier",
		"damage_multiplier",
		"skill_damage_multiplier",
		"nature_damage_multiplier",
		"burning_damage_multiplier",
		"forbidden_damage_taken_multiplier",
		"trench_counter_damage_multiplier",
		"heal_multiplier",
		"incoming_heal_multiplier",
		"crit_damage_multiplier",
		"damage_taken_multiplier",
		"revive_time_multiplier",
		"shield_multiplier",
	]


## 判断fraction属性状态。
func _is_fraction_stat(stat: String) -> bool:
	return stat in [
		"armor_pierce",
		"crit_chance",
		"skill_cooldown_reduction",
		"life_steal_percent",
		"poison_attack_ratio",
		"slow_percent",
		"explosion_chance",
		"law_retaliation_attack_ratio",
		"forbidden_death_burst_multiplier",
		"forbidden_execute_attack_ratio",
		"trench_dodge_chance",
		"poem_stat_share_ratio",
		"poem_cooldown_chance",
	]


## 处理属性显示name逻辑。
func _stat_display_name(stat: String) -> String:
	match stat:
		"max_hp_multiplier":
			return "生命"
		"attack_multiplier":
			return "攻击"
		"defense_multiplier":
			return "防御"
		"attack_speed_multiplier":
			return "攻速"
		"move_speed_multiplier":
			return "移速"
		"damage_multiplier":
			return "伤害"
		"skill_damage_multiplier":
			return "技能伤害"
		"nature_damage_multiplier":
			return "自然爆条伤害"
		"burning_damage_multiplier":
			return "燃烧增伤"
		"heal_multiplier":
			return "治疗/护盾"
		"incoming_heal_multiplier":
			return "承疗"
		"damage_taken_multiplier":
			return "受到伤害"
		"revive_time_multiplier":
			return "复活时间"
		"shield_multiplier":
			return "护盾"
		"crit_damage_multiplier":
			return "暴击伤害"
		"armor_pierce":
			return "破甲"
		"crit_chance":
			return "暴击率"
		"skill_cooldown_reduction":
			return "技能冷却"
		"life_steal_percent":
			return "攻击吸血"
		"poison_attack_ratio":
			return "毒层攻击系数"
		"slow_percent":
			return "自然减速"
		"explosion_chance":
			return "爆炸概率"
		"law_retaliation_attack_ratio":
			return "律法反击系数"
		"forbidden_damage_taken_multiplier":
			return "禁忌易伤"
		"forbidden_death_burst_multiplier":
			return "死亡爆发系数"
		"forbidden_execute_attack_ratio":
			return "禁忌处决阈值"
		"trench_dodge_chance":
			return "战壕闪避"
		"trench_counter_damage_multiplier":
			return "闪避后增伤"
		"trench_counter_duration":
			return "增伤持续"
		"poem_stat_share_ratio":
			return "长诗祝福系数"
		"poem_cooldown_chance":
			return "冷却祝福概率"
		"poem_cooldown_seconds":
			return "冷却缩减"
		"search_range_bonus":
			return "索敌范围"
		"max_dp_bonus":
			return "DP上限"
		"deploy_cost_discount":
			return "部署费用"
		"victory_gold_multiplier":
			return "胜利金币"
	return stat


## 处理BBCodeescape逻辑。
func _bbcode_escape(value: String) -> String:
	var result := ""
	for i in range(value.length()):
		var character := value.substr(i, 1)
		match character:
			"[":
				result += "[lb]"
			"]":
				result += "[rb]"
			_:
				result += character
	return result


## 格式化详情。
func _format_detail(summary: Dictionary) -> String:
	var count := int(summary.get("count", 0))
	var max_threshold := int(summary.get("max_threshold", 0))
	var next_threshold := int(summary.get("next_threshold", max_threshold))
	var threshold_text := "%d/%d" % [count, max_threshold if bool(summary.get("is_active", false)) else next_threshold]
	var members: Array = summary.get("members", [])
	var member_text := "暂无"
	if not members.is_empty():
		var names: PackedStringArray = []
		for member in members:
			names.append(str(member))
		member_text = "、".join(names)
	return "%s  %s  %s层\n%s\n角色：%s" % [
		str(summary.get("display_name", "")),
		threshold_text,
		int(summary.get("layer", 0)),
		str(summary.get("description", "")),
		member_text
	]
