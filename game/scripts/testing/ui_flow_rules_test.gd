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
	var deployment_bar := DeploymentBar.new()
	add_child(deployment_bar)
	await get_tree().process_frame

	t.assert_true(deployment_bar.hand_frame != null, "deployment hand area exposes an outer frame")
	t.assert_eq(deployment_bar.hand_frame.name, "PreparationAreaFrame", "hand frame has a stable UI node name")
	t.assert_eq(deployment_bar.bar_height, 116.0, "hand area height contains raised cards inside its frame")
	t.assert_true(
		deployment_bar.position.y >= GridSystem.PREP_GRID_RECT.end.y,
		"preparation hand area sits below the reduced battlefield at any viewport height"
	)
	BattleManager.state = BattleManager.BattleState.IN_PROGRESS
	deployment_bar._apply_stage_layout(false)
	t.assert_true(
		deployment_bar.position.y >= GridSystem.BATTLE_GRID_RECT.end.y,
		"battle hand area stays below the expanded battlefield"
	)
	var title := deployment_bar.hand_frame.get_node_or_null("PreparationAreaTitle") as Label
	t.assert_true(title != null, "hand frame includes a preparation-area label")
	if title:
		t.assert_eq(title.text, "备战区", "hand frame label is localized")

	remove_child(deployment_bar)
	deployment_bar.queue_free()
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
