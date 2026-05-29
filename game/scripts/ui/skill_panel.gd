# skill_panel.gd — 选中角色技能/操作面板
# 显示选中单位的技能按钮、姿态切换、撤退按钮
class_name SkillPanel
extends Control

var selected_unit: HeroUnit = null
var skill_buttons: Array[Button] = []
var stance_btn: Button
var retreat_btn: Button
var info_label: Label
var deployment_system: DeploymentSystem = null

@export var panel_width: float = 220.0


func _ready() -> void:
	# 连接DeploymentSystem
	var tree := get_tree()
	if tree:
		var nodes := tree.get_nodes_in_group("deployment_system")
		if nodes.size() > 0:
			deployment_system = nodes[0]
			deployment_system.unit_selected.connect(_on_unit_selected)
			deployment_system.unit_deselected.connect(_on_unit_deselected)

	_setup_ui()
	_update_visibility()


func _setup_ui() -> void:
	# 面板背景
	var bg := ColorRect.new()
	bg.size = Vector2(panel_width, size.y)
	bg.position = Vector2(size.x - panel_width, 0)
	bg.color = Color(0.1, 0.1, 0.15, 0.85)
	add_child(bg)

	# 信息标签
	info_label = Label.new()
	info_label.position = Vector2(size.x - panel_width + 10, 10)
	info_label.size = Vector2(panel_width - 20, 150)
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(info_label)

	# 技能按钮
	var btn_y := 170.0
	for i in range(3):
		var btn := Button.new()
		btn.position = Vector2(size.x - panel_width + 10, btn_y + i * 38)
		btn.size = Vector2(panel_width - 20, 32)
		btn.text = "技能 %d" % (i + 1)
		btn.add_theme_font_size_override("font_size", 12)
		var skill_idx := i
		btn.pressed.connect(func(): _on_skill_pressed(skill_idx))
		add_child(btn)
		skill_buttons.append(btn)

	# 姿态切换按钮
	stance_btn = Button.new()
	stance_btn.position = Vector2(size.x - panel_width + 10, btn_y + 3 * 38 + 10)
	stance_btn.size = Vector2(panel_width - 20, 32)
	stance_btn.text = "切换姿态 [Space]"
	stance_btn.add_theme_font_size_override("font_size", 12)
	stance_btn.pressed.connect(_on_stance_pressed)
	add_child(stance_btn)

	# 撤退按钮
	retreat_btn = Button.new()
	retreat_btn.position = Vector2(size.x - panel_width + 10, btn_y + 4 * 38 + 10)
	retreat_btn.size = Vector2(panel_width - 20, 32)
	retreat_btn.text = "撤退 [R]"
	retreat_btn.add_theme_font_size_override("font_size", 12)
	retreat_btn.pressed.connect(_on_retreat_pressed)
	add_child(retreat_btn)


func _on_unit_selected(unit: HeroUnit) -> void:
	selected_unit = unit
	_update_visibility()
	_update_skills()
	_update_info()


func _on_unit_deselected() -> void:
	selected_unit = null
	_update_visibility()


func _update_visibility() -> void:
	visible = selected_unit != null and is_instance_valid(selected_unit)


func _update_info() -> void:
	if not selected_unit:
		return
	var ct := selected_unit.class_template
	var stance_text := "行进" if selected_unit.stance == UnitBase.Stance.MARCH else "驻扎"
	info_label.text = """%s (Lv.%d)
HP: %d/%d
ATK: %d  DEF: %d
射程: %.1f  速度: %.1f
姿态: %s
""" % [ct.job_name, 1,
	selected_unit.current_hp, selected_unit.max_hp,
	selected_unit.attack, selected_unit.defense,
	selected_unit.attack_range, selected_unit.move_speed,
	stance_text]


func _update_skills() -> void:
	if not selected_unit:
		return
	var skills: Array = selected_unit.class_template.skill_ids
	for i in range(3):
		if i < skills.size():
			var sd: SkillData = SkillData.get_skill(skills[i] as String)
			var cd: float = selected_unit.skill_cooldowns.get(skills[i], 0.0)
			if cd > 0:
				skill_buttons[i].text = "%s (CD:%.0f)" % [sd.skill_name, cd]
				skill_buttons[i].disabled = true
			else:
				skill_buttons[i].text = "%s [%s] DP:%d" % [sd.skill_name, ["Q", "W", "E"][i], sd.dp_cost]
				skill_buttons[i].disabled = false
		else:
			skill_buttons[i].text = "---"
			skill_buttons[i].disabled = true


func _on_skill_pressed(index: int) -> void:
	if deployment_system:
		deployment_system.use_selected_skill(index)
	_update_skills()
	_update_info()


func _on_stance_pressed() -> void:
	if deployment_system:
		deployment_system.toggle_selected_stance()
	_update_info()


func _on_retreat_pressed() -> void:
	if deployment_system:
		deployment_system.retreat_selected()
	_update_visibility()


func _process(_delta: float) -> void:
	if selected_unit and is_instance_valid(selected_unit):
		_update_skills()
		_update_info()
