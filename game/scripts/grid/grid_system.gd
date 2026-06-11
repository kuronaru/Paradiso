# grid_system.gd — 网格战斗场地
# 管理网格布局、单位位置追踪、范围查询、寻路
class_name GridSystem
extends Node2D

const M = "Grid"
const PREP_GRID_RECT := Rect2(64, 32, 1152, 560)
const BATTLE_GRID_RECT := Rect2(64, 32, 1152, 560)
const LAYOUT_TWEEN_TIME := 0.22

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
## Debug: 打印 UI 命中检测日志
@export var debug_ui_hits: bool = true

var layout_tween: Tween = null
var layout_animating: bool = false
var last_prepare_layout: bool = true


func _ready() -> void:
	# 初始化默认出生点（右侧边缘，仅在可部署/可移动范围内）
	if spawn_points.is_empty():
		for y in range(deploy_rows.x, deploy_rows.y + 1):
			spawn_points.append(Vector2i(grid_width - 1, y))
	BattleManager.grid = self
	last_prepare_layout = _is_prepare_layout()
	_apply_stage_layout(false)
	queue_redraw()


func _process(_delta: float) -> void:
	var wants_prepare := _is_prepare_layout()
	if wants_prepare != last_prepare_layout:
		last_prepare_layout = wants_prepare
		_apply_stage_layout(true)

	if layout_animating:
		_sync_unit_positions()
		queue_redraw()


func _is_prepare_layout() -> bool:
	return BattleManager.state == BattleManager.BattleState.PREPARING


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


func _sync_unit_positions() -> void:
	for unit in all_units:
		if is_instance_valid(unit) and _uses_grid_occupancy(unit) and (unit as UnitBase).is_standing():
			unit.global_position = grid_to_world(unit.grid_position)


func _draw() -> void:
	if not draw_grid:
		return

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


func grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""网格坐标转世界坐标（格子中心）"""
	return Vector2(
		grid_offset.x + grid_pos.x * cell_size + cell_size / 2.0,
		grid_offset.y + grid_pos.y * cell_size + cell_size / 2.0
	)


func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""世界坐标转网格坐标"""
	var gx := int((world_pos.x - grid_offset.x) / cell_size)
	var gy := int((world_pos.y - grid_offset.y) / cell_size)
	return Vector2i(clamp(gx, 0, grid_width - 1), clamp(gy, 0, grid_height - 1))


func is_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_width and grid_pos.y >= 0 and grid_pos.y < grid_height


func is_occupied(grid_pos: Vector2i) -> bool:
	return occupancy.has(grid_pos) or movement_reservations.has(grid_pos)


func is_deploy_zone(grid_pos: Vector2i) -> bool:
	return grid_pos.y >= deploy_rows.x and grid_pos.y <= deploy_rows.y


func is_move_zone(grid_pos: Vector2i) -> bool:
	"""是否在可移动范围内（与可部署范围一致）"""
	return is_in_bounds(grid_pos) and is_deploy_zone(grid_pos)


func can_place_at(grid_pos: Vector2i) -> bool:
	"""是否可以在指定位置部署"""
	return is_in_bounds(grid_pos) and not is_occupied(grid_pos) and is_deploy_zone(grid_pos)


func can_reserve_move_target(grid_pos: Vector2i, unit: Node) -> bool:
	if not is_move_zone(grid_pos):
		return false
	if occupancy.has(grid_pos) and occupancy[grid_pos] != unit:
		return false
	if movement_reservations.has(grid_pos) and movement_reservations[grid_pos] != unit:
		return false
	return true


func _uses_grid_occupancy(unit: Node) -> bool:
	return unit is UnitBase and (unit as UnitBase).team == "player"


func occupy_cell(grid_pos: Vector2i, unit: Node) -> void:
	"""占用一个格子"""
	occupancy[grid_pos] = unit
	if movement_reservations.get(grid_pos) == unit:
		movement_reservations.erase(grid_pos)


func free_cell(grid_pos: Vector2i) -> void:
	"""释放一个格子"""
	occupancy.erase(grid_pos)


func release_move_reservation(unit: Node) -> void:
	for reserved_pos in movement_reservations.keys():
		if movement_reservations[reserved_pos] == unit:
			movement_reservations.erase(reserved_pos)


func clear_move_reservations() -> void:
	movement_reservations.clear()


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


func cancel_unit_move(unit: Node, preferred_pos: Vector2i) -> bool:
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
		(unit as UnitBase).finish_grid_move(fallback)
	return true


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


func remove_unit(unit: Node) -> void:
	"""从网格移除单位"""
	if unit.grid_position in occupancy and occupancy[unit.grid_position] == unit:
		free_cell(unit.grid_position)
	release_move_reservation(unit)
	all_units.erase(unit)
	if unit.get_parent() == self:
		remove_child(unit)


func get_distance(a: Vector2i, b: Vector2i) -> float:
	"""网格曼哈顿距离"""
	return abs(a.x - b.x) + abs(a.y - b.y)


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


func _get_unit_query_grid_position(unit: Node) -> Vector2i:
	if unit is UnitBase:
		var combat_unit := unit as UnitBase
		if not _uses_grid_occupancy(unit):
			combat_unit.grid_position = world_to_grid(combat_unit.get_ground_position())
			return combat_unit.grid_position
		if combat_unit.is_moving():
			return world_to_grid(combat_unit.get_ground_position())
	return unit.grid_position


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


func get_touching_units(unit: UnitBase, team: String = "") -> Array:
	if not unit:
		return []
	return get_units_touching_circle(unit.get_ground_position(), unit.get_collision_radius(), team, unit)


func would_unit_collide_on_segment(unit: UnitBase, from_ground: Vector2, to_ground: Vector2, team: String = "") -> bool:
	"""检测单位地面圆从 from 到 to 的移动线段是否会碰到其他单位"""
	if not unit:
		return false
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
		var radius_sum := unit.get_collision_radius() + other_unit.get_collision_radius()
		if _distance_point_to_segment_squared(other_unit.get_ground_position(), from_ground, to_ground) <= radius_sum * radius_sum:
			return true
	return false


func _distance_point_to_segment_squared(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_sq := segment.length_squared()
	if length_sq <= 0.0001:
		return point.distance_squared_to(segment_start)
	var t := clampf((point - segment_start).dot(segment) / length_sq, 0.0, 1.0)
	var closest := segment_start + segment * t
	return point.distance_squared_to(closest)


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


func _is_cell_available_for_unit(cell: Vector2i, unit: Node = null) -> bool:
	if not is_move_zone(cell):
		return false
	if occupancy.has(cell) and occupancy[cell] != unit:
		return false
	if movement_reservations.has(cell) and movement_reservations[cell] != unit:
		return false
	return true


func find_path(from: Vector2i, to: Vector2i) -> Array:
	"""简单BFS寻路（忽略障碍物，只做网格约束）"""
	var queue: Array = [[from]]
	var visited: Dictionary = {from: true}

	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var current: Vector2i = path.back()

		if current == to:
			return path

		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var next: Vector2i = current + dir
			if not is_in_bounds(next) or visited.has(next):
				continue
			# 忽略被占据的格子（除非是目标）
			if occupancy.has(next) and next != to:
				continue
			visited[next] = true
			var new_path := path.duplicate()
			new_path.append(next)
			queue.append(new_path)

	return []  # 无路径


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


func _is_mouse_over_ui() -> bool:
	"""递归检查鼠标是否在任何可见 Control 节点上"""
	return _check_control_hit(get_tree().root, get_global_mouse_position())


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


func _is_unit_visual_control(control: Control) -> bool:
	"""判断Control是否属于战场单位自身的占位UI；这类UI不应阻挡单位点击"""
	var node: Node = control
	while node:
		if node is UnitBase:
			return true
		node = node.get_parent()
	return false
