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
	_test_projection_round_trip(grid)
	await _test_battle_button_layout(grid)
	_test_enemy_preview_layout(grid)
	_test_hero_grid_scale(grid)
	await _test_drag_only_deployment(grid)
	await _test_retreat_to_reserve_cleanup(grid)
	_test_enemy_grid_scale_and_advance(grid)
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
	t.assert_near(grid.get_reserve_bottom_left().x, grid.get_recruit_panel_left_x(), 0.001, "reserve bottom-left aligns with the recruit panel left border")
	t.assert_near(grid.get_reserve_bottom_left().y, grid.get_recruit_panel_top_y() - grid.reserve_recruit_gap, 0.001, "reserve shadow keeps the requested gap above the recruit panel")
	var reserve_polygon := grid.get_reserve_polygon()
	var reserve_far_world := grid.screen_to_world(reserve_polygon[0], 0.0)
	var reserve_near_world := grid.screen_to_world(reserve_polygon[3], 0.0)
	var reserve_slot_width := float(grid.grid_width) * grid.cell_size / float(grid.reserve_slot_count)
	t.assert_near(absf(reserve_near_world.z - reserve_far_world.z), reserve_slot_width, 0.001, "reserve depth equals one slot width")
	var battlefield_front_bottom := grid.world_to_screen(Vector3(0.0, -grid.board_thickness, 0.0))
	var reserve_far_edge := grid.get_reserve_polygon()[0]
	t.assert_true(reserve_far_edge.y > battlefield_front_bottom.y, "reserve extension keeps a visible gap below the battlefield")
	t.assert_true(grid.is_world_point_inside_reserve(grid.reserve_slot_to_world(0)), "reserve slot center belongs to the projected reserve extension")

	var blocker := Node.new()
	grid.occupy_cell(Vector2i(7, 3), blocker)
	t.assert_false(grid.can_place_at(Vector2i(7, 3)), "a friendly occupied cell is not deployable")
	grid.free_cell(Vector2i(7, 3))
	blocker.free()


func _test_projection_round_trip(grid: GridSystem) -> void:
	t.assert_true(grid.camera_pitch_degrees >= 45.0 and grid.camera_pitch_degrees <= 60.0, "camera pitch stays in the requested 45-60 degree range")
	t.assert_true(grid.perspective_strength > 0.0, "battlefield enables mild Z-based perspective")
	var world_point := Vector3(314.0, 27.0, 183.0)
	var screen_point := grid.world_to_screen(world_point)
	var restored := grid.screen_to_world(screen_point, world_point.y)
	t.assert_near(restored.x, world_point.x, 0.001, "projection round trip restores horizontal position")
	t.assert_near(restored.y, world_point.y, 0.001, "projection round trip restores height")
	t.assert_near(restored.z, world_point.z, 0.001, "projection round trip restores depth")

	var target_cell := Vector2i(6, 2)
	t.assert_eq(grid.world_to_grid(grid.grid_to_world(target_cell)), target_cell, "projected cell center maps back to the same grid cell")
	var ground_screen := grid.world_to_screen(Vector3(100.0, 0.0, 100.0))
	var raised_screen := grid.world_to_screen(Vector3(100.0, 40.0, 100.0))
	t.assert_true(raised_screen.y < ground_screen.y, "positive 3D height moves a billboard upward on screen")

	var board_depth := float(grid.grid_height) * grid.cell_size
	t.assert_true(
		grid.world_to_screen(Vector3(0.0, 0.0, board_depth)).y < grid.world_to_screen(Vector3(0.0, 0.0, 0.0)).y,
		"larger Z projects toward the top of the screen"
	)
	var near_width := grid.world_to_screen(Vector3(grid.cell_size, 0.0, 0.0)).distance_to(grid.world_to_screen(Vector3(0.0, 0.0, 0.0)))
	var far_width := grid.world_to_screen(Vector3(grid.cell_size, 0.0, board_depth)).distance_to(grid.world_to_screen(Vector3(0.0, 0.0, board_depth)))
	t.assert_true(far_width < near_width, "larger Z shrinks projected X distances")
	var near_height := grid.world_to_screen(Vector3(0.0, 0.0, grid.cell_size)).distance_to(grid.world_to_screen(Vector3(0.0, 0.0, 0.0)))
	var far_height := grid.world_to_screen(Vector3(0.0, 0.0, board_depth)).distance_to(grid.world_to_screen(Vector3(0.0, 0.0, board_depth - grid.cell_size)))
	t.assert_true(far_height < near_height, "larger Z shrinks projected Y distances")


func _test_battle_button_layout(grid: GridSystem) -> void:
	BattleManager.state = BattleManager.BattleState.PREPARING
	var resource_bar := ResourceBar.new()
	add_child(resource_bar)
	await get_tree().process_frame
	resource_bar._process(0.0)
	var preview_rect := resource_bar.preview_button_margin.get_rect()
	var start_rect := resource_bar.start_button_margin.get_rect()
	var reserve_right := grid.get_reserve_screen_bounds().end.x
	t.assert_true(preview_rect.position.x >= reserve_right + ResourceBar.BATTLE_BUTTON_SIDE_GAP - 0.001, "enemy preview button sits to the right of the reserve area (button %.1f, reserve %.1f)" % [preview_rect.position.x, reserve_right])
	t.assert_near(start_rect.position.x, preview_rect.position.x, 0.001, "enemy preview and battle buttons share one vertical column")
	t.assert_near(start_rect.position.y - preview_rect.end.y, ResourceBar.BATTLE_BUTTON_VERTICAL_GAP, 0.001, "battle buttons keep the requested vertical gap")
	t.assert_true(start_rect.end.y <= grid.get_recruit_panel_top_y() - ResourceBar.BATTLE_BUTTON_RECRUIT_GAP + 0.001, "battle buttons stay above the recruit panel")
	remove_child(resource_bar)
	resource_bar.queue_free()
	await get_tree().process_frame


func _test_enemy_preview_layout(grid: GridSystem) -> void:
	var enemy_pool := [_enemy_template("preview_melee"), _enemy_template("preview_ranged")]
	enemy_pool[1]["type"] = EnemyUnit.EnemyType.RANGED
	battle_manager.setup_battle([], enemy_pool, 1, false)
	grid._apply_stage_layout(false)
	var planned: Array[Dictionary] = battle_manager.get_next_wave_preview_enemies()
	t.assert_eq(planned.size(), 4, "preparation caches every enemy in the next wave")
	t.assert_eq(grid.enemy_preview_units.size(), planned.size(), "enemy preview creates one non-combat UnitBase per planned enemy")
	t.assert_near(grid.get_reserve_bottom_left().x, grid.get_recruit_panel_left_x(), 0.001, "preparation layout uses the reserve bottom-left as its horizontal anchor")
	var visible_columns := grid.get_enemy_preview_visible_column_count()
	t.assert_true(visible_columns >= 2 and visible_columns <= 3, "default preparation view exposes about two enemy-board columns (actual %d)" % visible_columns)

	var unique_cells: Dictionary = {}
	for index in range(grid.enemy_preview_units.size()):
		var preview := grid.enemy_preview_units[index]
		unique_cells[grid.enemy_preview_cells[index]] = true
		t.assert_true(preview.is_reserve_preview and not preview.ai_enabled, "enemy preview unit stays in non-combat display state: %d" % index)
		t.assert_false(preview in battle_manager.enemy_units, "enemy preview unit is not registered as a live enemy: %d" % index)
		t.assert_false(preview in grid.all_units, "enemy preview unit is excluded from battlefield occupancy: %d" % index)
	t.assert_eq(unique_cells.size(), planned.size(), "preview enemies occupy random distinct cells when space is available")

	var reserve_before := grid.get_reserve_polygon()
	var battlefield_before := grid.get_main_battlefield_screen_bounds()
	grid.set_enemy_preview_view(true, false)
	var battlefield_after := grid.get_main_battlefield_screen_bounds()
	var preview_after := grid.get_enemy_preview_board_screen_bounds()
	t.assert_true(battlefield_before.position.x - battlefield_after.position.x >= grid.cell_size * 3.0 - 0.001, "full enemy preview shifts the battlefield left by at least three columns")
	t.assert_true(preview_after.end.x <= grid.get_viewport_rect().size.x - RecruitUI.PANEL_MARGIN + 0.001, "full enemy preview reveals the complete 5-column enemy board")
	var reserve_after := grid.get_reserve_polygon()
	for index in range(reserve_before.size()):
		t.assert_near(reserve_after[index].x, reserve_before[index].x, 0.001, "enemy preview does not shift reserve X: %d" % index)
		t.assert_near(reserve_after[index].y, reserve_before[index].y, 0.001, "enemy preview does not shift reserve Y: %d" % index)

	var planned_ids: Array[String] = []
	for template in planned:
		planned_ids.append(str(template.get("enemy_id", "")))
	planned_ids.sort()
	grid.set_enemy_preview_view(false, false)
	t.assert_true(battle_manager.start_next_wave(), "cached preview wave can start normally")
	var spawned_ids: Array[String] = []
	for enemy in battle_manager.enemy_units:
		spawned_ids.append(str((enemy as EnemyUnit).spawn_template.get("enemy_id", "")))
	for entry in grid.enemy_spawn_queue:
		spawned_ids.append(str((entry as Dictionary)["template"].get("enemy_id", "")))
	spawned_ids.sort()
	t.assert_eq(spawned_ids, planned_ids, "battle consumes the same randomized enemy templates that were previewed")
	battle_manager.setup_battle([], [], 1, false)
	grid._apply_stage_layout(false)


func _test_hero_grid_scale(grid: GridSystem) -> void:
	var melee_template := ClassDefinitions.get_template("fighter_champion")
	var ranged_template := ClassDefinitions.get_template("ranger_hunter")
	t.assert_near(melee_template.attack_range, 1.0, 0.001, "melee range remains one adjacent cell")
	t.assert_near(ranged_template.attack_range, 2.0, 0.001, "legacy ranged reach is adapted to the 9-column map")

	var hero := HeroUnit.new()
	hero.setup(melee_template, 1)
	grid.place_unit(hero, Vector2i(4, 0))
	t.assert_near(hero.unit_radius, grid.cell_size * 0.4, 0.001, "hero art footprint follows preparation cell size")
	t.assert_near(hero.get_collision_radius(), grid.cell_size * 0.25, 0.001, "hero collision follows preparation cell size")
	var logical_center := grid.screen_to_world(hero.get_ground_position(), 0.0)
	var far_edge := grid.world_to_screen(logical_center + Vector3(0.0, 0.0, grid.cell_size * 0.5))
	var near_edge := grid.world_to_screen(logical_center - Vector3(0.0, 0.0, grid.cell_size * 0.5))
	var expected_visual_center := far_edge.lerp(near_edge, grid.unit_visual_y_anchor) - hero.global_position
	var actual_visual_center := hero.body_placeholder.position + Vector2(hero.unit_radius, hero.unit_radius)
	t.assert_near(actual_visual_center.x, expected_visual_center.x, 0.001, "2D hero visual center follows the projected tile X at its anchor")
	t.assert_near(actual_visual_center.y, expected_visual_center.y, 0.001, "2D hero visual center moves from tile depth 1/2 to 1/5")
	var expected_collision_point := hero.ground_anchor_offset + grid.project_ground_offset(
		hero.get_ground_position(), Vector2(hero.get_collision_radius(), 0.0)
	)
	var actual_collision_point := hero.collision_debug_ring.points[0]
	t.assert_near(actual_collision_point.x, expected_collision_point.x, 0.001, "collision debug X uses battlefield projection")
	t.assert_near(actual_collision_point.y, expected_collision_point.y, 0.001, "collision debug Y uses battlefield projection")

	# 第 3/4 圆周点会从第一行单位向近景跨过 Z=0；切换预览时也必须随单位整体平移。
	var crossing_point_index := 72
	var attack_point_before := hero.attack_range_debug_ring.points[crossing_point_index]
	var hero_position_before := hero.global_position
	grid.set_enemy_preview_view(true, false)
	var attack_point_after := hero.attack_range_debug_ring.points[crossing_point_index]
	var hero_shift := hero.global_position - hero_position_before
	t.assert_near(attack_point_after.x, attack_point_before.x, 0.001, "attack-range point crossing Z=0 keeps its local X in enemy preview")
	t.assert_near(attack_point_after.y, attack_point_before.y, 0.001, "attack-range point crossing Z=0 keeps its local Y in enemy preview")
	t.assert_true(hero_shift.x <= -grid.cell_size * 3.0 + 0.001, "enemy preview still shifts the owning combat unit left")
	grid.set_enemy_preview_view(false, false)

	grid.cell_size = 128.0
	grid._sync_unit_positions()
	t.assert_near(hero.unit_radius, 51.2, 0.001, "hero art footprint follows battle cell size")
	t.assert_near(hero.get_collision_radius(), 32.0, 0.001, "hero collision follows battle cell size")
	grid.remove_unit(hero)
	hero.queue_free()
	grid._apply_stage_layout(false)


func _test_drag_only_deployment(grid: GridSystem) -> void:
	var was_roguelike := GameManager.is_roguelike_run
	GameManager.is_roguelike_run = false
	BattleManager.state = BattleManager.BattleState.PREPARING
	var deployment := DeploymentSystem.new()
	add_child(deployment)
	var command_menu := CharacterCommandMenu.new()
	add_child(command_menu)
	deployment.setup_hand([{"class_id": "fighter_champion", "level": 1, "star_level": 1}])
	var deployment_bar_defaults := DeploymentBar.new()
	t.assert_near(deployment_bar_defaults.drag_gesture_time, 0.3, 0.001, "reserve hero drag uses the requested 0.3 second gesture window")
	t.assert_true(deployment_bar_defaults.drag_distance_threshold > 0.0, "reserve hero drag requires actual mouse displacement")
	deployment_bar_defaults.free()
	var first_pos := Vector2i(3, 0)

	deployment._on_cell_clicked(first_pos)
	t.assert_eq(deployment.hand_cards.size(), 1, "clicking an empty battlefield cell no longer deploys a reserve hero")
	t.assert_false(deployment.select_card(0), "legacy click-to-select deployment entry is disabled")
	t.assert_true(deployment.begin_drag(0), "holding a reserve hero starts drag deployment")
	deployment._finish_drag_at(first_pos)
	t.assert_true(grid.occupancy.get(first_pos) is HeroUnit, "drag release deploys the reserve hero at any legal cell")
	var first_hero := grid.occupancy[first_pos] as HeroUnit

	deployment._on_unit_clicked(first_hero)
	t.assert_false(deployment.is_dragging, "pressing a battlefield hero does not drag before the 0.3 second threshold")
	t.assert_eq(deployment.pending_drag_unit, first_hero, "pressed battlefield hero waits in the drag threshold state")
	deployment._finish_pending_unit_click()
	t.assert_eq(deployment.selected_unit, first_hero, "releasing before the threshold selects the hero")
	t.assert_true(command_menu.visible, "short click shows the hero interaction panel")
	t.assert_eq(command_menu.menu_panel.get_child_count(), 2, "hero interaction panel only contains sell and retreat buttons")
	var expected_menu_size := Vector2(command_menu.button_size.x * 2.0 + command_menu.button_gap, command_menu.button_size.y)
	t.assert_eq(command_menu.menu_panel.size, expected_menu_size, "hero interaction panel is reduced to two square buttons")
	var hero_screen_center := command_menu._get_unit_screen_position(first_hero)
	t.assert_true(command_menu.menu_panel.position.y + command_menu.menu_panel.size.y <= hero_screen_center.y - first_hero.unit_radius - command_menu.unit_head_gap + 0.001, "hero interaction panel stays close above the current visual")
	command_menu._clear_selection_and_hide()

	deployment._on_unit_clicked(first_hero)
	deployment._update_pending_unit_drag(deployment.pending_drag_start_mouse_pos, true)
	t.assert_false(deployment.is_dragging, "stationary holding never starts battlefield dragging")
	deployment._update_pending_unit_drag(
		deployment.pending_drag_start_mouse_pos + Vector2(DeploymentSystem.UNIT_DRAG_MIN_DISTANCE + 1.0, 0.0),
		true
	)
	t.assert_true(deployment.is_dragging and deployment.drag_source_unit == first_hero, "mouse displacement inside the gesture window starts unit dragging")
	t.assert_false(first_hero.visible, "source hero is hidden while its drag preview is active")
	var moved_pos := Vector2i(4, 1)
	deployment._finish_drag_at(moved_pos)
	t.assert_eq(first_hero.grid_position, moved_pos, "battlefield hero can be dragged to an arbitrary empty legal cell")
	t.assert_true(first_hero.visible, "battlefield hero is restored after drag release")

	var second_pos := Vector2i(6, 2)
	var second_hero := HeroUnit.new()
	second_hero.setup(ClassDefinitions.get_template("ranger_hunter"), 1)
	t.assert_true(grid.place_unit(second_hero, second_pos), "swap regression target hero is placed")
	second_hero.mark_deployed({"class_id": "ranger_hunter", "level": 1, "star_level": 1}, second_pos)
	t.assert_true(deployment.begin_unit_drag(first_hero), "deployed hero can begin a second drag")
	deployment._finish_drag_at(second_pos)
	t.assert_eq(first_hero.grid_position, second_pos, "dragging onto a friendly hero moves the source to the target cell")
	t.assert_eq(second_hero.grid_position, moved_pos, "dragging onto a friendly hero swaps the target into the source cell")

	t.assert_true(deployment.begin_unit_drag(first_hero), "hero can begin an invalid-drop regression drag")
	deployment._finish_drag_at(Vector2i(5, 3))
	t.assert_eq(first_hero.grid_position, second_pos, "invalid drag release keeps the hero at its original cell")
	t.assert_true(first_hero.visible, "invalid drag release restores the original hero visual")

	for hero in [first_hero, second_hero]:
		grid.remove_unit(hero)
		BattleManager.unregister_player_unit(hero)
		hero.queue_free()
	command_menu._hide_menu(true)
	remove_child(command_menu)
	command_menu.queue_free()
	remove_child(deployment)
	deployment.queue_free()
	GameManager.is_roguelike_run = was_roguelike
	await get_tree().process_frame


func _test_retreat_to_reserve_cleanup(grid: GridSystem) -> void:
	var was_roguelike := GameManager.is_roguelike_run
	GameManager.is_roguelike_run = false
	BattleManager.state = BattleManager.BattleState.PREPARING
	var deployment := DeploymentSystem.new()
	add_child(deployment)
	var hero := HeroUnit.new()
	var card_data := {"class_id": "fighter_champion", "level": 1, "star_level": 1}
	hero.setup(ClassDefinitions.get_template("fighter_champion"), 1)
	hero.mark_deployed(card_data, Vector2i(4, 0))
	t.assert_true(grid.place_unit(hero, Vector2i(4, 0)), "retreat regression hero is deployed")
	deployment.selected_unit = hero
	deployment.retreat_selected()
	t.assert_false(hero in grid.all_units, "retreat removes the live hero from grid tracking immediately")
	t.assert_false(hero in BattleManager.player_units, "retreat unregisters the live hero from battle tracking")
	t.assert_eq(deployment.hand_cards.size(), 1, "retreat returns exactly one reserve entry")
	await get_tree().process_frame
	t.assert_false(is_instance_valid(hero), "retreated live hero is freed instead of moving on the battlefield")
	remove_child(deployment)
	deployment.queue_free()
	GameManager.is_roguelike_run = was_roguelike


func _test_enemy_grid_scale_and_advance(grid: GridSystem) -> void:
	var normal := EnemyUnit.new()
	normal.setup_from_template(_enemy_template("normal_scale"))
	grid.place_unit(normal, Vector2i(8, 0))
	t.assert_near(normal.unit_radius, grid.cell_size * 0.4, 0.001, "normal enemy body follows cell size")
	t.assert_near(normal.get_collision_radius(), grid.cell_size * 0.25, 0.001, "normal enemy collision follows cell size")
	var base_distance_before := normal.get_ground_position().distance_to(grid.get_nearest_player_base_world(normal.get_ground_position()))
	normal.ai_controller._move_enemy_forward(0.1)
	var base_distance_after := normal.get_ground_position().distance_to(grid.get_nearest_player_base_world(normal.get_ground_position()))
	t.assert_true(base_distance_after < base_distance_before, "unblocked enemy continues toward the nearest player base")
	grid.remove_unit(normal)
	BattleManager.unregister_enemy_unit(normal)
	normal.queue_free()

	var blocker := HeroUnit.new()
	blocker.setup(ClassDefinitions.get_template("fighter_champion"), 1)
	grid.place_unit(blocker, Vector2i(6, 1))
	var blocked_enemy := EnemyUnit.new()
	blocked_enemy.setup_from_template(_enemy_template("blocked_advance"))
	grid.place_unit(blocked_enemy, Vector2i(7, 1))
	blocked_enemy.ai_controller._move_enemy_forward(1.0)
	t.assert_eq(blocked_enemy.target, blocker, "enemy locks the player unit that blocks its advance")
	var separation := blocked_enemy.get_ground_position().distance_to(blocker.get_ground_position())
	var minimum_separation := blocked_enemy.get_collision_radius() + blocker.get_collision_radius()
	t.assert_true(separation >= minimum_separation - 0.001, "enemy stops at contact without overlapping the blocking hero")
	t.assert_eq(blocked_enemy.ai_controller.state, "attacking", "enemy enters attack state after a hero blocks its advance")
	grid.remove_unit(blocked_enemy)
	BattleManager.unregister_enemy_unit(blocked_enemy)
	blocked_enemy.queue_free()
	grid.remove_unit(blocker)
	BattleManager.unregister_player_unit(blocker)
	blocker.queue_free()

	var brute_data := _enemy_template("brute_scale")
	brute_data["type"] = EnemyUnit.EnemyType.BRUTE
	var brute := EnemyUnit.new()
	brute.setup_from_template(brute_data)
	grid.place_unit(brute, Vector2i(8, 0))
	t.assert_near(brute.unit_radius, grid.cell_size * 0.4 * 32.0 / 24.0, 0.001, "brute preserves its larger body tier")
	t.assert_near(brute.get_collision_radius(), grid.cell_size * 0.25 * 32.0 / 24.0, 0.001, "brute collision preserves its larger tier")
	grid.remove_unit(brute)
	BattleManager.unregister_enemy_unit(brute)
	brute.queue_free()


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
