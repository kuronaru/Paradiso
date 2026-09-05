# data_integrity_test.gd - Verifies JSON balance data and ID references.
extends SceneTree

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("DataIntegrity")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var registry := _registry()
	t.assert_true(registry != null, "DataRegistry autoload exists")
	if not registry:
		t.finish(self)
		return
	registry.ensure_loaded()

	_test_config(registry)
	_test_classes(registry)
	_test_skills(registry)
	_test_enemies(registry)
	_test_synergies(registry)
	_test_auto_traits(registry)
	_test_waves(registry)

	t.finish(self)


func _test_config(registry: Node) -> void:
	var required_keys := [
		"max_character_level",
		"max_deployment_points",
		"initial_deployment_points",
		"roguelike_max_rounds",
		"roguelike_player_max_life",
		"battle_grid_width",
		"battle_grid_height",
		"tavern_base_income",
		"tavern_income_per_round",
		"enemy_base_damage",
		"hero_revive_delay",
		"synergy_layer_per_star",
		"synergy_max_layer",
	]
	for key in required_keys:
		t.assert_true(registry.get_config(key, null) != null, "config has %s" % key)
	t.assert_true(int(registry.get_config("max_character_level", 0)) > 0, "max_character_level is positive")
	t.assert_true(int(registry.get_config("max_deployment_points", 0)) > 0, "max_deployment_points is positive")
	t.assert_true(int(registry.get_config("roguelike_player_max_life", 0)) > 0, "roguelike_player_max_life is positive")
	t.assert_eq(int(registry.get_config("battle_grid_width", 0)), 9, "battle grid width is 9")
	t.assert_eq(int(registry.get_config("battle_grid_height", 0)), 4, "battle grid height is 4")
	t.assert_eq(int(registry.get_config("tavern_base_income", 0)), 4, "tavern base income starts at 4")
	t.assert_eq(int(registry.get_config("tavern_income_per_round", 0)), 1, "tavern income grows by 1 per round")
	var recruit_costs: Dictionary = registry.get_config_section("tavern_recruit_cost_by_tier")
	t.assert_eq(int(recruit_costs.get("1", 0)), 2, "low-tier recruit price is 2")
	t.assert_eq(int(recruit_costs.get("2", 0)), 3, "mid-tier recruit price is 3")
	t.assert_eq(int(recruit_costs.get("3", 0)), 4, "high-tier recruit price is 4")
	t.assert_true(registry.get_config_section("synergy_default_modifiers").has("attack_multiplier"), "default synergy modifiers include attack_multiplier")


func _test_classes(registry: Node) -> void:
	var class_ids: Array = registry.get_all_class_ids()
	t.assert_true(not class_ids.is_empty(), "classes table is not empty")
	var synergy_ids := _string_set(registry.get_all_synergy_ids())
	for class_id in class_ids:
		var data: Dictionary = registry.get_class_data(class_id)
		t.assert_false(data.is_empty(), "class data exists: %s" % class_id)
		t.assert_eq(str(data.get("class_id", "")), class_id, "class_id field matches key: %s" % class_id)
		t.assert_true(str(data.get("job_name", data.get("name", ""))).strip_edges() != "", "class has display name: %s" % class_id)
		t.assert_true(int(data.get("deploy_cost", 0)) > 0, "class deploy_cost positive: %s" % class_id)
		t.assert_true(float(data.get("base_hp", data.get("hp", 0))) > 0.0, "class hp positive: %s" % class_id)
		t.assert_true(float(data.get("base_atk", data.get("atk", 0))) >= 0.0, "class atk non-negative: %s" % class_id)
		t.assert_true(float(data.get("base_def", data.get("def", 0))) >= 0.0, "class def non-negative: %s" % class_id)
		t.assert_true(float(data.get("attack_speed", 0.0)) > 0.0, "class attack_speed positive: %s" % class_id)
		t.assert_true(float(data.get("move_speed", 0.0)) >= 0.0, "class move_speed non-negative: %s" % class_id)
		t.assert_true(float(data.get("attack_range", 0.0)) >= 0.0, "class attack_range non-negative: %s" % class_id)
		t.assert_true(float(data.get("search_range", 0.0)) >= 0.0, "class search_range non-negative: %s" % class_id)

		var template := ClassDefinitions.get_template(class_id)
		t.assert_eq(template.class_id, class_id, "ClassDefinitions returns canonical template: %s" % class_id)

		var group_id := "main_%s" % str(data.get("class_group", ""))
		t.assert_true(synergy_ids.has(group_id), "class main synergy exists: %s -> %s" % [class_id, group_id])
		for tag in _string_array(data.get("stat_tags", [])):
			t.assert_true(synergy_ids.has("stat_%s" % tag.to_lower()), "class stat synergy exists: %s -> %s" % [class_id, tag])
		for tag in _string_array(data.get("alignment_tags", [])):
			t.assert_true(synergy_ids.has("alignment_%s" % tag.to_lower()), "class alignment synergy exists: %s -> %s" % [class_id, tag])
		for tag in _string_array(data.get("trait_tags", [])):
			t.assert_true(synergy_ids.has("trait_%s" % tag.to_lower()), "class trait synergy exists: %s -> %s" % [class_id, tag])
		for skill_id in _string_array(data.get("skill_ids", [])):
			t.assert_true(registry.get_all_skill_ids().has(skill_id), "class skill exists: %s -> %s" % [class_id, skill_id])

	for alias in ClassDefinitions.LEGACY_ALIASES.keys():
		t.assert_true(ClassDefinitions.has_class_id(str(alias)), "legacy class alias is accepted: %s" % alias)


func _test_skills(registry: Node) -> void:
	SkillData.reload_registry()
	var skill_ids: Array = registry.get_all_skill_ids()
	t.assert_true(not skill_ids.is_empty(), "skills table is not empty")
	for skill_id in skill_ids:
		var data: Dictionary = registry.get_skill(skill_id)
		t.assert_false(data.is_empty(), "skill data exists: %s" % skill_id)
		t.assert_eq(str(data.get("skill_id", "")), skill_id, "skill_id field matches key: %s" % skill_id)
		t.assert_true(str(data.get("skill_name", data.get("name", ""))).strip_edges() != "", "skill has display name: %s" % skill_id)
		t.assert_true(float(data.get("cooldown", 0.0)) >= 0.0, "skill cooldown non-negative: %s" % skill_id)
		t.assert_true(int(data.get("dp_cost", 0)) >= 0, "skill dp_cost non-negative: %s" % skill_id)
		t.assert_true(float(data.get("damage_multiplier", 0.0)) >= 0.0, "skill damage multiplier non-negative: %s" % skill_id)
		t.assert_true(float(data.get("aoe_radius", 0.0)) >= 0.0, "skill aoe radius non-negative: %s" % skill_id)
		t.assert_true(float(data.get("heal_amount", 0.0)) >= 0.0, "skill heal amount non-negative: %s" % skill_id)
		var skill := SkillData.get_skill(skill_id)
		t.assert_true(skill != null, "SkillData resolves skill: %s" % skill_id)


func _test_enemies(registry: Node) -> void:
	var pool: Array = registry.get_enemy_pool()
	t.assert_true(not pool.is_empty(), "enemy pool is not empty")
	t.assert_eq(pool.size(), 15, "enemy roster exposes 12 regular/elite enemies and 3 bosses")
	var chapter_counts := {}
	var rarity_counts := {"common": 0, "elite": 0, "boss": 0}
	for enemy in pool:
		var data: Dictionary = enemy
		var enemy_id := str(data.get("enemy_id", data.get("name", "")))
		t.assert_true(enemy_id.strip_edges() != "", "enemy has id/name")
		t.assert_true(str(data.get("name", "")).strip_edges() != "", "enemy has display name: %s" % enemy_id)
		t.assert_true(float(data.get("hp", 0.0)) > 0.0, "enemy hp positive: %s" % enemy_id)
		t.assert_true(float(data.get("atk", 0.0)) >= 0.0, "enemy atk non-negative: %s" % enemy_id)
		t.assert_true(float(data.get("def", 0.0)) >= 0.0, "enemy def non-negative: %s" % enemy_id)
		t.assert_true(float(data.get("attack_speed", 0.0)) > 0.0, "enemy attack_speed positive: %s" % enemy_id)
		t.assert_true(float(data.get("move_speed", 0.0)) >= 0.0, "enemy move_speed non-negative: %s" % enemy_id)
		t.assert_true(float(data.get("attack_range", 0.0)) >= 0.0, "enemy attack_range non-negative: %s" % enemy_id)
		t.assert_true(float(data.get("search_range", 0.0)) >= 0.0, "enemy search_range non-negative: %s" % enemy_id)
		var chapter_id := str(data.get("chapter_id", ""))
		var rarity := str(data.get("rarity", ""))
		t.assert_true(chapter_id in ["corrupted_border", "city_of_dead", "abyssal_court"], "enemy chapter is valid: %s" % enemy_id)
		t.assert_true(rarity in ["common", "elite", "boss"], "visible enemy rarity is valid: %s" % enemy_id)
		chapter_counts[chapter_id] = int(chapter_counts.get(chapter_id, 0)) + 1
		rarity_counts[rarity] = int(rarity_counts.get(rarity, 0)) + 1
		t.assert_true(str(data.get("combat_role", "")).strip_edges() != "", "enemy combat role set: %s" % enemy_id)
		t.assert_true(data.get("tags", []) is Array and not data.get("tags", []).is_empty(), "enemy tags set: %s" % enemy_id)
		for skill_id in _string_array(data.get("skills", [])):
			t.assert_true(registry.get_all_skill_ids().has(skill_id), "enemy skill exists: %s -> %s" % [enemy_id, skill_id])
		for passive in _dictionary_array(data.get("passives", [])):
			var script_path := str(passive.get("script", passive.get("script_path", "")))
			t.assert_true(script_path != "" and ResourceLoader.exists(script_path), "enemy passive script exists: %s" % enemy_id)
	for chapter_id in ["corrupted_border", "city_of_dead", "abyssal_court"]:
		t.assert_eq(int(chapter_counts.get(chapter_id, 0)), 5, "chapter exposes five roster enemies: %s" % chapter_id)
	t.assert_eq(int(rarity_counts.get("common", 0)), 9, "roster has nine common enemies")
	t.assert_eq(int(rarity_counts.get("elite", 0)), 3, "roster has three elite enemies")
	t.assert_eq(int(rarity_counts.get("boss", 0)), 3, "roster has three bosses")
	var split_add: Dictionary = registry.get_enemy("corrupted_slime_small")
	t.assert_true(bool(split_add.get("hidden", false)), "slime split add remains loadable but hidden from roster")


func _test_synergies(registry: Node) -> void:
	var synergy_ids: Array = registry.get_all_synergy_ids()
	t.assert_true(not synergy_ids.is_empty(), "synergy table is not empty")
	for synergy_id in synergy_ids:
		var data: Dictionary = registry.get_synergy(synergy_id)
		t.assert_false(data.is_empty(), "synergy data exists: %s" % synergy_id)
		t.assert_eq(str(data.get("synergy_id", "")), synergy_id, "synergy_id field matches key: %s" % synergy_id)
		t.assert_true(str(data.get("display_name", data.get("name", ""))).strip_edges() != "", "synergy has display name: %s" % synergy_id)
		t.assert_true(str(data.get("type", "")).strip_edges() != "", "synergy has type: %s" % synergy_id)
		var thresholds := _int_array(data.get("thresholds", []))
		t.assert_true(not thresholds.is_empty(), "synergy thresholds not empty: %s" % synergy_id)
		var previous := -999999
		for threshold in thresholds:
			t.assert_true(threshold > previous, "synergy thresholds strictly ascending: %s" % synergy_id)
			previous = threshold
		for modifier in _dictionary_array(data.get("scalable_modifiers", [])):
			t.assert_true(str(modifier.get("stat", "")).strip_edges() != "", "synergy scalable modifier stat set: %s" % synergy_id)
			t.assert_true(int(modifier.get("min_tier", 0)) >= 0, "synergy scalable modifier min_tier non-negative: %s" % synergy_id)
		for modifier in _dictionary_array(data.get("fixed_modifiers", [])):
			t.assert_true(str(modifier.get("stat", "")).strip_edges() != "", "synergy fixed modifier stat set: %s" % synergy_id)
			t.assert_true(int(modifier.get("min_tier", 0)) >= 0, "synergy fixed modifier min_tier non-negative: %s" % synergy_id)


func _test_auto_traits(registry: Node) -> void:
	var enabled_synergies := _string_set(registry.get_enabled_synergy_ids())
	var disabled_synergies := _string_set(registry.get_disabled_synergy_ids())
	for disabled_id in ["main_anmarit", "main_remolino_law", "main_kroen_trench", "main_tro_poem"]:
		t.assert_true(disabled_synergies.has(disabled_id), "disabled synergy retained: %s" % disabled_id)
		t.assert_false(registry.get_synergy(disabled_id).is_empty(), "disabled synergy data remains loadable: %s" % disabled_id)

	var template_ids: Array = registry.get_all_auto_trait_template_ids()
	var trait_ids: Array = registry.get_all_auto_trait_ids()
	t.assert_true(not template_ids.is_empty(), "auto trait templates are registered")
	t.assert_true(not trait_ids.is_empty(), "default auto traits are registered")
	var covered_templates: Dictionary = {}
	var square_placeholder_pattern := RegEx.new()
	square_placeholder_pattern.compile("\\[[^\\]]+\\]")
	for trait_id in trait_ids:
		var trait_data: Dictionary = registry.get_auto_trait(trait_id)
		var template_id := str(trait_data.get("template_id", ""))
		var description := str(trait_data.get("description", ""))
		t.assert_true(template_id in template_ids, "trait references template: %s -> %s" % [trait_id, template_id])
		t.assert_false(trait_data.has("display_name"), "auto trait no longer stores a separate display name: %s" % trait_id)
		t.assert_true(description.strip_edges() != "", "auto trait stores its design-document description: %s" % trait_id)
		for placeholder_match in square_placeholder_pattern.search_all(description):
			var placeholder := placeholder_match.get_string()
			t.assert_true(placeholder in ["[X]", "[+X]"], "trait uses only canonical numeric placeholders: %s -> %s" % [trait_id, placeholder])
		covered_templates[template_id] = true
	t.assert_eq(
		str(registry.get_auto_trait("E_GRANT_FRONT_TRAIT").get("description", "")),
		"<战斗开始时>使身前一格英雄获得【某特质】",
		"delegated trait keeps the design-document trigger and nested-trait placeholder"
	)
	t.assert_eq(
		str(registry.get_auto_trait("E_STATUS_IN_RANGE").get("description", "")),
		"<战斗中>每当范围内[X]名敌人进入【某状态】时，有50%概率使已激活的【某羁绊】层数[+X]",
		"status trait keeps the design-document status, synergy, and number placeholders"
	)
	t.assert_true("50%概率" in str(registry.get_auto_trait("E_STATUS_IN_RANGE").get("description", "")), "probability percentages remain literal instead of becoming placeholders")

	var hero_ids: Array = registry.get_all_autochess_hero_ids()
	t.assert_true(not hero_ids.is_empty(), "autochess hero skeletons are registered")
	for hero_id in hero_ids:
		var hero_data: Dictionary = registry.get_autochess_hero(hero_id)
		var trait_tier := int(hero_data.get("trait_tier", 0))
		t.assert_true(trait_tier >= 1 and trait_tier <= 6, "hero fixed trait tier is 1-6: %s" % hero_id)
		t.assert_eq(int(ClassDefinitions.get_tavern_data(hero_id).get("shop_level", 0)), trait_tier, "hero tier binds its minimum tavern level: %s" % hero_id)
		var hero_synergies := _string_array(hero_data.get("autochess_synergy_ids", []))
		for synergy_id in hero_synergies:
			t.assert_false(registry.get_synergy(synergy_id).is_empty(), "hero synergy reference exists: %s -> %s" % [hero_id, synergy_id])
		var hero_traits := _string_array(hero_data.get("trait_ids", []))
		if "trait_flying" in hero_synergies:
			t.assert_eq(hero_synergies.size(), 1, "flying hero carries only the flying synergy: %s" % hero_id)
			t.assert_true(hero_traits.is_empty(), "flying hero carries no auto trait: %s" % hero_id)
		for trait_id in hero_traits:
			t.assert_true(trait_id in trait_ids, "hero trait exists: %s -> %s" % [hero_id, trait_id])
			var trait_description := str(registry.get_auto_trait(trait_id).get("description", ""))
			var placeholder_count := trait_description.count("[X]") + trait_description.count("[+X]")
			if placeholder_count > 0:
				var trait_params = hero_data.get("trait_params", {}).get(trait_id, {}) \
					if hero_data.get("trait_params", {}) is Dictionary else {}
				var description_values = trait_params.get("description_values", {}) \
					if trait_params is Dictionary else {}
				t.assert_true(description_values is Dictionary, "hero stores concrete description values: %s -> %s" % [hero_id, trait_id])
				if description_values is Dictionary:
					for value_tier in ["base", "advanced"]:
						var values = description_values.get(value_tier, [])
						t.assert_true(values is Array, "hero description values are an array: %s -> %s/%s" % [hero_id, trait_id, value_tier])
						if values is Array:
							t.assert_eq(values.size(), placeholder_count, "hero description values match placeholder count: %s -> %s/%s" % [hero_id, trait_id, value_tier])

	for equipment_id in registry.get_all_autochess_equipment_ids():
		var equipment: Dictionary = registry.get_autochess_equipment(equipment_id)
		t.assert_eq(str(equipment.get("equipment_id", "")), equipment_id, "autochess equipment id matches key: %s" % equipment_id)
		var main_synergy_id := str(equipment.get("main_synergy_id", ""))
		if main_synergy_id != "":
			t.assert_true(main_synergy_id.begins_with("main_"), "equipment mapping targets a main synergy: %s" % equipment_id)
			t.assert_true(enabled_synergies.has(main_synergy_id), "equipment mapping targets an enabled main synergy: %s" % equipment_id)


func _test_waves(registry: Node) -> void:
	var expected_battles := [
		"f1_battle1", "f1_battle2", "f1_elite1", "f1_boss",
		"f2_battle1", "f2_battle2", "f2_elite1", "f2_boss",
		"f3_battle1", "f3_battle2", "f3_elite1", "f3_elite2", "f3_boss",
	]
	var wave_ids: Array = registry.get_all_wave_ids()
	t.assert_true(not wave_ids.is_empty(), "scripted waves table is not empty")
	for wave_id in wave_ids:
		var wave: Dictionary = registry.get_wave(wave_id)
		var enemy_id := str(wave.get("enemy_id", ""))
		t.assert_true(str(wave.get("battle_id", "")) in expected_battles, "wave battle id is recognized: %s" % wave_id)
		t.assert_true(not registry.get_enemy(enemy_id).is_empty(), "wave enemy exists: %s -> %s" % [wave_id, enemy_id])
		t.assert_true(int(wave.get("wave_index", 0)) >= 1, "wave index positive: %s" % wave_id)
		t.assert_true(int(wave.get("count", 0)) >= 1, "wave count positive: %s" % wave_id)
	for battle_id in expected_battles:
		var records: Array = registry.get_waves_for_battle(battle_id)
		t.assert_true(not records.is_empty(), "battle has scripted wave records: %s" % battle_id)
		var wave_indexes := {}
		for record in records:
			wave_indexes[int((record as Dictionary).get("wave_index", 0))] = true
		t.assert_eq(wave_indexes.size(), 2, "battle has two designed waves: %s" % battle_id)


func _registry() -> Node:
	return root.get_node_or_null("DataRegistry")


func _string_set(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		result[str(value)] = true
	return result


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	elif value is PackedStringArray:
		for item in value:
			result.append(str(item))
	elif str(value).strip_edges() != "":
		for item in str(value).split(",", false):
			result.append(item.strip_edges())
	return result


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
				result.append(item)
	return result
