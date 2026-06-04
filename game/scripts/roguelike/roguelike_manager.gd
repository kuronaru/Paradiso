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


func _ready() -> void:
	add_to_group("roguelike_manager")
	map_generator = MapGenerator.new()
	recruit_system = RecruitSystem.new()
	add_child(recruit_system)


func start_run() -> void:
	"""开始新的肉鸽流程"""
	GameManager.start_roguelike_run()
	map_data = map_generator.generate_floor_map(GameManager.current_floor)
	current_node_index = 0
	_enter_recruit_phase()


func _enter_recruit_phase() -> void:
	"""进入酒馆招募阶段"""
	phase = RunPhase.RECRUIT
	var options := recruit_system.generate_recruit_options(GameManager.current_floor, GameManager.party.size())
	recruit_phase_started.emit()
	Log.i(M, "进入招募阶段，%d 个选项" % options.size())


func purchase_recruit(option_index: int) -> bool:
	"""购买招募选项"""
	var options := recruit_system.get_current_options()
	if option_index < 0 or option_index >= options.size():
		return false
	var option = options[option_index]
	if not GameManager.spend_gold(option.cost):
		return false
	GameManager.add_to_party(option.class_id, option.level)
	recruit_system.remove_option(option_index)
	return true


func skip_recruit() -> void:
	"""跳过招募"""
	recruit_system.clear_options()
	_enter_map_phase()


func _enter_map_phase() -> void:
	"""进入地图推进阶段"""
	phase = RunPhase.MAP
	map_phase_started.emit()
	# MVP：自动选择下一个战斗节点
	_advance_to_next_node()


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


func _start_battle(node: Dictionary) -> void:
	"""开始战斗"""
	phase = RunPhase.BATTLE
	battle_phase_started.emit()

	# 用队伍数据初始化部署系统
	var battle_party := GameManager.get_battle_party_data()
	var deployment := _get_deployment_system()
	if deployment:
		deployment.setup_hand(battle_party)

	# 配置战斗
	BattleManager.setup_battle(battle_party, node.get("enemy_pool", EnemyUnit.get_enemy_pool()), node.get("waves", 3))
	BattleManager.enemy_spawn_points = node.get("spawn_points", [])

	# 连接战斗结束信号
	if not BattleManager.battle_won.is_connected(_on_battle_won):
		BattleManager.battle_won.connect(_on_battle_won)
	if not BattleManager.battle_lost.is_connected(_on_battle_lost):
		BattleManager.battle_lost.connect(_on_battle_lost)

	# 重置DP，给准备阶段足够的资源
	ResourceManager.reset_dp(20, 100)
	# 不自动开始战斗——等待玩家部署后按 F 键手动推进


func _get_deployment_system() -> DeploymentSystem:
	var tree := get_tree()
	if tree:
		var nodes := tree.get_nodes_in_group("deployment_system")
		if nodes.size() > 0:
			return nodes[0]
	return null


func _on_battle_won() -> void:
	"""战斗胜利"""
	current_node_index += 1
	var reward := _calculate_reward()
	if SynergyManager and SynergyManager.has_method("apply_victory_gold_bonus"):
		reward = SynergyManager.apply_victory_gold_bonus(reward)
	GameManager.earn_gold(reward)
	Log.i(M, "战斗胜利! 获得 %d 金币" % reward)
	_enter_recruit_phase()


func _on_battle_lost() -> void:
	"""战斗失败"""
	Log.i(M, "战斗失败! 冒险结束")
	_end_run(false)


func _calculate_reward() -> int:
	"""计算奖励金币"""
	return 30 + GameManager.current_floor * 10


func _rest_and_advance() -> void:
	current_node_index += 1
	_advance_to_next_node()


func _end_run(victory: bool) -> void:
	phase = RunPhase.ENDED
	GameManager.is_roguelike_run = false
	run_ended.emit(victory)
	if victory:
		Log.i(M, "恭喜! 冒险完成!")
	else:
		Log.i(M, "冒险失败...")
