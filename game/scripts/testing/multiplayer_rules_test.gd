# multiplayer_rules_test.gd - Pure coordinator and idempotency checks without opening sockets.
extends Node

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("MultiplayerRules")
var coordinator
var game_manager


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	coordinator = get_tree().root.get_node_or_null("MultiplayerRunManager")
	game_manager = get_tree().root.get_node_or_null("GameManager")
	t.assert_true(coordinator != null, "MultiplayerRunManager autoload exists")
	t.assert_true(game_manager != null, "GameManager autoload exists")
	if not coordinator or not game_manager:
		t.finish(get_tree())
		return

	_test_public_contract()
	_test_defender_selection()
	_test_payload_sanitizing()
	_test_damage_idempotency()
	_test_second_run_resets_damage_idempotency()

	coordinator._reset_runtime_state()
	game_manager.reset_run_life()
	t.finish(get_tree())


func _test_public_contract() -> void:
	for method_name in [
		"host_session",
		"join_session",
		"leave_session",
		"is_run_active",
		"set_local_ready",
		"start_session_run",
		"submit_local_battle_result",
		"route_local_joint_breach",
		"report_local_joint_stage_cleared",
	]:
		t.assert_true(coordinator.has_method(method_name), "coordinator exposes %s" % method_name)
	for signal_name in [
		"lobby_updated",
		"run_start_requested",
		"joint_defense_assigned",
		"joint_enemy_received",
		"joint_input_closed",
		"cooperative_round_resolved",
	]:
		t.assert_true(coordinator.has_signal(signal_name), "coordinator exposes %s" % signal_name)


func _test_defender_selection() -> void:
	coordinator._players = {
		31: _player(31, 3),
		11: _player(11, 1),
		41: _player(41, 4),
		21: _player(21, 2),
	}
	coordinator._round_results = {
		11: {"perfect": true},
		21: {"perfect": false},
		31: {"perfect": true},
		41: {"perfect": true},
	}
	t.assert_eq(coordinator._choose_defenders(), [11, 31], "only the first two perfect players by seat defend")
	var eliminated: Dictionary = coordinator._players[11].duplicate(true)
	eliminated["eliminated"] = true
	coordinator._players[11] = eliminated
	t.assert_eq(coordinator._choose_defenders(), [31, 41], "eliminated perfect player is skipped")


func _test_payload_sanitizing() -> void:
	var payload: Dictionary = coordinator._sanitize_enemy_payload({
		"enemy_uid": "enemy-1",
		"enemy_id": "goblin",
		"name": "哥布林",
		"max_hp": 50,
		"current_hp": 17,
		"atk": 8,
		"def": 2,
		"source_player_id": 999,
		"base_damage": 2,
		"transfer_count": 1,
		"callable": Callable(),
	}, 21)
	t.assert_eq(payload.get("source_player_id"), 21, "server overrides payload source with RPC sender")
	t.assert_eq(payload.get("current_hp"), 17, "remaining enemy hp survives transfer")
	t.assert_false(payload.has("callable"), "non-whitelisted values are removed from RPC payload")

	var forwarded: Dictionary = coordinator._merge_enemy_progress(payload, {
		"current_hp": 999,
	}, 2)
	t.assert_eq(forwarded.get("current_hp"), 17, "client cannot increase transferred enemy hp")
	t.assert_eq(forwarded.get("source_player_id"), 21, "source player survives every transfer")
	t.assert_eq(forwarded.get("transfer_count"), 2, "transfer count advances to the second defender")


func _test_damage_idempotency() -> void:
	game_manager.reset_run_life(10)
	coordinator._applied_life_damage_events.clear()
	coordinator._apply_source_life_damage("round:1:enemy:1", 2, 8)
	coordinator._apply_source_life_damage("round:1:enemy:1", 2, 8)
	t.assert_eq(game_manager.run_life, 8, "duplicate final-breach event deducts source life only once")
	coordinator._apply_source_life_damage("round:1:enemy:2", 3, 5)
	t.assert_eq(game_manager.run_life, 5, "a distinct final-breach event still applies")


func _test_second_run_resets_damage_idempotency() -> void:
	coordinator._session_active = true
	coordinator._run_active = false
	coordinator._applied_life_damage_events = {
		"same-room:first-run:round:1:enemy:1": true,
	}
	coordinator._apply_begin_run()
	t.assert_true(coordinator.is_run_active(), "session reports an active multiplayer run after begin")
	t.assert_true(
		coordinator._applied_life_damage_events.is_empty(),
		"a second run in the same room does not reuse first-run damage keys"
	)


func _player(peer_id: int, seat: int) -> Dictionary:
	return {
		"peer_id": peer_id,
		"seat": seat,
		"display_name": "P%d" % peer_id,
		"ready": true,
		"connected": true,
		"eliminated": false,
		"life": 20,
		"max_life": 20,
	}
