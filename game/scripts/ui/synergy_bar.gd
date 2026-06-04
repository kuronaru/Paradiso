# synergy_bar.gd — 顶部羁绊栏
class_name SynergyBar
extends Control

const M = "SynergyBar"

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
var detail_label: Label = null
var selected_synergy_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 2000
	size = Vector2(panel_width, 120.0)
	_reposition()
	_setup_detail_panel()
	if SynergyManager and not SynergyManager.synergy_changed.is_connected(_on_synergy_changed):
		SynergyManager.synergy_changed.connect(_on_synergy_changed)
		_on_synergy_changed(SynergyManager.get_synergy_summary())


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reposition()


func _reposition() -> void:
	var viewport_size := get_viewport_rect().size
	position = Vector2((viewport_size.x - panel_width) * 0.5, top_margin)


func _setup_detail_panel() -> void:
	detail_panel = PanelContainer.new()
	detail_panel.visible = false
	detail_panel.size = Vector2(panel_width, 132.0)
	detail_panel.position = Vector2(0, _get_item_height() + icon_spacing + 6.0)
	detail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(detail_panel)

	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 13)
	detail_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	detail_label.add_theme_constant_override("line_spacing", 2)
	detail_label.custom_minimum_size = Vector2(panel_width - 24.0, 110.0)
	detail_panel.add_child(detail_label)


func _on_synergy_changed(next_summaries: Array) -> void:
	summaries = next_summaries.duplicate(true)
	summaries.sort_custom(_sort_summaries_for_display)
	_refresh_icons()
	_refresh_detail()


func _refresh_icons() -> void:
	for item in icon_items:
		if is_instance_valid(item):
			item.queue_free()
	icon_items.clear()

	if summaries.is_empty():
		detail_panel.visible = false
		return

	var item_height := _get_item_height()
	var max_per_row: int = maxi(1, int(floor(panel_width / (icon_size + icon_spacing))))
	var row_count: int = int(ceil(float(summaries.size()) / float(max_per_row)))
	size.y = float(row_count) * (item_height + icon_spacing) + 150.0

	for i in range(summaries.size()):
		var summary: Dictionary = summaries[i]
		var row: int = int(i / max_per_row)
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

	detail_panel.position.y = float(row_count) * (item_height + icon_spacing) + 6.0


func _get_item_height() -> float:
	return progress_lamp_height + progress_lamp_gap + icon_size


func _add_progress_lamps(parent: Control, summary: Dictionary) -> void:
	var count: int = maxi(0, int(summary.get("count", 0)))
	var lamp_count: int = maxi(1, int(summary.get("activation_count", 1)))
	var gap: float = 3.0
	var lamp_total_width: float = maxf(1.0, icon_size - progress_lamp_width_shrink)
	var lamp_width: float = (lamp_total_width - gap * float(lamp_count - 1)) / float(lamp_count)
	var start_x: float = (icon_size - lamp_total_width) * 0.5

	for i in range(lamp_count):
		var lamp := ColorRect.new()
		lamp.size = Vector2(lamp_width, progress_lamp_height)
		lamp.position = Vector2(start_x + float(i) * (lamp_width + gap), 0.0)
		var required_count: int = i + 1
		var is_lit: bool = count >= required_count
		lamp.color = Color(0.20, 0.75, 1.0, 0.95) if is_lit else Color(0.24, 0.26, 0.30, 0.85)
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(lamp)


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


func _toggle_detail(synergy_id: String) -> void:
	if selected_synergy_id == synergy_id and detail_panel.visible:
		selected_synergy_id = ""
		detail_panel.visible = false
		return
	selected_synergy_id = synergy_id
	_refresh_detail()


func _refresh_detail() -> void:
	if selected_synergy_id == "":
		return
	for summary in summaries:
		if str(summary.get("id", "")) == selected_synergy_id:
			detail_label.text = _format_detail(summary)
			detail_panel.visible = true
			return
	detail_panel.visible = false
	selected_synergy_id = ""


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
