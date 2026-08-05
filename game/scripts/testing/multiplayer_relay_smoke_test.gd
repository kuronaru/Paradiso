# multiplayer_relay_smoke_test.gd — two clients behind a dedicated ENet authority.
extends Node

const PORT_FALLBACK := 24672
const TIMEOUT_SECONDS := 20.0

var manager: Node = null
var game_manager: Node = null
var role := ""
var port := PORT_FALLBACK
var owner_token := ""
var elapsed := 0.0
var ready_sent := false
var result_sent := false
var finishing := false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--owner-token="):
			owner_token = argument.trim_prefix("--owner-token=")
	manager = get_tree().root.get_node_or_null("MultiplayerRunManager")
	game_manager = get_tree().root.get_node_or_null("GameManager")
	if not manager or not game_manager or role not in ["owner", "client"]:
		_finish(false, "invalid relay test setup")
		return

	manager.run_start_requested.connect(_on_run_started)
	manager.joint_defense_assigned.connect(_on_joint_defense_assigned)
	manager.cooperative_round_resolved.connect(_on_round_resolved)
	manager.session_ended.connect(_on_session_ended)
	game_manager.reset_run_life(20)
	var token := owner_token if role == "owner" else ""
	var error := int(manager.join_relay_session(
		"127.0.0.1",
		port,
		"RelayOwner" if role == "owner" else "RelayClient",
		1,
		token
	))
	if error != OK:
		_finish(false, "%s could not connect to relay: %d" % [role, error])


func _process(delta: float) -> void:
	if finishing:
		return
	elapsed += delta
	if elapsed >= TIMEOUT_SECONDS:
		_finish(false, "%s timed out" % role)
		return
	if manager.is_session_active() and not ready_sent and _local_player_registered():
		ready_sent = true
		manager.set_local_ready(true)
	if role == "owner" and manager.can_start_run():
		manager.start_session_run()


func _local_player_registered() -> bool:
	var local_id := int(manager.get_local_player_id())
	for value in manager.get_players_snapshot():
		if value is Dictionary and int(value.get("peer_id", 0)) == local_id:
			return true
	return false


func _on_run_started() -> void:
	if result_sent:
		return
	result_sent = true
	if role == "owner":
		manager.submit_local_battle_result({
			"round": 1,
			"breached_enemies": [],
			"life": game_manager.run_life,
			"eliminated": false,
		})
		return
	game_manager.damage_run_life(1)
	manager.submit_local_battle_result({
		"round": 1,
		"breached_enemies": [{
			"enemy_uid": "relay-client-enemy",
			"enemy_id": "goblin",
			"name": "Goblin",
			"type": 0,
			"max_hp": 10,
			"current_hp": 7,
			"atk": 1,
			"def": 0,
			"attack_speed": 1.0,
			"move_speed": 1.0,
			"attack_range": 1.0,
			"search_range": 1.0,
			"source_player_id": manager.get_local_player_id(),
			"base_damage": 1,
			"transfer_count": 0,
		}],
		"life": game_manager.run_life,
		"eliminated": false,
	})


func _on_joint_defense_assigned(
		stage_index: int,
		payloads: Array,
		_keep_input_open: bool
	) -> void:
	if role != "owner" or stage_index != 0 or payloads.size() != 1:
		_finish(false, "unexpected relay joint assignment on %s" % role)
		return
	manager.route_local_joint_breach(payloads[0], 0)
	manager.report_local_joint_stage_cleared(0)


func _on_round_resolved(round_number: int) -> void:
	if round_number != 1:
		_finish(false, "unexpected resolved relay round %d" % round_number)
		return
	var expected_life := 20 if role == "owner" else 18
	if game_manager.run_life != expected_life:
		_finish(
			false,
			"%s expected life %d, got %d" % [role, expected_life, game_manager.run_life]
		)
		return
	if role == "owner" and not manager.is_local_room_host():
		_finish(false, "relay owner did not receive room-host authority")
		return
	_finish(true, "%s completed dedicated relay route" % role)


func _on_session_ended(reason: String) -> void:
	if not finishing:
		_finish(false, "%s relay session ended early: %s" % [role, reason])


func _finish(success: bool, message: String) -> void:
	if finishing:
		return
	finishing = true
	print("[%s] MultiplayerRelaySmoke: %s" % ["PASS" if success else "FAIL", message])
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if success else 1)
