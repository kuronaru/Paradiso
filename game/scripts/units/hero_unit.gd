# hero_unit.gd — 玩家英雄单位
class_name HeroUnit
extends UnitBase

var deploy_cost: int = 10
var is_selected: bool = false
var star_level: int = 1
var deployed_grid_position: Vector2i = Vector2i.ZERO
var run_card_data: Dictionary = {}

@export var hero_color: Color = Color(0.3, 0.6, 1.0)


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	team = "player"
	super._ready()


## 初始化单位或组件数据。
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


## 处理未被界面消费的输入事件。
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


## 切换姿态。
func toggle_stance() -> void:
	super.toggle_stance()
	Log.d(M, "[%s] 切换姿态: %s" % [unit_name, "驻扎" if stance == Stance.STATIONED else "行进"])


## 标记英雄的部署卡牌和格子。
func mark_deployed(card_data: Dictionary, grid_pos: Vector2i) -> void:
	run_card_data = card_data.duplicate(true)
	deployed_grid_position = grid_pos


## 准备单位进入下一回合。
func prepare_for_next_round() -> void:
	is_alive = true
	visible = true
	modulate = Color.WHITE
	target = null
	attack_cooldown = 0.0
	clear_combat_statuses()
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
	deactivate_ai()
	if ai_controller and ai_controller.has_method("reset_ai_state"):
		ai_controller.reset_ai_state()


## 战斗中被击倒：保留部署身份，等待准备阶段恢复。
func _die() -> void:
	if not is_alive:
		return

	is_alive = false
	target = null
	current_hp = 0
	hp_changed.emit(current_hp, max_hp)
	deactivate_ai()
	if ai_controller and ai_controller.has_method("reset_ai_state"):
		ai_controller.reset_ai_state()
	_clear_grid_presence()
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 0.35)
	died.emit(self)
	BattleManager.unit_died.emit(self)
	BattleManager.check_battle_end()


## 清理击倒英雄的战场占位。
func _clear_grid_presence() -> void:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	for occupied_pos in grid.occupancy.keys():
		if grid.occupancy[occupied_pos] == self:
			grid.free_cell(occupied_pos)
	grid.release_move_reservation(self)


## 撤回已部署英雄。
func retreat() -> void:
	if not is_alive:
		return
	var refund_amount := int(deploy_cost * _cfg_float("retreat_refund_ratio", 0.5))
	ResourceManager.refund(refund_amount)
	Log.i(M, "[%s] 撤退，返还 %d DP" % [unit_name, refund_amount])
	BattleManager.unregister_player_unit(self)
	BattleManager.unit_retreated.emit(self)
	var grid: GridSystem = BattleManager.grid
	if grid:
		grid.remove_unit(self)
	queue_free()


func _cfg_float(key: String, default_value: float) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var registry := tree.root.get_node_or_null("DataRegistry")
		if registry and registry.has_method("get_config"):
			return float(registry.get_config(key, default_value))
	return default_value
