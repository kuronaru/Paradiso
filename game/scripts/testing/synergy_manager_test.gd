# synergy_manager_test.gd - Unit tests for SynergyManager counting, overrides and effects.
extends SceneTree

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("SynergyManager")
var synergy_manager
var battle_manager
var resource_manager
var game_manager


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	synergy_manager = _autoload("SynergyManager")
	battle_manager = _autoload("BattleManager")
	resource_manager = _autoload("ResourceManager")
	game_manager = _autoload("GameManager")

	t.assert_true(synergy_manager != null, "SynergyManager autoload exists")
	t.assert_true(battle_manager != null, "BattleManager autoload exists")
	t.assert_true(resource_manager != null, "ResourceManager autoload exists")
	if not synergy_manager or not battle_manager or not resource_manager:
		t.finish(self)
		return

	_reset_state()
	t.assert_true(synergy_manager.get_test_synergy_options().size() > 0, "test synergy options are available")

	_test_empty_roster_defaults()
	_test_inactive_override_has_summary_without_modifiers()
	_test_main_synergy_override()
	_test_new_minor_scopes()
	_test_new_definition_options()
	_test_non_stackable_synergies_and_polymorph()
	_test_economy_and_rest_hooks()
	_test_clear_override()

	t.finish(self)


func _test_empty_roster_defaults() -> void:
	synergy_manager.clear_test_synergy_override()
	battle_manager.player_units.clear()
	battle_manager.enemy_units.clear()
	synergy_manager.recalculate()
	t.assert_eq(synergy_manager.get_synergy_summary().size(), 0, "empty roster has no summaries")
	var modifiers: Dictionary = synergy_manager.get_active_modifiers()
	t.assert_near(float(modifiers.get("attack_multiplier", 0.0)), 1.0, 0.0001, "empty roster attack multiplier is default")
	t.assert_eq(synergy_manager.get_active_main_effects().size(), 0, "empty roster has no main effects")


func _test_inactive_override_has_summary_without_modifiers() -> void:
	synergy_manager.set_test_synergy_override([
		{"id": "stat_str", "count": 1, "layer": 20},
	])
	var summary := _summary_by_id("stat_str")
	t.assert_false(summary.is_empty(), "inactive override still creates summary")
	t.assert_false(bool(summary.get("is_active", true)), "stat_str count 1 is inactive")
	var modifiers: Dictionary = synergy_manager.get_active_modifiers()
	t.assert_near(float(modifiers.get("attack_multiplier", 0.0)), 1.0, 0.0001, "inactive stat_str does not modify attack")
	t.assert_eq(synergy_manager.get_active_synergy_passive_effects().size(), 0, "inactive synergy creates no passive payload")


func _test_main_synergy_override() -> void:
	synergy_manager.set_test_synergy_override([
		{"id": "main_naka", "count": 3, "layer": 60},
	])
	t.assert_true(synergy_manager.is_test_synergy_override_enabled(), "test override is enabled")
	var specs: Array = synergy_manager.get_test_synergy_specs()
	t.assert_eq(specs.size(), 1, "test override stores one sanitized spec")
	t.assert_eq(str((specs[0] as Dictionary).get("id", "")), "main_naka", "test override keeps main_naka")

	var summary := _summary_by_id("main_naka")
	t.assert_false(summary.is_empty(), "main_naka summary exists")
	t.assert_true(bool(summary.get("is_active", false)), "main_naka is active")
	t.assert_eq(int(summary.get("active_tier", 0)), 3, "main_naka active tier is 3")
	t.assert_eq(int(summary.get("layer", 0)), 60, "main_naka layer is preserved")

	var expected_attack := 1.3 + 60.0 * 0.008
	var modifiers: Dictionary = synergy_manager.get_active_modifiers()
	t.assert_near(float(modifiers.get("attack_multiplier", 0.0)), 1.0, 0.0001, "member-scoped main synergy does not modify unrelated units globally")

	var main_effects: Dictionary = synergy_manager.get_active_main_effects()
	t.assert_true(main_effects.has("naka"), "main_naka exposes naka main effect")
	var naka: Dictionary = main_effects.get("naka", {})
	t.assert_eq(int(naka.get("tier", 0)), 3, "naka main effect tier is 3")
	t.assert_near(float(naka.get("burning_damage_multiplier", 0.0)), 1.0, 0.0001, "tier 3 naka uses neutral burning multiplier fallback")
	t.assert_near(float(naka.get("explosion_chance", -1.0)), 0.0, 0.0001, "tier 3 naka has no explosion chance")

	var passive_effects: Dictionary = synergy_manager.get_active_synergy_passive_effects()
	t.assert_true(passive_effects.has("main_naka"), "main_naka passive payload exists")
	var payload: Dictionary = passive_effects.get("main_naka", {})
	t.assert_true(bool(payload.get("is_main", false)), "main_naka passive payload is marked main")
	var member_modifiers: Dictionary = payload.get("member_modifiers", {})
	t.assert_near(float(member_modifiers.get("attack_multiplier", 0.0)), expected_attack, 0.0001, "main_naka member multiplier matches data formula")


func _test_new_minor_scopes() -> void:
	resource_manager.reset_dp(20, 100)
	synergy_manager.set_test_synergy_override([
		{"id": "trait_support", "count": 2, "layer": 40},
		{"id": "alignment_good", "count": 2, "layer": 40},
		{"id": "trait_advanced", "count": 5, "layer": 100},
		{"id": "alignment_lawful", "count": 2, "layer": 100},
	])
	var global: Dictionary = synergy_manager.get_active_modifiers()
	t.assert_near(float(global.get("damage_taken_multiplier", 1.0)), 0.8, 0.0001, "support applies global 20 percent damage reduction")
	t.assert_near(float(global.get("incoming_heal_multiplier", 1.0)), 1.6, 0.0001, "good layer 40 applies global incoming healing milestone")
	var advanced_payload: Dictionary = synergy_manager.get_active_synergy_passive_effects().get("trait_advanced", {})
	var advanced_members: Dictionary = advanced_payload.get("member_modifiers", {})
	t.assert_near(float(advanced_members.get("attack_multiplier", 1.0)), 1.3, 0.0001, "advanced tier 2 grants member attack")
	t.assert_near(float(advanced_members.get("skill_cooldown_reduction", 0.0)), 0.3, 0.0001, "advanced tier 5 grants member cooldown reduction")
	t.assert_eq(synergy_manager.get_synergy_layer("trait_advanced"), 0, "advanced is non-stackable even when override supplies layers")
	t.assert_eq(synergy_manager.notify_hero_acquired("fighter_champion"), 3, "lawful layer 100 repeats acquisition traits three times")


func _test_new_definition_options() -> void:
	var ids: Dictionary = {}
	for option in synergy_manager.get_test_synergy_options():
		ids[str(option.get("id", ""))] = option
	t.assert_true(ids.has("trait_flying"), "flying trait definition is available")
	t.assert_true(ids.has("trait_support"), "support trait definition is available")
	t.assert_true(ids.has("trait_advanced"), "advanced trait definition is available")
	t.assert_true(ids.has("trait_shapeshifter"), "shapeshifter trait definition is available")
	t.assert_eq(int((ids.get("stat_wis", {}) as Dictionary).get("activation_count", 0)), 2, "wisdom activates at two members")


func _test_non_stackable_synergies_and_polymorph() -> void:
	for synergy_id in ["trait_flying", "trait_advanced", "trait_shapeshifter"]:
		synergy_manager.set_test_synergy_override([{"id": synergy_id, "count": 5, "layer": 999}])
		t.assert_eq(synergy_manager.get_synergy_layer(synergy_id), 0, "%s always has zero layers" % synergy_id)
		var commands: Array[Dictionary] = [{"synergy_id": synergy_id, "amount": 50}]
		var result: Dictionary = synergy_manager.apply_trait_layer_batch(commands)
		t.assert_true((result.get("applied", {}) as Dictionary).is_empty(), "%s rejects trait layer commands" % synergy_id)

	synergy_manager.clear_test_synergy_override()
	var converted: Array[String] = synergy_manager.get_equipment_main_synergy_ids(["polymorph", "dragon_scale"])
	t.assert_true("main_naka" in converted, "polymorph converts mapped equipment into an extra main synergy")
	t.assert_true(synergy_manager.get_equipment_main_synergy_ids(["dragon_scale"]).is_empty(), "mapped equipment alone does not grant a main synergy")


func _test_economy_and_rest_hooks() -> void:
	synergy_manager.clear_test_synergy_override()
	synergy_manager.reset_run_state()
	battle_manager.player_units.clear()
	game_manager.is_roguelike_run = true
	game_manager.run_gold = 0
	game_manager.party = [
		{"class_id": "bard_lore", "star_level": 3},
		{"class_id": "bard_valor", "star_level": 3},
		{"class_id": "paladin_devotion", "star_level": 3},
	]
	synergy_manager.recalculate()
	t.assert_eq(int(_summary_by_id("stat_cha").get("layer", -1)), 0, "roster synergies start with zero layers")
	var commands: Array[Dictionary] = [{"synergy_id": "stat_cha", "amount": 150}]
	synergy_manager.apply_trait_layer_batch(commands)
	t.assert_eq(game_manager.run_gold, 30, "charisma awards 10 gold for each crossed 50-layer milestone")
	t.assert_eq(synergy_manager.get_recruit_cost_discount(), 1, "charisma layer 150 unlocks permanent recruit discount")

	synergy_manager.set_test_synergy_override([{"id": "stat_wis", "count": 2, "layer": 999}])
	var wis_bonus: int = int(synergy_manager.resolve_battle_end_gold_bonus(0))
	t.assert_true(wis_bonus == 2 or wis_bonus == 4, "wisdom 160 percent chance gives one guaranteed and at most one extra reward")

	synergy_manager.set_test_synergy_override([{"id": "alignment_neutral", "count": 3, "layer": 60}])
	t.assert_eq(synergy_manager.apply_rest_synergy_layers(), 4, "neutral tier 3 grants four rest layers")
	game_manager.party.clear()
	game_manager.is_roguelike_run = false


func _test_clear_override() -> void:
	synergy_manager.clear_test_synergy_override()
	t.assert_false(synergy_manager.is_test_synergy_override_enabled(), "clear disables test override")
	t.assert_eq(synergy_manager.get_test_synergy_specs().size(), 0, "clear removes test specs")
	battle_manager.player_units.clear()
	battle_manager.enemy_units.clear()
	synergy_manager.recalculate()
	t.assert_eq(synergy_manager.get_synergy_summary().size(), 0, "after clear and empty roster summaries are empty")
	t.assert_eq(synergy_manager.get_active_main_effects().size(), 0, "after clear and empty roster main effects are empty")


func _summary_by_id(synergy_id: String) -> Dictionary:
	for item in synergy_manager.get_synergy_summary():
		var summary: Dictionary = item
		if str(summary.get("id", "")) == synergy_id:
			return summary
	return {}


func _reset_state() -> void:
	paused = false
	battle_manager.player_units.clear()
	battle_manager.enemy_units.clear()
	battle_manager.wave_enemies.clear()
	battle_manager.enemy_pool.clear()
	battle_manager.state = 0
	game_manager.party.clear()
	resource_manager.reset_dp(20, 100)
	if synergy_manager.is_test_synergy_override_enabled():
		synergy_manager.clear_test_synergy_override()
	else:
		synergy_manager.recalculate()


func _autoload(node_name: String):
	return root.get_node_or_null(node_name)
