# battle_rules_test.gd - Regression coverage for the base-defense roguelike rules.
extends Node

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("BattleRules")
var battle_manager: Node
var game_manager: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	battle_manager = get_tree().root.get_node_or_null("BattleManager")
	game_manager = get_tree().root.get_node_or_null("GameManager")
	t.assert_true(battle_manager != null, "BattleManager autoload exists")
	t.assert_true(game_manager != null, "GameManager autoload exists")
	if not battle_manager or not game_manager:
		t.finish(get_tree())
		return
	var grid := GridSystem.new()
	grid.blocked_cells = [Vector2i(5, 3)]
	add_child(grid)
	await get_tree().process_frame

	_test_grid_and_bases(grid)
	_test_spawn_sequence(grid)
	_test_life_and_breach(grid)
	_test_soul_revive(grid)
	_test_tavern_rules()

	grid.queue_free()
	t.finish(get_tree())


func _test_grid_and_bases(grid: GridSystem) -> void:
	t.assert_eq(grid.grid_width, 9, "battle grid width is reduced to 9")
	t.assert_eq(grid.grid_height, 4, "battle grid height is reduced to 4")
	t.assert_eq(grid.player_base_cells, [Vector2i(0, 1), Vector2i(0, 2)], "player bases occupy the two middle rows")
	t.assert_eq(grid.enemy_base_cells, [Vector2i(8, 1), Vector2i(8, 2)], "enemy bases occupy the two middle rows")
	t.assert_true(grid.can_place_at(Vector2i(7, 3)), "normal terrain across the battlefield is deployable")
	t.assert_false(grid.can_place_at(Vector2i(5, 3)), "blocked terrain is not deployable")
	t.assert_false(grid.can_place_at(Vector2i(0, 2)), "player base is not manually deployable")
	t.assert_false(grid.can_place_at(Vector2i(8, 2)), "enemy base is not manually deployable")
	t.assert_true(
		grid.grid_offset.y + grid.grid_height * grid.cell_size <= 432.0,
		"preparation battlefield reserves vertical space for the hand area"
	)

	var blocker := Node.new()
	grid.occupy_cell(Vector2i(7, 3), blocker)
	t.assert_false(grid.can_place_at(Vector2i(7, 3)), "a friendly occupied cell is not deployable")
	grid.free_cell(Vector2i(7, 3))
	blocker.free()


func _test_spawn_sequence(grid: GridSystem) -> void:
	battle_manager.setup_battle([], [], 1, false)
	var templates: Array = []
	for index in range(4):
		templates.append(_enemy_template("spawn_%d" % index))
	grid.spawn_enemy_wave(templates, [])
	t.assert_eq(battle_manager.enemy_units.size(), 1, "first queued enemy spawns immediately")
	t.assert_true(grid.has_pending_enemy_spawns(), "remaining queued enemies block early completion")
	grid._process(0.61)
	grid._process(0.61)
	grid._process(0.61)
	t.assert_eq(battle_manager.enemy_units.size(), 4, "all queued enemies spawn after their intervals")
	var expected := [Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 1), Vector2i(8, 2)]
	for index in range(battle_manager.enemy_units.size()):
		t.assert_eq(battle_manager.enemy_units[index].grid_position, expected[index], "enemy spawn point cycles through the two bases: %d" % index)
	t.assert_false(grid.has_pending_enemy_spawns(), "spawn queue is empty after the final enemy")
	battle_manager.setup_battle([], [], 1, false)


func _test_life_and_breach(grid: GridSystem) -> void:
	game_manager.reset_run_life(3)
	battle_manager.setup_battle([], [], 1, false)
	var data := _enemy_template("breach")
	data["enemy_uid"] = "breach:1"
	data["source_player_id"] = 1
	data["base_damage"] = 1
	grid.spawn_enemy_wave([data], [])
	var enemy := battle_manager.enemy_units[0] as EnemyUnit
	enemy.global_position = grid.grid_to_world(grid.player_base_cells[1])
	t.assert_true(grid.is_enemy_in_player_base(enemy), "enemy center inside a player base is detected")
	t.assert_true(battle_manager.handle_enemy_reached_player_base(enemy), "base entry resolves the enemy")
	t.assert_eq(game_manager.run_life, 2, "local breach deducts player life")
	t.assert_eq(battle_manager.get_breached_enemy_payloads().size(), 1, "breached enemy snapshot is retained")
	t.assert_false(battle_manager.is_perfect_battle(), "any breach makes the local battle non-perfect")
	t.assert_false(battle_manager.handle_enemy_reached_player_base(enemy), "the same enemy cannot breach twice")


func _test_soul_revive(grid: GridSystem) -> void:
	battle_manager.setup_battle([], [], 1, false)
	battle_manager.state = 1
	var hero := HeroUnit.new()
	grid.place_unit(hero, Vector2i(4, 3))
	battle_manager.register_player_unit(hero)
	hero.max_hp = 100
	hero.current_hp = 1
	hero._die()
	t.assert_true(hero.is_in_soul_state, "defeated hero enters soul state")
	t.assert_false(grid.occupancy.has(Vector2i(4, 3)), "soul releases its former cell")
	hero.soul_time_remaining = 0.0
	hero._process(0.01)
	t.assert_true(hero.is_alive, "soul revives after the timer")
	t.assert_eq(hero.grid_position, Vector2i(4, 3), "unoccupied death cell is used first")
	t.assert_true(hero.ai_enabled, "revived hero automatically resumes combat")

	hero._die()
	var blocker := Node.new()
	grid.occupy_cell(Vector2i(4, 3), blocker)
	hero.soul_time_remaining = 0.0
	hero._process(0.01)
	t.assert_true(hero.is_alive, "occupied death cell falls back to a base")
	t.assert_true(hero.grid_position in grid.player_base_cells, "fallback revive occurs at a player base")
	grid.free_cell(Vector2i(4, 3))
	blocker.free()
	battle_manager.setup_battle([], [], 1, false)


func _test_tavern_rules() -> void:
	game_manager.is_roguelike_run = true
	game_manager.run_gold = 0
	game_manager.last_tavern_income_round = 0
	game_manager.current_run_round = 1
	t.assert_eq(game_manager.grant_current_round_tavern_income(), 4, "round one tavern income is 4")
	t.assert_eq(game_manager.grant_current_round_tavern_income(), 0, "round income is idempotent")
	game_manager.current_run_round = 2
	t.assert_eq(game_manager.grant_current_round_tavern_income(), 5, "round two tavern income is 5")
	game_manager.current_run_round = 3
	t.assert_eq(game_manager.grant_current_round_tavern_income(), 6, "round three tavern income is 6")

	var recruit := RecruitSystem.new()
	add_child(recruit)
	t.assert_eq(recruit._calculate_cost("", 1), 2, "low-tier recruit costs 2")
	t.assert_eq(recruit._calculate_cost("", 2), 3, "mid-tier recruit costs 3")
	t.assert_eq(recruit._calculate_cost("", 3), 4, "high-tier recruit costs 4")
	for tavern_level in range(1, 7):
		recruit.tavern_level = tavern_level
		var pool: Array[Dictionary] = recruit._build_available_option_pool()
		t.assert_true(not pool.is_empty(), "tavern level %d has recruit options" % tavern_level)
		for option in pool:
			var class_id := str(option.get("class_id", ""))
			var hero_tier := ClassDefinitions.get_template(class_id).trait_tier
			t.assert_true(hero_tier <= tavern_level, "tavern level %d never offers T%d hero %s" % [tavern_level, hero_tier, class_id])
			t.assert_eq(int(option.get("shop_level", 0)), hero_tier, "recruit option shop_level matches hero tier: %s" % class_id)
	recruit.queue_free()


func _enemy_template(enemy_id: String) -> Dictionary:
	return {
		"enemy_id": enemy_id,
		"name": enemy_id,
		"type": EnemyUnit.EnemyType.MELEE,
		"hp": 10,
		"atk": 1,
		"def": 0,
		"attack_speed": 1.0,
		"move_speed": 1.0,
		"attack_range": 1.0,
		"search_range": 1.0,
	}
