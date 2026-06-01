# GameManager.gd — 全局游戏状态管理
# 负责场景切换、游戏模式管理、全局数据持有
extends Node

const M = "Game"
const MAX_CHARACTER_LEVEL := 100
const UPGRADE_BASE_COST := 20
const UPGRADE_COST_STEP := 5
const SAVE_VERSION := 1
const SAVE_DIR_PATH := "res://userdata"
const SAVE_FILE_PATH := "res://userdata/save1"

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
	load_save()


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


func spend_gold(amount: int, auto_save: bool = true) -> bool:
	"""消费金币，返回是否成功"""
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		if auto_save:
			save_game()
		return true
	return false


func earn_gold(amount: int) -> void:
	"""获取金币"""
	gold += amount
	gold_changed.emit(gold)
	save_game()


func _ensure_save_data() -> void:
	"""初始化存档持有角色数据"""
	var level_by_class: Dictionary = {}
	for card in owned_characters:
		if not (card is Dictionary):
			continue
		var class_id: String = str(card.get("class_id", ""))
		if class_id in ClassDefinitions.get_all_class_ids() and not level_by_class.has(class_id):
			level_by_class[class_id] = clampi(int(card.get("level", 1)), 1, MAX_CHARACTER_LEVEL)

	var normalized: Array = []
	for class_id in ClassDefinitions.get_all_class_ids():
		normalized.append({
			"class_id": class_id,
			"level": int(level_by_class.get(class_id, 1))
		})

	var changed := owned_characters.size() != normalized.size()
	if not changed:
		for i in range(owned_characters.size()):
			var old_card: Dictionary = owned_characters[i]
			var new_card: Dictionary = normalized[i]
			if old_card.get("class_id", "") != new_card.get("class_id", "") or int(old_card.get("level", 1)) != int(new_card.get("level", 1)):
				changed = true
				break

	owned_characters = normalized
	if changed:
		owned_characters_changed.emit(owned_characters)


func load_save() -> void:
	"""运行游戏后自动加载 save1；不存在时创建默认存档"""
	_ensure_save_directory()
	var loaded := false
	var save_path := _get_save_file_absolute_path()

	if FileAccess.file_exists(save_path):
		var file := FileAccess.open(save_path, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_apply_save_data(parsed)
				loaded = true
			else:
				Log.w(M, "存档解析失败，使用默认存档: %s" % save_path)
		else:
			Log.w(M, "无法读取存档，使用默认存档: %s" % save_path)

	if not loaded:
		gold = 100
		owned_characters.clear()
		_ensure_save_data()
	else:
		_ensure_save_data()

	save_game()
	gold_changed.emit(gold)
	owned_characters_changed.emit(owned_characters)
	Log.i(M, "已加载存档 save1: 金币 %d, 角色 %d" % [gold, owned_characters.size()])


func save_game() -> bool:
	"""保存玩家存档资源和角色仓库到 userdata/save1"""
	_ensure_save_directory()
	var file := FileAccess.open(_get_save_file_absolute_path(), FileAccess.WRITE)
	if not file:
		Log.w(M, "无法写入存档: %s" % _get_save_file_absolute_path())
		return false

	file.store_string(JSON.stringify(_build_save_data(), "\t"))
	return true


func _apply_save_data(data: Dictionary) -> void:
	"""把存档数据应用到全局玩家数据"""
	var resources: Dictionary = data.get("resources", {})
	gold = max(0, int(resources.get("gold", 100)))

	owned_characters.clear()
	var stored_characters: Array = data.get("owned_characters", [])
	for card in stored_characters:
		if not (card is Dictionary):
			continue
		owned_characters.append({
			"class_id": str(card.get("class_id", "")),
			"level": clampi(int(card.get("level", 1)), 1, MAX_CHARACTER_LEVEL)
		})


func _build_save_data() -> Dictionary:
	"""构建当前版本的存档数据"""
	return {
		"version": SAVE_VERSION,
		"resources": {
			"gold": gold
		},
		"owned_characters": owned_characters
	}


func _ensure_save_directory() -> void:
	"""确保存档目录存在"""
	var dir_path := _get_save_dir_absolute_path()
	if DirAccess.dir_exists_absolute(dir_path):
		return
	var error := DirAccess.make_dir_recursive_absolute(dir_path)
	if error != OK:
		Log.w(M, "创建存档目录失败: %s error=%d" % [dir_path, error])


func _get_save_dir_absolute_path() -> String:
	"""获取项目根目录下 userdata 的绝对路径"""
	return ProjectSettings.globalize_path(SAVE_DIR_PATH)


func _get_save_file_absolute_path() -> String:
	"""获取 save1 存档文件的绝对路径"""
	return ProjectSettings.globalize_path(SAVE_FILE_PATH)


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
	if not spend_gold(cost, false):
		return false

	card["level"] = next_level
	owned_characters[index] = card
	owned_characters_changed.emit(owned_characters)
	party_changed.emit(party)
	save_game()
	Log.i(M, "角色升级: %s Lv.%d -> Lv.%d, 消耗金币 %d" % [
		card.get("class_id", ""),
		current_level,
		next_level,
		cost
	])
	return true
