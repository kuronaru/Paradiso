# ui_flow_rules_test.gd - Multiplayer entry/exit and run-result UI regression checks.
extends Node

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("UIFlowRules")
var coordinator: Node = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	coordinator = get_tree().root.get_node_or_null("MultiplayerRunManager")
	t.assert_true(coordinator != null, "multiplayer coordinator autoload exists")
	if not coordinator:
		t.finish(get_tree())
		return

	await _test_relic_selection_tracks_online_session()
	await _test_life_display()
	await _test_deployment_hand_frame()
	await _test_run_result_overlay()
	coordinator._reset_runtime_state()
	t.finish(get_tree())


func _test_relic_selection_tracks_online_session() -> void:
	coordinator._session_active = true
	coordinator._run_active = true
	var relic_select := RoguelikeRelicSelectUI.new()
	add_child(relic_select)
	await get_tree().process_frame

	t.assert_true(relic_select.online_selection, "relic selection remembers multiplayer origin")
	t.assert_true(
		coordinator.session_ended.is_connected(relic_select._on_multiplayer_session_ended),
		"relic selection listens for host/session disconnect"
	)
	t.assert_true(
		relic_select._is_online_session(coordinator),
		"relic selection recognizes an active multiplayer session"
	)

	remove_child(relic_select)
	relic_select.queue_free()
	coordinator._reset_runtime_state()
	await get_tree().process_frame


func _test_life_display() -> void:
	GameManager.is_roguelike_run = true
	GameManager.run_max_life = 20
	GameManager.run_life = 7
	var resource_bar := ResourceBar.new()
	add_child(resource_bar)
	await get_tree().process_frame
	resource_bar._process(0.0)

	var life_label := resource_bar.find_child("LifeLabel", true, false) as Label
	t.assert_true(life_label != null, "resource bar exposes a player-life label")
	if life_label:
		t.assert_true(life_label.visible, "life label is visible during a roguelike run")
		t.assert_eq(life_label.text, "生命: 7 / 20", "life label displays current and maximum life")

	remove_child(resource_bar)
	resource_bar.queue_free()
	await get_tree().process_frame


func _test_deployment_hand_frame() -> void:
	GameManager.is_roguelike_run = true
	BattleManager.state = BattleManager.BattleState.PREPARING
	var grid := GridSystem.new()
	add_child(grid)
	await get_tree().process_frame
	var deployment := DeploymentSystem.new()
	add_child(deployment)
	deployment.hand_cards = [{"class_id": "fighter_champion", "level": 1, "star_level": 1}]
	var player_unit_count_before_preview := BattleManager.player_units.size()
	var deployment_bar := DeploymentBar.new()
	add_child(deployment_bar)
	await get_tree().process_frame

	t.assert_true(deployment_bar.get_node_or_null("PreparationAreaFrame") == null, "reserve area has no text-label frame")
	t.assert_eq(deployment_bar.hand_row.name, "ReserveHeroSlots", "reserve area exposes battle-visual hero slots")
	t.assert_eq(deployment_bar.cards.size(), 1, "one reserve hero control is built for one hand hero")
	if not deployment_bar.cards.is_empty():
		var reserve_button := deployment_bar.cards[0] as Button
		t.assert_true(reserve_button.get_theme_stylebox("normal") is StyleBoxEmpty, "reserve hero has no card frame")
		var reserve_visual := deployment_bar.cards[0].find_child("BattleHeroVisual", true, false) as UnitBase
		t.assert_true(reserve_visual != null, "reserve hero exposes a battle-art visual node")
		if reserve_visual:
			t.assert_true(reserve_visual.is_reserve_preview, "reserve hero uses the explicit UnitBase reserve state")
			t.assert_false(reserve_visual.ai_enabled, "reserve hero does not call character AI")
			t.assert_false(reserve_visual.is_processing(), "reserve hero does not run combat process updates")
			t.assert_true(reserve_visual.ai_controller != null, "reserve hero remains a complete UnitBase instance")
			t.assert_eq(reserve_visual.ground_collision_area.collision_layer, 0, "reserve hero has no combat collision layer")
			t.assert_near(
				float(reserve_visual.get_meta("combat_visual_multiplier", 0.0)),
				grid.cell_size * 0.4 / 24.0,
				0.001,
				"reserve hero uses the same visual multiplier as a deployed hero"
			)
			t.assert_false(reserve_visual in grid.all_units, "reserve hero is not inserted into battlefield cells")
			var expected_anchor := grid.get_global_transform_with_canvas() * grid.reserve_slot_visual_anchor(0, grid.reserve_slot_count)
			t.assert_near(reserve_visual.get_billboard_screen_center().x, expected_anchor.x, 0.001, "reserve hero anchor matches the battlefield X baseline")
			t.assert_near(reserve_visual.get_billboard_screen_center().y, expected_anchor.y, 0.001, "reserve hero anchor sits one fifth below the slot screen top")
	t.assert_eq(BattleManager.player_units.size(), player_unit_count_before_preview, "building reserve visuals does not register combat units")
	t.assert_eq(deployment_bar.position, Vector2.ZERO, "reserve hero UI shares the battlefield canvas origin")
	var reserve_center := grid.reserve_slot_to_world(0, grid.reserve_slot_count)
	var reserve_screen_center := grid.get_global_transform_with_canvas() * reserve_center
	t.assert_true(deployment_bar.is_point_over_reserve_area(reserve_screen_center), "projected reserve slot is inside the interactive preparation area")
	BattleManager.state = BattleManager.BattleState.IN_PROGRESS
	deployment_bar._apply_stage_layout(false)
	t.assert_eq(deployment_bar.position, Vector2.ZERO, "battle reserve remains an extension of the battlefield")
	t.assert_true(deployment_bar.find_child("PreparationAreaTitle", true, false) == null, "reserve area has no text label")

	remove_child(deployment_bar)
	deployment_bar.queue_free()
	remove_child(deployment)
	deployment.queue_free()
	remove_child(grid)
	grid.queue_free()
	BattleManager.grid = null
	BattleManager.state = BattleManager.BattleState.PREPARING
	await get_tree().process_frame


func _test_run_result_overlay() -> void:
	var roguelike_manager := RoguelikeManager.new()
	add_child(roguelike_manager)
	var game_menu := GameMenuUI.new()
	add_child(game_menu)
	await get_tree().process_frame

	t.assert_true(
		roguelike_manager.run_ended.is_connected(game_menu._on_run_ended),
		"game menu listens for roguelike completion"
	)
	roguelike_manager.run_ended.emit(false)
	t.assert_true(game_menu.run_end_overlay.visible, "defeat opens the result overlay")
	t.assert_eq(game_menu.run_end_title.text, "冒险失败", "defeat overlay has a clear title")
	t.assert_false(game_menu.run_end_stay_button.visible, "offline defeat does not show multiplayer wait action")
	t.assert_eq(game_menu.run_end_return_button.text, "返回 AFK 大厅", "offline defeat offers a return path")

	game_menu._on_run_ended(true)
	t.assert_eq(game_menu.run_end_title.text, "冒险完成", "victory overlay has a clear title")

	remove_child(game_menu)
	game_menu.queue_free()
	remove_child(roguelike_manager)
	roguelike_manager.queue_free()
	GameManager.is_roguelike_run = false
	await get_tree().process_frame
