# hero_unit.gd — 玩家英雄单位
class_name HeroUnit
extends UnitBase

var deploy_cost: int = 10
var is_selected: bool = false

@export var hero_color: Color = Color(0.3, 0.6, 1.0)


func _ready() -> void:
	team = "player"
	super._ready()


func setup(class_data: ClassTemplate, lvl: int = 1) -> void:
	super.setup(class_data, lvl)
	deploy_cost = class_data.deploy_cost
	color = hero_color
	for child in get_children():
		if child is ColorRect:
			child.color = color
	BattleManager.register_player_unit(self)

	# 根据战斗状态决定初始AI行为
	# PREPARING → 静态部署（角色静止）
	# IN_PROGRESS / WAVE_BREAK → 实时部署（立即行动）
	match BattleManager.state:
		BattleManager.BattleState.PREPARING:
			deactivate_ai()
		_:
			activate_ai()


func _unhandled_input(event: InputEvent) -> void:
	if not is_selected or not is_alive:
		return
	if not (event is InputEventKey and event.pressed):
		return

	match event.keycode:
		KEY_Q:
			var skills := class_template.skill_ids
			if skills.size() >= 1:
				use_skill(skills[0])
		KEY_W:
			var skills := class_template.skill_ids
			if skills.size() >= 2:
				use_skill(skills[1])
		KEY_E:
			var skills := class_template.skill_ids
			if skills.size() >= 3:
				use_skill(skills[2])
		KEY_SPACE:
			toggle_stance()
		KEY_R:
			retreat()


func toggle_stance() -> void:
	super.toggle_stance()
	Log.d(M, "[%s] 切换姿态: %s" % [unit_name, "驻扎" if stance == Stance.STATIONED else "行进"])


func retreat() -> void:
	if not is_alive:
		return
	var refund_amount := int(deploy_cost * 0.5)
	ResourceManager.refund(refund_amount)
	Log.i(M, "[%s] 撤退，返还 %d DP" % [unit_name, refund_amount])
	BattleManager.unregister_player_unit(self)
	var grid: GridSystem = BattleManager.grid
	if grid:
		grid.remove_unit(self)
	queue_free()
