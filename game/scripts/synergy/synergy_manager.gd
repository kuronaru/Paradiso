# synergy_manager.gd - Synergy counting, tiers and modifier application.
extends Node

const M = "Synergy"

signal synergy_changed(summaries: Array)
signal resource_bonus_ready(bonus_payload: Dictionary)

var _definitions: Dictionary = {}
var _definition_order: Array[String] = []
var _summaries: Array[Dictionary] = []
var _active_modifiers: Dictionary = {}
var _active_fixed_modifiers: Dictionary = {}
var _active_main_effects: Dictionary = {}


func _ready() -> void:
	_build_definitions()
	if not BattleManager.battle_started.is_connected(_on_battle_state_changed):
		BattleManager.battle_started.connect(_on_battle_state_changed)
	if not BattleManager.unit_deployed.is_connected(_on_unit_roster_changed):
		BattleManager.unit_deployed.connect(_on_unit_roster_changed)
	if not BattleManager.unit_retreated.is_connected(_on_unit_roster_changed):
		BattleManager.unit_retreated.connect(_on_unit_roster_changed)
	recalculate()


func recalculate() -> void:
	var count_by_id: Dictionary = {}
	var layer_by_id: Dictionary = {}
	var member_names_by_id: Dictionary = {}
	var layer_per_star := _cfg_int("synergy_layer_per_star", 20)
	var max_layer := _cfg_int("synergy_max_layer", 999)

	for unit in BattleManager.player_units:
		if not is_instance_valid(unit):
			continue
		if not (unit is HeroUnit):
			continue
		var hero := unit as HeroUnit
		if not hero.class_template:
			continue

		var ids := _get_unit_synergy_ids(hero)
		var star_layers := clampi(int(hero.star_level), 1, 3) * layer_per_star
		for synergy_id in ids:
			count_by_id[synergy_id] = int(count_by_id.get(synergy_id, 0)) + 1
			layer_by_id[synergy_id] = int(layer_by_id.get(synergy_id, 0)) + star_layers
			if not member_names_by_id.has(synergy_id):
				member_names_by_id[synergy_id] = []
			member_names_by_id[synergy_id].append(hero.unit_name)

	_active_modifiers = _default_modifiers()
	_active_fixed_modifiers = {}
	_active_main_effects = {}
	_summaries.clear()

	for synergy_id in _definition_order:
		var definition := _definitions[synergy_id] as SynergyDefinition
		var count := int(count_by_id.get(synergy_id, 0))
		if count <= 0:
			continue

		var active_tier := definition.get_active_tier(count)
		var layer := clampi(int(layer_by_id.get(synergy_id, 0)), 0, max_layer)
		var summary := _build_summary(definition, count, active_tier, layer, member_names_by_id.get(synergy_id, []))
		_summaries.append(summary)

		if active_tier > 0:
			_apply_definition_modifiers(definition, active_tier, layer)
			if definition.type == SynergyDefinition.SynergyType.MAIN_NATION:
				_active_main_effects[definition.tag] = _build_main_effect_payload(definition, active_tier, layer)

	_summaries.sort_custom(_sort_summaries)
	_apply_modifiers_to_units()
	_apply_resource_modifiers()
	synergy_changed.emit(get_synergy_summary())


func get_synergy_summary() -> Array:
	return _summaries.duplicate(true)


func get_active_modifiers() -> Dictionary:
	return _active_modifiers.duplicate(true)


func get_fixed_modifiers() -> Dictionary:
	return _active_fixed_modifiers.duplicate(true)


func get_active_main_effects() -> Dictionary:
	return _active_main_effects.duplicate(true)


func get_discounted_deploy_cost(base_cost: int) -> int:
	var discount := clampf(float(_active_fixed_modifiers.get("deploy_cost_discount", 0.0)), 0.0, 0.75)
	return maxi(1, int(ceil(float(base_cost) * (1.0 - discount))))


func apply_victory_gold_bonus(base_reward: int) -> int:
	var multiplier := float(_active_fixed_modifiers.get("victory_gold_multiplier", 1.0))
	return maxi(0, int(round(float(base_reward) * multiplier)))


func _on_battle_state_changed() -> void:
	recalculate()


func _on_unit_roster_changed(_unit: Node) -> void:
	recalculate()


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


func _type_name(type: SynergyDefinition.SynergyType) -> String:
	match type:
		SynergyDefinition.SynergyType.MAIN_NATION:
			return "国家主羁绊"
		SynergyDefinition.SynergyType.MINOR_STAT:
			return "六维小羁绊"
		SynergyDefinition.SynergyType.MINOR_ALIGNMENT:
			return "阵营小羁绊"
	return "羁绊"


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


func _default_modifiers() -> Dictionary:
	var configured := _cfg_dict("synergy_default_modifiers")
	if not configured.is_empty():
		return configured
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


func _merge_fixed_value(stat: String, value: float) -> void:
	if stat == "":
		return
	match stat:
		"victory_gold_multiplier":
			_active_fixed_modifiers[stat] = float(_active_fixed_modifiers.get(stat, 1.0)) * value
		_:
			_active_fixed_modifiers[stat] = float(_active_fixed_modifiers.get(stat, 0.0)) + value


func _build_main_effect_payload(definition: SynergyDefinition, active_tier: int, layer: int) -> Dictionary:
	var payload := {
		"tier": active_tier,
		"layer": layer,
	}
	for key in definition.main_effect.keys():
		payload[key] = _resolve_main_effect_value(definition.main_effect[key], active_tier, layer)
	return payload


func _resolve_main_effect_value(value, active_tier: int, layer: int):
	if value is Dictionary:
		var min_tier := int(value.get("min_tier", 0))
		var fallback = value.get("fallback", 0.0)
		if active_tier < min_tier:
			return fallback
		if value.has("base") or value.has("per_layer") or value.has("max_value"):
			var base := float(value.get("base", 0.0))
			var per_layer := float(value.get("per_layer", 0.0))
			var max_value := float(value.get("max_value", base))
			return _linear_cap(base, per_layer, max_value, layer)
		return value.get("value", fallback)
	return value


func _linear_cap(base: float, per_layer: float, max_value: float, layer: int) -> float:
	return minf(base + float(layer) * per_layer, max_value)


func _apply_modifiers_to_units() -> void:
	for unit in BattleManager.player_units:
		if is_instance_valid(unit) and unit is UnitBase:
			(unit as UnitBase).apply_synergy_modifiers(_active_modifiers)


func _apply_resource_modifiers() -> void:
	if ResourceManager.has_method("apply_synergy_modifiers"):
		ResourceManager.apply_synergy_modifiers(_active_fixed_modifiers)
	resource_bonus_ready.emit(_active_fixed_modifiers.duplicate(true))


func _build_definitions() -> void:
	_definitions.clear()
	_definition_order.clear()

	var registry := _registry()
	if registry and registry.has_method("get_all_synergy_ids") and registry.has_method("get_synergy"):
		for synergy_id in registry.get_all_synergy_ids():
			var data: Dictionary = registry.get_synergy(str(synergy_id))
			if data.is_empty():
				continue
			_add(_definition_from_data(data))

	_definition_order.sort_custom(func(a: String, b: String) -> bool:
		return (_definitions[a] as SynergyDefinition).order < (_definitions[b] as SynergyDefinition).order
	)

	if _definitions.is_empty():
		push_warning("SynergyManager loaded no definitions from DataRegistry")


func _definition_from_data(data: Dictionary) -> SynergyDefinition:
	var main_effect := {}
	if data.get("main_effect", {}) is Dictionary:
		main_effect = data.get("main_effect", {}).duplicate(true)
	return SynergyDefinition.new(
		str(data.get("synergy_id", "")),
		str(data.get("display_name", data.get("name", ""))),
		str(data.get("short_name", "")),
		_synergy_type(str(data.get("type", "main_nation"))),
		str(data.get("tag", "")),
		_int_array(data.get("thresholds", [])),
		int(data.get("order", 0)),
		str(data.get("description", "")),
		_dictionary_array(data.get("scalable_modifiers", [])),
		_dictionary_array(data.get("fixed_modifiers", [])),
		str(data.get("mechanic_id", "")),
		main_effect
	)


func _add(definition: SynergyDefinition) -> void:
	if definition.synergy_id == "":
		return
	_definitions[definition.synergy_id] = definition
	_definition_order.append(definition.synergy_id)


func _synergy_type(value: String) -> SynergyDefinition.SynergyType:
	match value:
		"minor_stat":
			return SynergyDefinition.SynergyType.MINOR_STAT
		"minor_alignment":
			return SynergyDefinition.SynergyType.MINOR_ALIGNMENT
		_:
			return SynergyDefinition.SynergyType.MAIN_NATION


func _int_array(value) -> Array[int]:
	var result: Array[int] = []
	if value is Array:
		for item in value:
			result.append(int(item))
	elif str(value).strip_edges() != "":
		for item in str(value).split(",", false):
			result.append(int(item.strip_edges()))
	return result


func _dictionary_array(value) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				result.append(item.duplicate(true))
	return result


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
