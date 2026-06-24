# synergy_manager.gd — 羁绊计数、层数与数值应用
extends Node

const M = "Synergy"
const LAYER_PER_STAR := 20
const MAX_LAYER := 999
# const SynergyDefinitionScript = preload("res://scripts/synergy/synergy_definition.gd")

signal synergy_changed(summaries: Array)
signal resource_bonus_ready(bonus_payload: Dictionary)

var _definitions: Dictionary = {}
var _definition_order: Array[String] = []
var _summaries: Array[Dictionary] = []
var _active_modifiers: Dictionary = {}
var _active_fixed_modifiers: Dictionary = {}


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	_build_definitions()
	if not BattleManager.battle_started.is_connected(_on_battle_state_changed):
		BattleManager.battle_started.connect(_on_battle_state_changed)
	if not BattleManager.unit_deployed.is_connected(_on_unit_roster_changed):
		BattleManager.unit_deployed.connect(_on_unit_roster_changed)
	if not BattleManager.unit_retreated.is_connected(_on_unit_roster_changed):
		BattleManager.unit_retreated.connect(_on_unit_roster_changed)
	if not BattleManager.unit_died.is_connected(_on_unit_roster_changed):
		BattleManager.unit_died.connect(_on_unit_roster_changed)
	recalculate()


## 处理recalculate逻辑。
func recalculate() -> void:
	var count_by_id: Dictionary = {}
	var layer_by_id: Dictionary = {}
	var member_names_by_id: Dictionary = {}

	for unit in BattleManager.player_units:
		if not is_instance_valid(unit):
			continue
		if not (unit is HeroUnit):
			continue
		var hero := unit as HeroUnit
		if not hero.is_alive or not hero.class_template:
			continue

		var ids := _get_unit_synergy_ids(hero)
		var star_layers := clampi(int(hero.star_level), 1, 3) * LAYER_PER_STAR
		for synergy_id in ids:
			count_by_id[synergy_id] = int(count_by_id.get(synergy_id, 0)) + 1
			layer_by_id[synergy_id] = int(layer_by_id.get(synergy_id, 0)) + star_layers
			if not member_names_by_id.has(synergy_id):
				member_names_by_id[synergy_id] = []
			member_names_by_id[synergy_id].append(hero.unit_name)

	_active_modifiers = _default_modifiers()
	_active_fixed_modifiers = {}
	_summaries.clear()

	for synergy_id in _definition_order:
		var definition := _definitions[synergy_id] as SynergyDefinition
		var count := int(count_by_id.get(synergy_id, 0))
		if count <= 0:
			continue

		var active_tier := definition.get_active_tier(count)
		var layer := clampi(int(layer_by_id.get(synergy_id, 0)), 0, MAX_LAYER)
		var summary := _build_summary(definition, count, active_tier, layer, member_names_by_id.get(synergy_id, []))
		_summaries.append(summary)

		if active_tier > 0:
			_apply_definition_modifiers(definition, active_tier, layer)

	_summaries.sort_custom(_sort_summaries)
	_apply_modifiers_to_units()
	_apply_resource_modifiers()
	synergy_changed.emit(get_synergy_summary())


## 获取羁绊摘要。
func get_synergy_summary() -> Array:
	return _summaries.duplicate(true)


## 获取激活修正。
func get_active_modifiers() -> Dictionary:
	return _active_modifiers.duplicate(true)


## 获取固定修正。
func get_fixed_modifiers() -> Dictionary:
	return _active_fixed_modifiers.duplicate(true)


## 获取discounteddeploy消耗。
func get_discounted_deploy_cost(base_cost: int) -> int:
	var discount := clampf(float(_active_fixed_modifiers.get("deploy_cost_discount", 0.0)), 0.0, 0.75)
	return maxi(1, int(ceil(float(base_cost) * (1.0 - discount))))


## 应用victory金币bonus。
func apply_victory_gold_bonus(base_reward: int) -> int:
	var multiplier := float(_active_fixed_modifiers.get("victory_gold_multiplier", 1.0))
	return maxi(0, int(round(float(base_reward) * multiplier)))


## 处理战斗状态变化回调。
func _on_battle_state_changed() -> void:
	recalculate()


## 处理单位roster变化回调。
func _on_unit_roster_changed(_unit: Node) -> void:
	recalculate()


## 获取单位羁绊ids。
func _get_unit_synergy_ids(hero: HeroUnit) -> Array[String]:
	var ids: Array[String] = []
	var ct := hero.class_template
	var class_group := str(ct.class_group)
	if class_group != "":
		ids.append("main_%s" % class_group)
	for tag in ct.stat_tags:
		ids.append("stat_%s" % str(tag).to_lower())
	for tag in ct.alignment_tags:
		ids.append("alignment_%s" % str(tag).to_lower())
	return ids


## 构建摘要。
func _build_summary(definition: SynergyDefinition, count: int, active_tier: int, layer: int, members: Array) -> Dictionary:
	return {
		"id": definition.synergy_id,
		"display_name": definition.display_name,
		"short_name": definition.short_name,
		"type": definition.type,
		"type_name": _type_name(definition.type),
		"tag": definition.tag,
		"count": count,
		"active_tier": active_tier,
		"thresholds": definition.thresholds.duplicate(),
		"activation_count": definition.thresholds[0] if not definition.thresholds.is_empty() else 0,
		"next_threshold": definition.get_next_threshold(count),
		"max_threshold": definition.get_max_threshold(),
		"layer": layer,
		"is_active": active_tier > 0,
		"description": definition.description,
		"scalable_modifiers": definition.scalable_modifiers.duplicate(true),
		"fixed_modifiers": definition.fixed_modifiers.duplicate(true),
		"members": members.duplicate(),
		"order": definition.order,
	}


## 处理typename逻辑。
func _type_name(type: SynergyDefinition.SynergyType) -> String:
	match type:
		SynergyDefinition.SynergyType.MAIN_NATION:
			return "国家主羁绊"
		SynergyDefinition.SynergyType.MINOR_STAT:
			return "六维小羁绊"
		SynergyDefinition.SynergyType.MINOR_ALIGNMENT:
			return "阵营小羁绊"
	return "羁绊"


## 处理sort摘要逻辑。
func _sort_summaries(a: Dictionary, b: Dictionary) -> bool:
	var a_active := bool(a.get("is_active", false))
	var b_active := bool(b.get("is_active", false))
	if a_active != b_active:
		return a_active
	if int(a.get("layer", 0)) != int(b.get("layer", 0)):
		return int(a.get("layer", 0)) > int(b.get("layer", 0))
	var a_main := int(a.get("type", 0)) == SynergyDefinition.SynergyType.MAIN_NATION
	var b_main := int(b.get("type", 0)) == SynergyDefinition.SynergyType.MAIN_NATION
	if a_main != b_main:
		return a_main
	return int(a.get("order", 0)) < int(b.get("order", 0))


## 处理默认修正逻辑。
func _default_modifiers() -> Dictionary:
	return {
		"max_hp_multiplier": 1.0,
		"attack_multiplier": 1.0,
		"defense_multiplier": 1.0,
		"attack_speed_multiplier": 1.0,
		"move_speed_multiplier": 1.0,
		"damage_multiplier": 1.0,
		"skill_damage_multiplier": 1.0,
		"heal_multiplier": 1.0,
		"incoming_heal_multiplier": 1.0,
		"armor_pierce": 0.0,
		"crit_chance": 0.0,
		"crit_damage_multiplier": 1.0,
		"skill_cooldown_reduction": 0.0,
		"life_steal_percent": 0.0,
		"search_range_bonus": 0.0,
	}


## 应用definition修正。
func _apply_definition_modifiers(definition: SynergyDefinition, active_tier: int, layer: int) -> void:
	for modifier in definition.scalable_modifiers:
		if active_tier < int(modifier.get("min_tier", 0)):
			continue
		var stat := str(modifier.get("stat", ""))
		var base := float(modifier.get("base", 0.0))
		var per_layer := float(modifier.get("per_layer", 0.0))
		var max_value := float(modifier.get("max_value", base))
		var value: float = minf(base + float(layer) * per_layer, max_value)
		_merge_modifier_value(_active_modifiers, stat, value)

	for modifier in definition.fixed_modifiers:
		if active_tier < int(modifier.get("min_tier", 0)):
			continue
		var stat := str(modifier.get("stat", ""))
		var value := float(modifier.get("value", 0.0))
		_merge_fixed_value(stat, value)


## 处理merge修正值逻辑。
func _merge_modifier_value(target: Dictionary, stat: String, value: float) -> void:
	if stat == "":
		return
	var multiply_stats := [
		"max_hp_multiplier",
		"attack_multiplier",
		"defense_multiplier",
		"attack_speed_multiplier",
		"move_speed_multiplier",
		"damage_multiplier",
		"skill_damage_multiplier",
		"heal_multiplier",
		"incoming_heal_multiplier",
		"crit_damage_multiplier",
	]
	if stat in multiply_stats:
		target[stat] = float(target.get(stat, 1.0)) * value
	else:
		target[stat] = float(target.get(stat, 0.0)) + value


## 处理merge固定值逻辑。
func _merge_fixed_value(stat: String, value: float) -> void:
	if stat == "":
		return
	match stat:
		"victory_gold_multiplier":
			_active_fixed_modifiers[stat] = float(_active_fixed_modifiers.get(stat, 1.0)) * value
		_:
			_active_fixed_modifiers[stat] = float(_active_fixed_modifiers.get(stat, 0.0)) + value


## 应用修正单位。
func _apply_modifiers_to_units() -> void:
	for unit in BattleManager.player_units:
		if is_instance_valid(unit) and unit is UnitBase:
			(unit as UnitBase).apply_synergy_modifiers(_active_modifiers)


## 应用资源修正。
func _apply_resource_modifiers() -> void:
	if ResourceManager.has_method("apply_synergy_modifiers"):
		ResourceManager.apply_synergy_modifiers(_active_fixed_modifiers)
	resource_bonus_ready.emit(_active_fixed_modifiers.duplicate(true))


## 构建definitions。
func _build_definitions() -> void:
	_definitions.clear()
	_definition_order.clear()
	var order := 0

	_add(SynergyDefinition.new("main_nation_a", "国A", "A", SynergyDefinition.SynergyType.MAIN_NATION, "nation_a", [3, 6], order, "国家主羁绊：国A信条。MVP阶段先显示计数与层数，后续接入神职、誓言与守护型国家机制。", [], [], "nation_a_creed")); order += 1
	_add(SynergyDefinition.new("main_nation_b", "国B", "B", SynergyDefinition.SynergyType.MAIN_NATION, "nation_b", [3, 6], order, "国家主羁绊：国B信条。MVP阶段先显示计数与层数，后续接入奥术、工造与结界型国家机制。", [], [], "nation_b_creed")); order += 1
	_add(SynergyDefinition.new("main_nation_c", "国C", "C", SynergyDefinition.SynergyType.MAIN_NATION, "nation_c", [3, 6], order, "国家主羁绊：国C信条。MVP阶段先显示计数与层数，后续接入自然、巡猎与领域型国家机制。", [], [], "nation_c_creed")); order += 1
	_add(SynergyDefinition.new("main_nation_d", "国D", "D", SynergyDefinition.SynergyType.MAIN_NATION, "nation_d", [3, 6], order, "国家主羁绊：国D信条。MVP阶段先显示计数与层数，后续接入潜行、武技与机动型国家机制。", [], [], "nation_d_creed")); order += 1
	_add(SynergyDefinition.new("main_nation_e", "国E", "E", SynergyDefinition.SynergyType.MAIN_NATION, "nation_e", [3, 6], order, "国家主羁绊：国E信条。MVP阶段先显示计数与层数，后续接入军势、狂战与阵线型国家机制。", [], [], "nation_e_creed")); order += 1
	_add(SynergyDefinition.new("main_nation_f", "国F", "F", SynergyDefinition.SynergyType.MAIN_NATION, "nation_f", [3, 6], order, "国家主羁绊：国F信条。MVP阶段先显示计数与层数，后续接入乐歌、血脉与契约型国家机制。", [], [], "nation_f_creed")); order += 1
	_add(SynergyDefinition.new("stat_str", "力量", "力", SynergyDefinition.SynergyType.MINOR_STAT, "STR", [2, 3], order, "小羁绊：提升物理攻击倍率，3人后获得破甲。", [
		{"min_tier": 2, "stat": "attack_multiplier", "base": 1.15, "per_layer": 0.0038, "max_value": 5.0},
		{"min_tier": 3, "stat": "armor_pierce", "base": 0.10, "per_layer": 0.00025, "max_value": 0.35},
	])); order += 1
	_add(SynergyDefinition.new("stat_dex", "敏捷", "敏", SynergyDefinition.SynergyType.MINOR_STAT, "DEX", [2, 3], order, "小羁绊：提升攻速倍率，3人后获得暴击。", [
		{"min_tier": 2, "stat": "attack_speed_multiplier", "base": 1.12, "per_layer": 0.0032, "max_value": 4.3},
		{"min_tier": 3, "stat": "crit_chance", "base": 0.08, "per_layer": 0.0002, "max_value": 0.30},
	])); order += 1
	_add(SynergyDefinition.new("stat_con", "体质", "体", SynergyDefinition.SynergyType.MINOR_STAT, "CON", [2, 3], order, "小羁绊：提升最大生命倍率，3人后提升防御倍率。", [
		{"min_tier": 2, "stat": "max_hp_multiplier", "base": 1.20, "per_layer": 0.0038, "max_value": 5.0},
		{"min_tier": 3, "stat": "defense_multiplier", "base": 1.10, "per_layer": 0.0025, "max_value": 3.5},
		{"min_tier": 3, "stat": "incoming_heal_multiplier", "base": 1.10, "per_layer": 0.0015, "max_value": 2.5},
	])); order += 1
	_add(SynergyDefinition.new("stat_int", "智力", "智", SynergyDefinition.SynergyType.MINOR_STAT, "INT", [2, 3], order, "小羁绊：提升技能伤害倍率，3人后获得技能冷却缩减。", [
		{"min_tier": 2, "stat": "skill_damage_multiplier", "base": 1.20, "per_layer": 0.004, "max_value": 5.2},
		{"min_tier": 3, "stat": "skill_cooldown_reduction", "base": 0.08, "per_layer": 0.00025, "max_value": 0.35},
	])); order += 1
	_add(SynergyDefinition.new("stat_wis", "感知", "感", SynergyDefinition.SynergyType.MINOR_STAT, "WIS", [2, 3], order, "小羁绊：提升治疗/护盾倍率，3人后提升异常抗性与索敌数值。", [
		{"min_tier": 2, "stat": "heal_multiplier", "base": 1.15, "per_layer": 0.0035, "max_value": 4.6},
		{"min_tier": 3, "stat": "search_range_bonus", "base": 1.0, "per_layer": 0.0, "max_value": 1.0},
	])); order += 1
	_add(SynergyDefinition.new("stat_cha", "魅力", "魅", SynergyDefinition.SynergyType.MINOR_STAT, "CHA", [2, 3], order, "小羁绊：提升团队泛用输出与治疗，3人后提供固定资源优势。", [
		{"min_tier": 2, "stat": "damage_multiplier", "base": 1.10, "per_layer": 0.003, "max_value": 4.0},
		{"min_tier": 2, "stat": "heal_multiplier", "base": 1.10, "per_layer": 0.002, "max_value": 3.0},
	], [
		{"min_tier": 3, "stat": "max_dp_bonus", "value": 5.0},
	])); order += 1

	_add(SynergyDefinition.new("alignment_lawful", "守序", "序", SynergyDefinition.SynergyType.MINOR_ALIGNMENT, "LAWFUL", [2, 3], order, "小羁绊：提升有效防御倍率，3人后降低部署费用。", [
		{"min_tier": 2, "stat": "defense_multiplier", "base": 1.12, "per_layer": 0.003, "max_value": 4.0},
	], [
		{"min_tier": 3, "stat": "deploy_cost_discount", "value": 0.05},
	])); order += 1
	_add(SynergyDefinition.new("alignment_chaotic", "混沌", "混", SynergyDefinition.SynergyType.MINOR_ALIGNMENT, "CHAOTIC", [2, 3], order, "小羁绊：提升暴击伤害，3人后获得暴击率。", [
		{"min_tier": 2, "stat": "crit_damage_multiplier", "base": 1.15, "per_layer": 0.0035, "max_value": 4.5},
		{"min_tier": 3, "stat": "crit_chance", "base": 0.06, "per_layer": 0.00015, "max_value": 0.20},
	])); order += 1
	_add(SynergyDefinition.new("alignment_good", "善良", "善", SynergyDefinition.SynergyType.MINOR_ALIGNMENT, "GOOD", [2, 3], order, "小羁绊：提升治疗与承疗数值。", [
		{"min_tier": 2, "stat": "heal_multiplier", "base": 1.10, "per_layer": 0.0032, "max_value": 4.2},
		{"min_tier": 3, "stat": "incoming_heal_multiplier", "base": 1.10, "per_layer": 0.0025, "max_value": 3.5},
	])); order += 1
	_add(SynergyDefinition.new("alignment_evil", "邪恶", "邪", SynergyDefinition.SynergyType.MINOR_ALIGNMENT, "EVIL", [2, 3], order, "小羁绊：提供攻击吸血，3人后提高胜利金币收益。", [
		{"min_tier": 2, "stat": "life_steal_percent", "base": 0.03, "per_layer": 0.00017, "max_value": 0.20},
	], [
		{"min_tier": 3, "stat": "victory_gold_multiplier", "value": 1.05},
	])); order += 1
	_add(SynergyDefinition.new("alignment_neutral", "中立", "中", SynergyDefinition.SynergyType.MINOR_ALIGNMENT, "NEUTRAL", [2, 3], order, "小羁绊：提升全队泛用属性，3人后获得资源上限和胜利金币。", [
		{"min_tier": 2, "stat": "damage_multiplier", "base": 1.05, "per_layer": 0.0025, "max_value": 3.5},
		{"min_tier": 2, "stat": "max_hp_multiplier", "base": 1.05, "per_layer": 0.0015, "max_value": 2.5},
	], [
		{"min_tier": 3, "stat": "max_dp_bonus", "value": 10.0},
		{"min_tier": 3, "stat": "victory_gold_multiplier", "value": 1.05},
	])); order += 1


## 处理添加逻辑。
func _add(definition: SynergyDefinition) -> void:
	_definitions[definition.synergy_id] = definition
	_definition_order.append(definition.synergy_id)
