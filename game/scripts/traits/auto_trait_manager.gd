extends Node

const M := "AutoTrait"
const MAX_LAYER := 999
const SUPPORTED_TEMPLATE_IDS: Array[String] = [
	"CB_ENEMY_TYPE", "CB_MAIN_LAYER_STAT", "CB_SYNERGY_LAYER_STAT", "CB_DUAL_LAYER_DEF", "CB_FAST_MERGE", "CB_ADAPTIVE_DAMAGE", "CB_FRONT_LAYER_RELAY",
	"P_PRICE_ONE", "P_GAIN_REFRESH", "P_GAIN_NEXT_GOLD", "P_GAIN_EQUIPMENT", "P_SELL_REFRESH", "P_SELL_NEXT_GOLD", "P_SELL_SPECIAL_RECRUIT", "P_ROW_RECRUIT", "P_REST_NEXT_GOLD",
	"B_OWNER_ALL", "B_TAVERN_NAMED", "B_LINKED_SPLIT",
	"E_REST_ENTER_OWNER", "E_REST_ENTER_FRONT", "E_REST_END_FRONT", "E_REST_END_NAMED", "E_REST_HIGHEST_BENCH", "E_REST_COUNT_GAIN", "E_REST_COUNT_REFRESH", "E_REST_END_BACK", "E_REST_COUNT_DISTINCT_TIER", "E_REST_HIGHEST_DISTINCT_TIER", "E_REST_COUNT_ROW", "E_REST_COUNT_BENCH", "E_REST_COUNT_SPEND", "E_GRANT_FRONT_TRAIT", "E_GRANT_ROW_RIGHT_TRAIT", "E_FIRST_DEFEAT", "E_FIRST_SKILL", "E_DEFEAT_EVERY_3", "E_EVERY_SKILL", "E_FIRST_3_DEFEATS", "E_DEPLOY", "E_SELF_DEFEATED", "E_STATUS_IN_RANGE", "E_FIRST_REFRESH_BENCH",
	"SP_TRIGGER_REST_TRAIT_ON_SELL", "SP_TRIGGER_FRONT_ACQUIRE", "SP_COPY_FRONT_REST_TRAIT",
]

signal trait_triggered(trait_id: String, hero_id: String, trigger: String, result: Dictionary)
signal equipment_granted(equipment_id: String, amount: int)

var free_refresh_tokens: int = 0
var next_rest_gold: int = 0
var equipment_inventory: Dictionary = {}

var _round_heroes_gained: int = 0
var _round_refreshes: int = 0
var _round_gold_spent: int = 0
var _battle_serial: int = 0
var _battle_counts: Dictionary = {}
var _temporary_traits: Dictionary = {}
var _event_serial: int = 0
var _refresh_token_quoted: bool = false
var _rest_open: bool = false


func _ready() -> void:
	if not BattleManager.unit_deployed.is_connected(_on_unit_deployed):
		BattleManager.unit_deployed.connect(_on_unit_deployed)


func _on_unit_deployed(unit: Node) -> void:
	if unit is HeroUnit:
		notify_unit_deployed(unit as HeroUnit)


func reset_run_state() -> void:
	free_refresh_tokens = 0
	next_rest_gold = 0
	equipment_inventory.clear()
	_round_heroes_gained = 0
	_round_refreshes = 0
	_round_gold_spent = 0
	_battle_serial = 0
	_battle_counts.clear()
	_temporary_traits.clear()
	_event_serial = 0
	_refresh_token_quoted = false
	_rest_open = false


func preparation_value(tier: int, star_level: int) -> int:
	return int(ceil(float(clampi(tier, 1, 6)) / 3.0)) * _star_factor(star_level)


func burst_value(tier: int, star_level: int) -> int:
	return 4 * clampi(tier, 1, 6) * _star_factor(star_level)


func engine_value(tier: int, star_level: int) -> int:
	return clampi(tier, 1, 6) * _star_factor(star_level)


func get_supported_template_ids() -> Array[String]:
	return SUPPORTED_TEMPLATE_IDS.duplicate()


func get_equipment_inventory() -> Dictionary:
	return equipment_inventory.duplicate(true)


func grant_equipment(equipment_id: String, amount: int = 1) -> int:
	var safe_amount := maxi(0, amount)
	if equipment_id == "" or safe_amount <= 0 or DataRegistry.get_autochess_equipment(equipment_id).is_empty():
		return 0
	equipment_inventory[equipment_id] = int(equipment_inventory.get(equipment_id, 0)) + safe_amount
	equipment_granted.emit(equipment_id, safe_amount)
	return safe_amount


func consume_equipment(equipment_id: String, amount: int = 1) -> bool:
	var safe_amount := maxi(1, amount)
	var owned := int(equipment_inventory.get(equipment_id, 0))
	if owned < safe_amount:
		return false
	var remaining := owned - safe_amount
	if remaining > 0:
		equipment_inventory[equipment_id] = remaining
	else:
		equipment_inventory.erase(equipment_id)
	return true


func get_purchase_cost(class_id: String, base_cost: int) -> int:
	for trait_id in _base_trait_ids(class_id):
		if _template_id(trait_id) == "P_PRICE_ONE":
			return 1
	return maxi(0, base_cost)


func get_refresh_cost(base_cost: int) -> int:
	_refresh_token_quoted = base_cost > 0 and free_refresh_tokens > 0
	return 0 if _refresh_token_quoted else maxi(0, base_cost)


func notify_gold_spent(amount: int) -> void:
	_round_gold_spent += maxi(0, amount)


func notify_rest_started() -> void:
	_rest_open = true
	if next_rest_gold > 0:
		GameManager.earn_run_gold(next_rest_gold)
		next_rest_gold = 0
	_round_heroes_gained = 0
	_round_refreshes = 0
	_round_gold_spent = 0
	_battle_serial += 1
	_battle_counts.clear()
	for entry in _roster_entries():
		_run_trigger(entry, "REST_STARTED", {})


func notify_rest_ending() -> void:
	if not _rest_open:
		return
	_rest_open = false
	for entry in _roster_entries():
		_run_trigger(entry, "REST_ENDING", {})
	_temporary_traits.clear()


func notify_hero_acquired(card_data: Dictionary, repeat_count: int = 1) -> void:
	var entry := _entry_from_card(card_data, true)
	var repeats := maxi(1, repeat_count)
	_round_heroes_gained += 1
	for _i in range(repeats):
		_run_trigger(entry, "HERO_ACQUIRED", {"repeat_count": repeats})


func notify_hero_sold(card_data: Dictionary) -> void:
	var entry := _entry_from_card(card_data, true)
	_run_trigger(entry, "HERO_SOLD", {})


func notify_tavern_refreshed() -> void:
	if _refresh_token_quoted and free_refresh_tokens > 0:
		free_refresh_tokens -= 1
	_refresh_token_quoted = false
	_round_refreshes += 1
	for entry in _roster_entries():
		if bool(entry.get("on_bench", false)):
			_run_trigger(entry, "TAVERN_REFRESHED", {})


func notify_battle_started() -> void:
	# F键和波次按钮可绕过 RoguelikeManager.skip_recruit；在统一战斗入口补结算。
	notify_rest_ending()
	for entry in _field_entries():
		_run_trigger(entry, "BATTLE_STARTED", {})
	_refresh_field_trait_passives()


func notify_unit_deployed(hero: HeroUnit) -> void:
	var entry := _entry_from_hero(hero)
	_run_trigger(entry, "UNIT_DEPLOYED", {})


func notify_enemy_defeated(hero: HeroUnit, target: UnitBase = null) -> void:
	var entry := _entry_from_hero(hero)
	_run_trigger(entry, "UNIT_DEFEATED", {"target": target})


func notify_skill_used(hero: HeroUnit) -> void:
	var entry := _entry_from_hero(hero)
	_run_trigger(entry, "SKILL_USED", {})


func notify_self_defeated(hero: HeroUnit) -> void:
	var entry := _entry_from_hero(hero)
	_run_trigger(entry, "SELF_DEFEATED", {})


func notify_status_applied(source: UnitBase, target: UnitBase, status_id: String) -> void:
	for entry in _field_entries():
		if not _entry_has_template(entry, "E_STATUS_IN_RANGE"):
			continue
		var observer := entry.get("unit", null) as HeroUnit
		if not observer or not target:
			continue
		var max_range := 3.0
		for trait_id in entry.get("trait_ids", []):
			if _template_id(str(trait_id)) == "E_STATUS_IN_RANGE":
				max_range = float(_trait_data(str(trait_id), str(entry.get("class_id", ""))).get("params", {}).get("range", 3.0))
				break
		var cell_size := 64.0
		if BattleManager.grid:
			cell_size = maxf(float(BattleManager.grid.cell_size), 1.0)
		var distance_in_cells := observer.global_position.distance_to(target.global_position) / cell_size
		if observer == source or distance_in_cells <= max_range:
			_run_trigger(entry, "STATUS_APPLIED", {"source": source, "target": target, "status_id": status_id})


func get_merge_requirement(class_id: String) -> int:
	for trait_id in _base_trait_ids(class_id):
		if _template_id(trait_id) == "CB_FAST_MERGE":
			return 2
	return 3


func get_combat_modifiers(hero: HeroUnit) -> Dictionary:
	var merged: Dictionary = {}
	var entry := _entry_from_hero(hero)
	for trait_id in entry.get("trait_ids", []):
		var template_id := _template_id(str(trait_id))
		if template_id not in ["CB_MAIN_LAYER_STAT", "CB_SYNERGY_LAYER_STAT", "CB_DUAL_LAYER_DEF"]:
			continue
		var trait_data := _trait_data(str(trait_id), str(entry.get("class_id", "")))
		var params: Dictionary = trait_data.get("params", {})
		var synergy_ids := _target_synergy_ids(entry, params)
		if template_id == "CB_MAIN_LAYER_STAT":
			var main_ids: Array[String] = []
			for synergy_id in _owner_synergy_ids(entry):
				if synergy_id.begins_with("main_"):
					main_ids.append(synergy_id)
			synergy_ids = main_ids
		if synergy_ids.is_empty():
			continue
		var layer := SynergyManager.get_synergy_layer(synergy_ids[0])
		if template_id == "CB_DUAL_LAYER_DEF" and synergy_ids.size() > 1:
			layer += SynergyManager.get_synergy_layer(synergy_ids[1])
		var tier := int(entry.get("trait_tier", 1))
		var factor := _star_factor(int(entry.get("star_level", 1)))
		var step := float(int(ceil(float(tier) / 2.0)) * factor) / 100.0
		var cap := float((20 + 5 * tier) * factor) / 100.0
		var bonus := minf(float(int(layer / 3)) * step, cap)
		var stat := str(params.get("stat", "defense" if template_id == "CB_DUAL_LAYER_DEF" else "attack"))
		var modifier_key := _modifier_key(stat)
		if modifier_key == "skill_cooldown_reduction":
			merged[modifier_key] = minf(0.40, float(merged.get(modifier_key, 0.0)) + bonus)
		else:
			merged[modifier_key] = float(merged.get(modifier_key, 1.0)) * (1.0 + bonus)
	return merged


func before_deal_damage(hero: HeroUnit, context: Dictionary) -> void:
	var entry := _entry_from_hero(hero)
	var target := context.get("target", null) as UnitBase
	for trait_id in entry.get("trait_ids", []):
		var template_id := _template_id(str(trait_id))
		if template_id == "CB_ADAPTIVE_DAMAGE":
			context["armor_pierce"] = 0.95
		elif template_id == "CB_ENEMY_TYPE" and _matches_enemy_condition(target, _trait_data(str(trait_id), str(entry.get("class_id", ""))).get("params", {})):
			var tier := int(entry.get("trait_tier", 1))
			var factor := _star_factor(int(entry.get("star_level", 1)))
			var multiplier := 1.0 + float((20 + 5 * tier) * factor) / 100.0
			context["damage"] = maxi(1, int(round(float(context.get("damage", 0)) * multiplier)))


func after_deal_damage(hero: HeroUnit, context: Dictionary) -> void:
	var target := context.get("target", null) as UnitBase
	if not target or target.is_alive:
		return
	var kill_key := "kill:%d:%d" % [_battle_serial, target.get_instance_id()]
	if bool(_battle_counts.get(kill_key, false)):
		return
	_battle_counts[kill_key] = true
	notify_enemy_defeated(hero, target)


func _run_trigger(entry: Dictionary, trigger: String, context: Dictionary) -> void:
	if entry.is_empty():
		return
	for trait_id_value in entry.get("trait_ids", []):
		var trait_id := str(trait_id_value)
		var template_id := _template_id(trait_id)
		var template := DataRegistry.get_auto_trait_template(template_id)
		if str(template.get("trigger", "")) != trigger:
			continue
		var result := _execute_template(template_id, trait_id, entry, context)
		trait_triggered.emit(trait_id, str(entry.get("class_id", "")), trigger, result)


func _execute_template(template_id: String, trait_id: String, entry: Dictionary, context: Dictionary) -> Dictionary:
	var trait_data := _trait_data(trait_id, str(entry.get("class_id", "")))
	var params: Dictionary = trait_data.get("params", {})
	var tier := int(entry.get("trait_tier", 1))
	var star := int(entry.get("star_level", 1))
	var p := preparation_value(tier, star)
	var b := burst_value(tier, star)
	var e := engine_value(tier, star)
	if template_id == "E_REST_HIGHEST_BENCH" and not bool(entry.get("on_bench", false)):
		return {}
	match template_id:
		"P_GAIN_REFRESH", "P_SELL_REFRESH":
			free_refresh_tokens += p
			return {"free_refreshes": p}
		"P_GAIN_NEXT_GOLD", "P_SELL_NEXT_GOLD", "P_REST_NEXT_GOLD":
			next_rest_gold += p
			return {"next_rest_gold": p}
		"P_GAIN_EQUIPMENT":
			var equipment_id := str(params.get("equipment_id", "trait_supply"))
			var amount := maxi(1, int(params.get("fixed_amount", p)))
			var granted := grant_equipment(equipment_id, amount)
			return {"equipment_id": equipment_id, "amount": granted}
		"P_SELL_SPECIAL_RECRUIT":
			return _special_recruit(entry, params)
		"P_ROW_RECRUIT":
			return _row_recruit(entry, 1 if star >= 2 else 3)
		"B_OWNER_ALL":
			return _apply_layer_total(entry, b, _owner_synergy_ids(entry), template_id)
		"B_TAVERN_NAMED":
			var tavern_level := _current_tavern_level(int(entry.get("shop_level", 1)))
			return _apply_layer_total(entry, p * tavern_level, _target_synergy_ids(entry, params), template_id)
		"B_LINKED_SPLIT":
			return _apply_layer_total(entry, b, _target_synergy_ids(entry, params), template_id)
		"E_REST_ENTER_OWNER", "E_REST_END_NAMED", "E_REST_HIGHEST_BENCH":
			return _apply_layer_total(entry, e, _select_rest_synergies(template_id, entry, params), template_id)
		"E_REST_ENTER_FRONT", "E_REST_END_FRONT", "E_REST_END_BACK":
			var partner := _relative_entry(entry, -1 if template_id == "E_REST_END_BACK" else 1)
			var combined := _owner_synergy_ids(entry)
			for synergy_id in _owner_synergy_ids(partner):
				if synergy_id not in combined:
					combined.append(synergy_id)
			return _apply_layer_total(entry, e, combined, template_id)
		"E_REST_COUNT_GAIN":
			return _apply_layer_total(entry, e * mini(_round_heroes_gained, int(params.get("count_cap", 6))), _target_synergy_ids(entry, params), template_id)
		"E_REST_COUNT_REFRESH":
			return _apply_layer_total(entry, e * mini(_round_refreshes, int(params.get("count_cap", 6))), _target_synergy_ids(entry, params), template_id)
		"E_REST_COUNT_SPEND":
			return _apply_layer_total(entry, e * mini(int(_round_gold_spent / 3), int(params.get("count_cap", 6))), _target_synergy_ids(entry, params), template_id)
		"E_REST_COUNT_ROW":
			return _apply_layer_total(entry, e * mini(_same_row_count(entry), int(params.get("count_cap", 6))), _target_synergy_ids(entry, params), template_id)
		"E_REST_COUNT_BENCH":
			return _apply_layer_total(entry, e * mini(GameManager.party.size(), int(params.get("count_cap", 6))), _target_synergy_ids(entry, params), template_id)
		"E_REST_COUNT_DISTINCT_TIER", "E_REST_HIGHEST_DISTINCT_TIER":
			var distinct_targets := _select_rest_synergies(template_id, entry, params)
			var distinct_count := _distinct_field_tiers_for_synergy(distinct_targets[0]) if not distinct_targets.is_empty() else 0
			return _apply_layer_total(entry, e * mini(distinct_count, int(params.get("count_cap", 6))), distinct_targets, template_id)
		"E_FIRST_DEFEAT":
			return _apply_first_or_counted(entry, template_id, 1, 1, e)
		"E_FIRST_SKILL":
			return _apply_first_or_counted(entry, template_id, 1, 1, e)
		"E_DEFEAT_EVERY_3":
			return _apply_first_or_counted(entry, template_id, 3, 999, e)
		"E_EVERY_SKILL":
			return _apply_first_or_counted(entry, template_id, 1, int(params.get("count_cap", 6)), e)
		"E_FIRST_3_DEFEATS":
			return _apply_first_or_counted(entry, template_id, 1, 3, e)
		"E_DEPLOY", "E_SELF_DEFEATED", "E_FIRST_REFRESH_BENCH":
			return _apply_first_or_counted(entry, template_id, 1, 1, e)
		"E_STATUS_IN_RANGE":
			var wanted_status := str(params.get("status_id", ""))
			if wanted_status != "" and wanted_status != str(context.get("status_id", "")):
				return {}
			if randf() <= clampf(float(params.get("chance", 0.5)), 0.0, 1.0):
				return _apply_first_or_counted(entry, template_id, 1, int(params.get("count_cap", 6)), e)
			return {}
		"E_GRANT_FRONT_TRAIT", "E_GRANT_ROW_RIGHT_TRAIT":
			return _grant_delegated_trait(entry, params, template_id)
		"SP_TRIGGER_REST_TRAIT_ON_SELL":
			return _trigger_first_matching_roster_trait("REST_ENDING")
		"SP_TRIGGER_FRONT_ACQUIRE":
			var front := _relative_entry(entry, 1)
			if not front.is_empty():
				_run_trigger(front, "HERO_ACQUIRED", {"delegated": true})
			return {"delegated": not front.is_empty()}
		"SP_COPY_FRONT_REST_TRAIT":
			return _copy_front_rest_trait(entry)
	return {}


func _apply_first_or_counted(entry: Dictionary, template_id: String, every: int, cap: int, amount: int) -> Dictionary:
	var key := "%d:%s:%s" % [_battle_serial, _entry_key(entry), template_id]
	var count := int(_battle_counts.get(key, 0)) + 1
	_battle_counts[key] = count
	if count > cap or count % every != 0:
		return {"event_count": count}
	return _apply_layer_total(entry, amount, _owner_synergy_ids(entry), template_id)


func _apply_layer_total(entry: Dictionary, total: int, synergy_ids: Array[String], source_template: String) -> Dictionary:
	var filtered: Array[String] = []
	for synergy_id in synergy_ids:
		if synergy_id != "" and DataRegistry.is_synergy_enabled(synergy_id) \
				and DataRegistry.is_synergy_stackable(synergy_id) and synergy_id not in filtered:
			filtered.append(synergy_id)
	if total <= 0 or filtered.is_empty():
		return {}
	var commands: Array[Dictionary] = []
	var base := int(total / filtered.size())
	var remainder := total % filtered.size()
	var requires_active := source_template.begins_with("E_")
	for i in range(filtered.size()):
		commands.append({
			"synergy_id": filtered[i],
			"amount": base + (1 if i < remainder else 0),
			"requires_active": requires_active,
		})
	_event_serial += 1
	var result := SynergyManager.apply_trait_layer_batch(commands, {
		"event_id": "trait_%d" % _event_serial,
		"source_template": source_template,
		"source_entry": _entry_key(entry),
	})
	_apply_front_layer_relays(entry, result)
	_refresh_field_trait_passives()
	return result


func _apply_front_layer_relays(source_entry: Dictionary, original_result: Dictionary) -> void:
	var applied = original_result.get("applied", {})
	if not (applied is Dictionary) or applied.is_empty() or not (source_entry.get("unit", null) is HeroUnit):
		return
	var source_unit := source_entry.get("unit", null) as HeroUnit
	for relay_entry in _field_entries():
		var relay_unit := relay_entry.get("unit", null) as HeroUnit
		if not relay_unit or relay_unit == source_unit:
			continue
		# 敌方在棋盘右侧，+x 为身前；relay 身前的 source 获得层数时触发。
		if relay_unit.deployed_grid_position.y != source_unit.deployed_grid_position.y or relay_unit.deployed_grid_position.x + 1 != source_unit.deployed_grid_position.x:
			continue
		if not _entry_has_template(relay_entry, "CB_FRONT_LAYER_RELAY"):
			continue
		var total := preparation_value(int(relay_entry.get("trait_tier", 1)), int(relay_entry.get("star_level", 1)))
		var relay_ids: Array[String] = []
		for synergy_id in applied.keys():
			if int(applied[synergy_id]) > 0:
				relay_ids.append(str(synergy_id))
		if relay_ids.is_empty():
			continue
		var base := int(total / relay_ids.size())
		var remainder := total % relay_ids.size()
		var commands: Array[Dictionary] = []
		for i in range(relay_ids.size()):
			commands.append({"synergy_id": relay_ids[i], "amount": base + (1 if i < remainder else 0)})
		SynergyManager.apply_trait_layer_batch(commands, {"event_id": "relay_%d" % _event_serial, "relay": true})


func _grant_delegated_trait(entry: Dictionary, params: Dictionary, template_id: String) -> Dictionary:
	var target := _relative_entry(entry, 1)
	if template_id == "E_GRANT_ROW_RIGHT_TRAIT":
		target = _rightmost_row_entry(entry)
	if target.is_empty():
		return {}
	var granted_trait_id := str(params.get("granted_trait_id", "E_FIRST_SKILL"))
	var key := _entry_key(target)
	var ids: Array = _temporary_traits.get(key, [])
	if granted_trait_id not in ids:
		ids.append(granted_trait_id)
	_temporary_traits[key] = ids
	return {"target": key, "granted_trait_id": granted_trait_id}


func _trigger_first_matching_roster_trait(trigger: String) -> Dictionary:
	var entries := _field_entries()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var au := a.get("unit", null) as HeroUnit
		var bu := b.get("unit", null) as HeroUnit
		if not au or not bu:
			return au != null
		if au.deployed_grid_position.y != bu.deployed_grid_position.y:
			return au.deployed_grid_position.y < bu.deployed_grid_position.y
		return au.deployed_grid_position.x > bu.deployed_grid_position.x
	)
	for entry in entries:
		for trait_id in entry.get("trait_ids", []):
			if str(DataRegistry.get_auto_trait_template(_template_id(str(trait_id))).get("trigger", "")) == trigger:
				var result := _execute_template(_template_id(str(trait_id)), str(trait_id), entry, {"delegated": true})
				return {"trait_id": trait_id, "result": result}
	return {}


func _copy_front_rest_trait(entry: Dictionary) -> Dictionary:
	var front := _relative_entry(entry, 1)
	if front.is_empty():
		return {}
	for trait_id in front.get("trait_ids", []):
		var template_id := _template_id(str(trait_id))
		if str(DataRegistry.get_auto_trait_template(template_id).get("trigger", "")) == "REST_ENDING":
			return _execute_template(template_id, str(trait_id), entry, {"copied": true})
	return {}


func _special_recruit(entry: Dictionary, params: Dictionary) -> Dictionary:
	if not GameManager.can_add_to_party():
		return {}
	var target_tier := int(params.get("advanced_tier", 5)) if int(entry.get("star_level", 1)) >= 2 else int(params.get("base_tier", 1))
	target_tier = clampi(target_tier, 1, 6)
	var candidates: Array[String] = []
	for class_id in ClassDefinitions.get_all_class_ids():
		if int(ClassDefinitions.get_autochess_data(class_id).get("trait_tier", 1)) == target_tier:
			candidates.append(class_id)
	if candidates.is_empty():
		return {}
	var class_id: String = str(candidates.pick_random())
	var shop_level := int(ClassDefinitions.get_tavern_data(class_id).get("shop_level", 1))
	if not GameManager.add_to_party(class_id, 1, shop_level):
		return {}
	var card: Dictionary = GameManager.party.back()
	notify_hero_acquired(card, 1)
	return {"recruited": class_id, "trait_tier": target_tier}


func _row_recruit(entry: Dictionary, required: int) -> Dictionary:
	if _same_row_count(entry) < maxi(1, required) or not GameManager.can_add_to_party():
		return {}
	var dominant_synergy := _dominant_roster_synergy_id()
	if dominant_synergy == "":
		return {}
	var candidates: Array[String] = []
	for class_id in ClassDefinitions.get_all_class_ids():
		var hero_data := ClassDefinitions.get_autochess_data(class_id)
		for synergy_id in hero_data.get("autochess_synergy_ids", []):
			if str(synergy_id) == dominant_synergy:
				candidates.append(class_id)
				break
	if candidates.is_empty():
		return {}
	var class_id: String = str(candidates.pick_random())
	var shop_level := int(ClassDefinitions.get_tavern_data(class_id).get("shop_level", 1))
	if GameManager.add_to_party(class_id, 1, shop_level):
		var card: Dictionary = GameManager.party.back()
		notify_hero_acquired(card, 1)
		return {"recruited": class_id}
	return {}


func _select_rest_synergies(template_id: String, entry: Dictionary, params: Dictionary) -> Array[String]:
	var ids := _target_synergy_ids(entry, params)
	if template_id in ["E_REST_HIGHEST_BENCH", "E_REST_HIGHEST_DISTINCT_TIER"]:
		ids = _active_synergy_ids()
		var best_id := ""
		var best_layer := -1
		for synergy_id in ids:
			var layer := SynergyManager.get_synergy_layer(synergy_id)
			if layer > best_layer:
				best_layer = layer
				best_id = synergy_id
		var highest: Array[String] = []
		if best_id != "":
			highest.append(best_id)
		return highest
	return ids


func _target_synergy_ids(entry: Dictionary, params: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var configured = params.get("synergy_ids", [])
	if configured is Array:
		for value in configured:
			result.append(str(value))
	var single := str(params.get("synergy_id", ""))
	if single != "":
		result.append(single)
	return result if not result.is_empty() else _owner_synergy_ids(entry)


func _owner_synergy_ids(entry: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in entry.get("synergy_ids", []):
		var synergy_id := str(value)
		if DataRegistry.is_synergy_enabled(synergy_id) and DataRegistry.is_synergy_stackable(synergy_id) \
				and synergy_id not in result:
			result.append(synergy_id)
	return result


func _base_trait_ids(class_id: String) -> Array[String]:
	var result: Array[String] = []
	for value in ClassDefinitions.get_autochess_data(class_id).get("trait_ids", []):
		result.append(str(value))
	return result


func _trait_data(trait_id: String, class_id: String) -> Dictionary:
	var result := DataRegistry.get_auto_trait(trait_id)
	var hero_data := ClassDefinitions.get_autochess_data(class_id)
	var overrides = hero_data.get("trait_params", {}).get(trait_id, {}) if hero_data.get("trait_params", {}) is Dictionary else {}
	if overrides is Dictionary and not overrides.is_empty():
		var params: Dictionary = result.get("params", {}).duplicate(true)
		params.merge(overrides, true)
		result["params"] = params
	return result


func _template_id(trait_id: String) -> String:
	return str(DataRegistry.get_auto_trait(trait_id).get("template_id", trait_id))


func _entry_from_card(card: Dictionary, on_bench: bool) -> Dictionary:
	var class_id := ClassDefinitions.canonicalize_class_id(str(card.get("class_id", "")))
	var hero_data := ClassDefinitions.get_autochess_data(class_id)
	return {
		"class_id": class_id,
		"star_level": clampi(int(card.get("star_level", card.get("level", 1))), 1, 3),
		"shop_level": maxi(1, int(card.get("shop_level", 1))),
		"trait_tier": clampi(int(hero_data.get("trait_tier", 1)), 1, 6),
		"synergy_ids": hero_data.get("autochess_synergy_ids", []).duplicate(),
		"trait_ids": _trait_ids_with_temporary(class_id, card, null),
		"on_bench": on_bench,
		"card": card,
		"unit": null,
	}


func _entry_from_hero(hero: HeroUnit) -> Dictionary:
	if not hero or not hero.class_template:
		return {}
	var class_id := hero.class_template.class_id
	var hero_data := ClassDefinitions.get_autochess_data(class_id)
	return {
		"class_id": class_id,
		"star_level": hero.star_level,
		"shop_level": maxi(1, int(hero.run_card_data.get("shop_level", 1))),
		"trait_tier": clampi(int(hero_data.get("trait_tier", 1)), 1, 6),
		"synergy_ids": hero_data.get("autochess_synergy_ids", []).duplicate(),
		"trait_ids": _trait_ids_with_temporary(class_id, hero.run_card_data, hero),
		"on_bench": false,
		"card": hero.run_card_data,
		"unit": hero,
	}


func _trait_ids_with_temporary(class_id: String, card: Dictionary, hero: HeroUnit) -> Array[String]:
	var ids := _base_trait_ids(class_id)
	var key := str(card.get("instance_id", ""))
	if key == "" and hero:
		key = "unit_%d" % hero.get_instance_id()
	for value in _temporary_traits.get(key, []):
		if str(value) not in ids:
			ids.append(str(value))
	return ids


func _roster_entries() -> Array[Dictionary]:
	var entries := _field_entries()
	for card in GameManager.party:
		if card is Dictionary:
			entries.append(_entry_from_card(card, true))
	return entries


func _field_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for unit in BattleManager.player_units:
		if unit is HeroUnit and is_instance_valid(unit):
			entries.append(_entry_from_hero(unit as HeroUnit))
	return entries


func _relative_entry(entry: Dictionary, x_offset: int) -> Dictionary:
	var owner := entry.get("unit", null) as HeroUnit
	if not owner:
		return {}
	for candidate in _field_entries():
		var unit := candidate.get("unit", null) as HeroUnit
		if unit and unit.deployed_grid_position.y == owner.deployed_grid_position.y and unit.deployed_grid_position.x == owner.deployed_grid_position.x + x_offset:
			return candidate
	return {}


func _rightmost_row_entry(entry: Dictionary) -> Dictionary:
	var owner := entry.get("unit", null) as HeroUnit
	if not owner:
		return {}
	var result: Dictionary = {}
	var best_x := -999999
	for candidate in _field_entries():
		var unit := candidate.get("unit", null) as HeroUnit
		if unit and unit != owner and unit.deployed_grid_position.y == owner.deployed_grid_position.y and unit.deployed_grid_position.x > best_x:
			best_x = unit.deployed_grid_position.x
			result = candidate
	return result


func _same_row_count(entry: Dictionary) -> int:
	var owner := entry.get("unit", null) as HeroUnit
	if not owner:
		return 0
	var count := 0
	for candidate in _field_entries():
		var unit := candidate.get("unit", null) as HeroUnit
		if unit and unit.deployed_grid_position.y == owner.deployed_grid_position.y:
			count += 1
	return count


func _distinct_field_tiers_for_synergy(synergy_id: String) -> int:
	var tiers: Dictionary = {}
	for entry in _field_entries():
		if synergy_id in _owner_synergy_ids(entry):
			tiers[int(entry.get("trait_tier", 1))] = true
	return tiers.size()


func _active_synergy_ids() -> Array[String]:
	var result: Array[String] = []
	for summary in SynergyManager.get_synergy_summary():
		if bool(summary.get("is_active", false)):
			result.append(str(summary.get("id", "")))
	return result


func _dominant_roster_synergy_id() -> String:
	var counts: Dictionary = {}
	for roster_entry in _roster_entries():
		for synergy_id in _owner_synergy_ids(roster_entry):
			counts[synergy_id] = int(counts.get(synergy_id, 0)) + 1
	var best_id := ""
	var best_count := 0
	for synergy_id in counts.keys():
		var count := int(counts[synergy_id])
		if count > best_count or (count == best_count and str(synergy_id) < best_id):
			best_count = count
			best_id = str(synergy_id)
	return best_id


func _current_tavern_level(fallback: int) -> int:
	var nodes := get_tree().get_nodes_in_group("roguelike_manager") if is_inside_tree() else []
	if not nodes.is_empty():
		var manager = nodes[0]
		if manager and manager.get("recruit_system") != null:
			return maxi(1, int(manager.recruit_system.tavern_level))
	return maxi(1, fallback)


func _entry_key(entry: Dictionary) -> String:
	var card = entry.get("card", {})
	if card is Dictionary and card.has("instance_id"):
		return str(card.get("instance_id"))
	var unit := entry.get("unit", null) as HeroUnit
	return "unit_%d" % unit.get_instance_id() if unit else str(entry.get("class_id", ""))


func _entry_has_template(entry: Dictionary, wanted_template: String) -> bool:
	for trait_id in entry.get("trait_ids", []):
		if _template_id(str(trait_id)) == wanted_template:
			return true
	return false


func _refresh_field_trait_passives() -> void:
	for entry in _field_entries():
		var unit := entry.get("unit", null) as HeroUnit
		if unit and unit.has_method("sync_auto_trait_passives"):
			unit.sync_auto_trait_passives()


func _matches_enemy_condition(target: UnitBase, params: Dictionary) -> bool:
	if not target:
		return false
	var condition := str(params.get("condition", "any"))
	match condition:
		"burning":
			return target.has_burning_status()
		"slowed":
			return target.status_move_speed_multiplier < 1.0
		"high_move_speed":
			return target.move_speed >= float(params.get("threshold", 2.5))
		"low_hp":
			return float(target.current_hp) / float(maxi(1, target.max_hp)) <= float(params.get("threshold", 0.5))
		"high_defense":
			return target.defense >= int(params.get("threshold", 20))
		"status":
			return target.combat_statuses.has(str(params.get("status_id", "")))
		"enemy_type":
			return target is EnemyUnit and int((target as EnemyUnit).enemy_type) == int(params.get("enemy_type", -1))
		"backline":
			return target.grid_position.x >= int(params.get("min_x", 6))
	return true


func _modifier_key(stat: String) -> String:
	match stat:
		"attack_speed": return "attack_speed_multiplier"
		"skill_cooldown", "cooldown": return "skill_cooldown_reduction"
		"defense": return "defense_multiplier"
		"skill_damage": return "skill_damage_multiplier"
		"heal", "healing": return "heal_multiplier"
		"max_hp", "hp": return "max_hp_multiplier"
	return "attack_multiplier"


func _star_factor(star_level: int) -> int:
	return 2 if star_level >= 2 else 1
