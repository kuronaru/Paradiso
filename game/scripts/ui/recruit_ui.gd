# recruit_ui.gd — 酒馆招募界面
class_name RecruitUI
extends Control

const M = "RecruitUI"

signal recruit_purchased
signal recruit_skipped

var roguelike_manager: RoguelikeManager = null
var option_buttons: Array[Button] = []
var skip_btn: Button
var gold_label: Label
var title_label: Label


func _ready() -> void:
	var tree := get_tree()
	if tree:
		var nodes := tree.get_nodes_in_group("roguelike_manager")
		if nodes.size() > 0:
			roguelike_manager = nodes[0]
			roguelike_manager.recruit_phase_started.connect(_show)

	_setup_ui()
	hide()


func _setup_ui() -> void:
	var bg := ColorRect.new()
	bg.size = get_viewport_rect().size
	bg.color = Color(0.05, 0.03, 0.08, 0.92)
	add_child(bg)

	title_label = Label.new()
	title_label.text = "酒馆招募"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, 40)
	title_label.size.x = bg.size.x
	add_child(title_label)

	gold_label = Label.new()
	gold_label.position = Vector2(0, 80)
	gold_label.size.x = bg.size.x
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	add_child(gold_label)

	var start_x := 180.0
	for i in range(4):
		var btn := Button.new()
		btn.position = Vector2(start_x + i * 240, 200)
		btn.size = Vector2(200, 180)
		btn.add_theme_font_size_override("font_size", 13)
		var idx := i
		btn.pressed.connect(func(): _on_purchase(idx))
		add_child(btn)
		option_buttons.append(btn)

	skip_btn = Button.new()
	skip_btn.position = Vector2(0, 420)
	skip_btn.size = Vector2(160, 40)
	skip_btn.position.x = (bg.size.x - skip_btn.size.x) / 2
	skip_btn.text = "跳过招募 →"
	skip_btn.add_theme_font_size_override("font_size", 14)
	skip_btn.pressed.connect(_on_skip)
	add_child(skip_btn)

	var hint := Label.new()
	hint.text = "选择一位新队友加入冒险"
	hint.position = Vector2(0, 480)
	hint.size.x = bg.size.x
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(hint)


func _show() -> void:
	_refresh()
	show()


func _refresh() -> void:
	if not roguelike_manager:
		return

	var options := roguelike_manager.recruit_system.get_current_options()
	gold_label.text = "持有金币: %d" % GameManager.gold

	for i in range(4):
		if i < options.size():
			var opt = options[i]
			var ct := ClassDefinitions.get_template(opt.class_id)
			option_buttons[i].text = "%s\nLv.%d\n\n消耗: %d 金币" % [ct.job_name, opt.level, opt.cost]
			option_buttons[i].disabled = GameManager.gold < opt.cost
			option_buttons[i].visible = true
		else:
			option_buttons[i].visible = false


func _on_purchase(index: int) -> void:
	if roguelike_manager:
		if roguelike_manager.purchase_recruit(index):
			_refresh()
			recruit_purchased.emit()
			_on_skip()


func _on_skip() -> void:
	hide()
	if roguelike_manager:
		roguelike_manager.skip_recruit()
	recruit_skipped.emit()
