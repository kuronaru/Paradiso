# synergy_manager_test.gd - Unit tests for SynergyManager counting, overrides and effects.
extends SceneTree

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("SynergyManager")
var synergy_manager
var battle_manager
var resource_manager


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	synergy_manager = _autoload("SynergyManager")
	battle_manager = _autoload("BattleManager")
	resource_manager = _autoload("ResourceManager")

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
	_test_fixed_modifiers()
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
	t.assert_near(float(modifiers.get("attack_multiplier", 0.0)), expected_attack, 0.0001, "main_naka attack multiplier matches data formula")

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


func _test_fixed_modifiers() -> void:
	resource_manager.reset_dp(20, 100)
	synergy_manager.set_test_synergy_override([
		{"id": "stat_cha", "count": 3, "layer": 60},
		{"id": "alignment_neutral", "count": 3, "layer": 60},
	])
	var fixed: Dictionary = synergy_manager.get_fixed_modifiers()
	t.assert_near(float(fixed.get("max_dp_bonus", 0.0)), 15.0, 0.0001, "fixed max_dp_bonus stacks additively")
	t.assert_near(float(fixed.get("victory_gold_multiplier", 1.0)), 1.05, 0.0001, "victory gold multiplier is applied")
	t.assert_eq(resource_manager.max_dp, 115, "ResourceManager max_dp receives synergy max_dp_bonus")
	t.assert_eq(synergy_manager.apply_victory_gold_bonus(100), 105, "victory gold bonus applies multiplier")


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
	resource_manager.reset_dp(20, 100)
	if synergy_manager.is_test_synergy_override_enabled():
		synergy_manager.clear_test_synergy_override()
	else:
		synergy_manager.recalculate()


func _autoload(node_name: String):
	return root.get_node_or_null(node_name)
