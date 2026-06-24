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
var wait_retry_timer: float = 0.0
const TARGET_RECHECK_INTERVAL: float = 1.0
const WAIT_RETRY_INTERVAL: float = 0.35


## 重置AI状态。
func reset_ai_state() -> void:
	var grid: GridSystem = BattleManager.grid
	if owner_unit and owner_unit.is_moving() and grid:
		grid.cancel_unit_move(owner_unit, owner_unit.movement_origin_grid_position)
	elif owner_unit and owner_unit.is_waiting():
		owner_unit.finish_grid_move(owner_unit.grid_position)
	state = "idle"
	path.clear()
	path_progress = 0.0
	move_target_pos = Vector2i.ZERO
	target_recheck_timer = 0.0
	wait_retry_timer = 0.0


## 处理force攻击目标逻辑。
func force_attack_target(target_unit: Node) -> void:
	if not owner_unit or not target_unit or not is_instance_valid(target_unit):
		return
	owner_unit.target = target_unit
	path.clear()
	path_progress = 0.0
	target_recheck_timer = 0.0
	wait_retry_timer = 0.0
	state = "attacking"


## 执行当前 AI 行为。
func execute(delta: float) -> void:
	if not owner_unit or not owner_unit.is_alive:
		return
	if owner_unit.is_moving() and state != "moving":
		state = "moving"
	elif owner_unit.is_waiting() and state != "waiting":
		state = "waiting"

	match state:
		"idle":
			_on_idle(delta)
		"moving":
			_on_moving(delta)
		"waiting":
			_on_waiting(delta)
		"attacking":
			_on_attacking(delta)


## 处理 AI 空闲状态。
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


## 处理 AI 移动状态。
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
		var attack_entry_target := _get_attack_entry_target(target_ground)
		if grid.would_unit_collide_on_segment(owner_unit, owner_unit.get_ground_position(), target_ground, owner_unit.team, target_grid):
			_enter_waiting()
		else:
			grid.finish_unit_move(owner_unit, target_grid)
			if not path.is_empty() and path[0] == target_grid:
				path.pop_front()
			if attack_entry_target and is_instance_valid(attack_entry_target):
				var pushed_enemies := grid.push_enemies_overlapping_hero_target(owner_unit, target_grid)
				force_attack_target(attack_entry_target)
				if attack_entry_target in pushed_enemies and attack_entry_target.ai_controller:
					attack_entry_target.ai_controller.force_attack_target(owner_unit)
				return
		if state != "waiting":
			if not path.is_empty() and _try_start_next_path_step():
				return
			state = "idle"
	else:
		var dir := (target_world - current_pos).normalized()
		var next_pos := owner_unit.global_position + dir * move_dist
		var next_ground := next_pos + owner_unit.ground_anchor_offset
		if grid.would_unit_collide_on_segment(owner_unit, owner_unit.get_ground_position(), next_ground, owner_unit.team, target_grid):
			_enter_waiting()
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


## 处理 AI 等待状态。
func _on_waiting(delta: float) -> void:
	if _uses_continuous_enemy_movement():
		state = "idle"
		return
	_find_target()
	if owner_unit.target and is_instance_valid(owner_unit.target) and _is_in_attack_range(owner_unit.target):
		owner_unit.finish_grid_move(owner_unit.grid_position)
		path.clear()
		state = "attacking"
		return
	if not owner_unit.target or not is_instance_valid(owner_unit.target):
		owner_unit.finish_grid_move(owner_unit.grid_position)
		path.clear()
		state = "idle"
		return
	wait_retry_timer -= delta
	if wait_retry_timer > 0.0:
		return
	wait_retry_timer = WAIT_RETRY_INTERVAL
	path = _build_path_to_target(owner_unit.target)
	if not path.is_empty() and _try_start_next_path_step():
		return


## 处理 AI 攻击状态。
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


## 根据职业模板的索敌优先级寻找目标
func _find_target() -> void:
	"""根据职业模板的索敌优先级寻找目标"""
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	_update_continuous_grid_position()

	var target_team := _get_target_team()
	var search_center := grid.world_to_grid(owner_unit.get_ground_position())
	var candidates := grid.get_units_in_range(search_center, owner_unit.search_range, target_team)
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
				owner_unit.target = grid.get_nearest_unit(search_center, target_team)
		ClassTemplate.TargetPriority.LOWEST_HP:
			_select_by(candidates, func(u): return u.current_hp, false)
		ClassTemplate.TargetPriority.HIGHEST_ATK:
			_select_by(candidates, func(u): return u.attack, true)
		ClassTemplate.TargetPriority.FARTHEST:
			_select_by(candidates, func(u): return grid.get_distance(search_center, u.grid_position), true)
		ClassTemplate.TargetPriority.RANDOM:
			candidates.shuffle()
			owner_unit.target = candidates[0] if not candidates.is_empty() else null


## 判断治疗者状态。
func _is_healer() -> bool:
	return owner_unit.class_template and owner_unit.class_template.attack_mode == ClassTemplate.AttackMode.HEAL


## 获取目标队伍。
func _get_target_team() -> String:
	if _is_healer():
		return owner_unit.team
	return "enemy" if owner_unit.team == "player" else "player"


## 按指定评分函数选择目标。
func _select_by(candidates: Array, value_fn: Callable, highest: bool) -> void:
	var best = null
	var best_val = -INF if highest else INF
	for u in candidates:
		var v = value_fn.call(u)
		if (highest and v > best_val) or (not highest and v < best_val):
			best_val = v
			best = u
	owner_unit.target = best


## 计算到目标的距离。
func _distance_to(target: Node) -> float:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return INF
	if owner_unit is UnitBase and target is UnitBase:
		return owner_unit.get_ground_position().distance_to((target as UnitBase).get_ground_position()) / maxf(grid.cell_size, 1.0)
	return grid.get_distance(owner_unit.grid_position, target.grid_position)


## 判断攻击范围状态。
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


## 获取攻击入口目标。
func _get_attack_entry_target(entry_ground_position: Vector2) -> UnitBase:
	if not owner_unit.target or not is_instance_valid(owner_unit.target):
		return null
	if not (owner_unit.target is UnitBase):
		return null

	var target_unit := owner_unit.target as UnitBase
	if not target_unit.is_alive or target_unit.get_team() == owner_unit.get_team():
		return null
	if _would_attack_from_ground_position(target_unit, entry_ground_position):
		return target_unit
	return null


## 判断在指定地面位置是否能攻击目标。
func _would_attack_from_ground_position(target_unit: UnitBase, entry_ground_position: Vector2) -> bool:
	if not target_unit or not is_instance_valid(target_unit):
		return false
	var distance := entry_ground_position.distance_to(target_unit.get_ground_position())
	var touching_distance := owner_unit.get_collision_radius() + target_unit.get_collision_radius()
	if distance <= touching_distance:
		return true
	return distance / _cell_size() <= owner_unit.attack_range


## 判断单位是否需要接触目标才能攻击。
func _requires_contact_attack() -> bool:
	return false


## 判断敌人是否使用连续移动。
func _uses_continuous_enemy_movement() -> bool:
	return owner_unit is EnemyUnit


## 开始向目标移动。
func _start_move_toward(target: Node) -> void:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	if not (target is UnitBase):
		state = "idle"
		return
	if _is_in_attack_range(target):
		state = "attacking"
		return
	path = _build_path_to_target(target as UnitBase)
	if path.is_empty() or not _try_start_next_path_step():
		_enter_waiting()


## 没有目标时向敌方半场推进
func _move_forward() -> void:
	"""没有目标时向敌方半场推进"""
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	var direction := 1 if owner_unit.team == "player" else -1
	var next_pos := owner_unit.grid_position + Vector2i(direction, 0)
	path = [next_pos] if grid.can_reserve_move_target(next_pos, owner_unit) else []
	if path.is_empty() or not _try_start_next_path_step():
		_enter_waiting()


## 构建前往目标的路径。
func _build_path_to_target(target_unit: UnitBase) -> Array:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return []
	return grid.find_path_to_attack_position(owner_unit.grid_position, target_unit, owner_unit.attack_range, owner_unit)


## 尝试开始路径中的下一步移动。
func _try_start_next_path_step() -> bool:
	var grid: GridSystem = BattleManager.grid
	if not grid or path.is_empty():
		return false
	var next_pos: Vector2i = path[0]
	var detour_pos := grid.find_diagonal_move_detour(owner_unit, owner_unit.grid_position, next_pos)
	if detour_pos != GridSystem.INVALID_GRID_POS:
		path.insert(0, detour_pos)
		next_pos = detour_pos
	if grid.would_unit_collide_on_segment(
		owner_unit,
		owner_unit.get_ground_position(),
		grid.grid_to_world(next_pos) + owner_unit.ground_anchor_offset,
		owner_unit.team,
		next_pos
	):
		return false
	if not grid.begin_unit_move(owner_unit, next_pos):
		return false
	move_origin_pos = owner_unit.movement_origin_grid_position
	move_target_pos = next_pos
	state = "moving"
	return true


## 进入waiting。
func _enter_waiting() -> void:
	var grid: GridSystem = BattleManager.grid
	if grid:
		grid.cancel_unit_move(owner_unit, owner_unit.movement_origin_grid_position, true)
	else:
		owner_unit.begin_grid_wait(owner_unit.grid_position)
	wait_retry_timer = WAIT_RETRY_INTERVAL
	state = "waiting"


## 推进敌人向目标移动。
func _move_enemy_toward(target: Node, delta: float) -> void:
	if not (target is UnitBase):
		state = "idle"
		return
	var target_unit := target as UnitBase
	if _is_in_attack_range(target_unit):
		state = "attacking"
		return
	var dir := target_unit.get_ground_position() - owner_unit.get_ground_position()
	if dir.length_squared() <= 0.01:
		state = "attacking"
		return
	var speed_px := owner_unit.move_speed * _cell_size()
	var distance := dir.length()
	var attack_distance := owner_unit.attack_range * _cell_size()
	var travel := minf(speed_px * delta, maxf(0.0, distance - attack_distance))
	if travel > 0.0:
		owner_unit.global_position += dir.normalized() * travel
	if _is_in_attack_range(target_unit):
		state = "attacking"
	else:
		state = "idle"
	_update_continuous_grid_position()


## 处理移动敌人forward逻辑。
func _move_enemy_forward(delta: float) -> void:
	var direction := Vector2(-1.0, 0.0)
	owner_unit.global_position += direction * owner_unit.move_speed * _cell_size() * delta
	_update_continuous_grid_position()


## 处理移动过程中的玩家碰撞。
func _resolve_player_collision_during_move(grid: GridSystem) -> bool:
	return false


## 更新连续网格位置。
func _update_continuous_grid_position() -> void:
	if not _uses_continuous_enemy_movement():
		return
	var grid: GridSystem = BattleManager.grid
	if grid:
		owner_unit.grid_position = grid.world_to_grid(owner_unit.get_ground_position())


## 获取当前网格尺寸。
func _cell_size() -> float:
	var grid: GridSystem = BattleManager.grid
	return grid.cell_size if grid else 64.0
