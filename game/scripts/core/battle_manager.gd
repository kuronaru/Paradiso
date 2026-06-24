# BattleManager.gd — 战斗全局管理
# 负责战斗初始化、波次控制、胜负判定
extends Node

const M = "Battle"

signal battle_started
signal battle_won
signal battle_lost
signal wave_cleared(wave_index: int)
signal all_waves_cleared
signal unit_deployed(unit: Node)
signal unit_retreated(unit: Node)
signal unit_died(unit: Node)

## 战斗状态
enum BattleState {
	PREPARING,    ## 准备阶段（可部署）
	IN_PROGRESS,  ## 战斗进行中
	WAVE_BREAK,   ## 波次间隙
	VICTORY,      ## 胜利
	DEFEAT        ## 失败
}

var state: BattleState = BattleState.PREPARING
var grid: Node = null                         # GridSystem引用

## 波次数据
var current_wave: int = 0
var total_waves: int = 3
var enemy_pool: Array = []                    # 敌人模板池
var wave_enemies: Array = []                  # 当前波次的敌人

## 单位追踪
var player_units: Array = []                   # 场上玩家单位
var enemy_units: Array = []                    # 场上敌人单位

## 敌方生成点（网格坐标）
var enemy_spawn_points: Array = []


## 初始化一场战斗
func setup_battle(_party_data: Array, enemies: Array, wave_count: int = 3, preserve_player_units: bool = false) -> void:
	"""初始化一场战斗"""
	# 清除上一场状态
	if preserve_player_units:
		_clear_enemy_units()
		_prepare_existing_player_units()
	else:
		player_units.clear()
		enemy_units.clear()
	wave_enemies.clear()

	total_waves = wave_count
	enemy_pool = enemies.duplicate()
	current_wave = 0
	state = BattleState.PREPARING

	# 根据party_data生成玩家角色（由DeploymentSystem处理）
	Log.i(M, "战斗初始化: %d 波敌人" % total_waves)

	battle_started.emit()


## 战斗结束后保留玩家部署，并把角色放回部署时的位置。
func prepare_player_units_for_next_round() -> void:
	"""战斗结束后保留玩家部署，并把角色放回部署时的位置。"""
	_clear_enemy_units()
	_prepare_existing_player_units()
	state = BattleState.PREPARING


## 清理敌人单位。
func _clear_enemy_units() -> void:
	if grid:
		for unit in enemy_units.duplicate():
			if is_instance_valid(unit):
				grid.remove_unit(unit)
				unit.queue_free()
	enemy_units.clear()
	wave_enemies.clear()


## 准备现有玩家单位。
func _prepare_existing_player_units() -> void:
	if player_units.is_empty():
		return

	var valid_units: Array = []
	for unit in player_units.duplicate():
		if not is_instance_valid(unit):
			player_units.erase(unit)
			continue
		if unit is UnitBase and not unit.is_alive:
			player_units.erase(unit)
			continue
		valid_units.append(unit)

	if grid:
		if grid.has_method("clear_move_reservations"):
			grid.clear_move_reservations()
		for unit in valid_units:
			if unit.grid_position in grid.occupancy and grid.occupancy[unit.grid_position] == unit:
				grid.free_cell(unit.grid_position)

		for unit in valid_units:
			var target_pos: Vector2i = unit.grid_position
			if unit is HeroUnit:
				target_pos = (unit as HeroUnit).deployed_grid_position
			if not grid.is_in_bounds(target_pos) or not grid.is_deploy_zone(target_pos) or grid.is_occupied(target_pos):
				target_pos = unit.grid_position
			if not grid.is_occupied(target_pos):
				grid.occupy_cell(target_pos, unit)
				unit.grid_position = target_pos
				unit.global_position = grid.grid_to_world(target_pos)
				if unit is UnitBase:
					(unit as UnitBase).finish_grid_move(target_pos)

	for unit in valid_units:
		if unit is HeroUnit:
			(unit as HeroUnit).prepare_for_next_round()


## 开始下一波敌人
func start_next_wave() -> bool:
	"""开始下一波敌人"""
	if current_wave >= total_waves:
		_all_waves_cleared()
		return false

	current_wave += 1
	state = BattleState.IN_PROGRESS
	_spawn_wave_enemies(current_wave)

	# 激活所有场上玩家单位的AI（静态部署 → 实时战斗）
	for unit in player_units:
		if is_instance_valid(unit) and unit.has_method("activate_ai"):
			unit.activate_ai()

	Log.i(M, "第 %d 波开始" % current_wave)
	return true


## 生成波次敌人（由EnemySpawner实际处理）
func _spawn_wave_enemies(wave_index: int) -> void:
	"""生成波次敌人（由EnemySpawner实际处理）"""
	wave_enemies.clear()
	# 从enemy_pool中选取敌人模板，波次越深敌人越多/越强
	var count: int = 2 + wave_index * 2
	var available_enemies = enemy_pool.duplicate()
	for i in range(count):
		if available_enemies.is_empty():
			break
		var idx: int = randi() % available_enemies.size()
		wave_enemies.append(available_enemies[idx])
	# 通知GridSystem生成实体
	if grid and grid.has_method("spawn_enemy_wave"):
		grid.spawn_enemy_wave(wave_enemies, enemy_spawn_points)
	# 生成完毕，清空模板列表（check_battle_end 依赖此判断）
	wave_enemies.clear()


## 检查战斗是否结束
func check_battle_end() -> void:
	"""检查战斗是否结束"""
	if state != BattleState.IN_PROGRESS:
		return

	if enemy_units.is_empty() and wave_enemies.is_empty():
		# 当前波次清空
		wave_cleared.emit(current_wave)

		if current_wave >= total_waves:
			_all_waves_cleared()
		else:
			# 自动进入下一波
			start_next_wave()

	if player_units.is_empty() and state == BattleState.IN_PROGRESS:
		_battle_lost()


## 所有波次完成
func _all_waves_cleared() -> void:
	"""所有波次完成"""
	state = BattleState.VICTORY
	all_waves_cleared.emit()
	battle_won.emit()
	Log.i(M, "战斗胜利!")


## 战斗失败
func _battle_lost() -> void:
	"""战斗失败"""
	state = BattleState.DEFEAT
	battle_lost.emit()
	Log.i(M, "战斗失败!")


## 注册玩家单位。
func register_player_unit(unit: Node) -> void:
	if unit not in player_units:
		player_units.append(unit)


## 注册敌人单位。
func register_enemy_unit(unit: Node) -> void:
	if unit not in enemy_units:
		enemy_units.append(unit)


## 注销玩家单位。
func unregister_player_unit(unit: Node) -> void:
	player_units.erase(unit)
	check_battle_end()


## 注销敌人单位。
func unregister_enemy_unit(unit: Node) -> void:
	enemy_units.erase(unit)
	check_battle_end()
