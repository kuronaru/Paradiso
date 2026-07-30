# battle_manager.gd — 单棋盘战斗管理
# 负责本地波次、据点漏怪、完美战果与联合防守阶段。
extends Node

const M = "Battle"

signal battle_started
signal battle_won
signal battle_lost
signal battle_resolved(result: Dictionary)
signal wave_cleared(wave_index: int)
signal all_waves_cleared
signal unit_deployed(unit: Node)
signal unit_retreated(unit: Node)
signal unit_died(unit: Node)
signal enemy_breached(payload: Dictionary)
signal joint_defense_started(stage_index: int)
signal joint_defense_cleared(stage_index: int)

enum BattleState {
	PREPARING,
	IN_PROGRESS,
	WAVE_BREAK,
	VICTORY,
	DEFEAT
}

enum BattlePhase {
	LOCAL,
	JOINT
}

var state: BattleState = BattleState.PREPARING
var phase: BattlePhase = BattlePhase.LOCAL
var grid: Node = null

## 波次数据
var current_wave: int = 0
var total_waves: int = 3
var enemy_pool: Array = []
var wave_enemies: Array = []

## 单位追踪
var player_units: Array = []
var enemy_units: Array = []

## 敌方生成点（网格坐标）
var enemy_spawn_points: Array = []

## 本地战果
var defeated_enemy_count: int = 0
var breached_enemy_payloads: Array[Dictionary] = []
var _next_enemy_serial: int = 1

## 联合防守状态
var joint_stage_index: int = -1
var joint_input_open: bool = false
var _joint_seen_enemy_uids: Dictionary = {}


## 初始化一场本地战斗。
func setup_battle(_party_data: Array, enemies: Array, wave_count: int = 3, preserve_player_units: bool = false) -> void:
	if preserve_player_units:
		_clear_enemy_units()
		_prepare_existing_player_units()
	else:
		_clear_enemy_units()
		player_units.clear()
	wave_enemies.clear()

	phase = BattlePhase.LOCAL
	total_waves = maxi(1, wave_count)
	enemy_pool = enemies.duplicate(true)
	current_wave = 0
	defeated_enemy_count = 0
	breached_enemy_payloads.clear()
	_next_enemy_serial = 1
	joint_stage_index = -1
	joint_input_open = false
	_joint_seen_enemy_uids.clear()
	state = BattleState.PREPARING

	Log.i(M, "战斗初始化: %d 波敌人" % total_waves)
	battle_started.emit()


## 战斗结束后保留玩家部署，并把角色放回部署时的位置。
func prepare_player_units_for_next_round() -> void:
	_clear_enemy_units()
	_prepare_existing_player_units()
	phase = BattlePhase.LOCAL
	joint_stage_index = -1
	joint_input_open = false
	state = BattleState.PREPARING


## 清理敌人单位和待出生队列。
func _clear_enemy_units() -> void:
	if grid:
		if grid.has_method("clear_enemy_spawn_queue"):
			grid.clear_enemy_spawn_queue()
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
		if unit is UnitBase and not unit.is_alive and not (unit is HeroUnit):
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
			if not grid.is_in_bounds(target_pos) or not grid.can_place_at(target_pos):
				target_pos = grid.find_nearest_open_player_cell(unit.global_position, unit.grid_position, unit)
			if target_pos.x >= 0 and not grid.is_occupied(target_pos):
				grid.occupy_cell(target_pos, unit)
				unit.grid_position = target_pos
				unit.global_position = grid.grid_to_world(target_pos)
				if unit is UnitBase:
					(unit as UnitBase).finish_grid_move(target_pos)

	for unit in valid_units:
		if unit is HeroUnit:
			unit.set_process(true)
			(unit as HeroUnit).prepare_for_next_round()


## 开始下一波本地敌人。
func start_next_wave() -> bool:
	if phase != BattlePhase.LOCAL:
		return false
	if current_wave >= total_waves:
		_all_waves_cleared()
		return false

	var was_preparing := state == BattleState.PREPARING
	current_wave += 1
	state = BattleState.IN_PROGRESS
	if was_preparing and GameManager.is_roguelike_run:
		GameManager.clear_run_gold()
	_spawn_wave_enemies(current_wave)

	for unit in player_units:
		if is_instance_valid(unit) and unit.has_method("activate_ai") and unit.is_alive:
			unit.activate_ai()

	Log.i(M, "第 %d 波开始" % current_wave)
	return true


## 将一波模板交给 GridSystem 的依次出生队列。
func _spawn_wave_enemies(wave_index: int) -> void:
	wave_enemies.clear()
	var count: int = _cfg_int("battle_base_wave_enemy_count", 2) + wave_index * _cfg_int("battle_enemy_count_per_wave", 2)
	var available_enemies = enemy_pool.duplicate(true)
	for _i in range(count):
		if available_enemies.is_empty():
			break
		var idx: int = randi() % available_enemies.size()
		var enemy_data: Dictionary = available_enemies[idx].duplicate(true)
		enemy_data["enemy_uid"] = _make_enemy_uid()
		enemy_data["source_player_id"] = _local_player_id()
		enemy_data["transfer_count"] = 0
		enemy_data["base_damage"] = int(enemy_data.get("base_damage", _cfg_int("enemy_base_damage", 1)))
		wave_enemies.append(enemy_data)

	if grid and grid.has_method("spawn_enemy_wave"):
		grid.spawn_enemy_wave(wave_enemies, enemy_spawn_points)
	wave_enemies.clear()
	if count <= 0 or available_enemies.is_empty():
		call_deferred("check_battle_end")


## 检查当前阶段是否完成。
func check_battle_end() -> void:
	if state != BattleState.IN_PROGRESS:
		return
	if not enemy_units.is_empty() or not wave_enemies.is_empty() or _has_pending_enemy_spawns():
		return

	if phase == BattlePhase.JOINT:
		if joint_input_open:
			return
		state = BattleState.VICTORY
		_set_player_units_waiting(true)
		joint_defense_cleared.emit(joint_stage_index)
		Log.i(M, "联合防守第 %d 段完成" % (joint_stage_index + 1))
		return

	wave_cleared.emit(current_wave)
	if current_wave >= total_waves:
		_all_waves_cleared()
	else:
		start_next_wave()


## 所有本地波次完成。
func _all_waves_cleared() -> void:
	if state == BattleState.VICTORY:
		return
	state = BattleState.VICTORY
	_set_player_units_waiting(true)
	var result := get_battle_result()
	all_waves_cleared.emit()
	battle_resolved.emit(result)
	battle_won.emit()
	Log.i(M, "本地战斗完成: %s" % ("完美" if result["perfect"] else "有漏怪"))


## 玩家生命归零时结束本地战斗。
func _battle_lost() -> void:
	if state == BattleState.DEFEAT:
		return
	state = BattleState.DEFEAT
	if grid and grid.has_method("clear_enemy_spawn_queue"):
		grid.clear_enemy_spawn_queue()
	_set_player_units_waiting(true)
	battle_lost.emit()
	Log.i(M, "玩家生命归零，战斗失败")


## 处理敌人进入我方据点。返回 true 表示敌人已被移出战场。
func handle_enemy_reached_player_base(enemy: EnemyUnit) -> bool:
	if not enemy or not is_instance_valid(enemy) or enemy not in enemy_units:
		return false
	if enemy.has_method("is_resolved") and enemy.is_resolved():
		return false

	var payload: Dictionary = enemy.to_transfer_payload() if enemy.has_method("to_transfer_payload") else {}
	if payload.is_empty():
		payload = {
			"enemy_uid": _make_enemy_uid(),
			"enemy_id": enemy.enemy_id,
			"name": enemy.unit_name,
			"current_hp": enemy.current_hp,
			"max_hp": enemy.max_hp,
			"source_player_id": _local_player_id(),
			"base_damage": _cfg_int("enemy_base_damage", 1),
			"transfer_count": 0,
		}

	if enemy.has_method("mark_resolved"):
		enemy.mark_resolved()
	enemy_units.erase(enemy)
	if grid:
		grid.remove_unit(enemy)
	enemy.queue_free()

	if phase == BattlePhase.JOINT:
		enemy_breached.emit(payload)
		_route_joint_breach(payload)
	else:
		breached_enemy_payloads.append(payload.duplicate(true))
		enemy_breached.emit(payload)
		var damage := maxi(1, int(payload.get("base_damage", _cfg_int("enemy_base_damage", 1))))
		GameManager.damage_run_life(damage)
		if not GameManager.is_run_player_alive():
			_battle_lost()
			return true

	call_deferred("check_battle_end")
	return true


## 开始本机承担的一段联合防守。
func begin_joint_defense(stage_index: int, initial_payloads: Array, keep_input_open: bool) -> void:
	_clear_enemy_units()
	phase = BattlePhase.JOINT
	joint_stage_index = stage_index
	joint_input_open = keep_input_open
	_joint_seen_enemy_uids.clear()
	current_wave = 1
	total_waves = 1
	state = BattleState.IN_PROGRESS

	for unit in player_units:
		if is_instance_valid(unit) and unit is UnitBase:
			unit.set_process(true)
			if unit.is_alive:
				unit.activate_ai()
	for payload in initial_payloads:
		if payload is Dictionary:
			receive_joint_enemy_payload(payload)

	joint_defense_started.emit(stage_index)
	call_deferred("check_battle_end")


## 接收一名实时转移到本段联合防守的敌人。
func receive_joint_enemy_payload(payload: Dictionary) -> bool:
	if phase != BattlePhase.JOINT or state == BattleState.DEFEAT:
		return false
	var normalized := payload.duplicate(true)
	var enemy_uid := str(normalized.get("enemy_uid", ""))
	if enemy_uid.is_empty():
		enemy_uid = _make_enemy_uid()
		normalized["enemy_uid"] = enemy_uid
	if _joint_seen_enemy_uids.has(enemy_uid):
		return false
	_joint_seen_enemy_uids[enemy_uid] = true
	normalized["transfer_count"] = int(normalized.get("transfer_count", 0)) + 1
	if grid and grid.has_method("spawn_enemy_wave"):
		grid.spawn_enemy_wave([normalized], enemy_spawn_points)
	return true


## 上一名防守者已完成，当前段不会再收到新敌人。
func close_joint_input() -> void:
	if phase != BattlePhase.JOINT:
		return
	joint_input_open = false
	call_deferred("check_battle_end")


func is_perfect_battle() -> bool:
	return breached_enemy_payloads.is_empty()


func get_breached_enemy_payloads() -> Array:
	return breached_enemy_payloads.duplicate(true)


func get_battle_result() -> Dictionary:
	return {
		"round": GameManager.current_run_round,
		"perfect": is_perfect_battle(),
		"defeated_count": defeated_enemy_count,
		"breached_count": breached_enemy_payloads.size(),
		"breached_enemies": get_breached_enemy_payloads(),
		"life": GameManager.run_life,
		"eliminated": not GameManager.is_run_player_alive(),
	}


## 注册玩家单位。
func register_player_unit(unit: Node) -> void:
	if unit not in player_units:
		player_units.append(unit)


## 注册敌人单位。
func register_enemy_unit(unit: Node) -> void:
	if unit not in enemy_units:
		enemy_units.append(unit)


## 注销玩家单位。英雄进入灵魂状态时不会调用此接口。
func unregister_player_unit(unit: Node) -> void:
	player_units.erase(unit)


## 注销被击败的敌人。
func unregister_enemy_unit(unit: Node) -> void:
	var was_registered := unit in enemy_units
	enemy_units.erase(unit)
	if was_registered:
		defeated_enemy_count += 1
	call_deferred("check_battle_end")


func _has_pending_enemy_spawns() -> bool:
	return grid and grid.has_method("has_pending_enemy_spawns") and grid.has_pending_enemy_spawns()


## 等待其他玩家时冻结本棋盘单位；网络 Autoload 仍保持 ALWAYS 处理。
func _set_player_units_waiting(waiting: bool) -> void:
	for unit in player_units:
		if not is_instance_valid(unit) or not (unit is UnitBase):
			continue
		unit.deactivate_ai()
		unit.set_process(not waiting)


func _route_joint_breach(payload: Dictionary) -> void:
	var coordinator := _multiplayer_run_manager()
	if coordinator and coordinator.has_method("route_local_joint_breach"):
		coordinator.route_local_joint_breach(payload, joint_stage_index)
		return
	# 没有联机协调器时，联合阶段最后漏怪仍惩罚来源的本地玩家。
	if int(payload.get("source_player_id", _local_player_id())) == _local_player_id():
		GameManager.damage_run_life(maxi(1, int(payload.get("base_damage", _cfg_int("enemy_base_damage", 1)))))


func _make_enemy_uid() -> String:
	var uid := "%d:%d:%d:%d" % [_local_player_id(), GameManager.current_run_round, current_wave, _next_enemy_serial]
	_next_enemy_serial += 1
	return uid


func _local_player_id() -> int:
	var coordinator := _multiplayer_run_manager()
	if coordinator and coordinator.has_method("get_local_player_id"):
		return int(coordinator.get_local_player_id())
	return 1


func _multiplayer_run_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("MultiplayerRunManager")


func _cfg_int(key: String, default_value: int) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var registry := tree.root.get_node_or_null("DataRegistry")
		if registry and registry.has_method("get_config"):
			return int(registry.get_config(key, default_value))
	return default_value
