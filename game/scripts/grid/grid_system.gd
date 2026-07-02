# grid_system.gd — 网格战斗场地
# 管理网格布局、单位位置追踪、范围查询、寻路
class_name GridSystem
extends Node2D

const M = "Grid"
const PREP_GRID_RECT := Rect2(64, 32, 1152, 560)
const BATTLE_GRID_RECT := Rect2(64, 32, 1152, 560)
const LAYOUT_TWEEN_TIME := 0.22
const INVALID_GRID_POS := Vector2i(-9999, -9999)
const PATH_DIRS_8 := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

signal cell_clicked(grid_pos: Vector2i)
signal unit_clicked(unit: Node)
signal unit_placed(unit: Node, grid_pos: Vector2i)

## 网格配置
@export var grid_width: int = 19         # 格子列数
@export var grid_height: int = 10        # 格子行数
@export var cell_size: float = 64.0      # 格子像素大小
@export var grid_offset: Vector2 = Vector2(32, 32)  # 网格起始偏移

## 部署区域（玩家可部署的行范围）
@export var deploy_rows: Vector2i = Vector2i(1, 6)

## 敌方出生点
@export var spawn_points: Array[Vector2i] = []

## 占据表 {Vector2i: Node}
var occupancy: Dictionary = {}
## 移动目标预留表 {Vector2i: Node}
var movement_reservations: Dictionary = {}
## 所有单位引用
var all_units: Array[Node] = []

## 可视化
@export var draw_grid: bool = true
@export var grid_color: Color = Color(0.5, 0.5, 0.5, 0.65)
@export var deploy_zone_color: Color = Color(0.2, 0.5, 0.2, 0.3)
@export var spawn_zone_color: Color = Color(0.5, 0.2, 0.2, 0.3)
@export var debug_unit_body_radii: bool = true
@export var debug_attack_ranges: bool = true
@export var debug_collision_prediction: bool = true
@export var debug_collision_prediction_logs: bool = true
@export var debug_collision_prediction_duration: float = 1.2
@export var debug_collision_prediction_max_entries: int = 12
@export var collision_prediction_path_color: Color = Color(1.0, 0.86, 0.18, 0.9)
@export var collision_prediction_hit_color: Color = Color(1.0, 0.24, 0.16, 0.95)
@export var attack_entry_push_epsilon: float = 1.0
@export var debug_attack_entry_push_logs: bool = true
@export var debug_diagonal_detour_logs: bool = true
## Debug: 打印 UI 命中检测日志
@export var debug_ui_hits: bool = true

var layout_tween: Tween = null
var layout_animating: bool = false
var last_prepare_layout: bool = true
var collision_debug_entries: Dictionary = {}


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	# 初始化默认出生点（右侧边缘，仅在可部署/可移动范围内）
	if spawn_points.is_empty():
		for y in range(deploy_rows.x, deploy_rows.y + 1):
			spawn_points.append(Vector2i(grid_width - 1, y))
	BattleManager.grid = self
	last_prepare_layout = _is_prepare_layout()
	_apply_stage_layout(false)
	queue_redraw()


## 每帧更新运行状态。
func _process(delta: float) -> void:
	var wants_prepare := _is_prepare_layout()
	if wants_prepare != last_prepare_layout:
		last_prepare_layout = wants_prepare
		_apply_stage_layout(true)

	var needs_redraw := false
	if layout_animating:
		_sync_unit_positions()
		needs_redraw = true
	if _update_collision_debug_entries(delta):
		needs_redraw = true
	if needs_redraw:
		queue_redraw()


## 判断布局状态。
func _is_prepare_layout() -> bool:
	return BattleManager.state == BattleManager.BattleState.PREPARING


## 应用阶段布局。
func _apply_stage_layout(animated: bool) -> void:
	var target_rect := PREP_GRID_RECT if _is_prepare_layout() else BATTLE_GRID_RECT
	var next_cell_size := maxf(1.0, floorf(minf(
		target_rect.size.x / float(grid_width),
		target_rect.size.y / float(grid_height)
	)))
	var next_grid_size := Vector2(float(grid_width) * next_cell_size, float(grid_height) * next_cell_size)
	var next_offset := target_rect.position + (target_rect.size - next_grid_size) * 0.5

	if layout_tween and layout_tween.is_valid():
		layout_tween.kill()
		layout_animating = false

	if animated and is_inside_tree():
		layout_animating = true
		layout_tween = create_tween()
		layout_tween.set_parallel(true)
		layout_tween.tween_property(self, "grid_offset", next_offset, LAYOUT_TWEEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		layout_tween.tween_property(self, "cell_size", next_cell_size, LAYOUT_TWEEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		layout_tween.finished.connect(func():
			layout_animating = false
			_sync_unit_positions()
			queue_redraw()
		)
	else:
		grid_offset = next_offset
		cell_size = next_cell_size
		_sync_unit_positions()
		queue_redraw()


## 同步单位位置。
func _sync_unit_positions() -> void:
	for unit in all_units:
		if is_instance_valid(unit) and _uses_grid_occupancy(unit) and not (unit as UnitBase).is_moving():
			unit.global_position = grid_to_world(unit.grid_position)


## 绘制调试或界面可视元素。
func _draw() -> void:
	if draw_grid:
		# 网格线 — 画在格子边界上（非格子中心）
		for x in range(grid_width + 1):
			var line_x := grid_offset.x + x * cell_size
			draw_line(Vector2(line_x, grid_offset.y), Vector2(line_x, grid_offset.y + grid_height * cell_size), grid_color, 1.0)

		for y in range(grid_height + 1):
			var line_y := grid_offset.y + y * cell_size
			draw_line(Vector2(grid_offset.x, line_y), Vector2(grid_offset.x + grid_width * cell_size, line_y), grid_color, 1.0)

		# 部署区域高亮 — 用格子边界坐标
		var deploy_rect := Rect2(
			Vector2(grid_offset.x, grid_offset.y + deploy_rows.x * cell_size),
			Vector2(grid_width * cell_size, (deploy_rows.y - deploy_rows.x + 1) * cell_size)
		)
		draw_rect(deploy_rect, deploy_zone_color)

		# 出生区域高亮 — 用格子边界坐标
		if not spawn_points.is_empty():
			for sp in spawn_points:
				var sp_rect := Rect2(
					Vector2(grid_offset.x + sp.x * cell_size, grid_offset.y + sp.y * cell_size),
					Vector2(cell_size, cell_size)
				)
				draw_rect(sp_rect, spawn_zone_color)

	if debug_collision_prediction:
		_draw_collision_debug_entries()


## 网格坐标转世界坐标（格子中心）
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""网格坐标转世界坐标（格子中心）"""
	return Vector2(
		grid_offset.x + grid_pos.x * cell_size + cell_size / 2.0,
		grid_offset.y + grid_pos.y * cell_size + cell_size / 2.0
	)


## 世界坐标转网格坐标
func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""世界坐标转网格坐标"""
	var gx := int((world_pos.x - grid_offset.x) / cell_size)
	var gy := int((world_pos.y - grid_offset.y) / cell_size)
	return Vector2i(clamp(gx, 0, grid_width - 1), clamp(gy, 0, grid_height - 1))


## 判断边界状态。
func is_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_width and grid_pos.y >= 0 and grid_pos.y < grid_height


## 判断占用状态。
func is_occupied(grid_pos: Vector2i) -> bool:
	return occupancy.has(grid_pos) or movement_reservations.has(grid_pos)


## 判断格子是否位于部署区域。
func is_deploy_zone(grid_pos: Vector2i) -> bool:
	return grid_pos.y >= deploy_rows.x and grid_pos.y <= deploy_rows.y


## 是否在可移动范围内（与可部署范围一致）
func is_move_zone(grid_pos: Vector2i) -> bool:
	"""是否在可移动范围内（与可部署范围一致）"""
	return is_in_bounds(grid_pos) and is_deploy_zone(grid_pos)


## 是否可以在指定位置部署
func can_place_at(grid_pos: Vector2i) -> bool:
	"""是否可以在指定位置部署"""
	return is_in_bounds(grid_pos) and not is_occupied(grid_pos) and is_deploy_zone(grid_pos)


## 判断是否可以预留移动目标格。
func can_reserve_move_target(grid_pos: Vector2i, unit: Node) -> bool:
	if not is_move_zone(grid_pos):
		return false
	if occupancy.has(grid_pos) and occupancy[grid_pos] != unit:
		return false
	if movement_reservations.has(grid_pos) and movement_reservations[grid_pos] != unit:
		return false
	return true


## 判断单位是否使用网格占用表。
func _uses_grid_occupancy(unit: Node) -> bool:
	return unit is UnitBase and (unit as UnitBase).team == "player"


## 占用一个格子
func occupy_cell(grid_pos: Vector2i, unit: Node) -> void:
	"""占用一个格子"""
	occupancy[grid_pos] = unit
	if movement_reservations.get(grid_pos) == unit:
		movement_reservations.erase(grid_pos)


## 释放一个格子
func free_cell(grid_pos: Vector2i) -> void:
	"""释放一个格子"""
	occupancy.erase(grid_pos)


## 释放移动预留。
func release_move_reservation(unit: Node) -> void:
	for reserved_pos in movement_reservations.keys():
		if movement_reservations[reserved_pos] == unit:
			movement_reservations.erase(reserved_pos)


## 清理移动预留。
func clear_move_reservations() -> void:
	movement_reservations.clear()


## 让友方单位离开当前站位，并预留一个目标格中心
func begin_unit_move(unit: Node, target_pos: Vector2i) -> bool:
	"""让友方单位离开当前站位，并预留一个目标格中心"""
	if not _uses_grid_occupancy(unit):
		return false
	if not can_reserve_move_target(target_pos, unit):
		return false
	release_move_reservation(unit)
	if unit.grid_position in occupancy and occupancy[unit.grid_position] == unit:
		free_cell(unit.grid_position)
	movement_reservations[target_pos] = unit
	if unit is UnitBase:
		(unit as UnitBase).begin_grid_move(target_pos)
	return true


## 提交移动结果：单位站到目标格中心并重新占格
func finish_unit_move(unit: Node, final_pos: Vector2i) -> bool:
	"""提交移动结果：单位站到目标格中心并重新占格"""
	if not _uses_grid_occupancy(unit):
		return false
	if movement_reservations.has(final_pos) and movement_reservations[final_pos] != unit:
		return false
	if occupancy.has(final_pos) and occupancy[final_pos] != unit:
		return false
	release_move_reservation(unit)
	occupy_cell(final_pos, unit)
	unit.grid_position = final_pos
	unit.global_position = grid_to_world(final_pos)
	if unit is UnitBase:
		(unit as UnitBase).finish_grid_move(final_pos)
	return true


## 取消移动并把单位吸附回一个合法站立格
func cancel_unit_move(unit: Node, preferred_pos: Vector2i, enter_waiting: bool = false) -> bool:
	"""取消移动并把单位吸附回一个合法站立格"""
	if not _uses_grid_occupancy(unit):
		return false
	release_move_reservation(unit)
	var fallback := find_nearest_open_player_cell(unit.global_position, preferred_pos, unit)
	if fallback.x < 0:
		return false
	occupy_cell(fallback, unit)
	unit.grid_position = fallback
	unit.global_position = grid_to_world(fallback)
	if unit is UnitBase:
		if enter_waiting:
			(unit as UnitBase).begin_grid_wait(fallback)
		else:
			(unit as UnitBase).finish_grid_move(fallback)
	return true


## 放置单位到网格
func place_unit(unit: Node, grid_pos: Vector2i) -> bool:
	"""放置单位到网格"""
	if _uses_grid_occupancy(unit):
		if not can_place_at(grid_pos):
			return false
		occupy_cell(grid_pos, unit)
	elif not is_in_bounds(grid_pos):
		return false
	unit.grid_position = grid_pos
	unit.global_position = grid_to_world(grid_pos)
	if unit is UnitBase and _uses_grid_occupancy(unit):
		(unit as UnitBase).finish_grid_move(grid_pos)
	if unit not in all_units:
		all_units.append(unit)
		add_child(unit)
	unit_placed.emit(unit, grid_pos)
	return true


## 从网格移除单位
func remove_unit(unit: Node) -> void:
	"""从网格移除单位"""
	if unit.grid_position in occupancy and occupancy[unit.grid_position] == unit:
		free_cell(unit.grid_position)
	release_move_reservation(unit)
	all_units.erase(unit)
	if unit.get_parent() == self:
		remove_child(unit)


## 网格曼哈顿距离
func get_distance(a: Vector2i, b: Vector2i) -> float:
	"""网格曼哈顿距离"""
	return abs(a.x - b.x) + abs(a.y - b.y)


## 获取范围内的单位
func get_units_in_range(center: Vector2i, radius: float, team: String = "") -> Array:
	"""获取范围内的单位"""
	var result: Array = []
	for unit in all_units:
		if not is_instance_valid(unit):
			continue
		if unit is UnitBase and not (unit as UnitBase).is_alive:
			continue
		if team != "" and unit.has_method("get_team") and unit.get_team() != team:
			continue
		var unit_grid := _get_unit_query_grid_position(unit)
		if get_distance(center, unit_grid) <= radius:
			result.append(unit)
	return result


## 获取最近的单位
func get_nearest_unit(center: Vector2i, team: String = "") -> Node:
	"""获取最近的单位"""
	var nearest: Node = null
	var nearest_dist: float = INF
	for unit in all_units:
		if not is_instance_valid(unit):
			continue
		if unit is UnitBase and not (unit as UnitBase).is_alive:
			continue
		if team != "" and unit.has_method("get_team") and unit.get_team() != team:
			continue
		var d := get_distance(center, _get_unit_query_grid_position(unit))
		if d < nearest_dist:
			nearest_dist = d
			nearest = unit
	return nearest


## 获取单位查询网格位置。
func _get_unit_query_grid_position(unit: Node) -> Vector2i:
	if unit is UnitBase:
		var combat_unit := unit as UnitBase
		if not _uses_grid_occupancy(unit):
			combat_unit.grid_position = world_to_grid(combat_unit.get_ground_position())
			return combat_unit.grid_position
		if combat_unit.is_moving():
			return world_to_grid(combat_unit.get_ground_position())
	return unit.grid_position


## 获取与指定地面圆形接触的单位
func get_units_touching_circle(center: Vector2, radius: float, team: String = "", exclude: Node = null) -> Array:
	"""获取与指定地面圆形接触的单位"""
	var result: Array = []
	for unit in all_units:
		if unit == exclude or not is_instance_valid(unit):
			continue
		if not (unit is UnitBase):
			continue
		var combat_unit := unit as UnitBase
		if not combat_unit.is_alive:
			continue
		if team != "" and combat_unit.get_team() != team:
			continue
		var radius_sum := radius + combat_unit.get_collision_radius()
		if center.distance_squared_to(combat_unit.get_ground_position()) <= radius_sum * radius_sum:
			result.append(combat_unit)
	return result


## 获取接触单位。
func get_touching_units(unit: UnitBase, team: String = "") -> Array:
	if not unit:
		return []
	return get_units_touching_circle(unit.get_ground_position(), unit.get_collision_radius(), team, unit)


## 英雄攻击入格时，把与目标格地面圆重叠的敌人推开
func push_enemies_overlapping_hero_target(hero: UnitBase, target_grid: Vector2i) -> Array:
	"""英雄攻击入格时，把与目标格地面圆重叠的敌人推开"""
	var pushed: Array = []
	if not hero or hero.get_team() != "player":
		return pushed

	var hero_ground := grid_to_world(target_grid) + hero.ground_anchor_offset
	for other in all_units:
		if other == hero or not is_instance_valid(other):
			continue
		if not (other is UnitBase):
			continue

		var enemy := other as UnitBase
		if not enemy.is_alive or enemy.get_team() == hero.get_team():
			continue

		var radius_sum := hero.get_collision_radius() + enemy.get_collision_radius()
		if hero_ground.distance_squared_to(enemy.get_ground_position()) >= radius_sum * radius_sum:
			continue

		var pushed_ground := _find_enemy_push_ground(hero, enemy, hero_ground)
		enemy.global_position = pushed_ground - enemy.ground_anchor_offset
		enemy.grid_position = world_to_grid(enemy.get_ground_position())
		pushed.append(enemy)
		if debug_attack_entry_push_logs:
			Log.d(M, "攻击入格推开: %s -> %s world=(%.1f, %.1f) grid=(%d, %d)" % [
				_unit_debug_name(hero),
				_unit_debug_name(enemy),
				pushed_ground.x,
				pushed_ground.y,
				enemy.grid_position.x,
				enemy.grid_position.y,
			])
	return pushed


## 查找敌人被推开后的地面位置。
func _find_enemy_push_ground(hero: UnitBase, enemy: UnitBase, hero_ground: Vector2) -> Vector2:
	var direction := _push_direction_away_from(enemy.get_ground_position(), hero_ground, hero)
	var min_distance := hero.get_collision_radius() + enemy.get_collision_radius() + maxf(0.0, attack_entry_push_epsilon)
	var candidate := hero_ground + direction * min_distance
	return _clear_enemy_ground_from_player_collisions(enemy, hero, hero_ground, candidate)


## 修正敌人地面位置以避开玩家碰撞。
func _clear_enemy_ground_from_player_collisions(enemy: UnitBase, hero: UnitBase, hero_ground: Vector2, candidate_ground: Vector2) -> Vector2:
	var candidate := candidate_ground
	for _i in range(8):
		var changed := false
		for other in all_units:
			if not is_instance_valid(other) or not (other is UnitBase):
				continue

			var player_unit := other as UnitBase
			if not player_unit.is_alive or player_unit.get_team() != hero.get_team():
				continue

			var player_ground := hero_ground if player_unit == hero else player_unit.get_ground_position()
			var min_distance := enemy.get_collision_radius() + player_unit.get_collision_radius() + maxf(0.0, attack_entry_push_epsilon)
			var offset := candidate - player_ground
			if offset.length_squared() >= min_distance * min_distance:
				continue

			var direction := offset.normalized() if offset.length_squared() > 0.0001 else _push_direction_away_from(enemy.get_ground_position(), player_ground, hero)
			candidate = player_ground + direction * min_distance
			changed = true
		if not changed:
			break
	return candidate


## 计算远离中心点的推开方向。
func _push_direction_away_from(from_ground: Vector2, center_ground: Vector2, hero: UnitBase) -> Vector2:
	var direction := from_ground - center_ground
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	if hero:
		direction = center_ground - hero.get_ground_position()
		if direction.length_squared() > 0.0001:
			return direction.normalized()
	return Vector2.RIGHT


## 对角移动被正交邻格友方卡住时，返回一个可用的正向中转格
func find_diagonal_move_detour(unit: UnitBase, from_grid: Vector2i, diagonal_target: Vector2i) -> Vector2i:
	"""对角移动被正交邻格友方卡住时，返回一个可用的正向中转格"""
	if not unit:
		return INVALID_GRID_POS
	var delta := diagonal_target - from_grid
	if absi(delta.x) != 1 or absi(delta.y) != 1:
		return INVALID_GRID_POS

	var from_ground := unit.get_ground_position()
	var target_ground := grid_to_world(diagonal_target) + unit.ground_anchor_offset
	var direct_collision := predict_unit_collision_on_segment(unit, from_ground, target_ground, unit.get_team(), diagonal_target, false)
	if direct_collision.is_empty():
		return INVALID_GRID_POS

	var side_x := from_grid + Vector2i(delta.x, 0)
	var side_y := from_grid + Vector2i(0, delta.y)
	var candidates: Array[Vector2i] = [side_x, side_y]
	var hit_unit := direct_collision.get("hit_unit", null) as UnitBase
	if hit_unit and is_instance_valid(hit_unit):
		var hit_grid := _get_unit_query_grid_position(hit_unit)
		if hit_grid == side_x:
			candidates = [side_y, side_x]
		elif hit_grid == side_y:
			candidates = [side_x, side_y]

	for candidate in candidates:
		if _can_use_diagonal_detour_candidate(unit, from_ground, candidate, diagonal_target):
			if debug_diagonal_detour_logs:
				Log.d(M, "斜向移动拆步: %s (%d,%d)->(%d,%d) 改为先到 (%d,%d)" % [
					_unit_debug_name(unit),
					from_grid.x,
					from_grid.y,
					diagonal_target.x,
					diagonal_target.y,
					candidate.x,
					candidate.y,
				])
			return candidate
	return INVALID_GRID_POS


## 判断斜向绕行候选格是否可用。
func _can_use_diagonal_detour_candidate(unit: UnitBase, from_ground: Vector2, middle_grid: Vector2i, final_grid: Vector2i) -> bool:
	if not can_reserve_move_target(middle_grid, unit):
		return false
	var middle_ground := grid_to_world(middle_grid) + unit.ground_anchor_offset
	var final_ground := grid_to_world(final_grid) + unit.ground_anchor_offset
	if not predict_unit_collision_on_segment(unit, from_ground, middle_ground, unit.get_team(), middle_grid, false).is_empty():
		return false
	if not predict_unit_collision_on_segment(unit, middle_ground, final_ground, unit.get_team(), final_grid, false).is_empty():
		return false
	return true


## 预测单位地面圆从 from 到 to 的移动线段碰撞，返回命中单位和接触坐标
func predict_unit_collision_on_segment(unit: UnitBase, from_ground: Vector2, to_ground: Vector2, team: String = "", target_grid: Vector2i = Vector2i(-9999, -9999), record_debug: bool = true) -> Dictionary:
	"""预测单位地面圆从 from 到 to 的移动线段碰撞，返回命中单位和接触坐标"""
	if not unit:
		return {}
	var best_result: Dictionary = {}
	var best_time: float = INF
	for other in all_units:
		if other == unit or not is_instance_valid(other):
			continue
		if not (other is UnitBase):
			continue
		var other_unit := other as UnitBase
		if not other_unit.is_alive:
			continue
		if team != "" and other_unit.get_team() != team:
			continue
		if other_unit.is_moving() and other_unit.movement_origin_grid_position == target_grid:
			continue
		var radius_sum := unit.get_collision_radius() + other_unit.get_collision_radius()
		var hit_time := _segment_circle_hit_time(other_unit.get_ground_position(), from_ground, to_ground, radius_sum)
		if hit_time < 0.0:
			continue
		if hit_time < best_time:
			best_time = hit_time
			var hit_position := from_ground.lerp(to_ground, hit_time)
			var contact_position := hit_position
			var contact_dir := other_unit.get_ground_position() - hit_position
			if contact_dir.length_squared() > 0.0001:
				contact_position = hit_position + contact_dir.normalized() * unit.get_collision_radius()
			best_result = {
				"moving_unit": unit,
				"hit_unit": other_unit,
				"from": from_ground,
				"to": to_ground,
				"hit_position": hit_position,
				"contact_position": contact_position,
				"hit_grid": world_to_grid(contact_position),
				"time": hit_time,
				"moving_radius": unit.get_collision_radius(),
				"hit_radius": other_unit.get_collision_radius(),
			}
	if not best_result.is_empty() and record_debug:
		_record_collision_debug(best_result)
	return best_result


## 检测单位地面圆从 from 到 to 的移动线段是否会碰到其他单位
func would_unit_collide_on_segment(unit: UnitBase, from_ground: Vector2, to_ground: Vector2, team: String = "", target_grid: Vector2i = Vector2i(-9999, -9999)) -> bool:
	"""检测单位地面圆从 from 到 to 的移动线段是否会碰到其他单位"""
	return not predict_unit_collision_on_segment(unit, from_ground, to_ground, team, target_grid).is_empty()


## 计算点到线段的平方距离。
func _distance_point_to_segment_squared(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_sq := segment.length_squared()
	if length_sq <= 0.0001:
		return point.distance_squared_to(segment_start)
	var t := clampf((point - segment_start).dot(segment) / length_sq, 0.0, 1.0)
	var closest := segment_start + segment * t
	return point.distance_squared_to(closest)


## 计算线段命中圆形的时间比例。
func _segment_circle_hit_time(circle_center: Vector2, segment_start: Vector2, segment_end: Vector2, radius: float) -> float:
	var travel := segment_end - segment_start
	var length_sq := travel.length_squared()
	if length_sq <= 0.0001:
		return 0.0 if segment_start.distance_squared_to(circle_center) <= radius * radius else -1.0

	var offset := segment_start - circle_center
	var c := offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0

	var a := length_sq
	var b := 2.0 * offset.dot(travel)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0

	var sqrt_discriminant := sqrt(discriminant)
	var denominator := 2.0 * a
	var t0 := (-b - sqrt_discriminant) / denominator
	var t1 := (-b + sqrt_discriminant) / denominator
	if t0 >= 0.0 and t0 <= 1.0:
		return t0
	if t1 >= 0.0 and t1 <= 1.0:
		return t1
	return -1.0


## 记录碰撞预测调试信息。
func _record_collision_debug(result: Dictionary) -> void:
	if not debug_collision_prediction:
		return
	var moving_unit := result.get("moving_unit", null) as UnitBase
	var hit_unit := result.get("hit_unit", null) as UnitBase
	if not moving_unit or not hit_unit:
		return

	var key := "%s:%s" % [moving_unit.get_instance_id(), hit_unit.get_instance_id()]
	var is_new := not collision_debug_entries.has(key)
	var entry: Dictionary = {}
	if not is_new:
		entry = collision_debug_entries[key]

	var label: Label = null
	if entry.has("label"):
		label = entry["label"] as Label
	if not label or not is_instance_valid(label):
		label = _create_collision_debug_label()

	entry["label"] = label
	entry["result"] = result.duplicate()
	entry["time_left"] = maxf(0.05, debug_collision_prediction_duration)
	collision_debug_entries[key] = entry
	_update_collision_debug_label(entry)
	_trim_collision_debug_entries()

	if debug_collision_prediction_logs and is_new:
		var contact_position: Vector2 = result.get("contact_position", Vector2.ZERO)
		var hit_grid: Vector2i = result.get("hit_grid", world_to_grid(contact_position))
		Log.d(M, "碰撞预测: %s -> %s 接触坐标 world=(%.1f, %.1f) grid=(%d, %d)" % [
			_unit_debug_name(moving_unit),
			_unit_debug_name(hit_unit),
			contact_position.x,
			contact_position.y,
			hit_grid.x,
			hit_grid.y,
		])
	queue_redraw()


## 创建碰撞调试标签。
func _create_collision_debug_label() -> Label:
	var label := Label.new()
	label.name = "CollisionPredictionDebug"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 200
	label.size = Vector2(260, 52)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.65, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)
	return label


## 更新碰撞调试条目。
func _update_collision_debug_entries(delta: float) -> bool:
	if collision_debug_entries.is_empty():
		return false

	var changed := false
	for key in collision_debug_entries.keys():
		if not collision_debug_entries.has(key):
			continue
		var entry: Dictionary = collision_debug_entries[key]
		var result: Dictionary = entry.get("result", {})
		var moving_unit := result.get("moving_unit", null) as UnitBase
		var hit_unit := result.get("hit_unit", null) as UnitBase
		if not moving_unit or not hit_unit or not is_instance_valid(moving_unit) or not is_instance_valid(hit_unit):
			_remove_collision_debug_entry(key)
			changed = true
			continue

		var time_left := float(entry.get("time_left", 0.0)) - delta
		if time_left <= 0.0:
			_remove_collision_debug_entry(key)
			changed = true
			continue

		entry["time_left"] = time_left
		collision_debug_entries[key] = entry
		_update_collision_debug_label(entry)
		changed = true
	return changed


## 更新碰撞调试标签。
func _update_collision_debug_label(entry: Dictionary) -> void:
	var label := entry.get("label", null) as Label
	if not label or not is_instance_valid(label):
		return
	var result: Dictionary = entry.get("result", {})
	var hit_unit := result.get("hit_unit", null) as UnitBase
	if not hit_unit or not is_instance_valid(hit_unit):
		return

	var contact_position: Vector2 = result.get("contact_position", Vector2.ZERO)
	var hit_grid: Vector2i = result.get("hit_grid", world_to_grid(contact_position))
	var time_left := float(entry.get("time_left", debug_collision_prediction_duration))
	var alpha := clampf(time_left / maxf(debug_collision_prediction_duration, 0.001), 0.15, 1.0)
	label.visible = debug_collision_prediction
	label.modulate = Color(1.0, 1.0, 1.0, alpha)
	label.position = to_local(contact_position) + Vector2(10.0, -54.0)
	label.text = "碰撞: %s\n格(%d,%d) 世界(%.0f,%.0f)" % [
		_unit_debug_name(hit_unit),
		hit_grid.x,
		hit_grid.y,
		contact_position.x,
		contact_position.y,
	]


## 绘制碰撞预测调试条目。
func _draw_collision_debug_entries() -> void:
	for key in collision_debug_entries.keys():
		var entry: Dictionary = collision_debug_entries[key]
		var result: Dictionary = entry.get("result", {})
		var moving_unit := result.get("moving_unit", null) as UnitBase
		var hit_unit := result.get("hit_unit", null) as UnitBase
		if not moving_unit or not hit_unit or not is_instance_valid(moving_unit) or not is_instance_valid(hit_unit):
			continue

		var time_left := float(entry.get("time_left", debug_collision_prediction_duration))
		var alpha := clampf(time_left / maxf(debug_collision_prediction_duration, 0.001), 0.15, 1.0)
		var path_color := collision_prediction_path_color
		path_color.a *= alpha
		var hit_color := collision_prediction_hit_color
		hit_color.a *= alpha

		var from_pos: Vector2 = to_local(result.get("from", Vector2.ZERO))
		var to_pos: Vector2 = to_local(result.get("to", Vector2.ZERO))
		var hit_position: Vector2 = to_local(result.get("hit_position", Vector2.ZERO))
		var contact_position: Vector2 = to_local(result.get("contact_position", Vector2.ZERO))
		var hit_unit_pos := to_local(hit_unit.get_ground_position())
		var moving_radius := float(result.get("moving_radius", moving_unit.get_collision_radius()))
		var hit_radius := float(result.get("hit_radius", hit_unit.get_collision_radius()))

		draw_line(from_pos, to_pos, path_color, 2.0, true)
		draw_arc(hit_position, moving_radius, 0.0, TAU, 48, path_color, 2.0, true)
		draw_arc(hit_unit_pos, hit_radius, 0.0, TAU, 48, hit_color, 2.0, true)
		draw_circle(hit_position, 4.0, path_color)
		draw_circle(contact_position, 5.0, hit_color)
		draw_line(contact_position + Vector2(-7.0, 0.0), contact_position + Vector2(7.0, 0.0), hit_color, 2.0, true)
		draw_line(contact_position + Vector2(0.0, -7.0), contact_position + Vector2(0.0, 7.0), hit_color, 2.0, true)


## 裁剪过量的碰撞预测调试条目。
func _trim_collision_debug_entries() -> void:
	if debug_collision_prediction_max_entries <= 0:
		return
	while collision_debug_entries.size() > debug_collision_prediction_max_entries:
		var oldest_key := ""
		var oldest_time := INF
		for key in collision_debug_entries.keys():
			var entry: Dictionary = collision_debug_entries[key]
			var time_left := float(entry.get("time_left", 0.0))
			if time_left < oldest_time:
				oldest_time = time_left
				oldest_key = key
		if oldest_key.is_empty():
			return
		_remove_collision_debug_entry(oldest_key)


## 移除碰撞调试入口。
func _remove_collision_debug_entry(key: String) -> void:
	if not collision_debug_entries.has(key):
		return
	var entry: Dictionary = collision_debug_entries[key]
	var label := entry.get("label", null) as Label
	if label and is_instance_valid(label):
		label.queue_free()
	collision_debug_entries.erase(key)


## 获取单位调试名称。
func _unit_debug_name(unit: UnitBase) -> String:
	if not unit:
		return "<null>"
	if not unit.unit_name.is_empty():
		return unit.unit_name
	return str(unit.name)


## 根据世界坐标查找最近的合法友方空格
func find_nearest_open_player_cell(world_pos: Vector2, preferred: Vector2i, unit: Node = null) -> Vector2i:
	"""根据世界坐标查找最近的合法友方空格"""
	if is_move_zone(preferred) and _is_cell_available_for_unit(preferred, unit):
		return preferred

	var best := Vector2i(-1, -1)
	var best_dist := INF
	for x in range(grid_width):
		for y in range(deploy_rows.x, deploy_rows.y + 1):
			var cell := Vector2i(x, y)
			if not _is_cell_available_for_unit(cell, unit):
				continue
			var d := grid_to_world(cell).distance_squared_to(world_pos)
			if d < best_dist:
				best_dist = d
				best = cell
	return best


## 判断格子是否可供指定单位使用。
func _is_cell_available_for_unit(cell: Vector2i, unit: Node = null) -> bool:
	if not is_move_zone(cell):
		return false
	if occupancy.has(cell) and occupancy[cell] != unit:
		return false
	if movement_reservations.has(cell) and movement_reservations[cell] != unit:
		return false
	return true


## 8方向A*寻路，返回从起点之后开始的格子序列
func find_path(from: Vector2i, to: Vector2i, unit: Node = null) -> Array:
	"""8方向A*寻路，返回从起点之后开始的格子序列"""
	if from == to:
		return []
	if not is_move_zone(from) or not is_move_zone(to):
		return []
	if not _is_cell_available_for_unit(to, unit):
		return []

	var open: Array[Vector2i] = [from]
	var came_from: Dictionary = {}
	var cost_so_far: Dictionary = {from: 0.0}

	while not open.is_empty():
		var current := _pop_best_path_cell(open, cost_so_far, to)
		if current == to:
			return _reconstruct_path(came_from, from, to)

		for dir_value in PATH_DIRS_8:
			var dir: Vector2i = dir_value
			var next: Vector2i = current + dir
			if not _is_path_step_available(current, next, unit, to):
				continue
			var step_cost := 1.4142 if dir.x != 0 and dir.y != 0 else 1.0
			var new_cost := float(cost_so_far[current]) + step_cost
			if not cost_so_far.has(next) or new_cost < float(cost_so_far[next]):
				cost_so_far[next] = new_cost
				came_from[next] = current
				if next not in open:
					open.append(next)

	return []


## 寻找一个可停留且能攻击目标的英雄站位路径
func find_path_to_attack_position(from: Vector2i, target: UnitBase, attack_range: float, unit: Node = null) -> Array:
	"""寻找一个可停留且能攻击目标的英雄站位路径"""
	if not target:
		return []

	var attacker_ground_offset := Vector2.ZERO
	if unit is UnitBase:
		attacker_ground_offset = (unit as UnitBase).ground_anchor_offset

	var from_ground := grid_to_world(from) + attacker_ground_offset
	if target.get_body_outline_distance_from_ground(from_ground) / maxf(cell_size, 1.0) <= attack_range:
		return []

	var best_path: Array = []
	var best_score: float = INF
	for x in range(grid_width):
		for y in range(deploy_rows.x, deploy_rows.y + 1):
			var candidate := Vector2i(x, y)
			var candidate_ground : Vector2 = grid_to_world(candidate) + attacker_ground_offset
			var candidate_distance := target.get_body_outline_distance_from_ground(candidate_ground) / maxf(cell_size, 1.0)
			if candidate_distance > attack_range:
				continue
			if not _is_cell_available_for_unit(candidate, unit):
				continue
			var candidate_path: Array = find_path(from, candidate, unit)
			if candidate_path.is_empty():
				continue
			var score: float = float(candidate_path.size()) + candidate_distance * 0.01
			if score < best_score:
				best_score = score
				best_path = candidate_path
	return best_path


## 弹出路径搜索中评分最优的格子。
func _pop_best_path_cell(open: Array[Vector2i], cost_so_far: Dictionary, goal: Vector2i) -> Vector2i:
	var best_index := 0
	var best_score: float = INF
	for i in range(open.size()):
		var cell: Vector2i = open[i]
		var score: float = float(cost_so_far[cell]) + _path_heuristic(cell, goal)
		if score < best_score:
			best_score = score
			best_index = i
	return open.pop_at(best_index)


## 计算路径搜索启发式距离。
func _path_heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	return float(maxi(dx, dy))


## 根据回溯表重建路径。
func _reconstruct_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array:
	var result: Array = []
	var current := goal
	while current != start:
		result.push_front(current)
		if not came_from.has(current):
			return []
		current = came_from[current]
	return result


## 判断路径下一步是否可用。
func _is_path_step_available(from: Vector2i, to: Vector2i, unit: Node, goal: Vector2i) -> bool:
	if not is_move_zone(to):
		return false
	if not _is_cell_available_for_unit(to, unit) and to != goal:
		return false
	var dir := to - from
	if dir.x != 0 and dir.y != 0:
		var side_a := from + Vector2i(dir.x, 0)
		var side_b := from + Vector2i(0, dir.y)
		if not _is_cell_available_for_unit(side_a, unit) and not _is_cell_available_for_unit(side_b, unit):
			return false
	return true


## 移动单位到新格子
func move_unit(unit: Node, new_pos: Vector2i) -> bool:
	"""移动单位到新格子"""
	if not is_in_bounds(new_pos):
		return false
	if occupancy.has(new_pos) and occupancy[new_pos] != unit:
		return false
	if movement_reservations.has(new_pos) and movement_reservations[new_pos] != unit:
		return false
	var old_pos: Vector2i = unit.grid_position
	if occupancy.get(old_pos) == unit:
		free_cell(old_pos)
	release_move_reservation(unit)
	occupy_cell(new_pos, unit)
	unit.grid_position = new_pos
	if unit is UnitBase:
		(unit as UnitBase).finish_grid_move(new_pos)
	return true


## 批量生成敌人
func spawn_enemy_wave(enemy_templates: Array, spawns: Array) -> void:
	"""批量生成敌人"""
	var sp_list := spawns.duplicate()
	if sp_list.is_empty():
		# 使用默认右侧出生点（仅在可部署范围内）
		for y in range(deploy_rows.x, deploy_rows.y + 1):
			sp_list.append(Vector2i(grid_width - 1, y))

	var sp_idx := 0
	for template in enemy_templates:
		var enemy := EnemyUnit.new()
		enemy.setup_from_template(template)
		var spawn_pos: Vector2i
		if sp_idx < sp_list.size():
			spawn_pos = sp_list[sp_idx]
			sp_idx += 1
		else:
			spawn_pos = sp_list[sp_idx % sp_list.size()]
			sp_idx += 1

		# 找最近的空位
		if is_occupied(spawn_pos):
			var found := false
			for offset in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
				var alt: Vector2i = spawn_pos + offset
				if is_in_bounds(alt) and not is_occupied(alt):
					spawn_pos = alt
					found = true
					break
			if not found:
				# 扫描附近空位
				for dx in range(-2, 3):
					for dy in range(-2, 3):
						var alt := spawn_pos + Vector2i(dx, dy)
						if is_in_bounds(alt) and not is_occupied(alt):
							spawn_pos = alt
							found = true
							break
					if found:
						break

		enemy.grid_position = spawn_pos
		enemy.global_position = grid_to_world(spawn_pos)
		all_units.append(enemy)
		add_child(enemy)
		BattleManager.register_enemy_unit(enemy)


## 处理输入事件。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 检查鼠标是否在 UI 上，防止穿透点击触发部署
		if _is_mouse_over_ui():
			return
		var clicked_unit := _get_unit_at_mouse_position()
		if clicked_unit:
			unit_clicked.emit(clicked_unit)
			return
		var grid_pos := world_to_grid(get_global_mouse_position())
		if is_in_bounds(grid_pos):
			cell_clicked.emit(grid_pos)


## 检测鼠标是否点击到战场单位；不依赖网格占用，允许单位移动、重叠或离开格子中心
func _get_unit_at_mouse_position() -> Node:
	"""检测鼠标是否点击到战场单位；不依赖网格占用，允许单位移动、重叠或离开格子中心"""
	var mouse_pos := get_global_mouse_position()
	var fallback_unit: UnitBase = null
	for i in range(all_units.size() - 1, -1, -1):
		var unit := all_units[i]
		if not is_instance_valid(unit):
			continue
		if not (unit is UnitBase):
			continue

		var combat_unit := unit as UnitBase
		if not combat_unit.is_alive:
			continue

		var hit_size := combat_unit.unit_radius * 2.0
		var hit_rect := Rect2(
			combat_unit.global_position - Vector2(hit_size, hit_size) * 0.5,
			Vector2(hit_size, hit_size)
		)
		if hit_rect.has_point(mouse_pos):
			# 重叠时优先返回玩家角色，确保点击角色形象可以打开角色命令菜单
			if combat_unit is HeroUnit:
				return combat_unit
			if not fallback_unit:
				fallback_unit = combat_unit
	return fallback_unit


## 递归检查鼠标是否在任何可见 Control 节点上
func _is_mouse_over_ui() -> bool:
	"""递归检查鼠标是否在任何可见 Control 节点上"""
	return _check_control_hit(get_tree().root, get_global_mouse_position())


## 递归检查控件命中状态。
func _check_control_hit(node: Node, mouse_pos: Vector2) -> bool:
	for child in node.get_children():
		if child is Control and child.is_visible_in_tree() and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if child.get_global_rect().has_point(mouse_pos):
				if _is_unit_visual_control(child):
					continue
				if debug_ui_hits:
					var label: String = str(child.name) if not child.name.is_empty() else "<unnamed>"
					Log.d(M, "UI拦截: %s (%s) rect=%s" % [label, child.get_class(), child.get_global_rect()])
				return true
		if _check_control_hit(child, mouse_pos):
			return true
	return false


## 判断Control是否属于战场单位自身的占位UI；这类UI不应阻挡单位点击
func _is_unit_visual_control(control: Control) -> bool:
	"""判断Control是否属于战场单位自身的占位UI；这类UI不应阻挡单位点击"""
	var node: Node = control
	while node:
		if node is UnitBase:
			return true
		node = node.get_parent()
	return false
