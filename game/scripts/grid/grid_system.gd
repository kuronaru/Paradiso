# grid_system.gd — 网格战斗场地
# 管理网格布局、单位位置追踪、范围查询、寻路
class_name GridSystem
extends Node2D

signal cell_clicked(grid_pos: Vector2i)
signal unit_placed(unit: Node, grid_pos: Vector2i)

## 网格配置
@export var grid_width: int = 20         # 格子列数
@export var grid_height: int = 12        # 格子行数
@export var cell_size: float = 64.0      # 格子像素大小
@export var grid_offset: Vector2 = Vector2(32, 32)  # 网格起始偏移

## 部署区域（玩家可部署的行范围）
@export var deploy_rows: Vector2i = Vector2i(0, 4)

## 敌方出生点
@export var spawn_points: Array[Vector2i] = []

## 占据表 {Vector2i: Node}
var occupancy: Dictionary = {}
## 所有单位引用
var all_units: Array[Node] = []

## 可视化
@export var draw_grid: bool = true
@export var grid_color: Color = Color(0.3, 0.3, 0.3, 0.5)
@export var deploy_zone_color: Color = Color(0.2, 0.5, 0.2, 0.3)
@export var spawn_zone_color: Color = Color(0.5, 0.2, 0.2, 0.3)


func _ready() -> void:
	# 初始化默认出生点（右侧边缘）
	if spawn_points.is_empty():
		for y in range(deploy_rows.x, grid_height):
			spawn_points.append(Vector2i(grid_width - 1, y))
	BattleManager.grid = self
	queue_redraw()


func _draw() -> void:
	if not draw_grid:
		return

	for x in range(grid_width + 1):
		var start := grid_to_world(Vector2i(x, 0))
		var end := grid_to_world(Vector2i(x, grid_height))
		draw_line(start, end, grid_color, 1.0)

	for y in range(grid_height + 1):
		var start := grid_to_world(Vector2i(0, y))
		var end := grid_to_world(Vector2i(grid_width, y))
		draw_line(start, end, grid_color, 1.0)

	# 部署区域高亮
	var deploy_rect := Rect2(
		grid_to_world(Vector2i(0, deploy_rows.x)),
		grid_to_world(Vector2i(grid_width, deploy_rows.y + 1)) - grid_to_world(Vector2i(0, deploy_rows.x))
	)
	draw_rect(deploy_rect, deploy_zone_color)

	# 出生区域高亮
	if not spawn_points.is_empty():
		for sp in spawn_points:
			var sp_rect := Rect2(
				grid_to_world(sp),
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
	return occupancy.has(grid_pos)


func is_deploy_zone(grid_pos: Vector2i) -> bool:
	return grid_pos.y >= deploy_rows.x and grid_pos.y <= deploy_rows.y


func can_place_at(grid_pos: Vector2i) -> bool:
	"""是否可以在指定位置部署"""
	return is_in_bounds(grid_pos) and not is_occupied(grid_pos) and is_deploy_zone(grid_pos)


func occupy_cell(grid_pos: Vector2i, unit: Node) -> void:
	"""占用一个格子"""
	occupancy[grid_pos] = unit


func free_cell(grid_pos: Vector2i) -> void:
	"""释放一个格子"""
	occupancy.erase(grid_pos)


func place_unit(unit: Node, grid_pos: Vector2i) -> bool:
	"""放置单位到网格"""
	if not can_place_at(grid_pos):
		return false
	occupy_cell(grid_pos, unit)
	unit.grid_position = grid_pos
	unit.global_position = grid_to_world(grid_pos)
	if unit not in all_units:
		all_units.append(unit)
		add_child(unit)
	unit_placed.emit(unit, grid_pos)
	return true


func remove_unit(unit: Node) -> void:
	"""从网格移除单位"""
	if unit.grid_position in occupancy:
		free_cell(unit.grid_position)
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
		if team != "" and unit.has_method("get_team") and unit.get_team() != team:
			continue
		if get_distance(center, unit.grid_position) <= radius:
			result.append(unit)
	return result


func get_nearest_unit(center: Vector2i, team: String = "") -> Node:
	"""获取最近的单位"""
	var nearest: Node = null
	var nearest_dist: float = INF
	for unit in all_units:
		if team != "" and unit.has_method("get_team") and unit.get_team() != team:
			continue
		var d := get_distance(center, unit.grid_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = unit
	return nearest


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
	if not is_in_bounds(new_pos) or (is_occupied(new_pos) and occupancy[new_pos] != unit):
		return false
	var old_pos: Vector2i = unit.grid_position
	free_cell(old_pos)
	occupy_cell(new_pos, unit)
	unit.grid_position = new_pos
	return true


func spawn_enemy_wave(enemy_templates: Array, spawns: Array) -> void:
	"""批量生成敌人"""
	var sp_list := spawns.duplicate()
	if sp_list.is_empty():
		# 使用默认右侧出生点
		for y in range(deploy_rows.x, grid_height):
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

		occupy_cell(spawn_pos, enemy)
		enemy.grid_position = spawn_pos
		enemy.global_position = grid_to_world(spawn_pos)
		all_units.append(enemy)
		add_child(enemy)
		BattleManager.register_enemy_unit(enemy)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var grid_pos := world_to_grid(get_global_mouse_position())
		if is_in_bounds(grid_pos):
			cell_clicked.emit(grid_pos)
