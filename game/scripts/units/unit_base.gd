# unit_base.gd — 单位基类
# 所有战场单位（玩家角色 + 敌人）的基础抽象
class_name UnitBase
extends Node2D

const M = "Unit"

signal died(unit: Node)
signal hp_changed(current: int, max_hp: int)
signal stance_changed(is_stationed: bool)

enum Stance {
	MARCH,      ## 行进 — 可移动，攻击力降低，范围缩小
	STATIONED   ## 驻扎 — 定身/缓速，防御提升，范围扩大
}

## 网格位置
var grid_position: Vector2i = Vector2i.ZERO

## 基础属性
var unit_name: String = ""
var max_hp: int = 100
var current_hp: int = 100
var attack: int = 10
var defense: int = 5
var attack_speed: float = 1.0
var move_speed: float = 2.0
var attack_range: float = 1.5
var search_range: float = 5.0

## 职业数据
var class_template: ClassTemplate = null

## 当前姿态
var stance: Stance = Stance.MARCH
var target: Node = null
var is_alive: bool = true

## 冷却计时器
var attack_cooldown: float = 0.0
var skill_cooldowns: Dictionary = {}  # {skill_id: remaining_time}

## 团队标识
@export var team: String = "player"   # "player" | "enemy"

## AI控制器
var ai_controller: UnitAI = null
## AI是否启用（静态部署时为false，波次开始后激活）
var ai_enabled: bool = true

## 可视化（占位）
@export var color: Color = Color.WHITE
@export var unit_radius: float = 24.0
@export var floating_number_rise: float = 28.0
@export var floating_number_duration: float = 0.65
## 血条节点
var hp_bar_bg: ColorRect = null
var hp_bar_fill: ColorRect = null


func _ready() -> void:
	_setup_visual()
	_setup_ai()
	hp_changed.connect(_update_hp_bar)
	_update_hp_bar(current_hp, max_hp)


func _process(delta: float) -> void:
	if not is_alive:
		return
	# 更新冷却
	if attack_cooldown > 0:
		attack_cooldown -= delta
	for skill_id in skill_cooldowns:
		skill_cooldowns[skill_id] = max(0.0, skill_cooldowns[skill_id] - delta)
	# 执行AI（仅在启用时）
	if ai_enabled and ai_controller:
		ai_controller.execute(delta)


func setup(class_data: ClassTemplate, lvl: int = 1) -> void:
	"""从职业模板初始化"""
	class_template = class_data
	unit_name = class_data.job_name
	max_hp = class_data.base_hp
	current_hp = max_hp
	attack = class_data.base_atk
	defense = class_data.base_def
	attack_speed = class_data.attack_speed
	move_speed = class_data.move_speed
	attack_range = class_data.attack_range
	search_range = class_data.search_range
	# 初始化技能冷却
	for sid in class_data.skill_ids:
		skill_cooldowns[sid] = 0.0


func _setup_visual() -> void:
	"""创建基本的占位可视化（含血条）"""
	var bar_width := unit_radius * 2.0
	var bar_height := 6.0
	var bar_y := -unit_radius - bar_height - 4.0

	# 血条背景
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.size = Vector2(bar_width, bar_height)
	hp_bar_bg.position = Vector2(-unit_radius, bar_y)
	hp_bar_bg.color = Color(0.15, 0.15, 0.15, 0.85)
	add_child(hp_bar_bg)

	# 血条填充
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.size = Vector2(bar_width, bar_height)
	hp_bar_fill.position = Vector2(-unit_radius, bar_y)
	# 颜色在 _update_hp_bar 中根据 team 设置
	add_child(hp_bar_fill)

	# 单位方块
	var rect := ColorRect.new()
	rect.size = Vector2(unit_radius * 2, unit_radius * 2)
	rect.position = -Vector2(unit_radius, unit_radius)
	rect.color = color
	add_child(rect)

	# 名称标签
	var label := Label.new()
	label.text = unit_name
	label.add_theme_font_size_override("font_size", 10)
	label.position = Vector2(-20, unit_radius + 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


func _setup_ai() -> void:
	ai_controller = UnitAI.new()
	ai_controller.owner_unit = self
	add_child(ai_controller)


func _update_hp_bar(_current: int, _max_hp: int) -> void:
	"""更新血条显示"""
	if not hp_bar_fill:
		return
	var ratio: float = clamp(float(current_hp) / max(max_hp, 1), 0.0, 1.0)
	hp_bar_fill.size.x = unit_radius * 2.0 * ratio
	# 玩家蓝色，敌人红色
	if team == "player":
		hp_bar_fill.color = Color(0.25, 0.6, 1.0, 0.9)
	else:
		hp_bar_fill.color = Color(1.0, 0.2, 0.2, 0.9)


func get_team() -> String:
	return team


func take_damage(amount: int) -> void:
	"""受到伤害"""
	var actual: int = max(1, amount - defense)
	current_hp -= actual
	_show_floating_number(-actual, Color(1.0, 0.2, 0.2, 1.0))
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		current_hp = 0
		_die()


func heal(amount: int) -> void:
	"""恢复生命"""
	var actual: int = min(amount, max_hp - current_hp)
	if actual <= 0:
		return
	current_hp += actual
	_show_floating_number(actual, Color(0.2, 1.0, 0.35, 1.0))
	hp_changed.emit(current_hp, max_hp)


func _show_floating_number(amount: int, text_color: Color) -> void:
	"""显示伤害/治疗飘字：从单位中心向上跳起后淡出"""
	var label := Label.new()
	label.text = "%+d" % amount
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(unit_radius * 3.0, 28.0)
	label.position = -label.size * 0.5
	label.z_index = 100
	add_child(label)

	var start_pos := label.position
	var end_pos := start_pos + Vector2(0.0, -floating_number_rise)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", end_pos, floating_number_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, floating_number_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(label.queue_free)


func _die() -> void:
	is_alive = false
	died.emit(self)
	if team == "player":
		BattleManager.unregister_player_unit(self)
	else:
		BattleManager.unregister_enemy_unit(self)
	# 死亡后延迟移除
	var timer := get_tree().create_timer(0.3)
	timer.timeout.connect(_remove_from_grid)


func activate_ai() -> void:
	"""激活AI行为（波次开始/实时部署时调用）"""
	ai_enabled = true


func deactivate_ai() -> void:
	"""暂停AI行为（静态部署时调用）"""
	ai_enabled = false


func _remove_from_grid() -> void:
	var g: GridSystem = BattleManager.grid
	if g:
		g.remove_unit(self)
	queue_free()


func toggle_stance() -> void:
	"""切换行进/驻扎状态"""
	if stance == Stance.MARCH:
		stance = Stance.STATIONED
		# 应用驻扎修正
		if class_template:
			defense = int(class_template.base_def * class_template.stance_defense_bonus)
			attack_range = class_template.attack_range * class_template.stance_range_bonus
			if class_template.stance_is_rooted:
				move_speed = 0.0
	else:
		stance = Stance.MARCH
		# 恢复行进修正
		if class_template:
			defense = class_template.base_def
			attack_range = class_template.attack_range
			move_speed = class_template.move_speed * class_template.march_move_speed_bonus
			attack = int(class_template.base_atk * class_template.march_attack_penalty)
	stance_changed.emit(stance == Stance.STATIONED)


func use_skill(skill_id: String) -> bool:
	"""使用技能"""
	var sd := SkillData.get_skill(skill_id)
	if not sd:
		return false
	if skill_cooldowns.get(skill_id, 0.0) > 0:
		return false
	if not ResourceManager.spend(sd.dp_cost):
		return false
	# 执行技能效果
	_execute_skill(sd)
	skill_cooldowns[skill_id] = sd.cooldown
	return true


func _execute_skill(sd: SkillData) -> void:
	"""执行技能逻辑"""
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return

	if sd.damage_multiplier > 0:
		# 伤害技能
		if sd.aoe_radius > 0:
			# AOE伤害
			var targets := grid.get_units_in_range(grid_position, sd.aoe_radius, _enemy_team())
			for t in targets:
				if t.has_method("take_damage"):
					t.take_damage(int(attack * sd.damage_multiplier))
		else:
			# 单体伤害
			if target and is_instance_valid(target) and target.has_method("take_damage"):
				target.take_damage(int(attack * sd.damage_multiplier))

	if sd.heal_amount > 0:
		# 治疗技能
		var targets := grid.get_units_in_range(grid_position, sd.aoe_radius, team)
		for t in targets:
			if t.has_method("heal"):
				t.heal(int(attack * sd.heal_amount))

	if sd.buff_defense > 0:
		# Buff技能
		defense = int(defense * sd.buff_defense)
		if sd.duration > 0:
			var timer := get_tree().create_timer(sd.duration)
			timer.timeout.connect(func(): defense = class_template.base_def if class_template else defense)

	if sd.duration > 0 and sd.buff_defense == 0:
		# 通用持续效果
		pass

	Log.i(M, "[%s] 使用了技能: %s" % [unit_name, sd.skill_name])


func _enemy_team() -> String:
	return "enemy" if team == "player" else "player"


func perform_attack() -> void:
	"""执行普攻"""
	if attack_cooldown > 0:
		return
	if not target or not is_instance_valid(target):
		return
	var interval := class_template.get_attack_speed_interval() if class_template else 1.0
	attack_cooldown = interval

	if class_template and class_template.attack_mode == ClassTemplate.AttackMode.HEAL:
		if target.has_method("heal"):
			target.heal(attack)
	else:
		if target.has_method("take_damage"):
			target.take_damage(attack)
