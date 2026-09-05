# enemy_roster_test.gd - Enemy chapter, wave and combat mechanic coverage.
extends Node

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("EnemyRoster")
var grid: GridSystem


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	DataRegistry.ensure_loaded()
	_test_scripted_encounters()

	grid = GridSystem.new()
	grid.draw_grid = false
	grid.debug_unit_body_radii = false
	grid.debug_attack_ranges = false
	grid.debug_collision_prediction = false
	grid.debug_ui_hits = false
	add_child(grid)
	await get_tree().process_frame

	_test_enemy_target_priorities()
	_test_target_priority_matrix()
	_test_plague_and_timed_modifier()
	_test_attack_triggered_mechanics()
	_test_shieldguard_and_black_knight()
	_test_banshee_debuff()
	_test_demon_mob_mechanics()
	_test_slime_split()
	_test_boss_phases()
	_test_boss_active_mechanics()

	_clear_units()
	grid.queue_free()
	t.finish(get_tree())


func _test_scripted_encounters() -> void:
	var generator := MapGenerator.new()
	var expected_chapters := {
		1: "corrupted_border",
		2: "city_of_dead",
		3: "abyssal_court",
	}
	for floor_number in [1, 2, 3]:
		var map: Array = generator.generate_floor_map(floor_number)
		var combat_nodes := map.filter(func(node): return str((node as Dictionary).get("type", "")) in ["battle", "elite", "boss"])
		t.assert_true(not combat_nodes.is_empty(), "floor has combat encounters: %d" % floor_number)
		for node_value in combat_nodes:
			var node: Dictionary = node_value
			var waves: Array = node.get("scripted_waves", [])
			t.assert_eq(waves.size(), int(node.get("waves", 0)), "node wave count matches scripted waves: %s" % node.get("battle_id", ""))
			t.assert_true(not waves.is_empty(), "node has scripted waves: %s" % node.get("battle_id", ""))
			for wave_value in waves:
				for template_value in wave_value as Array:
					var template: Dictionary = template_value
					t.assert_eq(str(template.get("chapter_id", "")), expected_chapters[floor_number], "scripted enemy belongs to floor chapter")

	var sample_node := generator.build_encounter_node(1, "battle", 1)
	BattleManager.setup_battle([], sample_node.get("enemy_pool", []), 99, false, sample_node.get("scripted_waves", []))
	var preview := BattleManager.get_next_wave_preview_enemies()
	t.assert_eq(BattleManager.total_waves, 2, "scripted battle overrides random wave count")
	t.assert_eq(preview.size(), 3, "first designed wave contains three enemies")
	for template in preview:
		t.assert_eq(str((template as Dictionary).get("enemy_id", "")), "plague_goblin", "scripted preview preserves enemy order")


func _test_enemy_target_priorities() -> void:
	_clear_units()
	var low_def := _spawn_hero(Vector2i(3, 1), 100, 12, 1)
	var high_def := _spawn_hero(Vector2i(4, 2), 100, 12, 10)
	var spearman := _spawn_enemy("blackfeather_spearman", Vector2i(7, 1))
	spearman.ai_controller._find_target()
	t.assert_eq(spearman.target, low_def, "blackfeather spearman targets lowest defense hero")

	var ghoul := _spawn_enemy("starving_ghoul", Vector2i(7, 2))
	low_def.current_hp = 90
	high_def.current_hp = 30
	ghoul.ai_controller._find_target()
	t.assert_eq(ghoul.target, high_def, "ghoul targets lowest hp ratio hero")


func _test_target_priority_matrix() -> void:
	_clear_units()
	var near := _spawn_priority_hero(Vector2i(6, 1), {
		"max_hp": 100, "current_hp": 20, "attack": 10, "defense": 1,
		"attack_speed": 0.5, "move_speed": 1.0, "attack_range": 1.0, "search_range": 3.0,
		"level": 1, "star_level": 1, "airborne": false,
	})
	var middle := _spawn_priority_hero(Vector2i(4, 2), {
		"max_hp": 200, "current_hp": 100, "attack": 20, "defense": 5,
		"attack_speed": 1.0, "move_speed": 2.0, "attack_range": 2.0, "search_range": 6.0,
		"level": 5, "star_level": 2, "airborne": false,
	})
	var far := _spawn_priority_hero(Vector2i(2, 1), {
		"max_hp": 300, "current_hp": 270, "attack": 30, "defense": 9,
		"attack_speed": 1.5, "move_speed": 3.0, "attack_range": 3.0, "search_range": 9.0,
		"level": 9, "star_level": 3, "airborne": true,
	})
	var selector := _spawn_enemy("blackfeather_spearman", Vector2i(7, 1))
	selector.search_range = 8.0

	var expected_targets := {
		"nearest": near,
		"farthest": far,
		"lowest_hp": near,
		"highest_hp": far,
		"lowest_hp_ratio": near,
		"highest_hp_ratio": far,
		"lowest_max_hp": near,
		"highest_max_hp": far,
		"lowest_missing_hp": far,
		"highest_missing_hp": middle,
		"lowest_attack": near,
		"highest_attack": far,
		"lowest_defense": near,
		"highest_defense": far,
		"lowest_attack_speed": near,
		"highest_attack_speed": far,
		"lowest_move_speed": near,
		"highest_move_speed": far,
		"lowest_attack_range": near,
		"highest_attack_range": far,
		"lowest_search_range": near,
		"highest_search_range": far,
		"lowest_level": near,
		"highest_level": far,
		"lowest_star_level": near,
		"highest_star_level": far,
		"ground_first": near,
		"airborne_first": far,
	}
	for priority_key in expected_targets:
		selector.target_priority = priority_key
		selector.target = null
		selector.ai_controller._find_target()
		t.assert_eq(selector.target, expected_targets[priority_key], "target priority selects expected unit: %s" % priority_key)

	selector.target_priority = "random"
	selector.ai_controller._find_target()
	t.assert_true(selector.target in [near, middle, far], "random target priority selects a valid candidate")

	var aliases := {
		"highest_atk": "highest_attack",
		"lowest_atk": "lowest_attack",
		"highest_def": "highest_defense",
		"lowest_def": "lowest_defense",
		"highest_star": "highest_star_level",
		"lowest_star": "lowest_star_level",
		"most_injured": "highest_missing_hp",
		"least_injured": "lowest_missing_hp",
		"air-first": "airborne_first",
		"grounded first": "ground_first",
	}
	for alias_key in aliases:
		t.assert_eq(ClassTemplate.normalize_target_priority_key(alias_key), aliases[alias_key], "target priority alias is normalized: %s" % alias_key)
	t.assert_eq(ClassTemplate.normalize_target_priority_key("not_a_priority"), "nearest", "unknown target priority falls back to nearest")

	for index in range(ClassTemplate.TARGET_PRIORITY_KEYS.size()):
		var canonical_key: String = ClassTemplate.TARGET_PRIORITY_KEYS[index]
		t.assert_eq(ClassTemplate.target_priority_from_key(canonical_key), index, "target priority key round-trips: %s" % canonical_key)
	t.assert_eq(ClassTemplate.TargetPriority.NEAREST, 0, "legacy nearest enum value is preserved")
	t.assert_eq(ClassTemplate.TargetPriority.LOWEST_HP, 1, "legacy lowest hp enum value is preserved")
	t.assert_eq(ClassTemplate.TargetPriority.HIGHEST_ATK, 2, "legacy highest attack enum value is preserved")
	t.assert_eq(ClassTemplate.TargetPriority.FARTHEST, 3, "legacy farthest enum value is preserved")
	t.assert_eq(ClassTemplate.TargetPriority.RANDOM, 4, "legacy random enum value is preserved")


func _test_plague_and_timed_modifier() -> void:
	_clear_units()
	var hero := _spawn_hero(Vector2i(4, 1), 100, 10, 2)
	var goblin := _spawn_enemy("plague_goblin", Vector2i(5, 1))
	var passive = goblin.get_combat_passives()[0]
	for _i in range(3):
		passive.after_basic_attack({"target": hero})
	t.assert_true(hero.has_timed_combat_modifier("enemy_plague"), "three plague hits apply healing reduction")
	hero.current_hp = 50
	var healed := hero.heal(20)
	t.assert_eq(healed, 13, "plague reduces incoming healing to configured multiplier")
	hero._update_combat_statuses(5.0)
	t.assert_false(hero.has_timed_combat_modifier("enemy_plague"), "plague expires after its duration")


func _test_shieldguard_and_black_knight() -> void:
	_clear_units()
	var attacker := _spawn_hero(Vector2i(3, 1), 100, 30, 0)
	var guard := _spawn_enemy("skeleton_shieldguard", Vector2i(4, 1))
	var front_damage := guard.receive_attack_damage(30, 0.0, attacker)
	attacker.grid_position = Vector2i(5, 1)
	var rear_damage := guard.receive_attack_damage(30, 0.0, attacker)
	t.assert_true(front_damage < rear_damage, "shieldguard reduces attacks from the front")

	var knight := _spawn_enemy("abyssal_black_knight", Vector2i(6, 1))
	var hp_before := knight.current_hp
	knight.receive_attack_damage(30, 0.0, attacker)
	t.assert_eq(knight.current_hp, hp_before, "black knight shield absorbs initial damage")
	knight.receive_attack_damage(120, 0.0, attacker)
	var state: Dictionary = knight.get_combat_passives()[0].get_debug_state()
	t.assert_eq(int(state.get("shield_remaining", -1)), 0, "black knight shield can be broken")
	t.assert_true(knight.attack > knight.base_attack, "black knight gains attack after shield break")
	t.assert_true(knight.defense < knight.base_defense, "black knight loses defense after shield break")


func _test_attack_triggered_mechanics() -> void:
	_clear_units()
	var primary := _spawn_hero(Vector2i(4, 1), 140, 10, 0)
	var nearby := _spawn_hero(Vector2i(4, 2), 140, 10, 0)
	var ogre := _spawn_enemy("ogre_butcher", Vector2i(5, 1))
	var ogre_passive = ogre.get_combat_passives()[0]
	for _i in range(3):
		ogre_passive.after_basic_attack({"target": primary})
	t.assert_true(primary.current_hp < primary.max_hp, "ogre third attack sweeps primary target area")
	t.assert_true(nearby.current_hp < nearby.max_hp, "ogre sweep hits adjacent heroes")

	var archer := _spawn_enemy("bonebow_hunter", Vector2i(7, 1))
	var archer_passive = archer.get_combat_passives()[0]
	var first_context := {"target": primary, "damage": 20}
	var second_context := {"target": primary, "damage": 20}
	archer_passive.before_deal_damage(first_context)
	archer_passive.before_deal_damage(second_context)
	t.assert_true(int(second_context["damage"]) > int(first_context["damage"]), "bonebow gains damage while focusing the same target")

	var ghoul := _spawn_enemy("starving_ghoul", Vector2i(6, 2))
	ghoul.current_hp = ghoul.max_hp - 20
	primary.current_hp = int(primary.max_hp * 0.4)
	var ghoul_hp_before := ghoul.current_hp
	ghoul.get_combat_passives()[0].after_deal_damage({"target": primary, "damage_dealt": 20})
	t.assert_true(ghoul.current_hp > ghoul_hp_before, "ghoul steals life from wounded heroes")


func _test_banshee_debuff() -> void:
	_clear_units()
	var hero := _spawn_hero(Vector2i(4, 1), 100, 10, 2)
	var banshee := _spawn_enemy("wailing_banshee", Vector2i(5, 1))
	var speed_before := hero.attack_speed
	banshee.get_combat_passives()[0].on_tick({"delta": 6.1})
	t.assert_true(hero.has_timed_combat_modifier("banshee_wail"), "banshee applies area attack-speed debuff")
	t.assert_true(hero.attack_speed < speed_before, "banshee debuff lowers attack speed")


func _test_demon_mob_mechanics() -> void:
	_clear_units()
	var low_attack := _spawn_hero(Vector2i(3, 1), 100, 10, 2)
	var high_attack := _spawn_hero(Vector2i(3, 2), 100, 30, 2)
	var inquisitor := _spawn_enemy("succubus_inquisitor", Vector2i(6, 1))
	inquisitor.get_combat_passives()[0].on_tick({"delta": 5.1})
	t.assert_false(low_attack.has_timed_combat_modifier("inquisitor_question"), "inquisitor leaves lower-attack hero unmarked")
	t.assert_true(high_attack.has_timed_combat_modifier("inquisitor_question"), "inquisitor questions highest-attack hero")
	t.assert_true(high_attack.attack < high_attack.base_attack, "inquisitor question lowers attack")

	var imp := _spawn_enemy("bloodpact_imp", Vector2i(6, 2))
	t.assert_true(imp.airborne, "imp starts combat airborne")
	imp.get_combat_passives()[0].on_tick({"delta": 3.0})
	t.assert_false(imp.airborne, "imp lands after opening swoop duration")

	var gargoyle := _spawn_enemy("court_gargoyle", Vector2i(7, 1))
	gargoyle.ai_controller.state = "attacking"
	gargoyle.get_combat_passives()[0].on_tick({"delta": 0.0})
	t.assert_false(gargoyle.airborne, "gargoyle lands while attacking")
	t.assert_true(gargoyle.defense > gargoyle.base_defense, "grounded gargoyle gains defense")
	gargoyle.ai_controller.state = "moving"
	gargoyle.get_combat_passives()[0].on_tick({"delta": 0.0})
	t.assert_true(gargoyle.airborne, "gargoyle returns to flight while moving")


func _test_slime_split() -> void:
	_clear_units()
	var slime := _spawn_enemy("corrupted_slime", Vector2i(5, 1))
	slime._die()
	grid._update_enemy_spawn_queue(1.0)
	var split_count := 0
	for unit_value in grid.all_units:
		var enemy := unit_value as EnemyUnit
		if enemy and enemy.enemy_id == "corrupted_slime_small":
			split_count += 1
	t.assert_eq(split_count, 2, "corrupted slime splits into two hidden add templates")


func _test_boss_phases() -> void:
	_clear_units()
	var king := _spawn_enemy("plaguecrown_goblin_king", Vector2i(6, 1))
	king.current_hp = int(round(float(king.max_hp) * 0.25))
	king.get_combat_passives()[0].on_tick({"delta": 0.0})
	var king_state: Dictionary = king.get_combat_passives()[0].get_debug_state()
	t.assert_eq(int(king_state.get("phase", 0)), 3, "goblin king enters rage phase below 30 percent hp")
	t.assert_true(king.attack_speed > king.base_attack_speed, "goblin king rage increases attack speed")

	var cemetery_knight := _spawn_enemy("headless_cemetery_knight", Vector2i(6, 2))
	cemetery_knight.current_hp = int(round(float(cemetery_knight.max_hp) * 0.6))
	cemetery_knight.get_combat_passives()[0].on_tick({"delta": 0.0})
	var cemetery_state: Dictionary = cemetery_knight.get_combat_passives()[0].get_debug_state()
	t.assert_eq(int(cemetery_state.get("phase", 0)), 2, "cemetery knight enters summon phase below 65 percent hp")
	t.assert_true(int(cemetery_state.get("summons_created", 0)) >= 2, "cemetery knight queues two shieldguards")

	var dragon := _spawn_enemy("fallen_black_dragon", Vector2i(7, 1))
	dragon.current_hp = int(round(float(dragon.max_hp) * 0.65))
	dragon.get_combat_passives()[0].on_tick({"delta": 0.0})
	var dragon_state: Dictionary = dragon.get_combat_passives()[0].get_debug_state()
	t.assert_eq(int(dragon_state.get("phase", 0)), 2, "black dragon enters flight phase below 70 percent hp")
	t.assert_true(bool(dragon_state.get("airborne", false)), "black dragon becomes airborne in phase two")
	dragon.current_hp = int(round(float(dragon.max_hp) * 0.3))
	dragon.get_combat_passives()[0].on_tick({"delta": 0.0})
	dragon_state = dragon.get_combat_passives()[0].get_debug_state()
	t.assert_eq(int(dragon_state.get("phase", 0)), 3, "black dragon enters dive phase below 35 percent hp")
	t.assert_false(bool(dragon_state.get("airborne", true)), "broken-wing phase returns black dragon to ground")


func _test_boss_active_mechanics() -> void:
	_clear_units()
	var goblin := _spawn_enemy("plague_goblin", Vector2i(5, 1))
	var king := _spawn_enemy("plaguecrown_goblin_king", Vector2i(6, 1))
	var goblin_speed := goblin.attack_speed
	king.get_combat_passives()[0].on_tick({"delta": 0.2})
	t.assert_true(goblin.attack_speed > goblin_speed, "goblin king command aura buffs nearby goblins")
	king.get_combat_passives()[0].on_tick({"delta": 7.0})
	var king_state: Dictionary = king.get_combat_passives()[0].get_debug_state()
	t.assert_true(int(king_state.get("summons_created", 0)) >= 1, "goblin king summons plague goblins")

	_clear_units()
	var breath_target := _spawn_hero(Vector2i(3, 1), 240, 20, 0)
	var same_line := _spawn_hero(Vector2i(2, 2), 240, 20, 0)
	var safe_line := _spawn_hero(Vector2i(2, 3), 240, 20, 0)
	var dragon := _spawn_enemy("fallen_black_dragon", Vector2i(7, 1))
	dragon.target = breath_target
	dragon.get_combat_passives()[0].on_tick({"delta": 7.1})
	t.assert_true(breath_target.current_hp < breath_target.max_hp, "black dragon breath damages selected line")
	t.assert_true(same_line.current_hp < same_line.max_hp, "black dragon breath covers configured adjacent row")
	t.assert_eq(safe_line.current_hp, safe_line.max_hp, "black dragon breath leaves distant row safe")

	dragon.current_hp = int(round(float(dragon.max_hp) * 0.3))
	dragon.get_combat_passives()[0].on_tick({"delta": 0.0})
	var farthest_hp := safe_line.current_hp
	dragon.get_combat_passives()[0].on_tick({"delta": 5.1})
	t.assert_true(safe_line.current_hp < farthest_hp, "black dragon dive strikes farthest hero in final phase")


func _spawn_enemy(enemy_id: String, cell: Vector2i) -> EnemyUnit:
	var enemy := EnemyUnit.new()
	enemy.setup_from_template(DataRegistry.get_enemy(enemy_id))
	enemy.grid_position = cell
	enemy.global_position = grid.grid_to_world(cell)
	grid.all_units.append(enemy)
	grid.add_child(enemy)
	enemy.set_process(false)
	return enemy


func _spawn_hero(cell: Vector2i, hp: int, atk: int, defense: int) -> UnitBase:
	var hero := UnitBase.new()
	hero.team = "player"
	hero.unit_name = "测试英雄"
	hero.max_hp = hp
	hero.current_hp = hp
	hero.attack = atk
	hero.defense = defense
	hero.attack_speed = 1.0
	hero.move_speed = 1.0
	hero.attack_range = 1.0
	hero.search_range = 8.0
	hero.set_base_stats_from_current()
	hero.grid_position = cell
	hero.global_position = grid.grid_to_world(cell)
	grid.all_units.append(hero)
	grid.add_child(hero)
	hero.set_process(false)
	BattleManager.register_player_unit(hero)
	return hero


func _spawn_priority_hero(cell: Vector2i, stats: Dictionary) -> HeroUnit:
	var hero := HeroUnit.new()
	hero.unit_name = "优先级测试英雄"
	hero.max_hp = int(stats.get("max_hp", 100))
	hero.current_hp = int(stats.get("current_hp", hero.max_hp))
	hero.attack = int(stats.get("attack", 10))
	hero.defense = int(stats.get("defense", 0))
	hero.attack_speed = float(stats.get("attack_speed", 1.0))
	hero.move_speed = float(stats.get("move_speed", 1.0))
	hero.attack_range = float(stats.get("attack_range", 1.0))
	hero.search_range = float(stats.get("search_range", 5.0))
	hero.level = int(stats.get("level", 1))
	hero.star_level = int(stats.get("star_level", 1))
	hero.airborne = bool(stats.get("airborne", false))
	hero.set_base_stats_from_current()
	hero.grid_position = cell
	hero.global_position = grid.grid_to_world(cell)
	grid.all_units.append(hero)
	grid.add_child(hero)
	hero.set_process(false)
	BattleManager.register_player_unit(hero)
	return hero


func _clear_units() -> void:
	if not grid:
		BattleManager.player_units.clear()
		BattleManager.enemy_units.clear()
		return
	grid.clear_enemy_spawn_queue()
	for unit_value in grid.all_units.duplicate():
		if not is_instance_valid(unit_value):
			continue
		grid.remove_unit(unit_value)
		unit_value.free()
	grid.all_units.clear()
	BattleManager.player_units.clear()
	BattleManager.enemy_units.clear()
	BattleManager.state = BattleManager.BattleState.PREPARING
