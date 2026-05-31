# grid_system.gd — 网格战斗场地
# 管理网格布局、单位位置追踪、范围查询、寻路
class_name GridSystem
extends Node2D

const M = "Grid"

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
## 所有单位引用
var all_units: Array[Node] = []

## 可视化
@export var draw_grid: bool = true
@export var grid_color: Color = Color(0.5, 0.5, 0.5, 0.65)
@export var deploy_zone_color: Color = Color(0.2, 0.5, 0.2, 0.3)
@export var spawn_zone_color: Color = Color(0.5, 0.2, 0.2, 0.3)
## Debug: 打印 UI 命中检测日志
@export var debug_ui_hits: bool = true


func _ready() -> void:
	# 初始化默认出生点（右侧边缘，仅在可部署/可移动范围内）
	if spawn_points.is_empty():
		for y in range(deploy_rows.x, deploy_rows.y + 1):
			spawn_points.append(Vector2i(grid_width - 1, y))
	BattleManager.grid = self
	queue_redraw()


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
	return occupancy.has(grid_pos)


func is_deploy_zone(grid_pos: Vector2i) -> bool:
	return grid_pos.y >= deploy_rows.x and grid_pos.y <= deploy_rows.y


func is_move_zone(grid_pos: Vector2i) -> bool:
	"""是否在可移动范围内（与可部署范围一致）"""
	return is_in_bounds(grid_pos) and is_deploy_zone(grid_pos)


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

		occupy_cell(spawn_pos, enemy)
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
