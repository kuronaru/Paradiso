# unit_ai.gd — 单位AI控制器
# 自走棋风格：自动索敌、移动、攻击
class_name UnitAI
extends Node

const M = "AI"

var owner_unit: UnitBase = null
var state: String = "idle"       # idle | moving | attacking
var path: Array = []
var path_progress: float = 0.0
var move_target_pos: Vector2 = Vector2.ZERO
var target_recheck_timer: float = 0.0
const TARGET_RECHECK_INTERVAL: float = 1.0


func execute(delta: float) -> void:
	if not owner_unit or not owner_unit.is_alive:
		return

	match state:
		"idle":
			_on_idle(delta)
		"moving":
			_on_moving(delta)
		"attacking":
			_on_attacking(delta)


func _on_idle(_delta: float) -> void:
	_find_target()
	if owner_unit.target and is_instance_valid(owner_unit.target):
		var dist := _distance_to(owner_unit.target)
		if dist <= owner_unit.attack_range:
			state = "attacking"
		elif owner_unit.move_speed > 0:
			_start_move_toward(owner_unit.target)
	elif owner_unit.move_speed > 0 and owner_unit.stance != UnitBase.Stance.STATIONED:
		# 没有目标时向敌人方向移动
		_move_forward()


func _on_moving(delta: float) -> void:
	if path.is_empty():
		state = "idle"
		return

	var grid: GridSystem = BattleManager.grid
	if not grid:
		return

	var target_world := grid.grid_to_world(move_target_pos)
	var current_pos := owner_unit.global_position
	var move_dist := owner_unit.move_speed * delta * grid.cell_size

	if current_pos.distance_to(target_world) <= move_dist + 1.0:
		# 到达目标格子
		grid.move_unit(owner_unit, move_target_pos)
		owner_unit.global_position = grid.grid_to_world(move_target_pos)
		path.pop_front()
		if path.is_empty():
			state = "idle"
		else:
			move_target_pos = path[0]
	else:
		var dir := (target_world - current_pos).normalized()
		owner_unit.global_position += dir * move_dist

	# 移动中检查是否可以攻击
	_find_target()
	if owner_unit.target and is_instance_valid(owner_unit.target):
		if _distance_to(owner_unit.target) <= owner_unit.attack_range:
			path.clear()
			state = "attacking"


func _on_attacking(_delta: float) -> void:
	if not owner_unit.target or not is_instance_valid(owner_unit.target):
		owner_unit.target = null
		state = "idle"
		return

	var dist := _distance_to(owner_unit.target)
	if dist <= owner_unit.attack_range:
		owner_unit.perform_attack()
	elif owner_unit.move_speed > 0:
		_start_move_toward(owner_unit.target)


func _find_target() -> void:
	"""根据职业模板的索敌优先级寻找目标"""
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return

	var enemy_team := "enemy" if owner_unit.team == "player" else "player"
	var candidates := grid.get_units_in_range(owner_unit.grid_position, owner_unit.search_range, enemy_team)

	if candidates.is_empty():
		owner_unit.target = null
		return

	var priority
	if owner_unit.class_template:
		priority = owner_unit.class_template.target_priority
	else:
		priority = ClassTemplate.TargetPriority.NEAREST

	match priority:
		ClassTemplate.TargetPriority.NEAREST:
			owner_unit.target = grid.get_nearest_unit(owner_unit.grid_position, enemy_team)
		ClassTemplate.TargetPriority.LOWEST_HP:
			_select_by(candidates, func(u): return u.current_hp, false)
		ClassTemplate.TargetPriority.HIGHEST_ATK:
			_select_by(candidates, func(u): return u.attack, true)
		ClassTemplate.TargetPriority.FARTHEST:
			_select_by(candidates, func(u): return grid.get_distance(owner_unit.grid_position, u.grid_position), true)
		ClassTemplate.TargetPriority.RANDOM:
			candidates.shuffle()
			owner_unit.target = candidates[0] if not candidates.is_empty() else null


func _select_by(candidates: Array, value_fn: Callable, highest: bool) -> void:
	var best = null
	var best_val = -INF if highest else INF
	for u in candidates:
		var v = value_fn.call(u)
		if (highest and v > best_val) or (not highest and v < best_val):
			best_val = v
			best = u
	owner_unit.target = best


func _distance_to(target: Node) -> float:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return INF
	return grid.get_distance(owner_unit.grid_position, target.grid_position)


func _start_move_toward(target: Node) -> void:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	# 简单的直线移动（不使用复杂寻路）
	var dir: Vector2i = target.grid_position - owner_unit.grid_position
	var step := Vector2i(sign(dir.x), sign(dir.y))
	if step == Vector2i.ZERO:
		state = "attacking"
		return
	var next_pos := owner_unit.grid_position + step
	if grid.is_deploy_zone(next_pos) and grid.is_in_bounds(next_pos) and not grid.is_occupied(next_pos):
		move_target_pos = next_pos
		path = [next_pos]
		state = "moving"
	else:
		# 尝试绕路
		var alts := [
			owner_unit.grid_position + Vector2i(step.x, 0),
			owner_unit.grid_position + Vector2i(0, step.y),
		]
		for alt in alts:
			if alt != next_pos and grid.is_deploy_zone(alt) and grid.is_in_bounds(alt) and not grid.is_occupied(alt):
				move_target_pos = alt
				path = [alt]
				state = "moving"
				return
		state = "idle"


func _move_forward() -> void:
	"""没有目标时向敌方半场推进"""
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	var direction := 1 if owner_unit.team == "player" else -1
	var next_pos := owner_unit.grid_position + Vector2i(direction, 0)
	if grid.is_deploy_zone(next_pos) and grid.is_in_bounds(next_pos) and not grid.is_occupied(next_pos):
		move_target_pos = next_pos
		path = [next_pos]
		state = "moving"
