# GameManager.gd — 全局游戏状态管理
# 负责场景切换、游戏模式管理、全局数据持有
extends Node

const M = "Game"
const MAX_CHARACTER_LEVEL := 100
const UPGRADE_BASE_COST := 20
const UPGRADE_COST_STEP := 5

signal gold_changed(gold: int)
signal owned_characters_changed(characters: Array)
signal party_changed(party: Array)

enum GameMode {
	BATTLE,        ## 战斗模式
	RECRUIT,       ## 酒馆招募
	MAP,           ## 地图推进
	MAIN_MENU      ## 主菜单
}

var current_mode: GameMode = GameMode.BATTLE

## 肉鸽模式下的全局队伍数据
var party: Array = []               # 本次冒险队伍 [{class_id, star_level, level}]
var owned_characters: Array = []    # 存档持有角色 [{class_id, level}]
var gold: int = 100                 # 存档金币
var current_floor: int = 1          # 当前层数
var is_roguelike_run: bool = false  # 是否在肉鸽流程中

## 肉鸽运行状态
var run_history: Array = []         # 经过的节点记录
var blessings: Array = []           # 祝福/遗物


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_save_data()


func start_battle(party_data: Array, enemy_pool: Array, wave_count: int = 3) -> void:
	"""开始一场战斗"""
	BattleManager.setup_battle(party_data, enemy_pool, wave_count)
	current_mode = GameMode.BATTLE


func start_roguelike_run() -> void:
	"""开始一次新的肉鸽流程"""
	_ensure_save_data()
	is_roguelike_run = true
	party.clear()
	current_floor = 1
	run_history.clear()
	blessings.clear()
	# 给初始基础角色
	_add_starter_party()
	party_changed.emit(party)
	_enter_recruit_phase()


func _add_starter_party() -> void:
	"""添加初始队伍（战士+游侠）"""
	add_to_party("warrior", 1)
	add_to_party("ranger", 1)


func _enter_recruit_phase() -> void:
	"""进入酒馆招募阶段"""
	current_mode = GameMode.RECRUIT


func proceed_to_next_floor() -> void:
	"""推进到下一层"""
	current_floor += 1


func add_to_party(class_id: String, star_level: int = 1) -> void:
	"""添加角色到本次冒险队伍；level 表示局内招募星级"""
	var star := clampi(star_level, 1, 3)
	party.append({
		"class_id": class_id,
		"star_level": star,
		"level": get_effective_level_for_star(class_id, star)
	})
	party_changed.emit(party)


func spend_gold(amount: int) -> bool:
	"""消费金币，返回是否成功"""
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false


func earn_gold(amount: int) -> void:
	"""获取金币"""
	gold += amount
	gold_changed.emit(gold)


func _ensure_save_data() -> void:
	"""初始化存档持有角色数据"""
	if not owned_characters.is_empty():
		return
	for class_id in ClassDefinitions.get_all_class_ids():
		owned_characters.append({"class_id": class_id, "level": 1})
	owned_characters_changed.emit(owned_characters)


func get_owned_character_level(class_id: String) -> int:
	"""获取存档中的角色养成等级"""
	_ensure_save_data()
	for card in owned_characters:
		if card.get("class_id", "") == class_id:
			return int(card.get("level", 1))
	return 1


func get_star_level_cap(star_level: int) -> int:
	"""获取局内招募星级对应的战斗等级上限"""
	match clampi(star_level, 1, 3):
		1:
			return 30
		2:
			return 70
		_:
			return 100


func get_effective_level_for_star(class_id: String, star_level: int) -> int:
	"""根据养成等级和星级上限计算本次战斗实际等级"""
	return min(get_owned_character_level(class_id), get_star_level_cap(star_level))


func get_battle_party_data() -> Array:
	"""生成用于部署和战斗的队伍数据"""
	var result: Array = []
	for member in party:
		var class_id: String = member.get("class_id", "warrior")
		var star_level: int = int(member.get("star_level", member.get("level", 1)))
		var data: Dictionary = member.duplicate(true)
		data["star_level"] = star_level
		data["level"] = get_effective_level_for_star(class_id, star_level)
		result.append(data)
	return result


func calculate_upgrade_cost(current_level: int, target_level: int) -> int:
	"""计算从当前等级升到目标等级所需金币"""
	var from_level := clampi(current_level, 1, MAX_CHARACTER_LEVEL)
	var to_level := clampi(target_level, 1, MAX_CHARACTER_LEVEL)
	if to_level <= from_level:
		return 0

	var total := 0
	for level in range(from_level, to_level):
		total += UPGRADE_BASE_COST + level * UPGRADE_COST_STEP
	return total


func upgrade_owned_character(index: int, target_level: int) -> bool:
	"""将指定存档持有角色升级到目标等级"""
	_ensure_save_data()
	if index < 0 or index >= owned_characters.size():
		return false

	var card: Dictionary = owned_characters[index]
	var current_level: int = int(card.get("level", 1))
	var next_level := clampi(target_level, current_level, MAX_CHARACTER_LEVEL)
	var cost := calculate_upgrade_cost(current_level, next_level)
	if cost <= 0:
		return false
	if not spend_gold(cost):
		return false

	card["level"] = next_level
	owned_characters[index] = card
	owned_characters_changed.emit(owned_characters)
	party_changed.emit(party)
	Log.i(M, "角色升级: %s Lv.%d -> Lv.%d, 消耗金币 %d" % [
		card.get("class_id", ""),
		current_level,
		next_level,
		cost
	])
	return true
