extends SceneTree

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("AutoTraitManager")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var manager := root.get_node_or_null("AutoTraitManager")
	var registry := root.get_node_or_null("DataRegistry")
	var synergy_manager := root.get_node_or_null("SynergyManager")
	var game_manager := root.get_node_or_null("GameManager")
	t.assert_true(manager != null, "AutoTraitManager autoload exists")
	t.assert_true(registry != null, "DataRegistry autoload exists")
	if not manager or not registry:
		t.finish(self)
		return

	var supported: Array[String] = manager.get_supported_template_ids()
	var registered: Array[String] = registry.get_all_auto_trait_template_ids()
	t.assert_eq(supported.size(), registered.size(), "runtime supports every registered template")
	for template_id in registered:
		t.assert_true(template_id in supported, "template runtime implemented: %s" % template_id)

	t.assert_eq(manager.preparation_value(1, 1), 1, "P(T1, 1-star) = 1")
	t.assert_eq(manager.preparation_value(6, 1), 2, "P(T6, 1-star) = 2")
	t.assert_eq(manager.preparation_value(6, 2), 4, "P(T6, 2-star) = 4")
	t.assert_eq(manager.burst_value(5, 1), 20, "B(T5, 1-star) = 20")
	t.assert_eq(manager.burst_value(5, 3), 40, "B(T5, 3-star) uses high-star factor 2")
	t.assert_eq(manager.engine_value(4, 1), 4, "E(T4, 1-star) = 4")
	t.assert_eq(manager.engine_value(4, 2), 8, "E(T4, 2-star) = 8")
	t.assert_eq(manager.get_purchase_cost("cleric_light_domain", 4), 4, "traitless flying hero keeps its normal recruit price")
	t.assert_eq(manager.get_merge_requirement("bard_valor"), 2, "CB_FAST_MERGE reduces merge requirement")
	t.assert_eq(manager.get_merge_requirement("fighter_champion"), 3, "normal merge requirement remains three")
	t.assert_eq(int(registry.get_config("synergy_layer_per_star", -1)), 0, "all synergy layers start at zero")
	for synergy_id in ["trait_flying", "trait_advanced", "trait_shapeshifter"]:
		t.assert_false(registry.is_synergy_stackable(synergy_id), "%s is marked non-stackable" % synergy_id)

	manager.reset_run_state()
	manager.notify_hero_acquired({"class_id": "shapeshifter", "star_level": 1, "shop_level": 6}, 1)
	t.assert_eq(int(manager.get_equipment_inventory().get("polymorph", 0)), 1, "shapeshifter acquisition grants exactly one polymorph")
	game_manager.is_roguelike_run = true
	game_manager.party.clear()
	game_manager.add_to_party("shapeshifter", 1, 6)
	var shapeshifter_id := int(game_manager.party[0].get("instance_id", -1))
	t.assert_eq(manager.grant_equipment("dragon_scale"), 1, "mapped main-synergy equipment can enter run inventory")
	t.assert_true(game_manager.equip_run_card(shapeshifter_id, "polymorph"), "polymorph can be equipped from run inventory")
	t.assert_true(game_manager.equip_run_card(shapeshifter_id, "dragon_scale"), "mapped equipment can be equipped beside polymorph")
	t.assert_eq((game_manager.party[0].get("equipment_ids", []) as Array).size(), 2, "equipped card stores both equipment ids")
	t.assert_true(game_manager.unequip_run_card(shapeshifter_id, "dragon_scale"), "mapped equipment can be unequipped")
	t.assert_eq(int(manager.get_equipment_inventory().get("dragon_scale", 0)), 1, "unequipped equipment returns to run inventory")
	manager.reset_run_state()
	game_manager.party.clear()
	game_manager.is_roguelike_run = false
	manager.notify_hero_acquired({"class_id": "cleric_war_domain", "star_level": 1, "shop_level": 3}, 1)
	t.assert_eq(manager.free_refresh_tokens, 2, "P_GAIN_REFRESH uses fixed T5 preparation value")
	t.assert_eq(manager.get_refresh_cost(1), 0, "free refresh token changes quoted cost to zero")
	manager.notify_tavern_refreshed()
	t.assert_eq(manager.free_refresh_tokens, 1, "successful quoted free refresh consumes one token")
	manager.notify_tavern_refreshed()
	t.assert_eq(manager.free_refresh_tokens, 1, "unquoted refresh notification does not consume a token")

	synergy_manager.reset_run_state()
	manager.reset_run_state()
	manager.notify_hero_acquired({"class_id": "monk_shadow", "star_level": 1, "shop_level": 3}, 1)
	var allocated_total: int = int(
		synergy_manager.get_synergy_layer("main_laferida")
		+ synergy_manager.get_synergy_layer("alignment_chaotic")
	)
	t.assert_eq(allocated_total, 20, "B_OWNER_ALL distributes one T5 total budget without duplication")

	manager.reset_run_state()
	game_manager.is_roguelike_run = true
	game_manager.party.clear()
	game_manager.run_gold = 0
	game_manager.add_to_party("druid_spores", 1, 3)
	var sell_refresh_id := int(game_manager.party[0].get("instance_id", -1))
	t.assert_true(game_manager.sell_run_card(sell_refresh_id, 1), "run card can be sold through the gameplay API")
	t.assert_eq(manager.free_refresh_tokens, 2, "P_SELL_REFRESH triggers through card sale")
	game_manager.party.clear()
	game_manager.add_to_party("fighter_battle_master", 1, 1)
	var special_recruit_id := int(game_manager.party[0].get("instance_id", -1))
	t.assert_true(game_manager.sell_run_card(special_recruit_id, 1), "special recruit owner can be sold")
	t.assert_eq(game_manager.party.size(), 1, "P_SELL_SPECIAL_RECRUIT adds one free fixed-tier hero")

	for disabled_id in registry.get_disabled_synergy_ids():
		t.assert_false(registry.is_synergy_enabled(disabled_id), "disabled synergy is excluded from runtime: %s" % disabled_id)
		t.assert_false(registry.get_synergy(disabled_id).is_empty(), "disabled synergy data is retained: %s" % disabled_id)

	manager.reset_run_state()
	synergy_manager.reset_run_state()
	game_manager.party.clear()
	game_manager.is_roguelike_run = false
	t.finish(self)
