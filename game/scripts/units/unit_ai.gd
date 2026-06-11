# unit_ai.gd — 单位AI控制器
# 自走棋风格：自动索敌、移动、攻击
class_name UnitAI
extends Node

const M = "AI"

var owner_unit: UnitBase = null
var state: String = "idle"       # idle | moving | attacking
var path: Array = []
var path_progress: float = 0.0
var move_target_pos: Vector2i = Vector2i.ZERO
var move_origin_pos: Vector2i = Vector2i.ZERO
var target_recheck_timer: float = 0.0
const TARGET_RECHECK_INTERVAL: float = 1.0


func reset_ai_state() -> void:
	var grid: GridSystem = BattleManager.grid
	if owner_unit and owner_unit.is_moving() and grid:
		grid.cancel_unit_move(owner_unit, owner_unit.movement_origin_grid_position)
	state = "idle"
	path.clear()
	path_progress = 0.0
	move_target_pos = Vector2i.ZERO
	target_recheck_timer = 0.0


func execute(delta: float) -> void:
	if not owner_unit or not owner_unit.is_alive:
		return
	if owner_unit.is_moving() and state != "moving":
		state = "moving"

	match state:
		"idle":
			_on_idle(delta)
		"moving":
			_on_moving(delta)
		"attacking":
			_on_attacking(delta)


func _on_idle(delta: float) -> void:
	_update_continuous_grid_position()
	_find_target()
	if owner_unit.target and is_instance_valid(owner_unit.target):
		if _is_in_attack_range(owner_unit.target):
			state = "attacking"
		elif _uses_continuous_enemy_movement():
			_move_enemy_toward(owner_unit.target, delta)
		elif owner_unit.move_speed > 0:
			_start_move_toward(owner_unit.target)
	elif owner_unit.move_speed > 0 and owner_unit.stance != UnitBase.Stance.STATIONED:
		# 没有目标时向敌人方向移动
		if _uses_continuous_enemy_movement():
			_move_enemy_forward(delta)
		else:
			_move_forward()


func _on_moving(delta: float) -> void:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	if not owner_unit.is_moving():
		state = "idle"
		return

	var target_grid := owner_unit.movement_target_grid_position
	var target_world := grid.grid_to_world(target_grid)
	var current_pos := owner_unit.global_position
	var move_dist := owner_unit.move_speed * delta * grid.cell_size

	if current_pos.distance_to(target_world) <= move_dist + 1.0:
		# 到达目标格子
		var target_ground := target_world + owner_unit.ground_anchor_offset
		if grid.would_unit_collide_on_segment(owner_unit, owner_unit.get_ground_position(), target_ground, owner_unit.team):
			grid.cancel_unit_move(owner_unit, owner_unit.movement_origin_grid_position)
		else:
			grid.finish_unit_move(owner_unit, target_grid)
		path.clear()
		state = "idle"
	else:
		var dir := (target_world - current_pos).normalized()
		var next_pos := owner_unit.global_position + dir * move_dist
		var next_ground := next_pos + owner_unit.ground_anchor_offset
		if grid.would_unit_collide_on_segment(owner_unit, owner_unit.get_ground_position(), next_ground, owner_unit.team):
			grid.cancel_unit_move(owner_unit, owner_unit.movement_origin_grid_position)
			path.clear()
			state = "idle"
			return
		owner_unit.global_position = next_pos
		if _resolve_player_collision_during_move(grid):
			return

	# 移动中检查是否可以攻击
	_find_target()
	if owner_unit.target and is_instance_valid(owner_unit.target):
		if owner_unit.is_standing() and _is_in_attack_range(owner_unit.target):
			path.clear()
			state = "attacking"


func _on_attacking(_delta: float) -> void:
	if not owner_unit.target or not is_instance_valid(owner_unit.target):
		owner_unit.target = null
		state = "idle"
		return

	if _is_in_attack_range(owner_unit.target):
		owner_unit.perform_attack()
	elif _uses_continuous_enemy_movement():
		_move_enemy_toward(owner_unit.target, _delta)
	elif owner_unit.move_speed > 0:
		_start_move_toward(owner_unit.target)


func _find_target() -> void:
	"""根据职业模板的索敌优先级寻找目标"""
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	_update_continuous_grid_position()

	var target_team := _get_target_team()
	var candidates := grid.get_units_in_range(owner_unit.grid_position, owner_unit.search_range, target_team)
	if _is_healer():
		candidates = candidates.filter(func(u): return u != owner_unit and u.current_hp < u.max_hp)

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
			if _is_healer():
				_select_by(candidates, func(u): return u.current_hp, false)
			else:
				owner_unit.target = grid.get_nearest_unit(owner_unit.grid_position, target_team)
		ClassTemplate.TargetPriority.LOWEST_HP:
			_select_by(candidates, func(u): return u.current_hp, false)
		ClassTemplate.TargetPriority.HIGHEST_ATK:
			_select_by(candidates, func(u): return u.attack, true)
		ClassTemplate.TargetPriority.FARTHEST:
			_select_by(candidates, func(u): return grid.get_distance(owner_unit.grid_position, u.grid_position), true)
		ClassTemplate.TargetPriority.RANDOM:
			candidates.shuffle()
			owner_unit.target = candidates[0] if not candidates.is_empty() else null


func _is_healer() -> bool:
	return owner_unit.class_template and owner_unit.class_template.attack_mode == ClassTemplate.AttackMode.HEAL


func _get_target_team() -> String:
	if _is_healer():
		return owner_unit.team
	return "enemy" if owner_unit.team == "player" else "player"


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
	if owner_unit is UnitBase and target is UnitBase:
		return owner_unit.get_ground_position().distance_to((target as UnitBase).get_ground_position()) / maxf(grid.cell_size, 1.0)
	return grid.get_distance(owner_unit.grid_position, target.grid_position)


func _is_in_attack_range(target: Node) -> bool:
	if not target or not is_instance_valid(target):
		return false
	if owner_unit is UnitBase and target is UnitBase:
		var target_unit := target as UnitBase
		if owner_unit.is_touching_unit(target_unit):
			return true
		if _requires_contact_attack():
			return false
	return _distance_to(target) <= owner_unit.attack_range


func _requires_contact_attack() -> bool:
	if not (owner_unit is EnemyUnit):
		return false
	var enemy := owner_unit as EnemyUnit
	return enemy.enemy_type in [
		EnemyUnit.EnemyType.MELEE,
		EnemyUnit.EnemyType.BRUTE,
	]


func _uses_continuous_enemy_movement() -> bool:
	return owner_unit is EnemyUnit


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
	move_origin_pos = owner_unit.grid_position
	var next_pos := owner_unit.grid_position + step
	if grid.begin_unit_move(owner_unit, next_pos):
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
			if alt != next_pos and grid.begin_unit_move(owner_unit, alt):
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
	if grid.begin_unit_move(owner_unit, next_pos):
		move_origin_pos = owner_unit.grid_position
		move_target_pos = next_pos
		path = [next_pos]
		state = "moving"


func _move_enemy_toward(target: Node, delta: float) -> void:
	if not (target is UnitBase):
		state = "idle"
		return
	var target_unit := target as UnitBase
	if owner_unit.is_touching_unit(target_unit):
		state = "attacking"
		return
	var dir := target_unit.get_ground_position() - owner_unit.get_ground_position()
	if dir.length_squared() <= 0.01:
		state = "attacking"
		return
	var speed_px := owner_unit.move_speed * _cell_size()
	var distance := dir.length()
	var contact_distance := owner_unit.get_collision_radius() + target_unit.get_collision_radius()
	var travel := minf(speed_px * delta, maxf(0.0, distance - contact_distance))
	if travel > 0.0:
		owner_unit.global_position += dir.normalized() * travel
	if owner_unit.is_touching_unit(target_unit):
		state = "attacking"
	else:
		var contacts: Array = BattleManager.grid.get_touching_units(owner_unit, "player") if BattleManager.grid else []
		if not contacts.is_empty():
			owner_unit.target = contacts[0]
			state = "attacking"
		else:
			state = "idle"
	_update_continuous_grid_position()


func _move_enemy_forward(delta: float) -> void:
	var old_pos := owner_unit.global_position
	var direction := Vector2(-1.0, 0.0)
	owner_unit.global_position += direction * owner_unit.move_speed * _cell_size() * delta
	var contacts: Array = BattleManager.grid.get_touching_units(owner_unit, "player") if BattleManager.grid else []
	if not contacts.is_empty():
		owner_unit.global_position = old_pos
		owner_unit.target = contacts[0]
		state = "attacking"
	_update_continuous_grid_position()


func _resolve_player_collision_during_move(grid: GridSystem) -> bool:
	if owner_unit.team != "player":
		return false
	var contacts := grid.get_touching_units(owner_unit, "enemy")
	if contacts.is_empty():
		return false
	grid.cancel_unit_move(owner_unit, owner_unit.movement_origin_grid_position)
	path.clear()
	state = "idle"
	return true


func _update_continuous_grid_position() -> void:
	if not _uses_continuous_enemy_movement():
		return
	var grid: GridSystem = BattleManager.grid
	if grid:
		owner_unit.grid_position = grid.world_to_grid(owner_unit.get_ground_position())


func _cell_size() -> float:
	var grid: GridSystem = BattleManager.grid
	return grid.cell_size if grid else 64.0
