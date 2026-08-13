# roguelike_manager.gd — 肉鸽流程管理器
# 管理肉鸽运行的全生命周期：招募→战斗→奖励→推进
class_name RoguelikeManager
extends Node

const M = "Roguelike"

signal recruit_phase_started
signal battle_phase_started
signal map_phase_started
signal run_ended(victory: bool)

enum RunPhase {
	RECRUIT,
	MAP,
	BATTLE,
	REWARD,
	ENDED
}

var phase: RunPhase = RunPhase.RECRUIT
var map_data: Array = []               # 地图节点 [{type, enemy_pool, reward}]
var current_node_index: int = 0
var map_generator: MapGenerator = null
var recruit_system: RecruitSystem = null


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	add_to_group("roguelike_manager")
	map_generator = MapGenerator.new()
	recruit_system = RecruitSystem.new()
	add_child(recruit_system)
	if not GameManager.run_player_eliminated.is_connected(_on_run_player_eliminated):
		GameManager.run_player_eliminated.connect(_on_run_player_eliminated)
	if not BattleManager.joint_defense_cleared.is_connected(_on_joint_defense_cleared):
		BattleManager.joint_defense_cleared.connect(_on_joint_defense_cleared)
	_connect_multiplayer_coordinator()


## 开始新的肉鸽流程
func start_run() -> void:
	"""开始新的肉鸽流程"""
	GameManager.start_roguelike_run()
	recruit_system.reset_run()
	map_data.clear()
	current_node_index = 0
	_enter_recruit_phase()


## 进入酒馆招募阶段
func _enter_recruit_phase() -> void:
	"""进入酒馆招募阶段"""
	phase = RunPhase.RECRUIT
	GameManager.current_mode = GameManager.GameMode.RECRUIT
	var income := GameManager.grant_current_round_tavern_income()
	if AutoTraitManager and AutoTraitManager.has_method("notify_rest_started"):
		AutoTraitManager.notify_rest_started()
	var options := recruit_system.generate_recruit_options(GameManager.current_run_round, GameManager.party.size())
	_setup_round_preparation()
	recruit_phase_started.emit()
	Log.i(M, "进入招募阶段，固定收入 %d，%d 个选项" % [income, options.size()])


## 购买招募选项
func purchase_recruit(option_index: int) -> bool:
	"""购买招募选项"""
	var options := recruit_system.get_current_options()
	if option_index < 0 or option_index >= options.size():
		return false
	if not GameManager.can_add_to_party():
		Log.w(M, "手牌区已满，无法招募")
		return false
	var option = options[option_index]
	if not GameManager.spend_run_gold(option.cost):
		return false
	if not GameManager.add_to_party(option.class_id, option.level, option.shop_level):
		GameManager.earn_run_gold(option.cost)
		return false
	recruit_system.remove_option(option_index)
	var acquired_card: Dictionary = GameManager.party.back().duplicate(true)
	var repeat_count := 1
	if SynergyManager and SynergyManager.has_method("notify_hero_acquired"):
		repeat_count = SynergyManager.notify_hero_acquired(option.class_id, {
			"class_id": option.class_id,
			"star_level": option.level,
			"shop_level": option.shop_level,
		})
	if AutoTraitManager and AutoTraitManager.has_method("notify_hero_acquired"):
		AutoTraitManager.notify_hero_acquired(acquired_card, repeat_count)
	_sync_deployment_hand()
	return true


## 手动刷新酒馆。
func refresh_recruit_options() -> bool:
	"""手动刷新酒馆。"""
	if not GameManager.spend_run_gold(recruit_system.get_refresh_cost()):
		return false
	if SynergyManager and SynergyManager.has_method("notify_tavern_refreshed"):
		SynergyManager.notify_tavern_refreshed()
	if AutoTraitManager and AutoTraitManager.has_method("notify_tavern_refreshed"):
		AutoTraitManager.notify_tavern_refreshed()
	recruit_system.set_frozen(false)
	recruit_system.generate_recruit_options(GameManager.current_run_round, GameManager.party.size())
	return true


## 三合一晋升奖励：刷新为当前酒馆等级 +1 阶的 3 个英雄。
func refresh_recruit_options_for_promotion_reward() -> bool:
	if phase != RunPhase.RECRUIT or BattleManager.state != BattleManager.BattleState.PREPARING:
		return false
	recruit_system.generate_promotion_reward_options()
	recruit_phase_started.emit()
	return true


## 升级酒馆，并立即刷新一次招募列表。
func upgrade_tavern() -> bool:
	"""升级酒馆，并立即刷新一次招募列表。"""
	var cost := recruit_system.get_upgrade_cost()
	if cost <= 0:
		return false
	if not GameManager.spend_run_gold(cost):
		return false
	if not recruit_system.upgrade_tavern():
		GameManager.earn_run_gold(cost)
		return false
	return true


## 兼容旧入口：准备阶段内直接开始战斗。
func skip_recruit() -> void:
	"""兼容旧入口：准备阶段内直接开始战斗。"""
	recruit_system.clear_options()
	if AutoTraitManager and AutoTraitManager.has_method("notify_rest_ending"):
		AutoTraitManager.notify_rest_ending()
	if BattleManager.state == BattleManager.BattleState.PREPARING:
		BattleManager.start_next_wave()


## 开始回合战斗。
func _start_round_battle() -> void:
	var node := _build_round_node(GameManager.current_run_round)
	_start_battle(node)


## 初始化本回合战斗，但保留在准备/招募阶段让玩家部署。
func _setup_round_preparation() -> void:
	"""初始化本回合战斗，但保留在准备/招募阶段让玩家部署。"""
	var node := _build_round_node(GameManager.current_run_round)
	var battle_party := GameManager.get_battle_party_data()
	BattleManager.setup_battle(battle_party, node.get("enemy_pool", EnemyUnit.get_enemy_pool()), node.get("waves", 1), true)
	BattleManager.enemy_spawn_points = node.get("spawn_points", [])
	_sync_deployment_hand()

	if not BattleManager.battle_won.is_connected(_on_battle_won):
		BattleManager.battle_won.connect(_on_battle_won)
	if not BattleManager.battle_lost.is_connected(_on_battle_lost):
		BattleManager.battle_lost.connect(_on_battle_lost)

	ResourceManager.reset_dp()


## 同步deployment手牌。
func _sync_deployment_hand() -> void:
	var deployment := _get_deployment_system()
	if deployment:
		deployment.setup_hand(GameManager.get_battle_party_data())


## 进入地图推进阶段
func _enter_map_phase() -> void:
	"""进入地图推进阶段"""
	phase = RunPhase.MAP
	map_phase_started.emit()
	# MVP：自动选择下一个战斗节点
	_advance_to_next_node()


## 推进到下一个地图节点
func _advance_to_next_node() -> void:
	"""推进到下一个地图节点"""
	if current_node_index >= map_data.size():
		# 本层所有节点清完
		GameManager.proceed_to_next_floor()
		if GameManager.current_floor > 3:
			_end_run(true)
			return
		map_data = map_generator.generate_floor_map(GameManager.current_floor)
		current_node_index = 0

	var node = map_data[current_node_index]
	match node.type:
		"battle":
			_start_battle(node)
		"elite":
			_start_battle(node)
		"boss":
			_start_battle(node)
		"shop":
			_enter_recruit_phase()
			current_node_index += 1
		"rest":
			_rest_and_advance()
		_:
			current_node_index += 1
			_advance_to_next_node()


## 开始战斗
func _start_battle(node: Dictionary) -> void:
	"""开始战斗"""
	phase = RunPhase.BATTLE
	GameManager.current_mode = GameManager.GameMode.BATTLE
	battle_phase_started.emit()

	# 用队伍数据初始化部署系统
	var battle_party := GameManager.get_battle_party_data()
	var deployment := _get_deployment_system()
	if deployment:
		deployment.setup_hand(battle_party)

	# 配置战斗
	BattleManager.setup_battle(battle_party, node.get("enemy_pool", EnemyUnit.get_enemy_pool()), node.get("waves", 1), true)
	BattleManager.enemy_spawn_points = node.get("spawn_points", [])

	# 连接战斗结束信号
	if not BattleManager.battle_won.is_connected(_on_battle_won):
		BattleManager.battle_won.connect(_on_battle_won)
	if not BattleManager.battle_lost.is_connected(_on_battle_lost):
		BattleManager.battle_lost.connect(_on_battle_lost)

	# 重置DP，给准备阶段足够的资源
	ResourceManager.reset_dp()
	# 不自动开始战斗——等待玩家部署后按 F 键手动推进


## 获取deploymentsystem。
func _get_deployment_system() -> DeploymentSystem:
	var tree := get_tree()
	if tree:
		var nodes := tree.get_nodes_in_group("deployment_system")
		if nodes.size() > 0:
			return nodes[0]
	return null


## 战斗胜利
func _on_battle_won() -> void:
	"""战斗胜利"""
	var coordinator := _multiplayer_coordinator()
	if coordinator and coordinator.has_method("is_run_active") and coordinator.is_run_active():
		phase = RunPhase.REWARD
		coordinator.submit_local_battle_result(BattleManager.get_battle_result())
		Log.i(M, "本地战斗完成，等待其他玩家与联合战斗结算")
		return
	_complete_round_victory()


## 完成本回合的统一结算；联机模式只由房主广播的回合完成事件触发。
func _complete_round_victory() -> void:
	if phase == RunPhase.ENDED or not GameManager.is_run_player_alive():
		return
	var reward := _calculate_reward()
	if SynergyManager and SynergyManager.has_method("apply_victory_gold_bonus"):
		reward = SynergyManager.apply_victory_gold_bonus(reward)
	reward = GameManager.apply_roguelike_relic_victory_reward(reward)
	if SynergyManager and SynergyManager.has_method("resolve_battle_end_gold_bonus"):
		reward += SynergyManager.resolve_battle_end_gold_bonus(BattleManager.defeated_enemy_count)
	GameManager.earn_run_gold(reward)
	if SynergyManager and SynergyManager.has_method("apply_rest_synergy_layers"):
		SynergyManager.apply_rest_synergy_layers()
	BattleManager.prepare_player_units_for_next_round()
	recruit_system.advance_round()
	Log.i(M, "战斗胜利! 获得 %d 金币" % reward)

	if GameManager.current_run_round >= GameManager.max_run_rounds:
		_end_run(true)
		return

	GameManager.advance_roguelike_round()
	_enter_recruit_phase()


## 战斗失败
func _on_battle_lost() -> void:
	"""战斗失败"""
	var coordinator := _multiplayer_coordinator()
	if coordinator and coordinator.has_method("is_run_active") and coordinator.is_run_active():
		coordinator.mark_local_player_eliminated()
	GameManager.earn_run_gold(_cfg_int("battle_loss_gold", 0))
	Log.i(M, "玩家生命归零，冒险结束")
	_end_run(false)


## 计算奖励金币
func _calculate_reward() -> int:
	"""计算奖励金币"""
	return _cfg_int("battle_reward_gold", 0)


## 房主为本机分配联合防守段。
func _on_joint_defense_assigned(stage_index: int, payloads: Array, keep_input_open: bool) -> void:
	if phase == RunPhase.ENDED:
		return
	phase = RunPhase.BATTLE
	BattleManager.begin_joint_defense(stage_index, payloads, keep_input_open)


## 联合战斗中从上一名防守者实时转入敌人。
func _on_joint_enemy_received(payload: Dictionary) -> void:
	if phase != RunPhase.ENDED:
		BattleManager.receive_joint_enemy_payload(payload)


## 上游防守者已结束，不会再有新敌人转入。
func _on_joint_input_closed() -> void:
	BattleManager.close_joint_input()


## 本机承担的联合防守段完成。
func _on_joint_defense_cleared(stage_index: int) -> void:
	var coordinator := _multiplayer_coordinator()
	if coordinator and coordinator.has_method("report_local_joint_stage_cleared"):
		coordinator.report_local_joint_stage_cleared(stage_index)


## 全房间联合结算结束，同步推进到下一回合。
func _on_cooperative_round_resolved(round_number: int) -> void:
	if round_number != GameManager.current_run_round or phase == RunPhase.ENDED:
		return
	_complete_round_victory()


## 来源玩家可能在联合最终漏怪伤害后于等待阶段被淘汰。
func _on_run_player_eliminated() -> void:
	if phase == RunPhase.ENDED:
		return
	var coordinator := _multiplayer_coordinator()
	if coordinator and coordinator.has_method("is_run_active") and coordinator.is_run_active():
		coordinator.mark_local_player_eliminated()
	if BattleManager.state == BattleManager.BattleState.IN_PROGRESS:
		return
	_end_run(false)


func _connect_multiplayer_coordinator() -> void:
	var coordinator := _multiplayer_coordinator()
	if not coordinator:
		return
	if coordinator.has_signal("joint_defense_assigned") and not coordinator.joint_defense_assigned.is_connected(_on_joint_defense_assigned):
		coordinator.joint_defense_assigned.connect(_on_joint_defense_assigned)
	if coordinator.has_signal("joint_enemy_received") and not coordinator.joint_enemy_received.is_connected(_on_joint_enemy_received):
		coordinator.joint_enemy_received.connect(_on_joint_enemy_received)
	if coordinator.has_signal("joint_input_closed") and not coordinator.joint_input_closed.is_connected(_on_joint_input_closed):
		coordinator.joint_input_closed.connect(_on_joint_input_closed)
	if coordinator.has_signal("cooperative_round_resolved") and not coordinator.cooperative_round_resolved.is_connected(_on_cooperative_round_resolved):
		coordinator.cooperative_round_resolved.connect(_on_cooperative_round_resolved)
	if coordinator.has_signal("session_ended") and not coordinator.session_ended.is_connected(_on_multiplayer_session_ended):
		coordinator.session_ended.connect(_on_multiplayer_session_ended)


func _on_multiplayer_session_ended(reason: String) -> void:
	if phase == RunPhase.ENDED or not GameManager.is_roguelike_run:
		return
	Log.w(M, "联机会话结束: %s" % reason)
	_end_run(false)


func _multiplayer_coordinator() -> Node:
	var tree := get_tree()
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("MultiplayerRunManager")


## 处理restandadvance逻辑。
func _rest_and_advance() -> void:
	current_node_index += 1
	_advance_to_next_node()


## 处理end肉鸽流程逻辑。
func _end_run(victory: bool) -> void:
	phase = RunPhase.ENDED
	GameManager.is_roguelike_run = false
	run_ended.emit(victory)
	if victory:
		Log.i(M, "恭喜! 冒险完成!")
	else:
		Log.i(M, "冒险失败...")


## 构建回合节点。
func _build_round_node(round_number: int) -> Dictionary:
	var is_boss := round_number >= GameManager.max_run_rounds
	var is_elite := not is_boss and round_number % 4 == 0
	var enemy_pool := _get_scaled_enemy_pool(round_number, is_elite, is_boss)
	return {
		"type": "boss" if is_boss else ("elite" if is_elite else "battle"),
		"enemy_pool": enemy_pool,
		"waves": 1,
	}


## 获取scaled敌人池。
func _get_scaled_enemy_pool(round_number: int, is_elite: bool, is_boss: bool) -> Array:
	var source_pool := EnemyUnit.get_enemy_pool()
	var result: Array = []
	var scaling := _scaling("roguelike_round")
	var round_offset := float(maxi(0, round_number - 1))
	var hp_scale := float(scaling.get("base_multiplier", 1.0)) + round_offset * float(scaling.get("hp_per_round", 0.12))
	var atk_scale := float(scaling.get("base_multiplier", 1.0)) + round_offset * float(scaling.get("atk_per_round", 0.12))
	var def_scale := float(scaling.get("base_multiplier", 1.0)) + round_offset * float(scaling.get("def_per_round", 0.12))
	if is_elite:
		var elite_multiplier := float(scaling.get("elite_multiplier", 1.35))
		hp_scale *= elite_multiplier
		atk_scale *= elite_multiplier
		def_scale *= elite_multiplier

	for template in source_pool:
		var enemy_type = template.get("type", EnemyUnit.EnemyType.MELEE)
		if is_boss:
			if enemy_type != EnemyUnit.EnemyType.BOSS:
				continue
		elif enemy_type == EnemyUnit.EnemyType.BOSS:
			continue

		var scaled: Dictionary = template.duplicate(true)
		scaled["hp"] = int(round(float(scaled.get("hp", 80)) * hp_scale))
		scaled["atk"] = int(round(float(scaled.get("atk", 10)) * atk_scale))
		scaled["def"] = int(round(float(scaled.get("def", 3)) * def_scale))
		result.append(scaled)

	if result.is_empty():
		return source_pool
	return result


func _cfg_int(key: String, default_value: int) -> int:
	var registry := _registry()
	if registry and registry.has_method("get_config"):
		return int(registry.get_config(key, default_value))
	return default_value


func _scaling(scaling_id: String) -> Dictionary:
	var registry := _registry()
	if registry and registry.has_method("get_enemy_scaling"):
		var data: Dictionary = registry.get_enemy_scaling(scaling_id)
		if not data.is_empty():
			return data
	return {}


func _registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("DataRegistry")
