# GameManager.gd — 全局游戏状态管理
# 负责场景切换、游戏模式管理、全局数据持有
extends Node

enum GameMode {
	BATTLE,        ## 战斗模式
	RECRUIT,       ## 酒馆招募
	MAP,           ## 地图推进
	MAIN_MENU      ## 主菜单
}

var current_mode: GameMode = GameMode.BATTLE

## 肉鸽模式下的全局队伍数据
var party: Array = []              # 持有的角色卡牌列表 [{class_id, level, ...}]
var gold: int = 0                   # 金币
var current_floor: int = 1          # 当前层数
var is_roguelike_run: bool = false  # 是否在肉鸽流程中

## 肉鸽运行状态
var run_history: Array = []         # 经过的节点记录
var blessings: Array = []           # 祝福/遗物


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_battle(party_data: Array, enemy_pool: Array, wave_count: int = 3) -> void:
	"""开始一场战斗"""
	BattleManager.setup_battle(party_data, enemy_pool, wave_count)
	current_mode = GameMode.BATTLE


func start_roguelike_run() -> void:
	"""开始一次新的肉鸽流程"""
	is_roguelike_run = true
	party.clear()
	gold = 100
	current_floor = 1
	run_history.clear()
	blessings.clear()
	# 给初始基础角色
	_add_starter_party()
	_enter_recruit_phase()


func _add_starter_party() -> void:
	"""添加初始队伍（战士+游侠）"""
	party.append({"class_id": "warrior", "level": 1})
	party.append({"class_id": "ranger", "level": 1})


func _enter_recruit_phase() -> void:
	"""进入酒馆招募阶段"""
	current_mode = GameMode.RECRUIT


func proceed_to_next_floor() -> void:
	"""推进到下一层"""
	current_floor += 1


func add_to_party(class_id: String, level: int = 1) -> void:
	"""添加角色到队伍"""
	party.append({"class_id": class_id, "level": level})


func spend_gold(amount: int) -> bool:
	"""消费金币，返回是否成功"""
	if gold >= amount:
		gold -= amount
		return true
	return false


func earn_gold(amount: int) -> void:
	"""获取金币"""
	gold += amount
