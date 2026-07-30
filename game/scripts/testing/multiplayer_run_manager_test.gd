# multiplayer_run_manager_test.gd - Multiplayer coordinator lifecycle regression tests.
extends SceneTree

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("MultiplayerRunManager")
var manager
var game_manager
var original_max_rounds := 15


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	manager = root.get_node_or_null("MultiplayerRunManager")
	game_manager = root.get_node_or_null("GameManager")
	t.assert_true(manager != null, "MultiplayerRunManager autoload exists")
	t.assert_true(game_manager != null, "GameManager autoload exists")
	if not manager or not game_manager:
		t.finish(self)
		return

	original_max_rounds = int(game_manager.max_run_rounds)
	game_manager.max_run_rounds = 3
	await _test_final_round_ends_run_without_preparing_next_round()
	await _test_eliminated_player_without_result_releases_barrier()
	await _test_eliminated_player_with_result_releases_barrier()
	game_manager.max_run_rounds = original_max_rounds
	manager._reset_runtime_state()
	t.finish(self)


func _test_final_round_ends_run_without_preparing_next_round() -> void:
	_reset_manager_for_round(3)
	manager._round_expected = {1: true}
	manager._round_results = {
		1: _perfect_result(3),
	}

	manager._server_resolve_round()
	await process_frame

	t.assert_false(manager._run_active, "final round clears active run")
	t.assert_eq(manager._phase, manager.SessionPhase.ENDED, "final round ends coordinator phase")
	t.assert_eq(manager._round_number, 3, "final round does not prepare round plus one")
	t.assert_true(manager._round_expected.has(1), "final round ledger is not replaced by a next-round barrier")


func _test_eliminated_player_without_result_releases_barrier() -> void:
	_reset_manager_for_round(1)
	manager._players[2] = _player_state(2, 2)
	manager._round_expected = {
		1: true,
		2: true,
	}
	manager._round_results = {
		1: _perfect_result(1),
	}

	manager._server_mark_player_eliminated(2)
	await process_frame

	t.assert_false(manager._round_expected.has(2), "eliminated player without result leaves expected set")
	t.assert_true(bool(manager._players[2].get("eliminated", false)), "eliminated player state is retained")
	t.assert_eq(manager._round_number, 2, "barrier retries and advances after missing-result elimination")
	t.assert_true(manager._round_expected.has(1), "next round expects the remaining living player")
	t.assert_false(manager._round_expected.has(2), "next round excludes eliminated player")


func _test_eliminated_player_with_result_releases_barrier() -> void:
	_reset_manager_for_round(1)
	manager._players[2] = _player_state(2, 2)
	manager._round_expected = {
		1: true,
		2: true,
	}
	manager._round_results = {
		1: _perfect_result(1),
		2: _perfect_result(1),
	}

	manager._server_mark_player_eliminated(2)
	await process_frame

	t.assert_false(manager._round_expected.has(2), "eliminated player with result leaves expected set")
	t.assert_false(manager._round_results.has(2), "resolved result is cleared when the next-round ledger is prepared")
	t.assert_eq(manager._round_number, 2, "barrier advances when eliminated player already submitted")


func _reset_manager_for_round(round_number: int) -> void:
	manager._reset_runtime_state()
	manager._session_active = true
	manager._run_active = true
	manager._phase = manager.SessionPhase.WAITING_LOCAL_RESULTS
	manager._round_number = round_number
	manager._round_resolve_sent = false
	manager._players = {
		1: _player_state(1, 1),
	}
	manager._round_expected = {}
	manager._round_results = {}
	manager._round_breaches.clear()


func _player_state(peer_id: int, seat: int) -> Dictionary:
	return {
		"peer_id": peer_id,
		"seat": seat,
		"display_name": "P%d" % peer_id,
		"ready": false,
		"connected": true,
		"eliminated": false,
		"life": 20,
		"max_life": 20,
	}


func _perfect_result(round_number: int) -> Dictionary:
	return {
		"round": round_number,
		"perfect": true,
		"breached_count": 0,
		"breached_enemies": [],
		"life": 20,
		"eliminated": false,
	}
