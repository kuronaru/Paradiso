# grid_system.gd — 网格战斗场地
# 管理网格布局、单位位置追踪、范围查询、寻路
class_name GridSystem
extends Node2D

const M = "Grid"
const BattlefieldProjectionScript = preload("res://scripts/grid/battlefield_projection.gd")
const PREP_GRID_RECT := Rect2(64, 32, 1152, 400)
const LAYOUT_TWEEN_TIME := 0.22
const UNIT_DEPTH_Z_RANGE := 64
const INVALID_GRID_POS := Vector2i(-9999, -9999)
const ENEMY_PREVIEW_MIN_SHIFT_COLUMNS := 3.0
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

enum TerrainType {
	NORMAL,
	BLOCKED,
	PLAYER_BASE,
	ENEMY_BASE,
}

signal cell_clicked(grid_pos: Vector2i)
signal unit_clicked(unit: Node)
signal unit_placed(unit: Node, grid_pos: Vector2i)
signal enemy_preview_view_changed(enabled: bool)

## 网格配置
@export var grid_width: int = 9          # 格子列数
@export var grid_height: int = 4         # 格子行数
@export var cell_size: float = 64.0      # 格子像素大小
@export var grid_offset: Vector2 = Vector2(32, 32)  # 网格起始偏移

## 2.5D 轻透视投影。X 为横向、Y 为高度、Z 为棋盘纵深。
@export var projection_enabled: bool = true
@export_range(45.0, 60.0, 0.5) var camera_pitch_degrees: float = 55.0
@export_range(0.0, 0.25, 0.01) var perspective_strength: float = 0.12
@export_range(0.0, 1.0, 0.05) var unit_visual_y_anchor: float = 0.2
@export_range(0, 3, 1) var reserve_rows: int = 1
@export_range(0.0, 1.0, 0.02) var reserve_gap_cells: float = 0.2
@export_range(1, 16, 1) var reserve_slot_count: int = 10
@export_range(0.0, 24.0, 1.0) var reserve_recruit_gap: float = 6.0
@export var board_thickness: float = 18.0
@export var board_front_side_color: Color = Color(0.09, 0.11, 0.15, 0.92)
@export var board_right_side_color: Color = Color(0.07, 0.09, 0.12, 0.92)

## 战斗开始后招募栏隐藏，棋盘改为贴近屏幕边缘的独立布局。
@export_range(0.0, 128.0, 1.0) var combat_horizontal_margin: float = 16.0
@export_range(0.0, 128.0, 1.0) var combat_top_margin: float = 24.0
@export_range(0.0, 128.0, 1.0) var combat_bottom_margin: float = 12.0

## 准备阶段右侧的下一波敌人预览棋盘。
@export_range(1, 8, 1) var enemy_preview_columns: int = 5
@export_range(1, 8, 1) var enemy_preview_rows: int = 4
@export_range(0.0, 3.0, 0.05) var enemy_preview_gap_cells: float = 0.4
@export var enemy_preview_zone_color: Color = Color(0.38, 0.10, 0.12, 0.58)
@export var enemy_preview_line_color: Color = Color(0.92, 0.34, 0.30, 0.78)

## 旧版部署行范围，仅保留给外部旧代码读取；部署与寻路不再依赖它
@export var deploy_rows: Vector2i = Vector2i(0, 3)

## 地形配置
@export var blocked_cells: Array[Vector2i] = []
@export var player_base_cells: Array[Vector2i] = []
@export var enemy_base_cells: Array[Vector2i] = []

## 旧版敌方出生点入口；为空时与 enemy_base_cells 保持一致
@export var spawn_points: Array[Vector2i] = []
@export var enemy_spawn_interval: float = 0.6

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
@export var blocked_zone_color: Color = Color(0.16, 0.16, 0.2, 0.82)
@export var player_base_color: Color = Color(0.15, 0.38, 0.85, 0.58)
@export var enemy_base_color: Color = Color(0.78, 0.16, 0.18, 0.58)
@export var reserve_zone_color: Color = Color(0.08, 0.16, 0.28, 0.72)
@export var reserve_slot_line_color: Color = Color(0.3, 0.58, 0.9, 0.78)
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
var enemy_spawn_queue: Array[Dictionary] = []
var enemy_spawn_time_remaining: float = 0.0
var enemy_spawn_cycle_cursor: int = 0
var combat_view_shift_x: float = 0.0
var enemy_preview_view_enabled: bool = false
var enemy_preview_units: Array[UnitBase] = []
var enemy_preview_cells: Array[Vector2i] = []


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	_initialize_terrain_cells()
	if spawn_points.is_empty():
		for cell in enemy_base_cells:
			spawn_points.append(cell)
	BattleManager.grid = self
	if BattleManager.next_wave_preview_changed and not BattleManager.next_wave_preview_changed.is_connected(_on_next_wave_preview_changed):
		BattleManager.next_wave_preview_changed.connect(_on_next_wave_preview_changed)
	last_prepare_layout = _is_prepare_layout()
	_apply_stage_layout(false)
	_rebuild_enemy_preview(BattleManager.get_next_wave_preview_enemies())
	queue_redraw()


func _exit_tree() -> void:
	if BattleManager.next_wave_preview_changed and BattleManager.next_wave_preview_changed.is_connected(_on_next_wave_preview_changed):
		BattleManager.next_wave_preview_changed.disconnect(_on_next_wave_preview_changed)
	_clear_enemy_preview_units()


## 初始化地形和左右两侧的默认两格据点。
func _initialize_terrain_cells() -> void:
	blocked_cells = _normalized_cells(blocked_cells)
	player_base_cells = _normalized_cells(player_base_cells)
	enemy_base_cells = _normalized_cells(enemy_base_cells)

	if player_base_cells.is_empty():
		player_base_cells = _build_default_base_cells(0)
	if enemy_base_cells.is_empty():
		enemy_base_cells = _build_default_base_cells(grid_width - 1)

	_sort_cells_top_to_bottom(player_base_cells)
	_sort_cells_top_to_bottom(enemy_base_cells)


## 构建指定列的中间两格据点。
func _build_default_base_cells(column: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if grid_width <= 0 or grid_height <= 0:
		return result
	var count := mini(2, grid_height)
	var start_y := maxi(0, int(floor(float(grid_height - count) * 0.5)))
	var clamped_column := clampi(column, 0, grid_width - 1)
	for offset in range(count):
		result.append(Vector2i(clamped_column, start_y + offset))
	return result


## 去除越界或重复的地形坐标。
func _normalized_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cells:
		if is_in_bounds(cell) and cell not in result:
			result.append(cell)
	return result


## 据点始终保持从上到下、同一行从左到右的稳定顺序。
func _sort_cells_top_to_bottom(cells: Array[Vector2i]) -> void:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)


## 每帧更新运行状态。
func _process(delta: float) -> void:
	_update_enemy_spawn_queue(delta)
	for unit in all_units:
		if is_instance_valid(unit):
			_sync_unit_projection(unit)
	var wants_prepare := _is_prepare_layout()
	if wants_prepare != last_prepare_layout:
		last_prepare_layout = wants_prepare
		if not wants_prepare:
			enemy_preview_view_enabled = false
			combat_view_shift_x = 0.0
			_clear_enemy_preview_units()
		elif enemy_preview_units.is_empty():
			_rebuild_enemy_preview(BattleManager.get_next_wave_preview_enemies())
		_apply_stage_layout(true)

	var needs_redraw := false
	if layout_animating:
		_sync_unit_positions()
		_sync_enemy_preview_positions()
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
	var preparing := _is_prepare_layout()
	var viewport_size := get_viewport_rect().size
	var base_rect := PREP_GRID_RECT
	var layout_bottom := get_recruit_panel_top_y() - reserve_recruit_gap
	var sizing_bottom := get_recruit_panel_top_y()
	if not preparing:
		var horizontal_margin := clampf(combat_horizontal_margin, 0.0, viewport_size.x * 0.5)
		var top_margin := clampf(combat_top_margin, 0.0, viewport_size.y)
		layout_bottom = viewport_size.y - clampf(combat_bottom_margin, 0.0, viewport_size.y)
		sizing_bottom = layout_bottom
		base_rect = Rect2(
			Vector2(horizontal_margin, top_margin),
			Vector2(maxf(viewport_size.x - horizontal_margin * 2.0, 1.0), maxf(layout_bottom - top_margin, 1.0))
		)
	var target_rect := Rect2(
		base_rect.position,
		Vector2(base_rect.size.x, maxf(sizing_bottom - base_rect.position.y, 1.0))
	)
	var layout_factors := _get_projected_layout_factors()
	var projected_thickness := _get_front_projected_thickness(1.0)
	var next_cell_size := maxf(1.0, floorf(minf(
		target_rect.size.x / layout_factors.x,
		maxf(target_rect.size.y - projected_thickness, 1.0) / layout_factors.y
	)))
	var next_grid_size := Vector2(
		layout_factors.x * next_cell_size,
		layout_factors.y * next_cell_size
	)
	var active_grid_width := float(grid_width) * next_cell_size
	projected_thickness = _get_front_projected_thickness(next_cell_size)
	var next_offset := Vector2(
		target_rect.position.x + target_rect.size.x * 0.5 - active_grid_width * 0.5,
		layout_bottom - projected_thickness - next_grid_size.y
	)
	if preparing:
		# 以透视后的备战区左下角为锚点，而不是直接使用主战场原点。
		var reserve_bottom_left_local := _get_reserve_bottom_left_with_cell_size(next_cell_size)
		next_offset.x = get_recruit_panel_left_x() - reserve_bottom_left_local.x
	var next_combat_shift := 0.0
	if preparing and enemy_preview_view_enabled:
		next_combat_shift = _get_enemy_preview_shift_for_layout(next_offset, next_cell_size)

	if layout_tween and layout_tween.is_valid():
		layout_tween.kill()
		layout_animating = false

	if animated and is_inside_tree():
		layout_animating = true
		layout_tween = create_tween()
		layout_tween.set_parallel(true)
		layout_tween.tween_property(self, "grid_offset", next_offset, LAYOUT_TWEEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		layout_tween.tween_property(self, "cell_size", next_cell_size, LAYOUT_TWEEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		layout_tween.tween_property(self, "combat_view_shift_x", next_combat_shift, LAYOUT_TWEEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		layout_tween.finished.connect(func():
			layout_animating = false
			_sync_unit_positions()
			_sync_enemy_preview_positions()
			queue_redraw()
		)
	else:
		grid_offset = next_offset
		cell_size = next_cell_size
		combat_view_shift_x = next_combat_shift
		_sync_unit_positions()
		_sync_enemy_preview_positions()
		queue_redraw()


## 计算包含近景备战延伸区后的单位尺寸占用。
func _get_projected_layout_factors() -> Vector2:
	var safe_height := maxf(float(grid_height), 1.0)
	var reserve_depth := _get_reserve_depth_for_cell_size(1.0) + (maxf(reserve_gap_cells, 0.0) if reserve_rows > 0 else 0.0)
	if not projection_enabled:
		return Vector2(float(grid_width), safe_height + reserve_depth)
	var near_scale := BattlefieldProjectionScript.perspective_scale(-reserve_depth, safe_height, perspective_strength)
	var width_factor := float(grid_width) * near_scale
	var pitch := deg_to_rad(camera_pitch_degrees)
	var near_denominator := maxf(1.0 - perspective_strength * reserve_depth / safe_height, 0.05)
	var height_factor := (safe_height + reserve_depth) * sin(pitch) / near_denominator
	return Vector2(width_factor, height_factor)


## 招募栏在准备阶段的实际上边框，作为战场近景底边锚点。
func get_recruit_panel_top_y() -> float:
	return get_viewport_rect().size.y - RecruitUI.PANEL_HEIGHT - 8.0


## 招募栏左边框；准备阶段以备战区左下角对齐此处。
func get_recruit_panel_left_x() -> float:
	return RecruitUI.PANEL_MARGIN


## 槽位数量会改变槽宽与备战区纵深，因此必须同时重算整体布局。
func set_reserve_slot_count(next_count: int, animated: bool = false) -> void:
	var resolved_count := maxi(next_count, 1)
	if reserve_slot_count == resolved_count:
		return
	reserve_slot_count = resolved_count
	_apply_stage_layout(animated)


func _get_enemy_preview_shift_for_layout(next_offset: Vector2, next_cell_size: float) -> float:
	var right_world := (float(grid_width) + maxf(enemy_preview_gap_cells, 0.0) + float(enemy_preview_columns)) * next_cell_size
	var right_edge := -INF
	for row in [0.0, float(enemy_preview_rows)]:
		var point := next_offset + _project_with_cell_size(Vector3(right_world, 0.0, row * next_cell_size), next_cell_size)
		right_edge = maxf(right_edge, point.x)
	var required_shift := maxf(right_edge - (get_viewport_rect().size.x - RecruitUI.PANEL_MARGIN), 0.0)
	return -maxf(required_shift, ENEMY_PREVIEW_MIN_SHIFT_COLUMNS * next_cell_size)


func _get_front_projected_thickness(for_cell_size: float = -1.0) -> float:
	var resolved_cell_size := for_cell_size if for_cell_size > 0.0 else self.cell_size
	var total_reserve_depth := _get_reserve_depth_for_cell_size(resolved_cell_size) \
		+ (maxf(reserve_gap_cells, 0.0) * resolved_cell_size if reserve_rows > 0 else 0.0)
	var front_z := -total_reserve_depth
	var top := _project_with_cell_size(Vector3(0.0, 0.0, front_z), resolved_cell_size)
	var bottom := _project_with_cell_size(Vector3(0.0, -board_thickness, front_z), resolved_cell_size)
	return maxf(bottom.y - top.y, 0.0)


func _get_reserve_bottom_left_with_cell_size(for_cell_size: float) -> Vector2:
	var near_depth := -(maxf(reserve_gap_cells, 0.0) * for_cell_size + _get_reserve_depth_for_cell_size(for_cell_size))
	return _project_with_cell_size(Vector3(0.0, -board_thickness, near_depth), for_cell_size)


## 每个备战槽在地面上保持正方形：纵深等于该槽的横向宽度。
func _get_reserve_depth_for_cell_size(for_cell_size: float, slot_count: int = -1) -> float:
	if reserve_rows <= 0:
		return 0.0
	var count := reserve_slot_count if slot_count <= 0 else slot_count
	count = maxi(count, 1)
	var slot_width := float(grid_width) * for_cell_size / float(count)
	return slot_width * float(reserve_rows)


func _project_with_cell_size(world_position: Vector3, projection_cell_size: float) -> Vector2:
	if not projection_enabled:
		return Vector2(world_position.x, world_position.z - world_position.y)
	return BattlefieldProjectionScript.world_to_screen(
		world_position,
		Vector2.ZERO,
		camera_pitch_degrees,
		float(grid_width) * projection_cell_size * 0.5,
		float(grid_height) * projection_cell_size,
		perspective_strength
	)


## 同步单位位置。
func _sync_unit_positions() -> void:
	for unit in all_units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("sync_geometry_to_grid"):
			unit.sync_geometry_to_grid(cell_size)
		if _uses_grid_occupancy(unit) and not (unit as UnitBase).is_moving():
			unit.global_position = grid_to_world(unit.grid_position)
		_sync_unit_projection(unit)
	_sync_enemy_preview_positions()


## 绘制调试或界面可视元素。
func _draw() -> void:
	if draw_grid:
		_draw_board_sides()
		_draw_reserve_zone()
		_draw_enemy_preview_board()
		# 逐格绘制可部署普通地形、阻挡地形和双方据点。
		for x in range(grid_width):
			for y in range(grid_height):
				var cell := Vector2i(x, y)
				var terrain_color := deploy_zone_color
				match get_terrain_type(cell):
					TerrainType.BLOCKED:
						terrain_color = blocked_zone_color
					TerrainType.PLAYER_BASE:
						terrain_color = player_base_color
					TerrainType.ENEMY_BASE:
						terrain_color = enemy_base_color
				draw_colored_polygon(_get_cell_polygon(cell), terrain_color)

		# 网格线画在地形填充之上。
		for x in range(grid_width + 1):
			var start := world_to_screen(Vector3(float(x) * cell_size, 0.0, 0.0))
			var end := world_to_screen(Vector3(float(x) * cell_size, 0.0, float(grid_height) * cell_size))
			draw_line(start, end, grid_color, 1.0)

		for y in range(grid_height + 1):
			var start := world_to_screen(Vector3(0.0, 0.0, float(y) * cell_size))
			var end := world_to_screen(Vector3(float(grid_width) * cell_size, 0.0, float(y) * cell_size))
			draw_line(start, end, grid_color, 1.0)

	if debug_collision_prediction:
		_draw_collision_debug_entries()


## 绘制与战场连续的近景备战槽位。
func _draw_reserve_zone() -> void:
	if reserve_rows <= 0 or reserve_slot_count <= 0:
		return
	var width := float(grid_width) * cell_size
	var reserve_depth := _get_reserve_depth_for_cell_size(cell_size)
	var gap_depth := maxf(reserve_gap_cells, 0.0) * cell_size
	var far_depth := -gap_depth
	var near_depth := -(gap_depth + reserve_depth)
	var slot_width := width / float(reserve_slot_count)
	for index in range(reserve_slot_count):
		var left := float(index) * slot_width
		var right := float(index + 1) * slot_width
		var polygon := PackedVector2Array([
			world_to_screen(Vector3(left, 0.0, far_depth)),
			world_to_screen(Vector3(right, 0.0, far_depth)),
			world_to_screen(Vector3(right, 0.0, near_depth)),
			world_to_screen(Vector3(left, 0.0, near_depth)),
		])
		var fill := reserve_zone_color.lightened(0.035) if index % 2 == 0 else reserve_zone_color
		draw_colored_polygon(polygon, fill)
		for point_index in range(polygon.size()):
			draw_line(polygon[point_index], polygon[(point_index + 1) % polygon.size()], reserve_slot_line_color, 1.0)


## 网格坐标转世界坐标（格子中心）
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""网格坐标转世界坐标（格子中心）"""
	return world_to_screen(Vector3(
		(float(grid_pos.x) + 0.5) * cell_size,
		0.0,
		(float(grid_pos.y) + 0.5) * cell_size
	))


## 三维战场坐标转到当前二维画布。
func world_to_screen(world_position: Vector3) -> Vector2:
	var projection_origin := grid_offset
	if world_position.z >= 0.0:
		projection_origin.x += combat_view_shift_x
	return _world_to_screen_with_origin(world_position, projection_origin)


func _world_to_screen_with_origin(world_position: Vector3, projection_origin: Vector2) -> Vector2:
	if not projection_enabled:
		return projection_origin + Vector2(world_position.x, world_position.z - world_position.y)
	return BattlefieldProjectionScript.world_to_screen(
		world_position,
		projection_origin,
		camera_pitch_degrees,
		float(grid_width) * cell_size * 0.5,
		float(grid_height) * cell_size,
		perspective_strength
	)


## 二维画布点反算到指定高度的三维战场平面。
func screen_to_world(screen_position: Vector2, world_height: float = 0.0) -> Vector3:
	var combat_origin := grid_offset + Vector2(combat_view_shift_x, 0.0)
	var combat_world := _screen_to_world_with_origin(screen_position, world_height, combat_origin)
	if combat_world.z >= 0.0:
		return combat_world
	var reserve_world := _screen_to_world_with_origin(screen_position, world_height, grid_offset)
	if reserve_world.z < 0.0:
		return reserve_world
	return combat_world


func _screen_to_world_with_origin(screen_position: Vector2, world_height: float, origin: Vector2) -> Vector3:
	if not projection_enabled:
		var local := screen_position - origin
		return Vector3(local.x, world_height, local.y + world_height)
	return BattlefieldProjectionScript.screen_to_world(
		screen_position,
		world_height,
		origin,
		camera_pitch_degrees,
		float(grid_width) * cell_size * 0.5,
		float(grid_height) * cell_size,
		perspective_strength
	)


## 当前纵深方向的屏幕压缩比例。
func get_projection_depth_scale() -> float:
	return BattlefieldProjectionScript.depth_scale(camera_pitch_degrees, perspective_strength) if projection_enabled else 1.0


## 当前高度方向的屏幕投影比例。
func get_projection_height_scale() -> float:
	return BattlefieldProjectionScript.height_scale(camera_pitch_degrees) if projection_enabled else 1.0


## 把地面上的局部 X/Z 偏移转换为屏幕偏移，供碰撞圈和攻击范围逐点投影。
func project_ground_offset(screen_ground_position: Vector2, ground_offset: Vector2) -> Vector2:
	if not projection_enabled:
		return ground_offset
	var center_world := screen_to_world(screen_ground_position, 0.0)
	var offset_world := center_world + Vector3(ground_offset.x, 0.0, ground_offset.y)
	# 整个辅助轮廓继承中心点所属的投影空间。即使某个圆周采样点跨入 Z<0，
	# 也不能中途切换为未平移的备战区原点。
	var projection_origin := grid_offset
	if center_world.z >= 0.0:
		projection_origin.x += combat_view_shift_x
	return _world_to_screen_with_origin(offset_world, projection_origin) - screen_ground_position


## 当前地面点附近的局部投影基，用于让 CollisionShape2D 近似匹配透视平面。
func get_ground_projection_basis(screen_ground_position: Vector2) -> Transform2D:
	var x_axis := project_ground_offset(screen_ground_position, Vector2.RIGHT)
	var z_axis := project_ground_offset(screen_ground_position, Vector2.DOWN)
	return Transform2D(x_axis, z_axis, Vector2.ZERO)


## 获取格子的世界坐标矩形。
func _get_cell_rect(grid_pos: Vector2i) -> Rect2:
	var polygon := _get_cell_polygon(grid_pos)
	return Rect2(polygon[0], Vector2.ZERO).expand(polygon[1]).expand(polygon[2]).expand(polygon[3])


## 获取投影后的格子四边形。
func _get_cell_polygon(grid_pos: Vector2i) -> PackedVector2Array:
	var left := float(grid_pos.x) * cell_size
	var right := float(grid_pos.x + 1) * cell_size
	var far_depth := float(grid_pos.y) * cell_size
	var near_depth := float(grid_pos.y + 1) * cell_size
	return PackedVector2Array([
		world_to_screen(Vector3(left, 0.0, far_depth)),
		world_to_screen(Vector3(right, 0.0, far_depth)),
		world_to_screen(Vector3(right, 0.0, near_depth)),
		world_to_screen(Vector3(left, 0.0, near_depth)),
	])


## 绘制准备阶段右侧 4x5 下一波敌人棋盘。
func _draw_enemy_preview_board() -> void:
	if not _is_prepare_layout() or enemy_preview_columns <= 0 or enemy_preview_rows <= 0:
		return
	for column in range(enemy_preview_columns):
		for row in range(enemy_preview_rows):
			var polygon := _get_enemy_preview_cell_polygon(Vector2i(column, row))
			var fill := enemy_preview_zone_color.lightened(0.035) if (column + row) % 2 == 0 else enemy_preview_zone_color
			draw_colored_polygon(polygon, fill)
			for point_index in range(polygon.size()):
				draw_line(polygon[point_index], polygon[(point_index + 1) % polygon.size()], enemy_preview_line_color, 1.0)


func _get_enemy_preview_cell_polygon(preview_cell: Vector2i) -> PackedVector2Array:
	var start_column := float(grid_width) + maxf(enemy_preview_gap_cells, 0.0)
	var left := (start_column + float(preview_cell.x)) * cell_size
	var right := left + cell_size
	var far_depth := float(preview_cell.y) * cell_size
	var near_depth := float(preview_cell.y + 1) * cell_size
	return PackedVector2Array([
		world_to_screen(Vector3(left, 0.0, far_depth)),
		world_to_screen(Vector3(right, 0.0, far_depth)),
		world_to_screen(Vector3(right, 0.0, near_depth)),
		world_to_screen(Vector3(left, 0.0, near_depth)),
	])


## 绘制棋盘前沿和右侧厚度，让平面获得稳定的 3D 轮廓。
func _draw_board_sides() -> void:
	if not projection_enabled or board_thickness <= 0.0:
		return
	var width := float(grid_width) * cell_size
	var depth := float(grid_height) * cell_size
	# 主战场在 Z=0 处结束，先绘制其独立前沿，间隔区域保持为空。
	var battle_front_left := world_to_screen(Vector3(0.0, 0.0, 0.0))
	var battle_front_right := world_to_screen(Vector3(width, 0.0, 0.0))
	var battle_front_left_bottom := world_to_screen(Vector3(0.0, -board_thickness, 0.0))
	var battle_front_right_bottom := world_to_screen(Vector3(width, -board_thickness, 0.0))
	draw_colored_polygon(PackedVector2Array([
		battle_front_left, battle_front_right, battle_front_right_bottom, battle_front_left_bottom
	]), board_front_side_color)
	var far_right := world_to_screen(Vector3(width, 0.0, depth))
	var far_right_bottom := world_to_screen(Vector3(width, -board_thickness, depth))
	draw_colored_polygon(PackedVector2Array([
		far_right, battle_front_right, battle_front_right_bottom, far_right_bottom
	]), board_right_side_color)

	if _is_prepare_layout() and enemy_preview_columns > 0 and enemy_preview_rows > 0:
		var preview_left_x := (float(grid_width) + maxf(enemy_preview_gap_cells, 0.0)) * cell_size
		var preview_right_x := preview_left_x + float(enemy_preview_columns) * cell_size
		var preview_depth := float(enemy_preview_rows) * cell_size
		var preview_front_left := world_to_screen(Vector3(preview_left_x, 0.0, 0.0))
		var preview_front_right := world_to_screen(Vector3(preview_right_x, 0.0, 0.0))
		var preview_front_left_bottom := world_to_screen(Vector3(preview_left_x, -board_thickness, 0.0))
		var preview_front_right_bottom := world_to_screen(Vector3(preview_right_x, -board_thickness, 0.0))
		draw_colored_polygon(PackedVector2Array([
			preview_front_left, preview_front_right, preview_front_right_bottom, preview_front_left_bottom
		]), board_front_side_color)
		var preview_far_right := world_to_screen(Vector3(preview_right_x, 0.0, preview_depth))
		var preview_far_right_bottom := world_to_screen(Vector3(preview_right_x, -board_thickness, preview_depth))
		draw_colored_polygon(PackedVector2Array([
			preview_far_right, preview_front_right, preview_front_right_bottom, preview_far_right_bottom
		]), board_right_side_color)

	if reserve_rows > 0:
		var reserve_far := -maxf(reserve_gap_cells, 0.0) * cell_size
		var reserve_near := -(maxf(reserve_gap_cells, 0.0) * cell_size + _get_reserve_depth_for_cell_size(cell_size))
		var reserve_front_left := world_to_screen(Vector3(0.0, 0.0, reserve_near))
		var reserve_front_right := world_to_screen(Vector3(width, 0.0, reserve_near))
		var reserve_front_left_bottom := world_to_screen(Vector3(0.0, -board_thickness, reserve_near))
		var reserve_front_right_bottom := world_to_screen(Vector3(width, -board_thickness, reserve_near))
		draw_colored_polygon(PackedVector2Array([
			reserve_front_left, reserve_front_right, reserve_front_right_bottom, reserve_front_left_bottom
		]), board_front_side_color)
		var reserve_far_right := world_to_screen(Vector3(width, 0.0, reserve_far))
		var reserve_far_right_bottom := world_to_screen(Vector3(width, -board_thickness, reserve_far))
		draw_colored_polygon(PackedVector2Array([
			reserve_far_right, reserve_front_right, reserve_front_right_bottom, reserve_far_right_bottom
		]), board_right_side_color)


## 获取备战槽位中心的投影坐标。
func reserve_slot_to_world(slot_index: int, slot_count: int = -1) -> Vector2:
	var count := reserve_slot_count if slot_count <= 0 else slot_count
	count = maxi(count, 1)
	var index := clampi(slot_index, 0, count - 1)
	var width := float(grid_width) * cell_size
	var x := width * (float(index) + 0.5) / float(count)
	var z := -(maxf(reserve_gap_cells, 0.0) * cell_size + _get_reserve_depth_for_cell_size(cell_size, count) * 0.5)
	return world_to_screen(Vector3(x, 0.0, z))


## 获取备战槽人物锚点：与战场单位一致，从方格屏幕上沿向下 unit_visual_y_anchor。
func reserve_slot_visual_anchor(slot_index: int, slot_count: int = -1) -> Vector2:
	var count := reserve_slot_count if slot_count <= 0 else slot_count
	count = maxi(count, 1)
	var index := clampi(slot_index, 0, count - 1)
	var width := float(grid_width) * cell_size
	var x := width * (float(index) + 0.5) / float(count)
	var far_depth := -maxf(reserve_gap_cells, 0.0) * cell_size
	var near_depth := -(maxf(reserve_gap_cells, 0.0) * cell_size + _get_reserve_depth_for_cell_size(cell_size, count))
	var screen_top := world_to_screen(Vector3(x, 0.0, far_depth))
	var screen_bottom := world_to_screen(Vector3(x, 0.0, near_depth))
	return screen_top.lerp(screen_bottom, unit_visual_y_anchor)


## 获取备战延伸区四边形。
func get_reserve_polygon() -> PackedVector2Array:
	var width := float(grid_width) * cell_size
	var depth := _get_reserve_depth_for_cell_size(cell_size)
	var gap_depth := maxf(reserve_gap_cells, 0.0) * cell_size
	return PackedVector2Array([
		world_to_screen(Vector3(0.0, 0.0, -gap_depth)),
		world_to_screen(Vector3(width, 0.0, -gap_depth)),
		world_to_screen(Vector3(width, 0.0, -(gap_depth + depth))),
		world_to_screen(Vector3(0.0, 0.0, -(gap_depth + depth))),
	])


func get_reserve_screen_bounds() -> Rect2:
	var polygon := get_reserve_polygon()
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	return bounds


## 备战区厚度外轮廓的左下角，用于和招募栏上边框对齐。
func get_reserve_bottom_left() -> Vector2:
	var near_depth := -(maxf(reserve_gap_cells, 0.0) * cell_size + _get_reserve_depth_for_cell_size(cell_size))
	return world_to_screen(Vector3(0.0, -board_thickness, near_depth))


## 切换完整敌人预览。只平移 Z>=0 的战场和敌方棋盘，备战区保持原位。
func set_enemy_preview_view(enabled: bool, animated: bool = true) -> void:
	var resolved_enabled := enabled and _is_prepare_layout()
	if enemy_preview_view_enabled == resolved_enabled and not layout_animating:
		return
	enemy_preview_view_enabled = resolved_enabled
	_apply_stage_layout(animated)
	enemy_preview_view_changed.emit(enemy_preview_view_enabled)


func toggle_enemy_preview_view() -> void:
	set_enemy_preview_view(not enemy_preview_view_enabled, true)


## 主战场和敌方预览棋盘的投影包围盒，供 UI 布局与回归测试使用。
func get_main_battlefield_screen_bounds() -> Rect2:
	return _screen_bounds_from_polygon(PackedVector2Array([
		world_to_screen(Vector3(0.0, 0.0, 0.0)),
		world_to_screen(Vector3(float(grid_width) * cell_size, 0.0, 0.0)),
		world_to_screen(Vector3(float(grid_width) * cell_size, 0.0, float(grid_height) * cell_size)),
		world_to_screen(Vector3(0.0, 0.0, float(grid_height) * cell_size)),
	]))


func get_enemy_preview_board_screen_bounds() -> Rect2:
	var left := (float(grid_width) + maxf(enemy_preview_gap_cells, 0.0)) * cell_size
	var right := left + float(enemy_preview_columns) * cell_size
	var depth := float(enemy_preview_rows) * cell_size
	return _screen_bounds_from_polygon(PackedVector2Array([
		world_to_screen(Vector3(left, 0.0, 0.0)),
		world_to_screen(Vector3(right, 0.0, 0.0)),
		world_to_screen(Vector3(right, 0.0, depth)),
		world_to_screen(Vector3(left, 0.0, depth)),
	]))


func get_enemy_preview_visible_column_count() -> int:
	var viewport_width := get_viewport_rect().size.x
	var visible_count := 0
	for column in range(enemy_preview_columns):
		var column_bounds := _screen_bounds_from_polygon(PackedVector2Array([
			_get_enemy_preview_cell_polygon(Vector2i(column, 0))[0],
			_get_enemy_preview_cell_polygon(Vector2i(column, 0))[1],
			_get_enemy_preview_cell_polygon(Vector2i(column, enemy_preview_rows - 1))[2],
			_get_enemy_preview_cell_polygon(Vector2i(column, enemy_preview_rows - 1))[3],
		]))
		if column_bounds.position.x < viewport_width and column_bounds.end.x > 0.0:
			visible_count += 1
	return visible_count


func _screen_bounds_from_polygon(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	return bounds


func _on_next_wave_preview_changed(enemies: Array) -> void:
	_rebuild_enemy_preview(enemies)


func _rebuild_enemy_preview(enemies: Array) -> void:
	_clear_enemy_preview_units()
	if not _is_prepare_layout() or enemies.is_empty():
		queue_redraw()
		return
	var available_cells: Array[Vector2i] = []
	for column in range(enemy_preview_columns):
		for row in range(enemy_preview_rows):
			available_cells.append(Vector2i(column, row))
	var layout_rng := RandomNumberGenerator.new()
	layout_rng.randomize()
	for index in range(available_cells.size() - 1, 0, -1):
		var swap_index := layout_rng.randi_range(0, index)
		var swap_cell := available_cells[index]
		available_cells[index] = available_cells[swap_index]
		available_cells[swap_index] = swap_cell
	for index in range(enemies.size()):
		var template := enemies[index] as Dictionary
		var preview := _create_enemy_preview_unit(template)
		var preview_cell := available_cells[index % available_cells.size()]
		enemy_preview_units.append(preview)
		enemy_preview_cells.append(preview_cell)
	_sync_enemy_preview_positions()
	queue_redraw()


func _create_enemy_preview_unit(template: Dictionary) -> UnitBase:
	var preview := UnitBase.new()
	preview.name = "EnemyPreview_%s" % str(template.get("enemy_id", enemy_preview_units.size()))
	preview.team = "enemy"
	preview.ai_enabled = false
	preview.unit_name = str(template.get("name", "敌人"))
	preview.visual_id = str(template.get("visual_id", ""))
	preview.max_hp = int(template.get("max_hp", template.get("hp", 80)))
	preview.current_hp = preview.max_hp
	preview.attack = int(template.get("atk", 10))
	preview.defense = int(template.get("def", 3))
	preview.attack_speed = float(template.get("attack_speed", 1.0))
	preview.move_speed = float(template.get("move_speed", 1.5))
	preview.attack_range = float(template.get("attack_range", 1.5))
	preview.search_range = float(template.get("search_range", 5.0))
	preview.color = _enemy_preview_color(template.get("type", template.get("enemy_type", 0)))
	preview.set_base_stats_from_current()
	preview.set_meta("enemy_preview_template", template.duplicate(true))
	add_child(preview)
	preview.enter_reserve_preview_state(cell_size)
	return preview


func _enemy_preview_color(type_value: Variant) -> Color:
	var text_value := str(type_value).to_lower()
	if text_value in ["1", "ranged"]:
		return Color(1.0, 0.6, 0.2)
	if text_value in ["2", "brute"]:
		return Color(0.8, 0.2, 0.2)
	if text_value in ["3", "boss"]:
		return Color(0.8, 0.1, 0.5)
	return Color(1.0, 0.3, 0.3)


func _sync_enemy_preview_positions() -> void:
	for index in range(enemy_preview_units.size()):
		var preview := enemy_preview_units[index]
		if not is_instance_valid(preview) or index >= enemy_preview_cells.size():
			continue
		var preview_cell := enemy_preview_cells[index]
		var world_x := (float(grid_width) + maxf(enemy_preview_gap_cells, 0.0) + float(preview_cell.x) + 0.5) * cell_size
		var world_z := (float(preview_cell.y) + 0.5) * cell_size
		preview.sync_reserve_preview_geometry(cell_size)
		preview.global_position = world_to_screen(Vector3(world_x, 0.0, world_z))
		_sync_unit_projection(preview)


func _clear_enemy_preview_units() -> void:
	for preview in enemy_preview_units:
		if is_instance_valid(preview):
			preview.queue_free()
	enemy_preview_units.clear()
	enemy_preview_cells.clear()


## 判断二维战场点是否位于备战延伸区。
func is_world_point_inside_reserve(world_pos: Vector2) -> bool:
	if reserve_rows <= 0:
		return false
	var ground := screen_to_world(world_pos, 0.0)
	var far_depth := -maxf(reserve_gap_cells, 0.0) * cell_size
	var near_depth := -(maxf(reserve_gap_cells, 0.0) * cell_size + _get_reserve_depth_for_cell_size(cell_size))
	return ground.x >= 0.0 and ground.x < float(grid_width) * cell_size \
		and ground.z <= far_depth and ground.z >= near_depth


## 根据纵深设置单位绘制顺序，人物贴图本身始终保持正立。
func _sync_unit_projection(unit: Node) -> void:
	if not (unit is UnitBase):
		return
	var combat_unit := unit as UnitBase
	var ground := screen_to_world(combat_unit.get_ground_position(), 0.0)
	var board_depth := maxf(float(grid_height) * cell_size, 1.0)
	var depth_ratio := clampf(ground.z / board_depth, 0.0, 1.0)
	combat_unit.z_index = 1 + int(round((1.0 - depth_ratio) * float(UNIT_DEPTH_Z_RANGE)))
	if combat_unit.has_method("set_ground_projection_scale"):
		combat_unit.set_ground_projection_scale(get_projection_depth_scale(), projection_enabled)
	if combat_unit.has_method("set_billboard_screen_offset"):
		var far_edge := world_to_screen(ground + Vector3(0.0, 0.0, cell_size * 0.5))
		var near_edge := world_to_screen(ground - Vector3(0.0, 0.0, cell_size * 0.5))
		var visual_screen := far_edge.lerp(near_edge, unit_visual_y_anchor)
		combat_unit.set_billboard_screen_offset(visual_screen - combat_unit.global_position)


## 世界坐标转网格坐标
func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""世界坐标转网格坐标"""
	var ground := screen_to_world(world_pos, 0.0)
	var gx := int(floor(ground.x / cell_size))
	var gy := int(floor(ground.z / cell_size))
	return Vector2i(clamp(gx, 0, grid_width - 1), clamp(gy, 0, grid_height - 1))


## 判断二维画布点是否落在投影后的棋盘表面。
func is_world_point_inside_grid(world_pos: Vector2) -> bool:
	var ground := screen_to_world(world_pos, 0.0)
	return ground.x >= 0.0 and ground.x < float(grid_width) * cell_size \
		and ground.z >= 0.0 and ground.z < float(grid_height) * cell_size


## 判断边界状态。
func is_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_width and grid_pos.y >= 0 and grid_pos.y < grid_height


## 判断占用状态。
func is_occupied(grid_pos: Vector2i) -> bool:
	return occupancy.has(grid_pos) or movement_reservations.has(grid_pos)


## 获取格子的地形类型；越界位置按阻挡处理。
func get_terrain_type(grid_pos: Vector2i) -> int:
	if not is_in_bounds(grid_pos):
		return TerrainType.BLOCKED
	if grid_pos in player_base_cells:
		return TerrainType.PLAYER_BASE
	if grid_pos in enemy_base_cells:
		return TerrainType.ENEMY_BASE
	if grid_pos in blocked_cells:
		return TerrainType.BLOCKED
	return TerrainType.NORMAL


## 兼容旧部署区域 API；现在仅普通地形允许手动部署。
func is_deploy_zone(grid_pos: Vector2i) -> bool:
	return get_terrain_type(grid_pos) == TerrainType.NORMAL


## 普通地形和双方据点均可移动，阻挡地形不可移动。
func is_move_zone(grid_pos: Vector2i) -> bool:
	return is_in_bounds(grid_pos) and get_terrain_type(grid_pos) != TerrainType.BLOCKED


## 是否可以在指定位置部署
func can_place_at(grid_pos: Vector2i) -> bool:
	"""是否可以在指定位置部署"""
	return is_deploy_zone(grid_pos) and not is_occupied(grid_pos)


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
	elif not is_move_zone(grid_pos):
		return false
	if unit.has_method("sync_geometry_to_grid"):
		unit.sync_geometry_to_grid(cell_size)
	unit.grid_position = grid_pos
	unit.global_position = grid_to_world(grid_pos)
	if unit is UnitBase and _uses_grid_occupancy(unit):
		(unit as UnitBase).finish_grid_move(grid_pos)
	if unit not in all_units:
		all_units.append(unit)
		add_child(unit)
	_sync_unit_projection(unit)
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
		if not hero.can_ground_collide_with(enemy):
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
			if not enemy.can_ground_collide_with(player_unit):
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
		if not unit.can_ground_collide_with(other_unit):
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
	var moving_unit := _valid_collision_debug_unit(result, "moving_unit")
	var hit_unit := _valid_collision_debug_unit(result, "hit_unit")
	if moving_unit == null or hit_unit == null:
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
		var raw_entry = collision_debug_entries[key]
		if not raw_entry is Dictionary:
			_remove_collision_debug_entry(key)
			changed = true
			continue
		var entry: Dictionary = raw_entry
		var raw_result = entry.get("result", {})
		if not raw_result is Dictionary:
			_remove_collision_debug_entry(key)
			changed = true
			continue
		var result: Dictionary = raw_result
		var moving_unit := _valid_collision_debug_unit(result, "moving_unit")
		var hit_unit := _valid_collision_debug_unit(result, "hit_unit")
		if moving_unit == null or hit_unit == null:
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
	var raw_label = entry.get("label", null)
	if not is_instance_valid(raw_label) or not raw_label is Label:
		return
	var label := raw_label as Label
	var raw_result = entry.get("result", {})
	if not raw_result is Dictionary:
		return
	var result: Dictionary = raw_result
	var hit_unit := _valid_collision_debug_unit(result, "hit_unit")
	if hit_unit == null:
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
		var raw_entry = collision_debug_entries[key]
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var raw_result = entry.get("result", {})
		if not raw_result is Dictionary:
			continue
		var result: Dictionary = raw_result
		var moving_unit := _valid_collision_debug_unit(result, "moving_unit")
		var hit_unit := _valid_collision_debug_unit(result, "hit_unit")
		if moving_unit == null or hit_unit == null:
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
	var raw_entry = collision_debug_entries[key]
	if raw_entry is Dictionary:
		var raw_label = raw_entry.get("label", null)
		if is_instance_valid(raw_label) and raw_label is Label:
			(raw_label as Label).queue_free()
	collision_debug_entries.erase(key)


## 从调试快照中安全读取单位；对象可能在记录后、下一帧刷新前已被释放。
func _valid_collision_debug_unit(result: Dictionary, field: String) -> UnitBase:
	var value = result.get(field, null)
	if not is_instance_valid(value) or not value is UnitBase:
		return null
	return value as UnitBase


## 获取单位调试名称。
func _unit_debug_name(unit: UnitBase) -> String:
	if not unit:
		return "<null>"
	if not unit.unit_name.is_empty():
		return unit.unit_name
	return str(unit.name)


## 判断英雄是否能在指定格复活；除我方占位外还会检查存活敌人的身体碰撞。
func can_revive_at(cell: Vector2i, unit: Node = null) -> bool:
	if not is_move_zone(cell):
		return false
	if occupancy.has(cell) and occupancy[cell] != unit:
		return false
	if movement_reservations.has(cell) and movement_reservations[cell] != unit:
		return false

	var revive_ground := grid_to_world(cell)
	var revive_radius := 0.0
	if unit is UnitBase:
		var combat_unit := unit as UnitBase
		revive_ground += combat_unit.ground_anchor_offset
		revive_radius = combat_unit.get_collision_radius()
	return get_units_touching_circle(revive_ground, revive_radius, "enemy", unit).is_empty()


## 选择复活格：原地优先，否则选择离死亡点最近的可用我方据点。
func find_revive_cell(origin: Vector2i, unit: Node = null) -> Vector2i:
	if can_revive_at(origin, unit):
		return origin

	var best := INVALID_GRID_POS
	var best_dist := INF
	for base_cell in player_base_cells:
		if not can_revive_at(base_cell, unit):
			continue
		var distance := grid_to_world(base_cell).distance_squared_to(grid_to_world(origin))
		if distance < best_dist:
			best_dist = distance
			best = base_cell
	return best


## 获取距离指定世界坐标最近的我方据点中心。
func get_nearest_player_base_world(world_pos: Vector2) -> Vector2:
	if player_base_cells.is_empty():
		return world_pos
	var best_world := grid_to_world(player_base_cells[0])
	var best_dist := best_world.distance_squared_to(world_pos)
	for index in range(1, player_base_cells.size()):
		var candidate_world := grid_to_world(player_base_cells[index])
		var distance := candidate_world.distance_squared_to(world_pos)
		if distance < best_dist:
			best_dist = distance
			best_world = candidate_world
	return best_world


## 判断存活敌人的地面位置是否已经进入任意我方据点格。
func is_enemy_in_player_base(enemy: Node) -> bool:
	if not is_instance_valid(enemy) or not (enemy is UnitBase):
		return false
	var combat_unit := enemy as UnitBase
	if not combat_unit.is_alive or combat_unit.team != "enemy":
		return false
	return _world_to_grid_unclamped(combat_unit.get_ground_position()) in player_base_cells


## 世界坐标转未钳制网格坐标，供据点进入判定使用。
func _world_to_grid_unclamped(world_pos: Vector2) -> Vector2i:
	var safe_cell_size := maxf(cell_size, 1.0)
	var ground := screen_to_world(world_pos, 0.0)
	return Vector2i(
		int(floor(ground.x / safe_cell_size)),
		int(floor(ground.z / safe_cell_size))
	)


## 根据世界坐标查找最近的合法友方空格
func find_nearest_open_player_cell(world_pos: Vector2, preferred: Vector2i, unit: Node = null) -> Vector2i:
	"""根据世界坐标查找最近的合法友方空格"""
	if is_move_zone(preferred) and _is_cell_available_for_unit(preferred, unit):
		return preferred

	var best := Vector2i(-1, -1)
	var best_dist := INF
	for x in range(grid_width):
		for y in range(grid_height):
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
		for y in range(grid_height):
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
	if not is_move_zone(new_pos):
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


## 将一波敌人加入顺序出生队列；第一个敌人立即出生，后续按间隔生成。
func spawn_enemy_wave(enemy_templates: Array, spawns: Array) -> void:
	var spawn_cycle := _resolve_enemy_spawn_cycle(spawns)
	if spawn_cycle.is_empty():
		return

	var uses_default_bases := spawns.is_empty()
	var queue_was_empty := enemy_spawn_queue.is_empty()
	for index in range(enemy_templates.size()):
		var template = enemy_templates[index]
		if not (template is Dictionary):
			continue
		enemy_spawn_queue.append({
			"template": template,
			"spawn_pos": spawn_cycle[(enemy_spawn_cycle_cursor + index) % spawn_cycle.size()] if uses_default_bases else spawn_cycle[index % spawn_cycle.size()],
		})
	if uses_default_bases:
		enemy_spawn_cycle_cursor = (enemy_spawn_cycle_cursor + enemy_templates.size()) % spawn_cycle.size()

	if queue_was_empty and not enemy_spawn_queue.is_empty():
		_spawn_next_queued_enemy()
		enemy_spawn_time_remaining = _get_enemy_spawn_interval() if not enemy_spawn_queue.is_empty() else 0.0


## 是否还有尚未生成的敌人。
func has_pending_enemy_spawns() -> bool:
	return not enemy_spawn_queue.is_empty()


## 清空尚未生成的敌人，供重置战斗和结束战斗时调用。
func clear_enemy_spawn_queue() -> void:
	enemy_spawn_queue.clear()
	enemy_spawn_time_remaining = 0.0
	enemy_spawn_cycle_cursor = 0


## 更新敌人顺序出生计时。
func _update_enemy_spawn_queue(delta: float) -> void:
	if enemy_spawn_queue.is_empty():
		return
	enemy_spawn_time_remaining -= maxf(delta, 0.0)
	var interval := _get_enemy_spawn_interval()
	while not enemy_spawn_queue.is_empty() and enemy_spawn_time_remaining <= 0.0:
		_spawn_next_queued_enemy()
		if enemy_spawn_queue.is_empty():
			enemy_spawn_time_remaining = 0.0
			return
		enemy_spawn_time_remaining += interval


## 从队首生成一个敌人；模板字典不复制、不改写，原样交给 EnemyUnit。
func _spawn_next_queued_enemy() -> void:
	if enemy_spawn_queue.is_empty():
		return
	var entry: Dictionary = enemy_spawn_queue.pop_front()
	var template: Dictionary = entry["template"]
	var spawn_pos: Vector2i = entry["spawn_pos"]
	var enemy := EnemyUnit.new()
	enemy.setup_from_template(template)
	enemy.sync_geometry_to_grid(cell_size)
	enemy.grid_position = spawn_pos
	enemy.global_position = grid_to_world(spawn_pos)
	all_units.append(enemy)
	add_child(enemy)
	_sync_unit_projection(enemy)
	BattleManager.register_enemy_unit(enemy)


## 解析本波出生点；未显式传入时使用从上到下排序的两个敌方据点。
func _resolve_enemy_spawn_cycle(spawns: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value in spawns:
		if value is Vector2i:
			var cell: Vector2i = value
			if is_move_zone(cell) and cell not in result:
				result.append(cell)
	if result.is_empty():
		for cell in enemy_base_cells:
			if is_move_zone(cell) and cell not in result:
				result.append(cell)
	return result


## 获取配置后的敌人出生间隔。
func _get_enemy_spawn_interval() -> float:
	return maxf(0.01, _cfg_float("enemy_spawn_interval", enemy_spawn_interval))


func _cfg_float(key: String, default_value: float) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var registry := tree.root.get_node_or_null("DataRegistry")
		if registry and registry.has_method("get_config"):
			return float(registry.get_config(key, default_value))
	return default_value


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
		var mouse_position := get_global_mouse_position()
		if not is_world_point_inside_grid(mouse_position):
			return
		var grid_pos := world_to_grid(mouse_position)
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
		var visual_center := combat_unit.get_billboard_screen_center() \
			if combat_unit.has_method("get_billboard_screen_center") else combat_unit.global_position
		var hit_rect := Rect2(
			visual_center - Vector2(hit_size, hit_size) * 0.5,
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
