# auto_trait_text_formatter.gd — 将设计文档式占位描述解析为界面文本。
class_name AutoTraitTextFormatter
extends RefCounted

const SYNERGY_COLOR := "#f0bd55"
const NUMBER_COLOR := "#72d7ff"
const MAX_NESTING_DEPTH := 4
const SYNERGY_PLACEHOLDER := "【某羁绊】"


static func format_trait_description(
	trait_id: String,
	class_id: String = "",
	star_level: int = 1,
	use_bbcode: bool = true,
	context_synergy_ids: Array = [],
	nesting_depth: int = 0
) -> String:
	var trait_data: Dictionary = DataRegistry.get_auto_trait(trait_id)
	if trait_data.is_empty():
		return trait_id
	var template_id := str(trait_data.get("template_id", trait_id))
	var hero_data := ClassDefinitions.get_autochess_data(class_id) if class_id != "" else {}
	var params: Dictionary = trait_data.get("params", {}).duplicate(true)
	var trait_overrides = hero_data.get("trait_params", {}).get(trait_id, {}) \
		if hero_data.get("trait_params", {}) is Dictionary else {}
	if trait_overrides is Dictionary:
		params.merge(trait_overrides, true)
	var tier := clampi(int(hero_data.get("trait_tier", 1)), 1, 6)
	var synergies := _resolve_synergy_ids(template_id, params, hero_data, context_synergy_ids)
	var description := str(trait_data.get("description", "暂无描述"))

	description = _replace_numeric_placeholders(description, trait_id, template_id, tier, star_level, params, synergies, use_bbcode)
	description = _replace_synergy_placeholders(description, synergies, use_bbcode)
	description = description.replace("【某状态】", _status_name(str(params.get("status_id", ""))))
	description = description.replace("【某装备】", _equipment_name(str(params.get("equipment_id", ""))))
	description = description.replace("【某属性】", _stat_name(str(params.get("stat", _default_stat(template_id)))))
	description = description.replace("【某类型】", _enemy_condition_name(params))

	if "【某特质】" in description:
		var granted_trait_id := str(params.get("granted_trait_id", "E_FIRST_SKILL"))
		var nested_description := granted_trait_id
		if nesting_depth < MAX_NESTING_DEPTH:
			nested_description = format_trait_description(
				granted_trait_id,
				class_id,
				star_level,
				use_bbcode,
				synergies,
				nesting_depth + 1
			)
		description = description.replace("【某特质】", "特质“%s”" % nested_description)
	return description


static func format_trait_list(
	trait_ids: Array,
	class_id: String,
	star_level: int,
	use_bbcode: bool = true,
	context_synergy_ids: Array = []
) -> String:
	var descriptions: Array[String] = []
	for raw_trait_id in trait_ids:
		descriptions.append(format_trait_description(
			str(raw_trait_id), class_id, star_level, use_bbcode, context_synergy_ids
		))
	return "\n\n".join(descriptions) if not descriptions.is_empty() else "无特质"


static func _resolve_synergy_ids(template_id: String, params: Dictionary, hero_data: Dictionary, context_synergy_ids: Array) -> Array[String]:
	var result: Array[String] = []
	var configured = params.get("synergy_ids", [])
	if configured is Array:
		for value in configured:
			_append_stackable_synergy(result, str(value))
	var single := str(params.get("synergy_id", ""))
	if single != "":
		_append_stackable_synergy(result, single)
	if result.is_empty():
		var source = context_synergy_ids if not context_synergy_ids.is_empty() else hero_data.get("autochess_synergy_ids", [])
		for value in source:
			_append_stackable_synergy(result, str(value))
	if template_id == "CB_MAIN_LAYER_STAT":
		var main_result: Array[String] = []
		for synergy_id in result:
			if synergy_id.begins_with("main_"):
				main_result.append(synergy_id)
		result = main_result
	return result


static func _append_stackable_synergy(result: Array[String], synergy_id: String) -> void:
	if synergy_id == "" or synergy_id in result:
		return
	if DataRegistry.get_synergy(synergy_id).is_empty():
		return
	if not DataRegistry.is_synergy_stackable(synergy_id):
		return
	result.append(synergy_id)


static func _replace_synergy_placeholders(description: String, synergy_ids: Array[String], use_bbcode: bool) -> String:
	var placeholder_count := description.count(SYNERGY_PLACEHOLDER)
	if placeholder_count <= 0:
		return description
	var replacements: Array[String] = []
	if synergy_ids.is_empty():
		replacements.append(_format_synergy_name("任意羁绊", use_bbcode))
	else:
		for synergy_id in synergy_ids:
			var synergy_data := DataRegistry.get_synergy(synergy_id)
			var name := str(synergy_data.get("display_name", synergy_data.get("name", synergy_id)))
			replacements.append(_format_synergy_name(name, use_bbcode))
	if placeholder_count == 1:
		return description.replace(SYNERGY_PLACEHOLDER, "、".join(replacements))
	var result := description
	for index in range(placeholder_count):
		var replacement := replacements[mini(index, replacements.size() - 1)]
		var placeholder_position := result.find(SYNERGY_PLACEHOLDER)
		if placeholder_position < 0:
			break
		result = result.substr(0, placeholder_position) + replacement \
			+ result.substr(placeholder_position + SYNERGY_PLACEHOLDER.length())
	return result


static func _format_synergy_name(name: String, use_bbcode: bool) -> String:
	var visible_name := "【%s】" % name
	return "[color=%s]%s[/color]" % [SYNERGY_COLOR, visible_name] if use_bbcode else visible_name


static func _replace_numeric_placeholders(
	description: String,
	trait_id: String,
	template_id: String,
	tier: int,
	star_level: int,
	params: Dictionary,
	synergy_ids: Array[String],
	use_bbcode: bool
) -> String:
	var pattern := RegEx.new()
	pattern.compile("\\[\\+?X\\]")
	var matches := pattern.search_all(description)
	if matches.is_empty():
		return description
	var result := ""
	var cursor := 0
	var numeric_index := 0
	for regex_match in matches:
		var start := regex_match.get_start()
		var end := regex_match.get_end()
		var token := regex_match.get_string()
		result += description.substr(cursor, start - cursor)
		var value := _numeric_value(trait_id, template_id, tier, star_level, params, synergy_ids.size(), numeric_index)
		if token == "[+X]":
			value = "+" + value
		result += _format_number(value, use_bbcode)
		cursor = end
		numeric_index += 1
	result += description.substr(cursor)
	return result


static func _numeric_value(
	trait_id: String,
	template_id: String,
	tier: int,
	star_level: int,
	params: Dictionary,
	target_count: int,
	occurrence_index: int
) -> String:
	var configured_values := _description_values(params, star_level)
	if occurrence_index < configured_values.size():
		return _number_text(configured_values[occurrence_index])
	var fallback_values := _fallback_numeric_values(
		trait_id, template_id, tier, star_level, params, target_count
	)
	if occurrence_index < fallback_values.size():
		return _number_text(fallback_values[occurrence_index])
	return "X"


static func _number_text(value: Variant) -> String:
	if value is float and is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(value)


static func _description_values(params: Dictionary, star_level: int) -> Array:
	var configured = params.get("description_values", {})
	if not configured is Dictionary:
		return []
	var tier_key := "advanced" if star_level >= 2 else "base"
	var values = configured.get(tier_key, [])
	return values if values is Array else []


static func _fallback_numeric_values(
	trait_id: String,
	template_id: String,
	tier: int,
	star_level: int,
	params: Dictionary,
	target_count: int
) -> Array:
	var factor := 2 if star_level >= 2 else 1
	match template_id:
		"CB_ENEMY_TYPE":
			return [(20 + 5 * tier) * factor]
		"CB_MAIN_LAYER_STAT", "CB_SYNERGY_LAYER_STAT", "CB_DUAL_LAYER_DEF":
			return [3, int(ceil(float(tier) / 2.0)) * factor]
		"CB_FAST_MERGE":
			return [2]
		"CB_FRONT_LAYER_RELAY":
			return [_preparation_value(tier, star_level)]
		"P_PRICE_ONE":
			return [1]
		"P_GAIN_REFRESH", "P_GAIN_NEXT_GOLD", "P_GAIN_EQUIPMENT", \
		"P_SELL_REFRESH", "P_SELL_NEXT_GOLD", "P_REST_NEXT_GOLD":
			return [1 if trait_id == "P_GAIN_SHAPESHIFT" else _preparation_value(tier, star_level)]
		"P_SELL_SPECIAL_RECRUIT":
			return [int(params.get("advanced_tier", 5)) if star_level >= 2 else int(params.get("base_tier", 1))]
		"P_ROW_RECRUIT":
			return [1 if star_level >= 2 else 3, 1]
		"B_OWNER_ALL":
			return [_distributed_burst_values(tier, star_level, target_count)[0]]
		"B_TAVERN_NAMED":
			return [_preparation_value(tier, star_level)]
		"B_LINKED_SPLIT":
			return _distributed_burst_values(tier, star_level, target_count)
		"E_REST_ENTER_OWNER", "E_REST_ENTER_FRONT", "E_REST_END_FRONT", \
		"E_REST_END_NAMED", "E_REST_HIGHEST_BENCH", "E_REST_END_BACK", \
		"E_EVERY_SKILL", "E_DEPLOY", "E_SELF_DEFEATED", \
		"E_FIRST_REFRESH_BENCH", "E_FIRST_DEFEAT", "E_FIRST_SKILL":
			return [_engine_value(tier, star_level)]
		"E_REST_COUNT_GAIN", "E_REST_COUNT_REFRESH", "E_REST_COUNT_ROW", \
		"E_REST_COUNT_BENCH", "E_REST_COUNT_DISTINCT_TIER", \
		"E_REST_HIGHEST_DISTINCT_TIER":
			return [1, _engine_value(tier, star_level)]
		"E_REST_COUNT_SPEND":
			return [3, _engine_value(tier, star_level)]
		"E_DEFEAT_EVERY_3", "E_FIRST_3_DEFEATS":
			return [3, _engine_value(tier, star_level)]
		"E_STATUS_IN_RANGE":
			return [1, _engine_value(tier, star_level)]
	return []


static func _distributed_burst_values(tier: int, star_level: int, target_count: int) -> Array:
	var safe_count := maxi(target_count, 1)
	var total := _burst_value(tier, star_level)
	var values: Array = []
	for index in range(safe_count):
		values.append(int(total / safe_count) + (1 if index < total % safe_count else 0))
	return values


static func _format_number(value: String, use_bbcode: bool) -> String:
	return "[color=%s]%s[/color]" % [NUMBER_COLOR, value] if use_bbcode else value


static func _preparation_value(tier: int, star_level: int) -> int:
	return int(ceil(float(clampi(tier, 1, 6)) / 3.0)) * (2 if star_level >= 2 else 1)


static func _burst_value(tier: int, star_level: int) -> int:
	return 4 * clampi(tier, 1, 6) * (2 if star_level >= 2 else 1)


static func _engine_value(tier: int, star_level: int) -> int:
	return clampi(tier, 1, 6) * (2 if star_level >= 2 else 1)


static func _status_name(status_id: String) -> String:
	if status_id == "":
		return "任意状态"
	var status := DataRegistry.get_status_effect(status_id)
	return str(status.get("name", status_id))


static func _equipment_name(equipment_id: String) -> String:
	if equipment_id == "":
		return "指定装备"
	var equipment := DataRegistry.get_autochess_equipment(equipment_id)
	return str(equipment.get("display_name", equipment_id))


static func _default_stat(template_id: String) -> String:
	return "defense" if template_id == "CB_DUAL_LAYER_DEF" else "attack"


static func _stat_name(stat: String) -> String:
	match stat:
		"attack": return "攻击力"
		"attack_speed": return "攻击速度"
		"defense": return "防御力"
		"skill_damage": return "技能伤害"
		"skill_cooldown", "cooldown": return "技能冷却"
		"heal", "healing": return "治疗量"
		"max_hp", "hp": return "最大生命值"
	return stat if stat != "" else "属性"


static func _enemy_condition_name(params: Dictionary) -> String:
	match str(params.get("condition", "any")):
		"burning": return "燃烧中的"
		"slowed": return "被减速的"
		"high_move_speed": return "高移动速度的"
		"low_hp": return "低生命值的"
		"high_defense": return "高防御的"
		"status": return "%s状态下的" % _status_name(str(params.get("status_id", "")))
		"enemy_type": return "指定类型的"
		"backline": return "后排"
	return "任意类型"
