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
const ROGUELIKE_STARTING_GOLD := 0
const ROGUELIKE_MAX_HAND_CARDS := 10
const ROGUELIKE_MAX_DEPLOYED_UNITS := 8
const ROGUELIKE_MAX_ROUNDS := 15
const ROGUELIKE_MAX_CARD_STAR := 3
const ROGUELIKE_DEFAULT_RELIC_ID := "merchant_ledger"
const ROGUELIKE_PLAYER_MAX_LIFE := 20
const TAVERN_BASE_INCOME := 4
const TAVERN_INCOME_PER_ROUND := 1

const ROGUELIKE_RELIC_DEFINITIONS := [
	{
		"id": "merchant_ledger",
		"name": "商队账本",
		"summary": "开局额外获得 2 金币。",
		"description": "适合稳健开局，能在第一回合多买一名低费角色或保留一次刷新空间。",
		"modifiers": {
			"starting_gold_bonus": 2
		}
	},
	{
		"id": "bounty_seal",
		"name": "悬赏印章",
		"summary": "每次战斗胜利额外获得 1 金币。",
		"description": "偏长期经济的占位信物，鼓励尽快稳定阵容并滚动胜利收益。",
		"modifiers": {
			"victory_gold_bonus": 1
		}
	},
	{
		"id": "regular_coupon",
		"name": "熟客酒券",
		"summary": "手动刷新酒馆费用降低 1，最低为 0。",
		"description": "提高找对子和关键羁绊的效率，适合围绕刷新构筑阵容。",
		"modifiers": {
			"refresh_cost_delta": -1
		}
	},
	{
		"id": "spare_card_box",
		"name": "备用牌匣",
		"summary": "手牌区上限增加 2。",
		"description": "给等待三合一和保留功能卡更多空间，降低爆手牌的压力。",
		"modifiers": {
			"hand_limit_bonus": 2
		}
	},
	{
		"id": "tavern_signboard",
		"name": "翻新招牌",
		"summary": "开局酒馆等级提高 1。",
		"description": "牺牲纯经济换取更早的高等阶招募池，适合想快速成型的路线。",
		"modifiers": {
			"starting_tavern_level_bonus": 1
		}
	}
]

signal gold_changed(gold: int)
signal run_gold_changed(gold: int)
signal run_round_changed(round: int, max_rounds: int)
signal run_life_changed(current: int, maximum: int)
signal run_player_eliminated
signal owned_characters_changed(characters: Array)
signal party_changed(party: Array)
signal save_slot_changed(save_id: String)
signal run_relic_changed(relic: Dictionary)

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
var gold: int = 0                   # 存档金币
var run_gold: int = 0                # 单局肉鸽金币
var run_life: int = ROGUELIKE_PLAYER_MAX_LIFE
var run_max_life: int = ROGUELIKE_PLAYER_MAX_LIFE
var current_floor: int = 1          # 当前层数
var current_run_round: int = 1       # 当前肉鸽回合
var max_run_rounds: int = ROGUELIKE_MAX_ROUNDS
var is_roguelike_run: bool = false  # 是否在肉鸽流程中
var last_tavern_income_round: int = 0
var current_save_id: String = "save1"
var has_active_save: bool = false

## 肉鸽运行状态
var run_history: Array = []         # 经过的节点记录
var blessings: Array = []           # 祝福/遗物
var pending_run_relic_id: String = ""
var active_run_relic_id: String = ""
var _next_run_card_instance_id: int = 1


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	max_run_rounds = _cfg_int("roguelike_max_rounds", ROGUELIKE_MAX_ROUNDS)
	load_last_selected_save()


## 开始一场战斗
func start_battle(party_data: Array, enemy_pool: Array, wave_count: int = 3) -> void:
	"""开始一场战斗"""
	BattleManager.setup_battle(party_data, enemy_pool, wave_count)
	current_mode = GameMode.BATTLE


## 开始一次新的肉鸽流程
func start_roguelike_run(relic_id: String = "") -> void:
	"""开始一次新的肉鸽流程"""
	if SynergyManager and SynergyManager.has_method("reset_run_state"):
		SynergyManager.reset_run_state()
	_ensure_save_data()
	active_run_relic_id = _resolve_run_relic_id(relic_id)
	pending_run_relic_id = ""
	is_roguelike_run = true
	party.clear()
	current_floor = 1
	current_run_round = 1
	max_run_rounds = _cfg_int("roguelike_max_rounds", ROGUELIKE_MAX_ROUNDS)
	run_gold = _cfg_int("roguelike_starting_gold", ROGUELIKE_STARTING_GOLD) + get_roguelike_relic_modifier("starting_gold_bonus")
	run_max_life = maxi(1, _cfg_int("roguelike_player_max_life", ROGUELIKE_PLAYER_MAX_LIFE))
	run_life = run_max_life
	last_tavern_income_round = 0
	_next_run_card_instance_id = 1
	run_history.clear()
	blessings.clear()
	blessings.append(get_active_roguelike_relic())
	party_changed.emit(party)
	run_gold_changed.emit(run_gold)
	run_round_changed.emit(current_run_round, max_run_rounds)
	run_life_changed.emit(run_life, run_max_life)
	run_relic_changed.emit(get_active_roguelike_relic())
	_enter_recruit_phase()


## 添加初始队伍（战士+游侠）
func _add_starter_party() -> void:
	"""添加初始队伍（战士+游侠）"""
	add_to_party("warrior", 1)
	add_to_party("ranger", 1)


## 进入酒馆招募阶段
func _enter_recruit_phase() -> void:
	"""进入酒馆招募阶段"""
	current_mode = GameMode.RECRUIT


## 获取所有可选肉鸽信物定义。
func get_roguelike_relic_definitions() -> Array:
	return ROGUELIKE_RELIC_DEFINITIONS.duplicate(true)


## 获取指定信物定义。
func get_roguelike_relic_definition(relic_id: String) -> Dictionary:
	for relic in ROGUELIKE_RELIC_DEFINITIONS:
		var data: Dictionary = relic
		if str(data.get("id", "")) == relic_id:
			return data.duplicate(true)
	return {}


## 暂存下一局肉鸽将要携带的信物。
func set_pending_roguelike_relic(relic_id: String) -> bool:
	var resolved_id := _resolve_relic_id(relic_id)
	if resolved_id == "":
		return false
	pending_run_relic_id = resolved_id
	return true


## 获取待选择信物；未选择时返回默认信物。
func get_pending_roguelike_relic() -> Dictionary:
	var resolved_id := _resolve_relic_id(pending_run_relic_id)
	if resolved_id == "":
		resolved_id = ROGUELIKE_DEFAULT_RELIC_ID
	return get_roguelike_relic_definition(resolved_id)


## 获取当前局生效信物。
func get_active_roguelike_relic() -> Dictionary:
	var resolved_id := _resolve_relic_id(active_run_relic_id)
	if resolved_id == "":
		resolved_id = ROGUELIKE_DEFAULT_RELIC_ID
	return get_roguelike_relic_definition(resolved_id)


## 获取当前信物的整数修正值。
func get_roguelike_relic_modifier(key: String, default_value: int = 0) -> int:
	var relic := get_active_roguelike_relic()
	var modifiers: Dictionary = relic.get("modifiers", {})
	return int(modifiers.get(key, default_value))


## 应用当前信物对刷新费用的修正。
func apply_roguelike_relic_refresh_cost(base_cost: int) -> int:
	return maxi(0, base_cost + get_roguelike_relic_modifier("refresh_cost_delta"))


## 应用当前信物对胜利金币的修正。
func apply_roguelike_relic_victory_reward(base_reward: int) -> int:
	return maxi(0, base_reward + get_roguelike_relic_modifier("victory_gold_bonus"))


func _resolve_run_relic_id(relic_id: String) -> String:
	var resolved_id := _resolve_relic_id(relic_id)
	if resolved_id != "":
		return resolved_id
	resolved_id = _resolve_relic_id(pending_run_relic_id)
	if resolved_id != "":
		return resolved_id
	return ROGUELIKE_DEFAULT_RELIC_ID


func _resolve_relic_id(relic_id: String) -> String:
	if relic_id != "" and not get_roguelike_relic_definition(relic_id).is_empty():
		return relic_id
	return ""


## 推进到下一层
func proceed_to_next_floor() -> void:
	"""推进到下一层"""
	current_floor += 1


## 推进肉鸽单局回合，并同步旧楼层字段供现有UI显示。
func advance_roguelike_round() -> void:
	"""推进肉鸽单局回合，并同步旧楼层字段供现有UI显示。"""
	current_run_round += 1
	current_floor = current_run_round
	run_round_changed.emit(current_run_round, max_run_rounds)


## 计算指定回合进入酒馆时获得的固定收入。
func get_tavern_round_income(round_number: int = current_run_round) -> int:
	var round_index := maxi(1, round_number)
	return maxi(0,
		_cfg_int("tavern_base_income", TAVERN_BASE_INCOME)
		+ (round_index - 1) * _cfg_int("tavern_income_per_round", TAVERN_INCOME_PER_ROUND)
	)


## 幂等发放当前回合酒馆固定收入。
func grant_current_round_tavern_income() -> int:
	if not is_roguelike_run or last_tavern_income_round == current_run_round:
		return 0
	var income := get_tavern_round_income(current_run_round)
	last_tavern_income_round = current_run_round
	earn_run_gold(income)
	return income


## 重置单局玩家生命。
func reset_run_life(maximum: int = -1) -> void:
	run_max_life = maxi(1, maximum if maximum > 0 else _cfg_int("roguelike_player_max_life", ROGUELIKE_PLAYER_MAX_LIFE))
	run_life = run_max_life
	run_life_changed.emit(run_life, run_max_life)


## 扣除单局玩家生命，返回实际扣除值。
func damage_run_life(amount: int) -> int:
	if amount <= 0 or run_life <= 0:
		return 0
	var previous := run_life
	run_life = maxi(0, run_life - amount)
	var actual := previous - run_life
	run_life_changed.emit(run_life, run_max_life)
	if previous > 0 and run_life == 0:
		run_player_eliminated.emit()
	return actual


## 恢复单局玩家生命，返回实际恢复值。
func heal_run_life(amount: int) -> int:
	if amount <= 0 or run_life <= 0:
		return 0
	var previous := run_life
	run_life = mini(run_max_life, run_life + amount)
	var actual := run_life - previous
	if actual > 0:
		run_life_changed.emit(run_life, run_max_life)
	return actual


func is_run_player_alive() -> bool:
	return run_life > 0


## 检查当前单局手牌区是否还能加入角色。
func can_add_to_party(card_count: int = 1) -> bool:
	"""检查当前单局手牌区是否还能加入角色。"""
	if not is_roguelike_run:
		return true
	return party.size() + card_count <= _cfg_int("roguelike_max_hand_cards", ROGUELIKE_MAX_HAND_CARDS)


## 添加角色到本次冒险队伍；level 表示局内招募星级
func add_to_party(class_id: String, star_level: int = 1, shop_level: int = 1, upgrade_tier: int = 1) -> bool:
	"""添加角色到本次冒险队伍；level 表示局内招募星级"""
	if not can_add_to_party():
		return false
	var canonical_id := ClassDefinitions.canonicalize_class_id(class_id)
	var star := clampi(star_level, 1, ROGUELIKE_MAX_CARD_STAR)
	var tier := maxi(1, upgrade_tier)
	var card: Dictionary = {
		"class_id": canonical_id,
		"star_level": star,
		"level": get_effective_level_for_star(canonical_id, star),
		"shop_level": maxi(1, shop_level),
		"upgrade_tier": tier,
		"merge_locked": tier > 1,
		"is_golden": tier > 1
	}
	if is_roguelike_run:
		card["instance_id"] = _next_run_card_instance_id
		_next_run_card_instance_id += 1
	party.append(card)
	party_changed.emit(party)
	return true


## 从单局手牌数据中移除一张卡，部署成功时调用。
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

	var class_id := ClassDefinitions.canonicalize_class_id(str(card_data.get("class_id", "")))
	var star_level := int(card_data.get("star_level", card_data.get("level", 1)))
	var shop_level := int(card_data.get("shop_level", 1))
	var upgrade_tier := int(card_data.get("upgrade_tier", 1))
	for i in range(party.size()):
		var member: Dictionary = party[i]
		if ClassDefinitions.canonicalize_class_id(str(member.get("class_id", ""))) == class_id \
				and int(member.get("star_level", member.get("level", 1))) == star_level \
				and int(member.get("shop_level", 1)) == shop_level \
				and int(member.get("upgrade_tier", 1)) == upgrade_tier:
			party.remove_at(i)
			party_changed.emit(party)
			return true

	return false


## 撤回部署角色时，把卡牌放回单局手牌区。
func return_card_to_party(card_data: Dictionary) -> bool:
	"""撤回部署角色时，把卡牌放回单局手牌区。"""
	if not can_add_to_party():
		return false

	var restored := card_data.duplicate(true)
	var class_id := ClassDefinitions.canonicalize_class_id(str(restored.get("class_id", "fighter_champion")))
	var star := clampi(int(restored.get("star_level", restored.get("level", 1))), 1, ROGUELIKE_MAX_CARD_STAR)
	restored["class_id"] = class_id
	restored["star_level"] = star
	restored["level"] = get_effective_level_for_star(class_id, star)
	restored["shop_level"] = maxi(1, int(restored.get("shop_level", 1)))
	restored["upgrade_tier"] = maxi(1, int(restored.get("upgrade_tier", 1)))
	restored["merge_locked"] = bool(restored.get("merge_locked", false)) or int(restored["upgrade_tier"]) > 1
	restored["is_golden"] = bool(restored.get("is_golden", false)) or bool(restored["merge_locked"])
	if is_roguelike_run and not restored.has("instance_id"):
		restored["instance_id"] = _next_run_card_instance_id
		_next_run_card_instance_id += 1

	party.append(restored)
	party_changed.emit(party)
	return true


## 同名、同星、同商店等级的三张普通卡合成为一张更高星金卡；升星卡不再参与三合一。
func _try_promote_party_cards(class_id: String, star_level: int, shop_level: int, upgrade_tier: int) -> Dictionary:
	"""同名、同星、同商店等级的三张普通卡合成为一张更高星金卡；升星卡不再参与三合一。"""
	var canonical_id := ClassDefinitions.canonicalize_class_id(class_id)
	var source_star := clampi(star_level, 1, ROGUELIKE_MAX_CARD_STAR)
	if source_star >= ROGUELIKE_MAX_CARD_STAR:
		return {}
	if upgrade_tier > 1:
		return {}

	var matches: Array[int] = []
	for i in range(party.size()):
		var member: Dictionary = party[i]
		if ClassDefinitions.canonicalize_class_id(str(member.get("class_id", ""))) != canonical_id:
			continue
		if bool(member.get("merge_locked", false)):
			continue
		if int(member.get("upgrade_tier", 1)) > 1:
			continue
		if int(member.get("star_level", member.get("level", 1))) != source_star:
			continue
		if int(member.get("shop_level", 1)) != shop_level:
			continue
		matches.append(i)
		if matches.size() >= 3:
			break

	if matches.size() < 3:
		return {}

	for j in range(matches.size() - 1, -1, -1):
		party.remove_at(matches[j])

	var promoted_star := mini(source_star + 1, ROGUELIKE_MAX_CARD_STAR)
	var promoted_card := {
		"class_id": canonical_id,
		"star_level": promoted_star,
		"level": get_effective_level_for_star(canonical_id, promoted_star),
		"shop_level": shop_level,
		"upgrade_tier": 2,
		"merge_locked": true,
		"is_golden": true,
		"instance_id": _next_run_card_instance_id
	}
	_next_run_card_instance_id += 1
	party.append(promoted_card)
	Log.i(M, "三合一升星: %s 等阶%d %d星 -> %d星" % [canonical_id, shop_level, source_star, promoted_star])
	return promoted_card.duplicate(true)


## 消费金币，返回是否成功
func spend_gold(amount: int, auto_save: bool = true) -> bool:
	"""消费金币，返回是否成功"""
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		if auto_save:
			save_game()
		return true
	return false


## 获取金币
func earn_gold(amount: int) -> void:
	"""获取金币"""
	gold += amount
	gold_changed.emit(gold)
	save_game()


## 获取当前界面应显示和消费的金币。
func get_active_gold() -> int:
	"""获取当前界面应显示和消费的金币。"""
	return run_gold if is_roguelike_run else gold


## 消费单局肉鸽金币，不写入存档。
func spend_run_gold(amount: int) -> bool:
	"""消费单局肉鸽金币，不写入存档。"""
	if amount < 0:
		return false
	if run_gold >= amount:
		run_gold -= amount
		run_gold_changed.emit(run_gold)
		return true
	return false


## 获得单局肉鸽金币，不写入存档。
func earn_run_gold(amount: int) -> void:
	"""获得单局肉鸽金币，不写入存档。"""
	run_gold += max(0, amount)
	run_gold_changed.emit(run_gold)


## 清空本轮未花费的酒馆金币。
func clear_run_gold() -> void:
	"""清空本轮未花费的酒馆金币。"""
	if run_gold == 0:
		return
	run_gold = 0
	run_gold_changed.emit(run_gold)


## 初始化存档持有角色数据
func _ensure_save_data() -> void:
	"""初始化存档持有角色数据"""
	var level_by_class: Dictionary = {}
	for card in owned_characters:
		if not (card is Dictionary):
			continue
		var class_id := ClassDefinitions.canonicalize_class_id(str(card.get("class_id", "")))
		var stored_level := clampi(int(card.get("level", 1)), 1, _max_character_level())
		level_by_class[class_id] = maxi(int(level_by_class.get(class_id, 1)), stored_level)

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


## 运行游戏后自动加载上次选择的存档槽位
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


## 加载指定存档槽位；不存在时保持为空白存档
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


## 保存玩家存档资源和角色仓库到当前存档槽位
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


## 切换当前使用的存档槽位
func switch_save_slot(save_id: String) -> void:
	"""切换当前使用的存档槽位"""
	save_game()
	load_save(save_id)


## 在指定槽位创建新的默认存档
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


## 获取当前版本可用的存档槽位
func get_save_slot_ids() -> Array[String]:
	"""获取当前版本可用的存档槽位"""
	return SAVE_SLOT_IDS.duplicate()


## 判断指定存档槽位是否已有存档文件
func has_save_slot(save_id: String) -> bool:
	"""判断指定存档槽位是否已有存档文件"""
	return FileAccess.file_exists(_get_save_file_absolute_path(save_id))


## 判断三个存档槽位中是否存在任意存档
func has_any_save_slot() -> bool:
	"""判断三个存档槽位中是否存在任意存档"""
	for save_id in SAVE_SLOT_IDS:
		if has_save_slot(save_id):
			return true
	return false


## 获取继续游戏应使用的存档槽位
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


## 读取存档槽位摘要，用于主菜单选择界面
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
	summary["gold"] = max(0, int(resources.get("gold", _default_gold())))
	var characters: Array = parsed.get("owned_characters", [])
	summary["character_count"] = characters.size()
	return summary


## 把存档数据应用到全局玩家数据
func _apply_save_data(data: Dictionary) -> void:
	"""把存档数据应用到全局玩家数据"""
	var resources: Dictionary = data.get("resources", {})
	gold = max(0, int(resources.get("gold", _default_gold())))

	owned_characters.clear()
	var stored_characters: Array = data.get("owned_characters", [])
	for card in stored_characters:
		if not (card is Dictionary):
			continue
		owned_characters.append({
			"class_id": ClassDefinitions.canonicalize_class_id(str(card.get("class_id", ""))),
			"level": clampi(int(card.get("level", 1)), 1, _max_character_level())
		})


## 构建当前版本的存档数据
func _build_save_data() -> Dictionary:
	"""构建当前版本的存档数据"""
	return {
		"version": SAVE_VERSION,
		"resources": {
			"gold": gold
		},
		"owned_characters": owned_characters
	}


## 重置为新存档的默认玩家数据
func _reset_default_save_data() -> void:
	"""重置为新存档的默认玩家数据"""
	gold = _default_gold()
	owned_characters.clear()
	_ensure_save_data()


## 确保存档目录存在
func _ensure_save_directory() -> void:
	"""确保存档目录存在"""
	var dir_path := _get_save_dir_absolute_path()
	if DirAccess.dir_exists_absolute(dir_path):
		return
	var error := DirAccess.make_dir_recursive_absolute(dir_path)
	if error != OK:
		Log.w(M, "创建存档目录失败: %s error=%d" % [dir_path, error])


## 获取项目根目录下 userdata 的绝对路径
func _get_save_dir_absolute_path() -> String:
	"""获取项目根目录下 userdata 的绝对路径"""
	return ProjectSettings.globalize_path(SAVE_DIR_PATH)


## 获取指定存档槽位文件的绝对路径
func _get_save_file_absolute_path(save_id: String = "") -> String:
	"""获取指定存档槽位文件的绝对路径"""
	var normalized := _normalize_save_id(save_id if save_id != "" else current_save_id)
	return ProjectSettings.globalize_path("%s/%s" % [SAVE_DIR_PATH, normalized])


## 获取上次使用存档记录文件的绝对路径
func _get_last_save_file_absolute_path() -> String:
	"""获取上次使用存档记录文件的绝对路径"""
	return ProjectSettings.globalize_path(LAST_SAVE_FILE_PATH)


## 读取上次使用的存档槽位
func _read_last_save_id() -> String:
	"""读取上次使用的存档槽位"""
	var path := _get_last_save_file_absolute_path()
	if not FileAccess.file_exists(path):
		return "save1"

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return "save1"

	return _normalize_save_id(file.get_as_text().strip_edges())


## 记录上次使用的存档槽位
func _write_last_save_id(save_id: String) -> void:
	"""记录上次使用的存档槽位"""
	_ensure_save_directory()
	var file := FileAccess.open(_get_last_save_file_absolute_path(), FileAccess.WRITE)
	if file:
		file.store_string(_normalize_save_id(save_id))


## 规范化存档槽位ID
func _normalize_save_id(save_id: String) -> String:
	"""规范化存档槽位ID"""
	return save_id if save_id in SAVE_SLOT_IDS else "save1"


## 获取存档中的角色养成等级
func get_owned_character_level(class_id: String) -> int:
	"""获取存档中的角色养成等级"""
	_ensure_save_data()
	var canonical_id := ClassDefinitions.canonicalize_class_id(class_id)
	for card in owned_characters:
		if ClassDefinitions.canonicalize_class_id(str(card.get("class_id", ""))) == canonical_id:
			return int(card.get("level", 1))
	return 1


## 获取局内招募星级对应的战斗等级上限
func get_star_level_cap(star_level: int) -> int:
	"""获取局内招募星级对应的战斗等级上限"""
	var caps := _cfg_dict("star_level_caps")
	var star := clampi(star_level, 1, ROGUELIKE_MAX_CARD_STAR)
	if caps.has(str(star)):
		return int(caps[str(star)])
	match star:
		1:
			return 30
		2:
			return 70
		_:
			return _max_character_level()


## 根据养成等级和星级上限计算本次战斗实际等级
func get_effective_level_for_star(class_id: String, star_level: int) -> int:
	"""根据养成等级和星级上限计算本次战斗实际等级"""
	var canonical_id := ClassDefinitions.canonicalize_class_id(class_id)
	return min(get_owned_character_level(canonical_id), get_star_level_cap(star_level))


## 生成用于部署和战斗的队伍数据
func get_battle_party_data() -> Array:
	"""生成用于部署和战斗的队伍数据"""
	var result: Array = []
	for member in party:
		var class_id := ClassDefinitions.canonicalize_class_id(str(member.get("class_id", "fighter_champion")))
		var star_level: int = int(member.get("star_level", member.get("level", 1)))
		var data: Dictionary = member.duplicate(true)
		data["class_id"] = class_id
		data["star_level"] = star_level
		data["level"] = get_effective_level_for_star(class_id, star_level)
		result.append(data)
	return result


## 计算从当前等级升到目标等级所需金币
func calculate_upgrade_cost(current_level: int, target_level: int) -> int:
	"""计算从当前等级升到目标等级所需金币"""
	var from_level := clampi(current_level, 1, _max_character_level())
	var to_level := clampi(target_level, 1, _max_character_level())
	if to_level <= from_level:
		return 0

	var total := 0
	for level in range(from_level, to_level):
		total += _cfg_int("upgrade_base_cost", UPGRADE_BASE_COST) + level * _cfg_int("upgrade_cost_step", UPGRADE_COST_STEP)
	return total


## 将指定存档持有角色升级到目标等级
func upgrade_owned_character(index: int, target_level: int) -> bool:
	"""将指定存档持有角色升级到目标等级"""
	_ensure_save_data()
	if index < 0 or index >= owned_characters.size():
		return false

	var card: Dictionary = owned_characters[index]
	var current_level: int = int(card.get("level", 1))
	var next_level := clampi(target_level, current_level, _max_character_level())
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


func get_max_character_level() -> int:
	return _max_character_level()


func get_roguelike_max_hand_cards() -> int:
	return _cfg_int("roguelike_max_hand_cards", ROGUELIKE_MAX_HAND_CARDS) + get_roguelike_relic_modifier("hand_limit_bonus")


func _max_character_level() -> int:
	return _cfg_int("max_character_level", MAX_CHARACTER_LEVEL)


func _default_gold() -> int:
	return _cfg_int("default_gold", 100)


func _cfg_int(key: String, default_value: int) -> int:
	var registry := _registry()
	if registry and registry.has_method("get_config"):
		return int(registry.get_config(key, default_value))
	return default_value


func _cfg_dict(key: String) -> Dictionary:
	var registry := _registry()
	if registry and registry.has_method("get_config_section"):
		return registry.get_config_section(key)
	return {}


func _registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("DataRegistry")
