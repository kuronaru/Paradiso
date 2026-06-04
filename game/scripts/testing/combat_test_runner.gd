# combat_test_runner.gd — 战斗数值测试控制器
# 在测试场景中通过代码放置玩家角色和敌人，并直接启动双方AI。
class_name CombatTestRunner
extends Node

const M = "CombatTest"

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


func _ready() -> void:
	"""测试场景启动时自动创建默认对战双方"""
	call_deferred("restart_test")


func restart_test() -> void:
	"""清空当前场面并按配置重新开始测试"""
	_prepare_test_battle()
	_clear_grid_units()
	_place_configured_units()
	_start_unit_ai()


func set_hero_specs(specs: Array) -> void:
	"""设置玩家角色测试配置"""
	hero_specs = specs.duplicate(true)


func set_enemy_specs(specs: Array) -> void:
	"""设置敌人测试配置"""
	enemy_specs = specs.duplicate(true)


func spawn_hero(class_id: String, level: int, grid_pos: Vector2i) -> HeroUnit:
	"""通过代码放置一个玩家角色"""
	if not grid:
		return null

	var ct := ClassDefinitions.get_template(class_id)
	var hero := HeroUnit.new()
	hero.setup(ct, level)
	if not grid.place_unit(hero, grid_pos):
		BattleManager.unregister_player_unit(hero)
		hero.queue_free()
		Log.w(M, "无法放置测试角色 %s 到 (%d, %d)" % [class_id, grid_pos.x, grid_pos.y])
		return null

	BattleManager.unit_deployed.emit(hero)
	hero.activate_ai()
	return hero


func spawn_enemy(template: Dictionary, grid_pos: Vector2i) -> EnemyUnit:
	"""通过代码放置一个敌人"""
	if not grid:
		return null

	var enemy := EnemyUnit.new()
	enemy.setup_from_template(template)
	if not grid.place_unit(enemy, grid_pos):
		BattleManager.unregister_enemy_unit(enemy)
		enemy.queue_free()
		Log.w(M, "无法放置测试敌人到 (%d, %d)" % [grid_pos.x, grid_pos.y])
		return null

	enemy.activate_ai()
	return enemy


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
	if SynergyManager and SynergyManager.has_method("recalculate"):
		SynergyManager.recalculate()


func _clear_grid_units() -> void:
	"""清空网格中的旧单位"""
	if not grid:
		return

	for unit in grid.all_units.duplicate():
		if is_instance_valid(unit):
			unit.queue_free()
	grid.all_units.clear()
	grid.occupancy.clear()


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


func _start_unit_ai() -> void:
	"""确保测试开始后双方单位都进入自动AI"""
	for unit in BattleManager.player_units:
		if is_instance_valid(unit) and unit.has_method("activate_ai"):
			unit.activate_ai()
	for unit in BattleManager.enemy_units:
		if is_instance_valid(unit) and unit.has_method("activate_ai"):
			unit.activate_ai()


func _default_hero_pos() -> Vector2i:
	"""默认玩家测试位置：地图左侧中央"""
	if not grid:
		return Vector2i(4, 3)
	return Vector2i(4, _center_deploy_row())


func _default_enemy_pos() -> Vector2i:
	"""默认敌人测试位置：地图右侧中央"""
	if not grid:
		return Vector2i(14, 3)
	return Vector2i(grid.grid_width - 5, _center_deploy_row())


func _center_deploy_row() -> int:
	"""获取可部署区域的中央行"""
	return int(round((grid.deploy_rows.x + grid.deploy_rows.y) * 0.5))
