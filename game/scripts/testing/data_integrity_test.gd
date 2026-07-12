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
	_test_waves(registry)

	t.finish(self)


func _test_config(registry: Node) -> void:
	var required_keys := [
		"max_character_level",
		"max_deployment_points",
		"initial_deployment_points",
		"roguelike_max_rounds",
		"synergy_layer_per_star",
		"synergy_max_layer",
	]
	for key in required_keys:
		t.assert_true(registry.get_config(key, null) != null, "config has %s" % key)
	t.assert_true(int(registry.get_config("max_character_level", 0)) > 0, "max_character_level is positive")
	t.assert_true(int(registry.get_config("max_deployment_points", 0)) > 0, "max_deployment_points is positive")
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
		for skill_id in _string_array(data.get("skills", [])):
			t.assert_true(registry.get_all_skill_ids().has(skill_id), "enemy skill exists: %s -> %s" % [enemy_id, skill_id])


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


func _test_waves(registry: Node) -> void:
	var waves: Array = registry.get_waves_for_battle("")
	t.assert_true(waves is Array, "waves can be queried by battle id")


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
