# combat_test_runner.gd — 战斗数值测试控制器
# 在测试场景中通过代码放置玩家角色和敌人，并直接启动双方AI。
class_name CombatTestRunner
extends Node

const M = "CombatTest"

var debug_visuals_enabled: bool = true
var test_synergies_enabled: bool = false
var test_synergy_specs: Array[Dictionary] = []
var start_paused_on_ready: bool = true

## 默认玩家角色配置；可在测试代码中改写后调用 restart_test()
var hero_specs: Array = [
	{
		"class_id": "warrior",
		"level": 1,
		"grid_pos": Vector2i(4, 3),
	},
]

## 默认敌人配置；可在测试代码中改写后调用 restart_test()
var enemy_specs: Array = [
	{
		"name": "测试敌人",
		"type": EnemyUnit.EnemyType.MELEE,
		"grid_pos": Vector2i(14, 3),
		"hp": 120,
		"atk": 12,
		"def": 4,
		"attack_speed": 1.0,
		"move_speed": 1.5,
		"attack_range": 1.0,
		"search_range": 8.0,
	},
]

@onready var grid: GridSystem = $"../GridSystem"


## 测试场景启动时自动创建默认对战双方
func _ready() -> void:
	"""测试场景启动时自动创建默认对战双方"""
	call_deferred("_start_initial_test")


## 首次进入测试场景时生成默认单位，并按配置保持暂停。
func _start_initial_test() -> void:
	restart_test()
	if start_paused_on_ready:
		pause_test()


## 清空当前场面并按配置重新开始测试
func restart_test() -> void:
	"""清空当前场面并按配置重新开始测试"""
	get_tree().paused = false
	_prepare_test_battle()
	_clear_grid_units()
	_place_configured_units()
	_apply_current_test_synergy_state()
	_start_unit_ai()


## 开始或继续当前测试场景
func start_test() -> void:
	"""开始或继续当前测试场景"""
	get_tree().paused = false
	BattleManager.state = BattleManager.BattleState.IN_PROGRESS
	_start_unit_ai()


## 暂停当前测试场景
func pause_test() -> void:
	"""暂停当前测试场景"""
	get_tree().paused = true


## 设置玩家角色测试配置
func set_hero_specs(specs: Array) -> void:
	"""设置玩家角色测试配置"""
	hero_specs = specs.duplicate(true)


## 设置敌人测试配置
func set_enemy_specs(specs: Array) -> void:
	"""设置敌人测试配置"""
	enemy_specs = specs.duplicate(true)


## 通过代码放置一个玩家角色
func spawn_hero(class_id: String, level: int, grid_pos: Vector2i) -> HeroUnit:
	"""通过代码放置一个玩家角色"""
	if not grid:
		return null
	if not is_valid_hero_class_id(class_id):
		Log.w(M, "未知测试角色ID: %s" % class_id)
		return null
	if not can_spawn_more_heroes():
		Log.w(M, "测试角色数量已达上限 %d" % GameManager.ROGUELIKE_MAX_DEPLOYED_UNITS)
		return null

	var canonical_id := ClassDefinitions.canonicalize_class_id(class_id)
	var ct := ClassDefinitions.get_template(canonical_id)
	var hero := HeroUnit.new()
	hero.setup(ct, level)
	_apply_debug_visuals_to_unit(hero)
	if not grid.place_unit(hero, grid_pos):
		BattleManager.unregister_player_unit(hero)
		hero.queue_free()
		Log.w(M, "无法放置测试角色 %s 到 (%d, %d)" % [canonical_id, grid_pos.x, grid_pos.y])
		return null

	_apply_debug_visuals_to_unit(hero)
	BattleManager.unit_deployed.emit(hero)
	hero.activate_ai()
	return hero


## 在下一个可用位置增加一个玩家角色
func add_hero(class_id: String, level: int = 1) -> HeroUnit:
	"""在下一个可用位置增加一个玩家角色"""
	if not grid:
		return null
	var grid_pos := _next_open_hero_pos()
	if grid_pos == GridSystem.INVALID_GRID_POS:
		Log.w(M, "没有可用位置放置测试角色 %s" % class_id)
		return null
	return spawn_hero(class_id, level, grid_pos)


## 通过代码放置一个敌人
func spawn_enemy(template: Dictionary, grid_pos: Vector2i) -> EnemyUnit:
	"""通过代码放置一个敌人"""
	if not grid:
		return null

	var enemy := EnemyUnit.new()
	enemy.setup_from_template(template)
	_apply_debug_visuals_to_unit(enemy)
	if not grid.place_unit(enemy, grid_pos):
		BattleManager.unregister_enemy_unit(enemy)
		enemy.queue_free()
		Log.w(M, "无法放置测试敌人到 (%d, %d)" % [grid_pos.x, grid_pos.y])
		return null

	_apply_debug_visuals_to_unit(enemy)
	enemy.activate_ai()
	return enemy


## 检查角色ID是否可用于测试生成
func is_valid_hero_class_id(class_id: String) -> bool:
	"""检查角色ID是否可用于测试生成"""
	var trimmed := class_id.strip_edges()
	if trimmed == "":
		return false
	return ClassDefinitions.has_class_id(trimmed)


## 获取当前测试场上玩家英雄数量。
func get_deployed_hero_count() -> int:
	var count := 0
	for unit in BattleManager.player_units:
		if is_instance_valid(unit) and unit is HeroUnit:
			count += 1
	return count


## 检查测试场景是否还能继续添加玩家英雄。
func can_spawn_more_heroes() -> bool:
	return get_deployed_hero_count() < GameManager.ROGUELIKE_MAX_DEPLOYED_UNITS


## 是否开启开发调试可视化
func is_debug_visuals_enabled() -> bool:
	"""是否开启开发调试可视化"""
	return debug_visuals_enabled


## 切换调试可视化，包括单位半径、攻击范围、碰撞预测
func set_debug_visuals(enabled: bool) -> void:
	"""切换调试可视化，包括单位半径、攻击范围、碰撞预测"""
	debug_visuals_enabled = enabled
	if grid:
		grid.debug_unit_body_radii = enabled
		grid.debug_attack_ranges = enabled
		grid.debug_collision_prediction = enabled
		if not enabled:
			grid.collision_debug_entries.clear()
		grid.queue_redraw()

		for unit in grid.all_units:
			if is_instance_valid(unit) and unit is UnitBase:
				_apply_debug_visuals_to_unit(unit as UnitBase)


## 获取测试羁绊选项。
func get_test_synergy_options() -> Array[Dictionary]:
	if SynergyManager and SynergyManager.has_method("get_test_synergy_options"):
		return SynergyManager.get_test_synergy_options()
	return []


## 获取测试面板当前配置的羁绊。
func get_test_synergy_specs() -> Array:
	return test_synergy_specs.duplicate(true)


## 添加或更新测试羁绊配置。count <= 0 时移除该项。
func set_test_synergy_spec(synergy_id: String, count: int, layer: int) -> void:
	if synergy_id.strip_edges() == "":
		return
	var next_specs: Array[Dictionary] = []
	var updated := false
	for spec in test_synergy_specs:
		var existing_id := str(spec.get("id", ""))
		if existing_id == synergy_id:
			updated = true
			if count > 0:
				next_specs.append({
					"id": synergy_id,
					"count": count,
					"layer": layer,
				})
		else:
			next_specs.append(spec.duplicate(true))
	if not updated and count > 0:
		next_specs.append({
			"id": synergy_id,
			"count": count,
			"layer": layer,
		})
	test_synergy_specs = next_specs


## 让测试羁绊配置立即生效。
func apply_test_synergies() -> Array:
	test_synergies_enabled = true
	if SynergyManager and SynergyManager.has_method("set_test_synergy_override"):
		SynergyManager.set_test_synergy_override(test_synergy_specs)
		return SynergyManager.get_synergy_summary()
	return []


## 清空测试羁绊配置并恢复场上阵容自动计算。
func clear_test_synergies() -> void:
	test_synergies_enabled = false
	test_synergy_specs.clear()
	if SynergyManager and SynergyManager.has_method("clear_test_synergy_override"):
		SynergyManager.clear_test_synergy_override()
	elif SynergyManager and SynergyManager.has_method("recalculate"):
		SynergyManager.recalculate()


## 测试羁绊配置是否正在覆盖场上阵容羁绊。
func is_test_synergies_enabled() -> bool:
	return test_synergies_enabled


## 重置战斗全局状态，避免测试场景受到肉鸽流程影响
func _prepare_test_battle() -> void:
	"""重置战斗全局状态，避免测试场景受到肉鸽流程影响"""
	BattleManager.state = BattleManager.BattleState.IN_PROGRESS
	BattleManager.current_wave = 1
	BattleManager.total_waves = 1
	BattleManager.enemy_pool.clear()
	BattleManager.wave_enemies.clear()
	BattleManager.player_units.clear()
	BattleManager.enemy_units.clear()
	BattleManager.grid = grid
	if ResourceManager:
		ResourceManager.reset_dp(
			ResourceManager.get_configured_initial_dp("combat_test_initial_deployment_points"),
			ResourceManager.get_configured_max_dp()
		)
		ResourceManager.set_regen_enabled(true)
	_apply_current_test_synergy_state()


## 清空网格中的旧单位
func _clear_grid_units() -> void:
	"""清空网格中的旧单位"""
	if not grid:
		return

	for unit in grid.all_units.duplicate():
		if is_instance_valid(unit):
			unit.queue_free()
	grid.all_units.clear()
	grid.occupancy.clear()
	if grid.has_method("clear_move_reservations"):
		grid.clear_move_reservations()
	grid.collision_debug_entries.clear()


## 按测试配置批量放置双方单位
func _place_configured_units() -> void:
	"""按测试配置批量放置双方单位"""
	for spec in hero_specs:
		var class_id: String = spec.get("class_id", "warrior")
		var level: int = spec.get("level", 1)
		var grid_pos: Vector2i = spec.get("grid_pos", _default_hero_pos())
		spawn_hero(class_id, level, grid_pos)

	for spec in enemy_specs:
		var grid_pos: Vector2i = spec.get("grid_pos", _default_enemy_pos())
		var template: Dictionary = spec.duplicate(true)
		template.erase("grid_pos")
		spawn_enemy(template, grid_pos)


## 确保测试开始后双方单位都进入自动AI
func _start_unit_ai() -> void:
	"""确保测试开始后双方单位都进入自动AI"""
	for unit in BattleManager.player_units:
		if is_instance_valid(unit) and unit.has_method("activate_ai"):
			unit.activate_ai()
	for unit in BattleManager.enemy_units:
		if is_instance_valid(unit) and unit.has_method("activate_ai"):
			unit.activate_ai()


## 为单位应用当前调试可视化设置
func _apply_debug_visuals_to_unit(unit: UnitBase) -> void:
	"""为单位应用当前调试可视化设置"""
	if not unit:
		return
	unit.show_body_debug_ring = debug_visuals_enabled
	unit.show_collision_debug_ring = debug_visuals_enabled
	unit.show_attack_range_debug_ring = debug_visuals_enabled
	unit.refresh_ground_collision()


## 根据测试开关应用手动羁绊或恢复自动计算。
func _apply_current_test_synergy_state() -> void:
	if not SynergyManager:
		return
	if test_synergies_enabled and SynergyManager.has_method("set_test_synergy_override"):
		SynergyManager.set_test_synergy_override(test_synergy_specs)
	elif SynergyManager.has_method("clear_test_synergy_override") and SynergyManager.is_test_synergy_override_enabled():
		SynergyManager.clear_test_synergy_override()
	elif SynergyManager.has_method("recalculate"):
		SynergyManager.recalculate()


## 获取下一个可用的玩家测试位置
func _next_open_hero_pos() -> Vector2i:
	"""获取下一个可用的玩家测试位置"""
	if not grid:
		return GridSystem.INVALID_GRID_POS

	var rows: Array[int] = []
	var center_row := _center_deploy_row()
	for y in range(grid.deploy_rows.x, grid.deploy_rows.y + 1):
		rows.append(y)
	rows.sort_custom(func(a: int, b: int) -> bool:
		return abs(a - center_row) < abs(b - center_row)
	)

	var max_x := maxi(1, int(floor(float(grid.grid_width) * 0.5)))
	for x in range(1, max_x + 1):
		for y in rows:
			var grid_pos := Vector2i(x, y)
			if grid.can_place_at(grid_pos):
				return grid_pos
	return GridSystem.INVALID_GRID_POS


## 默认玩家测试位置：地图左侧中央
func _default_hero_pos() -> Vector2i:
	"""默认玩家测试位置：地图左侧中央"""
	if not grid:
		return Vector2i(4, 3)
	return Vector2i(4, _center_deploy_row())


## 默认敌人测试位置：地图右侧中央
func _default_enemy_pos() -> Vector2i:
	"""默认敌人测试位置：地图右侧中央"""
	if not grid:
		return Vector2i(14, 3)
	return Vector2i(grid.grid_width - 5, _center_deploy_row())


## 获取可部署区域的中央行
func _center_deploy_row() -> int:
	"""获取可部署区域的中央行"""
	return int(round((grid.deploy_rows.x + grid.deploy_rows.y) * 0.5))
