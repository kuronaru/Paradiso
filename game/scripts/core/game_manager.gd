# GameManager.gd — 全局游戏状态管理
# 负责场景切换、游戏模式管理、全局数据持有
extends Node

const M = "Game"
const MAX_CHARACTER_LEVEL := 100
const UPGRADE_BASE_COST := 20
const UPGRADE_COST_STEP := 5
const SAVE_VERSION := 1
const SAVE_DIR_PATH := "res://userdata"
const SAVE_SLOT_IDS: Array[String] = ["save1", "save2", "save3"]
const LAST_SAVE_FILE_PATH := "res://userdata/last_save"
const ROGUELIKE_STARTING_GOLD := 6
const ROGUELIKE_MAX_HAND_CARDS := 10
const ROGUELIKE_MAX_DEPLOYED_UNITS := 8
const ROGUELIKE_MAX_ROUNDS := 15

signal gold_changed(gold: int)
signal run_gold_changed(gold: int)
signal run_round_changed(round: int, max_rounds: int)
signal owned_characters_changed(characters: Array)
signal party_changed(party: Array)
signal save_slot_changed(save_id: String)

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
var run_gold: int = 0                # 单局肉鸽金币
var current_floor: int = 1          # 当前层数
var current_run_round: int = 1       # 当前肉鸽回合
var max_run_rounds: int = ROGUELIKE_MAX_ROUNDS
var is_roguelike_run: bool = false  # 是否在肉鸽流程中
var current_save_id: String = "save1"
var has_active_save: bool = false

## 肉鸽运行状态
var run_history: Array = []         # 经过的节点记录
var blessings: Array = []           # 祝福/遗物
var _next_run_card_instance_id: int = 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_last_selected_save()


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
	current_run_round = 1
	max_run_rounds = ROGUELIKE_MAX_ROUNDS
	run_gold = ROGUELIKE_STARTING_GOLD
	_next_run_card_instance_id = 1
	run_history.clear()
	blessings.clear()
	party_changed.emit(party)
	run_gold_changed.emit(run_gold)
	run_round_changed.emit(current_run_round, max_run_rounds)
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


func advance_roguelike_round() -> void:
	"""推进肉鸽单局回合，并同步旧楼层字段供现有UI显示。"""
	current_run_round += 1
	current_floor = current_run_round
	run_round_changed.emit(current_run_round, max_run_rounds)


func can_add_to_party(card_count: int = 1) -> bool:
	"""检查当前单局手牌区是否还能加入角色。"""
	if not is_roguelike_run:
		return true
	return party.size() + card_count <= ROGUELIKE_MAX_HAND_CARDS


func add_to_party(class_id: String, star_level: int = 1) -> bool:
	"""添加角色到本次冒险队伍；level 表示局内招募星级"""
	if not can_add_to_party():
		return false
	var star := clampi(star_level, 1, 3)
	var card := {
		"class_id": class_id,
		"star_level": star,
		"level": get_effective_level_for_star(class_id, star)
	}
	if is_roguelike_run:
		card["instance_id"] = _next_run_card_instance_id
		_next_run_card_instance_id += 1
	party.append(card)
	party_changed.emit(party)
	return true


func remove_from_party_card(card_data: Dictionary) -> bool:
	"""从单局手牌数据中移除一张卡，部署成功时调用。"""
	if not is_roguelike_run:
		return true

	var instance_id := int(card_data.get("instance_id", -1))
	for i in range(party.size()):
		var member: Dictionary = party[i]
		if instance_id >= 0 and int(member.get("instance_id", -2)) == instance_id:
			party.remove_at(i)
			party_changed.emit(party)
			return true

	var class_id := str(card_data.get("class_id", ""))
	var star_level := int(card_data.get("star_level", card_data.get("level", 1)))
	for i in range(party.size()):
		var member: Dictionary = party[i]
		if str(member.get("class_id", "")) == class_id and int(member.get("star_level", member.get("level", 1))) == star_level:
			party.remove_at(i)
			party_changed.emit(party)
			return true

	return false


func return_card_to_party(card_data: Dictionary) -> bool:
	"""撤回部署角色时，把卡牌放回单局手牌区。"""
	if not can_add_to_party():
		return false

	var restored := card_data.duplicate(true)
	var class_id := str(restored.get("class_id", "warrior"))
	var star := clampi(int(restored.get("star_level", restored.get("level", 1))), 1, 3)
	restored["class_id"] = class_id
	restored["star_level"] = star
	restored["level"] = get_effective_level_for_star(class_id, star)
	if is_roguelike_run and not restored.has("instance_id"):
		restored["instance_id"] = _next_run_card_instance_id
		_next_run_card_instance_id += 1

	party.append(restored)
	party_changed.emit(party)
	return true


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


func get_active_gold() -> int:
	"""获取当前界面应显示和消费的金币。"""
	return run_gold if is_roguelike_run else gold


func spend_run_gold(amount: int) -> bool:
	"""消费单局肉鸽金币，不写入存档。"""
	if amount < 0:
		return false
	if run_gold >= amount:
		run_gold -= amount
		run_gold_changed.emit(run_gold)
		return true
	return false


func earn_run_gold(amount: int) -> void:
	"""获得单局肉鸽金币，不写入存档。"""
	run_gold += max(0, amount)
	run_gold_changed.emit(run_gold)


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


func load_last_selected_save() -> void:
	"""运行游戏后自动加载上次选择的存档槽位"""
	_ensure_save_directory()
	current_save_id = _read_last_save_id()
	if has_save_slot(current_save_id):
		load_save(current_save_id)
		return

	var fallback_save_id := get_continue_save_id()
	current_save_id = fallback_save_id
	if has_save_slot(current_save_id):
		load_save(current_save_id)
		return

	_reset_default_save_data()
	has_active_save = false
	gold_changed.emit(gold)
	owned_characters_changed.emit(owned_characters)
	save_slot_changed.emit(current_save_id)


func load_save(save_id: String = "") -> void:
	"""加载指定存档槽位；不存在时保持为空白存档"""
	_ensure_save_directory()
	current_save_id = _normalize_save_id(save_id if save_id != "" else current_save_id)
	_write_last_save_id(current_save_id)
	var loaded := false
	var save_path := _get_save_file_absolute_path(current_save_id)

	if FileAccess.file_exists(save_path):
		var file := FileAccess.open(save_path, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_apply_save_data(parsed)
				loaded = true
			else:
				Log.w(M, "存档解析失败，保持为空白存档: %s" % save_path)
		else:
			Log.w(M, "无法读取存档，保持为空白存档: %s" % save_path)

	if not loaded:
		_reset_default_save_data()
		has_active_save = false
	else:
		_ensure_save_data()
		has_active_save = true
		save_game()

	gold_changed.emit(gold)
	owned_characters_changed.emit(owned_characters)
	save_slot_changed.emit(current_save_id)
	Log.i(M, "已加载存档 %s: 金币 %d, 角色 %d" % [current_save_id, gold, owned_characters.size()])


func save_game() -> bool:
	"""保存玩家存档资源和角色仓库到当前存档槽位"""
	if not has_active_save:
		return false
	_ensure_save_directory()
	var save_path := _get_save_file_absolute_path(current_save_id)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		Log.w(M, "无法写入存档: %s" % save_path)
		return false

	file.store_string(JSON.stringify(_build_save_data(), "\t"))
	return true


func switch_save_slot(save_id: String) -> void:
	"""切换当前使用的存档槽位"""
	save_game()
	load_save(save_id)


func create_new_save(save_id: String = "") -> void:
	"""在指定槽位创建新的默认存档"""
	current_save_id = _normalize_save_id(save_id if save_id != "" else current_save_id)
	_reset_default_save_data()
	has_active_save = true
	_write_last_save_id(current_save_id)
	save_game()
	gold_changed.emit(gold)
	owned_characters_changed.emit(owned_characters)
	save_slot_changed.emit(current_save_id)


func get_save_slot_ids() -> Array[String]:
	"""获取当前版本可用的存档槽位"""
	return SAVE_SLOT_IDS.duplicate()


func has_save_slot(save_id: String) -> bool:
	"""判断指定存档槽位是否已有存档文件"""
	return FileAccess.file_exists(_get_save_file_absolute_path(save_id))


func has_any_save_slot() -> bool:
	"""判断三个存档槽位中是否存在任意存档"""
	for save_id in SAVE_SLOT_IDS:
		if has_save_slot(save_id):
			return true
	return false


func get_continue_save_id() -> String:
	"""获取继续游戏应使用的存档槽位"""
	if has_save_slot(current_save_id):
		return current_save_id

	var last_save_id := _read_last_save_id()
	if has_save_slot(last_save_id):
		return last_save_id

	for save_id in SAVE_SLOT_IDS:
		if has_save_slot(save_id):
			return save_id
	return current_save_id


func get_save_slot_summary(save_id: String) -> Dictionary:
	"""读取存档槽位摘要，用于主菜单选择界面"""
	var normalized := _normalize_save_id(save_id)
	var summary := {
		"save_id": normalized,
		"exists": false,
		"gold": 0,
		"character_count": 0
	}
	var path := _get_save_file_absolute_path(normalized)
	if not FileAccess.file_exists(path):
		return summary

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return summary

	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return summary

	summary["exists"] = true
	var resources: Dictionary = parsed.get("resources", {})
	summary["gold"] = max(0, int(resources.get("gold", 100)))
	var characters: Array = parsed.get("owned_characters", [])
	summary["character_count"] = characters.size()
	return summary


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


func _reset_default_save_data() -> void:
	"""重置为新存档的默认玩家数据"""
	gold = 100
	owned_characters.clear()
	_ensure_save_data()


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


func _get_save_file_absolute_path(save_id: String = "") -> String:
	"""获取指定存档槽位文件的绝对路径"""
	var normalized := _normalize_save_id(save_id if save_id != "" else current_save_id)
	return ProjectSettings.globalize_path("%s/%s" % [SAVE_DIR_PATH, normalized])


func _get_last_save_file_absolute_path() -> String:
	"""获取上次使用存档记录文件的绝对路径"""
	return ProjectSettings.globalize_path(LAST_SAVE_FILE_PATH)


func _read_last_save_id() -> String:
	"""读取上次使用的存档槽位"""
	var path := _get_last_save_file_absolute_path()
	if not FileAccess.file_exists(path):
		return "save1"

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return "save1"

	return _normalize_save_id(file.get_as_text().strip_edges())


func _write_last_save_id(save_id: String) -> void:
	"""记录上次使用的存档槽位"""
	_ensure_save_directory()
	var file := FileAccess.open(_get_last_save_file_absolute_path(), FileAccess.WRITE)
	if file:
		file.store_string(_normalize_save_id(save_id))


func _normalize_save_id(save_id: String) -> String:
	"""规范化存档槽位ID"""
	return save_id if save_id in SAVE_SLOT_IDS else "save1"


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
