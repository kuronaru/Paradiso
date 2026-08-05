# synergy_manager.gd - Synergy counting, tiers and modifier application.
extends Node

const M = "Synergy"

signal synergy_changed(summaries: Array)
signal resource_bonus_ready(bonus_payload: Dictionary)
signal acquisition_trait_triggered(class_id: String, repeat_count: int, card_data: Dictionary)

var _definitions: Dictionary = {}
var _definition_order: Array[String] = []
var _summaries: Array[Dictionary] = []
var _active_modifiers: Dictionary = {}
var _active_fixed_modifiers: Dictionary = {}
var _active_main_effects: Dictionary = {}
var _active_synergy_passive_effects: Dictionary = {}
var _test_override_enabled: bool = false
var _test_synergy_specs: Array[Dictionary] = []
var _persistent_layers: Dictionary = {}
var _next_tavern_refresh_free: bool = false
var _cha_reward_steps_claimed: int = 0
var _cha_recruit_discount_unlocked: bool = false
var _wis_threshold_seen: bool = false
var _wis_scavenge_pending: bool = false
var _wis_scavenge_active: bool = false


func _ready() -> void:
	_build_definitions()
	if not BattleManager.battle_started.is_connected(_on_battle_started):
		BattleManager.battle_started.connect(_on_battle_started)
	if not BattleManager.unit_deployed.is_connected(_on_unit_roster_changed):
		BattleManager.unit_deployed.connect(_on_unit_roster_changed)
	if not BattleManager.unit_retreated.is_connected(_on_unit_roster_changed):
		BattleManager.unit_retreated.connect(_on_unit_roster_changed)
	if not GameManager.party_changed.is_connected(_on_party_changed):
		GameManager.party_changed.connect(_on_party_changed)
	recalculate()


func recalculate() -> void:
	var count_by_id: Dictionary = {}
	var layer_by_id: Dictionary = {}
	var member_names_by_id: Dictionary = {}
	var layer_per_star := _cfg_int("synergy_layer_per_star", 20)
	var max_layer := _cfg_int("synergy_max_layer", 999)

	if _test_override_enabled:
		_collect_test_synergy_counts(count_by_id, layer_by_id, member_names_by_id, max_layer)
	else:
		_collect_roster_synergy_counts(count_by_id, layer_by_id, member_names_by_id, layer_per_star)
		_apply_shapeshifter_main_count_bonus(count_by_id, member_names_by_id)
		for synergy_id in _persistent_layers.keys():
			if int(count_by_id.get(synergy_id, 0)) > 0:
				layer_by_id[synergy_id] = int(layer_by_id.get(synergy_id, 0)) + int(_persistent_layers[synergy_id])

	_active_modifiers = _default_modifiers()
	_active_fixed_modifiers = {}
	_active_main_effects = {}
	_active_synergy_passive_effects = {}
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
			var global_modifiers := _build_definition_unit_modifiers(definition, active_tier, layer, "global")
			var member_modifiers := _build_definition_unit_modifiers(definition, active_tier, layer, "members")
			var advanced_member_modifiers := _build_definition_unit_modifiers(definition, active_tier, layer, "advanced_members")
			_merge_modifiers_into(_active_modifiers, global_modifiers)
			_apply_definition_fixed_modifiers(definition, active_tier)
			_active_synergy_passive_effects[definition.synergy_id] = _build_synergy_passive_payload(
				definition,
				active_tier,
				layer,
				global_modifiers,
				member_modifiers,
				advanced_member_modifiers
			)
			if definition.type == SynergyDefinition.SynergyType.MAIN_NATION:
				_active_main_effects[definition.tag] = _build_main_effect_payload(definition, active_tier, layer)

	_summaries.sort_custom(_sort_summaries)
	_update_layer_milestones()
	_sync_passives_to_units()
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


func get_active_synergy_passive_effects() -> Dictionary:
	return _active_synergy_passive_effects.duplicate(true)


func get_test_synergy_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var layer_per_star := _cfg_int("synergy_layer_per_star", 20)
	var max_layer := _cfg_int("synergy_max_layer", 999)
	for synergy_id in _definition_order:
		var definition := _definitions[synergy_id] as SynergyDefinition
		var activation_count := definition.thresholds[0] if not definition.thresholds.is_empty() else 1
		options.append({
			"id": definition.synergy_id,
			"display_name": definition.display_name,
			"short_name": definition.short_name,
			"type": definition.type,
			"type_name": _type_name(definition.type),
			"thresholds": definition.thresholds.duplicate(),
			"activation_count": activation_count,
			"max_threshold": definition.get_max_threshold(),
			"default_layer": activation_count * layer_per_star,
			"max_layer": max_layer,
			"order": definition.order,
		})
	return options


func set_test_synergy_override(specs: Array) -> void:
	_test_override_enabled = true
	_test_synergy_specs = _sanitize_test_synergy_specs(specs)
	recalculate()


func clear_test_synergy_override() -> void:
	_test_override_enabled = false
	_test_synergy_specs.clear()
	recalculate()


func is_test_synergy_override_enabled() -> bool:
	return _test_override_enabled


func get_test_synergy_specs() -> Array:
	return _test_synergy_specs.duplicate(true)


func get_discounted_deploy_cost(base_cost: int) -> int:
	var discount := clampf(float(_active_fixed_modifiers.get("deploy_cost_discount", 0.0)), 0.0, 0.75)
	return maxi(1, int(ceil(float(base_cost) * (1.0 - discount))))


func apply_victory_gold_bonus(base_reward: int) -> int:
	var multiplier := float(_active_fixed_modifiers.get("victory_gold_multiplier", 1.0))
	return maxi(0, int(round(float(base_reward) * multiplier)))


func reset_run_state() -> void:
	_persistent_layers.clear()
	_next_tavern_refresh_free = false
	_cha_reward_steps_claimed = 0
	_cha_recruit_discount_unlocked = false
	_wis_threshold_seen = false
	_wis_scavenge_pending = false
	_wis_scavenge_active = false


func get_tavern_refresh_cost(base_cost: int) -> int:
	return 0 if _next_tavern_refresh_free else maxi(0, base_cost)


func notify_tavern_refreshed() -> void:
	_next_tavern_refresh_free = false
	var effect := _active_effect_for("stat_cha")
	var chance := clampf(float(effect.get("next_refresh_free_chance", 0.0)), 0.0, 1.0)
	if chance > 0.0 and randf() < chance:
		_next_tavern_refresh_free = true


func get_recruit_cost_discount() -> int:
	return 1 if _cha_recruit_discount_unlocked else 0


func notify_hero_acquired(class_id: String, card_data: Dictionary = {}) -> int:
	var repeat_count := 1
	var effect := _active_effect_for("alignment_lawful")
	if not effect.is_empty():
		repeat_count = int(effect.get("acquisition_repeat_count", 1))
		if int(_summary_by_id("alignment_lawful").get("layer", 0)) >= 100:
			repeat_count = maxi(repeat_count, 3)
	acquisition_trait_triggered.emit(class_id, repeat_count, card_data.duplicate(true))
	return repeat_count


func resolve_battle_end_gold_bonus(defeated_enemy_count: int) -> int:
	var bonus := 0
	var effect := _active_effect_for("stat_wis")
	if not effect.is_empty():
		bonus += _roll_repeated_chance(float(effect.get("battle_end_gold_chance", 0.0))) * int(effect.get("battle_end_gold_amount", 2))
	if _wis_scavenge_active:
		bonus += int(maxi(0, defeated_enemy_count) / 20) * 4
		_wis_scavenge_active = false
	return bonus


func apply_rest_synergy_layers() -> int:
	var summary := _summary_by_id("alignment_neutral")
	if summary.is_empty() or not bool(summary.get("is_active", false)):
		return 0
	var amount := 4 if int(summary.get("active_tier", 0)) >= 3 else 2
	for active_summary in _summaries:
		if not bool(active_summary.get("is_active", false)):
			continue
		var synergy_id := str(active_summary.get("id", ""))
		_persistent_layers[synergy_id] = int(_persistent_layers.get(synergy_id, 0)) + amount
	recalculate()
	return amount


func _on_battle_started() -> void:
	if _wis_scavenge_pending:
		_wis_scavenge_pending = false
		_wis_scavenge_active = true
	recalculate()


func _on_unit_roster_changed(_unit: Node) -> void:
	recalculate()


func _on_party_changed(_party: Array) -> void:
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
	for tag in ct.trait_tags:
		ids.append("trait_%s" % str(tag).to_lower())
	if hero.star_level >= 2:
		ids.append("trait_advanced")
	return ids


func _collect_roster_synergy_counts(count_by_id: Dictionary, layer_by_id: Dictionary, member_names_by_id: Dictionary, layer_per_star: int) -> void:
	var contributors: Dictionary = {}
	for unit in BattleManager.player_units:
		if not is_instance_valid(unit):
			continue
		if not (unit is HeroUnit):
			continue
		var hero := unit as HeroUnit
		if not hero.class_template:
			continue

		var ids := _get_unit_synergy_ids(hero)
		for synergy_id in ids:
			_add_contributor(contributors, synergy_id, hero.class_template.class_id, hero.star_level, hero.unit_name)

	for card_value in GameManager.party:
		if not (card_value is Dictionary):
			continue
		var card: Dictionary = card_value
		var class_id := ClassDefinitions.canonicalize_class_id(str(card.get("class_id", "")))
		if class_id == "":
			continue
		var template := ClassDefinitions.get_template(class_id)
		var star := clampi(int(card.get("star_level", card.get("level", 1))), 1, 3)
		var roster_ids: Array[String] = []
		for tag in template.stat_tags:
			roster_ids.append("stat_%s" % str(tag).to_lower())
		for tag in template.alignment_tags:
			roster_ids.append("alignment_%s" % str(tag).to_lower())
		for synergy_id in roster_ids:
			if not _definitions.has(synergy_id):
				continue
			var definition := _definitions[synergy_id] as SynergyDefinition
			if definition.count_scope == "roster":
				_add_contributor(contributors, synergy_id, class_id, star, template.job_name)

	for synergy_id in contributors.keys():
		var entries: Dictionary = contributors[synergy_id]
		count_by_id[synergy_id] = entries.size()
		member_names_by_id[synergy_id] = []
		var total_layer := 0
		for contributor in entries.values():
			var data: Dictionary = contributor
			total_layer += int(data.get("star", 1)) * layer_per_star
			member_names_by_id[synergy_id].append(str(data.get("name", "")))
		layer_by_id[synergy_id] = total_layer


func _add_contributor(contributors: Dictionary, synergy_id: String, contributor_id: String, star: int, display_name: String) -> void:
	if not _definitions.has(synergy_id) or contributor_id == "":
		return
	if not contributors.has(synergy_id):
		contributors[synergy_id] = {}
	var entries: Dictionary = contributors[synergy_id]
	var existing: Dictionary = entries.get(contributor_id, {})
	if existing.is_empty() or star > int(existing.get("star", 0)):
		entries[contributor_id] = {"star": clampi(star, 1, 3), "name": display_name}
	contributors[synergy_id] = entries


func _apply_shapeshifter_main_count_bonus(count_by_id: Dictionary, member_names_by_id: Dictionary) -> void:
	if int(count_by_id.get("trait_shapeshifter", 0)) <= 0:
		return
	for synergy_id in _definition_order:
		var definition := _definitions[synergy_id] as SynergyDefinition
		if definition.type != SynergyDefinition.SynergyType.MAIN_NATION or int(count_by_id.get(synergy_id, 0)) <= 0:
			continue
		count_by_id[synergy_id] = int(count_by_id[synergy_id]) + 1
		if not member_names_by_id.has(synergy_id):
			member_names_by_id[synergy_id] = []
		member_names_by_id[synergy_id].append("变形者加成")


func _collect_test_synergy_counts(count_by_id: Dictionary, layer_by_id: Dictionary, member_names_by_id: Dictionary, max_layer: int) -> void:
	for spec in _test_synergy_specs:
		var synergy_id := str(spec.get("id", ""))
		if not _definitions.has(synergy_id):
			continue
		var count := maxi(0, int(spec.get("count", 0)))
		if count <= 0:
			continue
		var layer := clampi(int(spec.get("layer", 0)), 0, max_layer)
		count_by_id[synergy_id] = count
		layer_by_id[synergy_id] = layer
		member_names_by_id[synergy_id] = ["测试配置 %d人" % count]


func _sanitize_test_synergy_specs(specs: Array) -> Array[Dictionary]:
	var max_layer := _cfg_int("synergy_max_layer", 999)
	var layer_per_star := _cfg_int("synergy_layer_per_star", 20)
	var by_id: Dictionary = {}
	for raw_spec in specs:
		if not (raw_spec is Dictionary):
			continue
		var spec: Dictionary = raw_spec
		var synergy_id := str(spec.get("id", spec.get("synergy_id", "")))
		if not _definitions.has(synergy_id):
			continue
		var count := maxi(0, int(spec.get("count", 0)))
		if count <= 0:
			continue
		var layer := int(spec.get("layer", count * layer_per_star))
		by_id[synergy_id] = {
			"id": synergy_id,
			"count": count,
			"layer": clampi(layer, 0, max_layer),
		}

	var result: Array[Dictionary] = []
	for synergy_id in _definition_order:
		if by_id.has(synergy_id):
			result.append((by_id[synergy_id] as Dictionary).duplicate(true))
	return result


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
			return "主羁绊"
		SynergyDefinition.SynergyType.MINOR_STAT:
			return "六维小羁绊"
		SynergyDefinition.SynergyType.MINOR_ALIGNMENT:
			return "阵营小羁绊"
		SynergyDefinition.SynergyType.MINOR_TRAIT:
			return "特性小羁绊"
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
		"damage_taken_multiplier": 1.0,
		"revive_time_multiplier": 1.0,
		"shield_multiplier": 1.0,
	}


func _build_definition_unit_modifiers(definition: SynergyDefinition, active_tier: int, layer: int, scope: String) -> Dictionary:
	var result := {}
	for modifier in definition.scalable_modifiers:
		if active_tier < int(modifier.get("min_tier", 0)):
			continue
		if layer < int(modifier.get("min_layer", 0)):
			continue
		if str(modifier.get("scope", definition.modifier_scope)) != scope:
			continue
		var stat := str(modifier.get("stat", ""))
		var base := float(modifier.get("base", 0.0))
		var per_layer := float(modifier.get("per_layer", 0.0))
		var max_value := float(modifier.get("max_value", base))
		var min_value := float(modifier.get("min_value", minf(base, max_value)))
		var value: float = clampf(base + float(layer) * per_layer, min_value, max_value)
		_merge_modifier_value(result, stat, value)
	return result


func _apply_definition_fixed_modifiers(definition: SynergyDefinition, active_tier: int) -> void:
	for modifier in definition.fixed_modifiers:
		if active_tier < int(modifier.get("min_tier", 0)):
			continue
		var stat := str(modifier.get("stat", ""))
		var value := float(modifier.get("value", 0.0))
		_merge_fixed_value(stat, value)


func _merge_modifiers_into(target: Dictionary, source: Dictionary) -> void:
	for stat in source.keys():
		_merge_modifier_value(target, str(stat), float(source[stat]))


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
		"damage_taken_multiplier",
		"revive_time_multiplier",
		"shield_multiplier",
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


func _build_synergy_passive_payload(
		definition: SynergyDefinition,
		active_tier: int,
		layer: int,
		global_modifiers: Dictionary,
		member_modifiers: Dictionary,
		advanced_member_modifiers: Dictionary) -> Dictionary:
	var resolved_effect := _build_main_effect_payload(definition, active_tier, layer)
	var is_main := definition.type == SynergyDefinition.SynergyType.MAIN_NATION
	return {
		"synergy_id": definition.synergy_id,
		"display_name": definition.display_name,
		"type": definition.type,
		"tag": definition.tag,
		"tier": active_tier,
		"layer": layer,
		"is_main": is_main,
		"mechanic_id": definition.mechanic_id,
		"global_modifiers": global_modifiers.duplicate(true),
		"member_modifiers": member_modifiers.duplicate(true),
		"advanced_member_modifiers": advanced_member_modifiers.duplicate(true),
		"effect": resolved_effect,
		"main_effect": resolved_effect if is_main else {},
	}


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


func _update_layer_milestones() -> void:
	if _test_override_enabled or not GameManager.is_roguelike_run:
		return
	var cha := _summary_by_id("stat_cha")
	if not cha.is_empty() and bool(cha.get("is_active", false)):
		var cha_layer := int(cha.get("layer", 0))
		var reward_steps := int(cha_layer / 50)
		if reward_steps > _cha_reward_steps_claimed:
			GameManager.earn_run_gold((reward_steps - _cha_reward_steps_claimed) * 10)
			_cha_reward_steps_claimed = reward_steps
		if cha_layer >= 150:
			_cha_recruit_discount_unlocked = true

	var wis := _summary_by_id("stat_wis")
	if not _wis_threshold_seen and not wis.is_empty() and bool(wis.get("is_active", false)) and int(wis.get("layer", 0)) >= 100:
		_wis_threshold_seen = true
		_wis_scavenge_pending = true


func _summary_by_id(synergy_id: String) -> Dictionary:
	for summary in _summaries:
		if str(summary.get("id", "")) == synergy_id:
			return summary
	return {}


func _active_effect_for(synergy_id: String) -> Dictionary:
	var payload: Dictionary = _active_synergy_passive_effects.get(synergy_id, {})
	var effect = payload.get("effect", {})
	return effect.duplicate(true) if effect is Dictionary else {}


func _roll_repeated_chance(chance: float) -> int:
	var safe_chance := maxf(0.0, chance)
	var guaranteed := int(floor(safe_chance))
	var remainder := safe_chance - float(guaranteed)
	return guaranteed + (1 if remainder > 0.0 and randf() < remainder else 0)


func _sync_passives_to_units() -> void:
	for unit in BattleManager.player_units:
		if is_instance_valid(unit) and unit is HeroUnit:
			(unit as HeroUnit).sync_synergy_passives(_active_synergy_passive_effects)


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
		main_effect,
		str(data.get("modifier_scope", "members" if str(data.get("type", "")) == "main_nation" else "global")),
		str(data.get("count_scope", "deployed"))
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
		"minor_trait":
			return SynergyDefinition.SynergyType.MINOR_TRAIT
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
