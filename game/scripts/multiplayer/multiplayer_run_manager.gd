# multiplayer_run_manager.gd — ENet 房间与多人肉鸽回合协调
# 每个进程只模拟自己的棋盘；房主只同步房间、高层战果和联合防守事件。
extends Node

signal lobby_updated(players)
signal connection_status_changed(status)
signal run_start_requested
signal joint_defense_assigned(stage_index, payloads, keep_input_open)
signal joint_enemy_received(payload)
signal joint_input_closed
signal cooperative_round_resolved(round_number)
signal session_ended(reason)
signal transport_changed(mode, generation)
signal public_endpoint_ready(success, external_address, port, error_code)
signal direct_connection_timed_out(generation)

const SERVER_PEER_ID := 1
const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const DEFAULT_MAX_LIFE := 20
const MAX_DISPLAY_NAME_LENGTH := 32
const MAX_ENEMY_ID_LENGTH := 96
const MAX_ENEMY_NAME_LENGTH := 96
const MAX_ENEMIES_PER_REPORT := 512
const MAX_NESTED_COLLECTION_SIZE := 32
const MAX_COMBAT_STAT := 10_000_000
const MAX_BASE_DAMAGE := 100_000
const MAX_TRANSFER_COUNT := 2
const PROTOCOL_VERSION := 2

enum SessionPhase {
	OFFLINE,
	LOBBY,
	LOCAL_BATTLE,
	WAITING_LOCAL_RESULTS,
	JOINT_DEFENSE,
	ROUND_RESOLVED,
	ENDED,
}

enum TransportMode {
	OFFLINE,
	LAN_DIRECT,
	PUBLIC_DIRECT,
	RELAY,
	NAKAMA,
}

var _enet_peer: ENetMultiplayerPeer = null
var _phase: SessionPhase = SessionPhase.OFFLINE
var _session_active := false
var _run_active := false
var _manual_leave := false
var _dedicated_server := false
var _local_display_name := "Player"
var _session_uid := ""
var _next_seat := 2
var _transport_mode: TransportMode = TransportMode.OFFLINE
var _transport_generation := 0
var _awaiting_connection := false
var _connect_time_remaining := 0.0
var _dedicated_owner_token := ""
var _relay_owner_token := ""
var _authority_peer_id := SERVER_PEER_ID
var _registration_sent := false

# {peer_id: {peer_id, seat, display_name, ready, connected, eliminated, life, max_life}}
var _players: Dictionary = {}

# 房主权威的当前回合账本。
var _round_number := 0
var _round_expected: Dictionary = {}
var _round_results: Dictionary = {}
var _round_breaches: Array[Dictionary] = []
var _round_resolve_sent := false
var _next_ticket_serial := 1

# 联合防守账本。所有 key 均使用房主签发的 enemy_uid。
var _defenders: Array[int] = []
var _joint_payload_by_uid: Dictionary = {}
var _stage_cleared: Dictionary = {}
var _stage_zero_breached: Dictionary = {}
var _stage_one_received: Dictionary = {}
var _stage_one_breached: Dictionary = {}
var _final_damage_uids: Dictionary = {}
var _applied_life_damage_events: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_multiplayer_signals()
	var helper := _public_network_helper()
	if helper and helper.has_signal("mapping_completed") \
			and not helper.mapping_completed.is_connected(_on_public_mapping_completed):
		helper.mapping_completed.connect(_on_public_mapping_completed)


func _process(delta: float) -> void:
	if not _awaiting_connection:
		return
	if _connect_time_remaining <= 0.0:
		return
	_connect_time_remaining -= maxf(delta, 0.0)
	if _connect_time_remaining > 0.0:
		return
	_handle_public_connection_failure()


## 创建 2～4 人 ENet 房间。房主占用玩家席位 0，最多接受 3 个客户端。
func host_session(port: int, display_name: String) -> Error:
	return _host_enet_session(port, display_name, TransportMode.LAN_DIRECT, false, "")


## 创建公网直连候选；ENet 启动后异步尝试 UPnP UDP 映射。
func host_public_session(port: int, display_name: String, enable_upnp: bool = true) -> Error:
	var error := _host_enet_session(port, display_name, TransportMode.PUBLIC_DIRECT, false, "")
	if error != OK:
		return error
	var advertised_address := _cfg_string("public_direct_advertise_address", "")
	if not advertised_address.is_empty():
		call_deferred("_emit_public_endpoint_result", true, advertised_address, port, OK)
		return OK
	if not enable_upnp or not _cfg_bool("public_upnp_enabled", true):
		call_deferred("_emit_public_endpoint_result", false, "", port, ERR_UNAVAILABLE)
		return OK
	var helper := _public_network_helper()
	if not helper or not helper.has_method("request_port_mapping") or not helper.request_port_mapping(port):
		call_deferred("_emit_public_endpoint_result", false, "", port, ERR_BUSY)
	return OK


## 创建不占玩家席位的专用中继服务端。
func host_dedicated_session(port: int, room_code: String, owner_token: String) -> Error:
	return _host_enet_session(port, "Relay", TransportMode.RELAY, true, owner_token, room_code)


func _host_enet_session(
		port: int,
		display_name: String,
		transport_mode: TransportMode,
		dedicated: bool,
		owner_token: String,
		session_label: String = ""
	) -> Error:
	if _session_active:
		return ERR_ALREADY_IN_USE
	if port <= 0 or port > 65535:
		return ERR_INVALID_PARAMETER

	var peer := ENetMultiplayerPeer.new()
	var maximum_clients := MAX_PLAYERS if dedicated else MAX_PLAYERS - 1
	var error := peer.create_server(port, maximum_clients)
	if error != OK:
		connection_status_changed.emit("error")
		return error

	_reset_runtime_state()
	_enet_peer = peer
	_local_display_name = _sanitize_display_name(display_name)
	_session_uid = session_label if not session_label.is_empty() else "%d-%d" % [
		int(Time.get_unix_time_from_system()),
		Time.get_ticks_usec(),
	]
	_session_active = true
	_dedicated_server = dedicated
	_dedicated_owner_token = owner_token
	_transport_mode = transport_mode
	_phase = SessionPhase.LOBBY
	multiplayer.multiplayer_peer = peer

	if not dedicated:
		_players[SERVER_PEER_ID] = _make_player_state(
			SERVER_PEER_ID,
			1,
			_local_display_name,
			true
		)
	connection_status_changed.emit("relay_hosting" if dedicated else "hosting")
	transport_changed.emit(int(_transport_mode), _transport_generation)
	_emit_lobby_updated()
	return OK


## 通过地址和 UDP 端口加入房间。
func join_session(address: String, port: int, display_name: String) -> Error:
	return _join_enet_session(address, port, display_name, TransportMode.LAN_DIRECT, 0, 0.0, "")


func join_public_session(
		address: String,
		port: int,
		display_name: String,
		generation: int,
		timeout_seconds: float = -1.0
	) -> Error:
	var timeout := timeout_seconds
	if timeout <= 0.0:
		timeout = _cfg_float("public_direct_connect_timeout", 4.0)
	return _join_enet_session(
		address,
		port,
		display_name,
		TransportMode.PUBLIC_DIRECT,
		generation,
		timeout,
		""
	)


func join_relay_session(
		address: String,
		port: int,
		display_name: String,
		generation: int,
		owner_token: String = ""
	) -> Error:
	return _join_enet_session(
		address,
		port,
		display_name,
		TransportMode.RELAY,
		generation,
		_cfg_float("public_direct_connect_timeout", 4.0),
		owner_token
	)


func switch_to_relay_session(
		address: String,
		port: int,
		display_name: String,
		generation: int,
		owner_token: String = ""
	) -> Error:
	if _run_active:
		return ERR_BUSY
	_release_public_mapping()
	_close_peer()
	_reset_runtime_state()
	return join_relay_session(address, port, display_name, generation, owner_token)


func _join_enet_session(
		address: String,
		port: int,
		display_name: String,
		transport_mode: TransportMode,
		generation: int,
		timeout_seconds: float,
		owner_token: String
	) -> Error:
	if _session_active:
		return ERR_ALREADY_IN_USE
	if port <= 0 or port > 65535:
		return ERR_INVALID_PARAMETER

	var target_address := address.strip_edges()
	if target_address.is_empty():
		target_address = "127.0.0.1"

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(target_address, port)
	if error != OK:
		connection_status_changed.emit("error")
		return error

	_reset_runtime_state()
	_enet_peer = peer
	_local_display_name = _sanitize_display_name(display_name)
	_session_active = true
	_transport_mode = transport_mode
	_transport_generation = maxi(0, generation)
	_relay_owner_token = owner_token
	_awaiting_connection = true
	_connect_time_remaining = maxf(0.1, timeout_seconds) if timeout_seconds > 0.0 else 0.0
	_phase = SessionPhase.LOBBY
	multiplayer.multiplayer_peer = peer
	connection_status_changed.emit("connecting")
	transport_changed.emit(int(_transport_mode), _transport_generation)
	return OK


## Attach a connected NakamaMultiplayerBridge without changing the gameplay RPC protocol.
func attach_nakama_session(
		room_code: String,
		display_name: String,
		is_host: bool,
		authority_peer_id: int = SERVER_PEER_ID
	) -> Error:
	if _session_active:
		return ERR_ALREADY_IN_USE
	if multiplayer.multiplayer_peer == null \
			or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED

	_reset_runtime_state()
	_local_display_name = _sanitize_display_name(display_name)
	_session_uid = room_code.strip_edges().to_upper()
	_session_active = true
	_transport_mode = TransportMode.NAKAMA
	_authority_peer_id = maxi(1, authority_peer_id)
	set_multiplayer_authority(_authority_peer_id)
	_phase = SessionPhase.LOBBY
	var local_id := get_local_player_id()
	if is_host:
		_players[local_id] = _make_player_state(local_id, 1, _local_display_name, true)
		connection_status_changed.emit("hosting")
		_emit_lobby_updated()
	else:
		connection_status_changed.emit("connected")
		call_deferred("_send_local_registration")
	transport_changed.emit(int(_transport_mode), _transport_generation)
	return OK


## 主动离开房间。房主离开时其他客户端会收到会话结束通知。
func leave_session() -> void:
	if not _session_active and _phase == SessionPhase.OFFLINE:
		return

	_manual_leave = true
	_release_public_mapping()
	if multiplayer.is_server() and _session_active:
		_rpc_session_ended.rpc("host_left")
	var local_reason := "host_left" if multiplayer.is_server() else "left"
	if _transport_mode == TransportMode.NAKAMA:
		var nakama_manager := _nakama_session_manager()
		if nakama_manager and nakama_manager.has_method("leave_room"):
			nakama_manager.call("leave_room", local_reason)
	_close_peer()
	_reset_runtime_state()
	connection_status_changed.emit("offline")
	session_ended.emit(local_reason)
	_manual_leave = false


## 取消尚未开局的连接尝试，不发送离房场景跳转事件。
func cancel_pending_session() -> void:
	if _run_active:
		return
	_manual_leave = true
	_release_public_mapping()
	_close_peer()
	_reset_runtime_state()
	connection_status_changed.emit("offline")
	_manual_leave = false


func is_session_active() -> bool:
	return _session_active


func is_run_active() -> bool:
	return _session_active and _run_active


func is_dedicated_server() -> bool:
	return _session_active and _dedicated_server


func get_transport_mode() -> int:
	return int(_transport_mode)


func get_transport_generation() -> int:
	return _transport_generation


func adopt_transport_generation(generation: int) -> void:
	if not _session_active or _run_active or generation < _transport_generation:
		return
	_transport_generation = generation
	transport_changed.emit(int(_transport_mode), _transport_generation)


func is_relay_transport() -> bool:
	return _session_active and _transport_mode == TransportMode.RELAY


func is_nakama_transport() -> bool:
	return _session_active and _transport_mode == TransportMode.NAKAMA


func get_protocol_version() -> int:
	return PROTOCOL_VERSION


func get_transport_snapshot() -> Dictionary:
	return {
		"mode": int(_transport_mode),
		"generation": _transport_generation,
		"dedicated_server": _dedicated_server,
		"awaiting_connection": _awaiting_connection,
	}


func get_local_player_id() -> int:
	if not _session_active:
		return _authority_peer_id
	var peer_id := multiplayer.get_unique_id()
	return peer_id if peer_id > 0 else 0


func is_local_room_host() -> bool:
	if not _session_active or _dedicated_server:
		return false
	var local_id := get_local_player_id()
	if not _players.has(local_id):
		return false
	return bool((_players[local_id] as Dictionary).get("room_host", false))


func get_players_snapshot() -> Array:
	return _build_players_snapshot()


## 设置本地玩家准备状态。房主同样需要准备。
func set_local_ready(ready: bool) -> void:
	if not _session_active or _run_active:
		return
	var local_id := get_local_player_id()
	if local_id <= 0:
		return
	if multiplayer.is_server():
		_server_set_ready(local_id, ready)
	else:
		_rpc_set_ready.rpc_id(_server_peer_id(), ready)


## 只有房主、2～4 人且所有已连接玩家都准备后才能开局。
func can_start_run() -> bool:
	if not _session_active or _run_active or not is_local_room_host():
		return false
	return _can_snapshot_start(_build_players_snapshot())


func _can_snapshot_start(snapshot: Array) -> bool:
	if snapshot.size() < MIN_PLAYERS or snapshot.size() > MAX_PLAYERS:
		return false
	for player_value in snapshot:
		var player: Dictionary = player_value
		if not bool(player.get("connected", false)) or not bool(player.get("ready", false)):
			return false
	return true


## 房主启动联机肉鸽。所有客户端收到 run_start_requested 后进入自己的本地流程。
func start_session_run() -> bool:
	if not can_start_run():
		return false
	if not multiplayer.is_server():
		_rpc_request_start_run.rpc_id(_server_peer_id())
		return true
	return _server_start_session_run()


func _server_start_session_run() -> bool:
	if not _session_active or not multiplayer.is_server() or _run_active:
		return false
	if not _can_snapshot_start(_build_players_snapshot()):
		return false
	_run_active = true
	_phase = SessionPhase.LOCAL_BATTLE
	var maximum_life := _configured_max_life()
	for peer_id_value in _players.keys():
		var peer_id := int(peer_id_value)
		var player: Dictionary = _players[peer_id].duplicate(true)
		player["ready"] = false
		player["eliminated"] = false
		player["life"] = maximum_life
		player["max_life"] = maximum_life
		_players[peer_id] = player

	_server_prepare_round(1)
	_broadcast_lobby_snapshot()
	_rpc_begin_run.rpc()
	_apply_begin_run()
	return true


## 提交本地战果。房主从 breached_enemies 是否为空自行推导 perfect。
func submit_local_battle_result(result: Dictionary) -> bool:
	if not _session_active or not _run_active:
		return false
	var local_id := get_local_player_id()
	if local_id <= 0:
		return false
	var sanitized := _sanitize_local_result(result, local_id, _round_number)
	if multiplayer.is_server():
		return _server_accept_local_result(local_id, sanitized)
	_rpc_submit_local_result.rpc_id(_server_peer_id(), sanitized)
	_phase = SessionPhase.WAITING_LOCAL_RESULTS
	return true


## 联合阶段漏怪入口。stage 0 漏怪实时转给 stage 1；stage 1 漏怪最终扣来源生命。
func route_local_joint_breach(payload: Dictionary, stage_index: int) -> void:
	if not _session_active or not _run_active or _phase != SessionPhase.JOINT_DEFENSE:
		return
	var sanitized := _sanitize_enemy_payload(payload)
	if sanitized.is_empty():
		return
	if multiplayer.is_server():
		_server_accept_joint_breach(get_local_player_id(), stage_index, sanitized)
	else:
		_rpc_submit_joint_breach.rpc_id(_server_peer_id(), stage_index, sanitized)


## 当前防守段在“输入已关闭、出生队列为空、场上敌人为空”后报告完成。
func report_local_joint_stage_cleared(stage_index: int) -> void:
	if not _session_active or not _run_active or _phase != SessionPhase.JOINT_DEFENSE:
		return
	if multiplayer.is_server():
		_server_accept_stage_cleared(get_local_player_id(), stage_index)
	else:
		_rpc_submit_stage_cleared.rpc_id(_server_peer_id(), stage_index)


## 标记本地玩家淘汰。若 BattleManager 可用，会先补交当前战果避免屏障永久等待。
func mark_local_player_eliminated() -> void:
	if not _session_active or not _run_active:
		return
	var battle := _battle_manager()
	if battle and battle.has_method("get_battle_result") and not _round_results.has(get_local_player_id()):
		submit_local_battle_result(battle.get_battle_result())
	if multiplayer.is_server():
		_server_mark_player_eliminated(get_local_player_id())
	else:
		_rpc_mark_player_eliminated.rpc_id(_server_peer_id())


func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_connected_to_server() -> void:
	if not _session_active:
		return
	_awaiting_connection = false
	_connect_time_remaining = 0.0
	connection_status_changed.emit("connected")
	_send_local_registration()


func _send_local_registration() -> void:
	if not _session_active or multiplayer.is_server() or _registration_sent:
		return
	var server_id := _server_peer_id()
	if server_id <= 0:
		return
	_registration_sent = true
	_rpc_register_player.rpc_id(server_id, {
		"display_name": _local_display_name,
		"protocol_version": PROTOCOL_VERSION,
		"owner_token": _relay_owner_token,
	})


func _on_connection_failed() -> void:
	if _manual_leave:
		return
	if _transport_mode == TransportMode.PUBLIC_DIRECT:
		_handle_public_connection_failure()
		return
	_close_peer()
	_reset_runtime_state()
	connection_status_changed.emit("error")
	session_ended.emit("connection_failed")


func _on_server_disconnected() -> void:
	if _manual_leave:
		return
	if _transport_mode == TransportMode.PUBLIC_DIRECT and not _run_active:
		_handle_public_connection_failure()
		return
	_close_peer()
	_reset_runtime_state()
	connection_status_changed.emit("offline")
	session_ended.emit("server_disconnected")


func _on_peer_connected(_peer_id: int) -> void:
	# 客户端通过注册 RPC 提交名字；房主在注册成功后才分配稳定 seat。
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	if _manual_leave or not _session_active or not multiplayer.is_server():
		return
	if not _players.has(peer_id):
		return

	var was_defender := peer_id in _defenders
	_players.erase(peer_id)
	_round_expected.erase(peer_id)
	_round_results.erase(peer_id)
	_broadcast_lobby_snapshot()

	if _run_active and _phase == SessionPhase.JOINT_DEFENSE and was_defender:
		_server_handle_defender_disconnect(peer_id)
	elif _run_active:
		_server_try_finish_local_barrier()


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_register_player(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if _run_active:
		_reject_remote_peer(sender_id, "run_started")
		return
	if int(info.get("protocol_version", -1)) != PROTOCOL_VERSION:
		_reject_remote_peer(sender_id, "version_mismatch")
		return
	if not _players.has(sender_id) and _players.size() >= MAX_PLAYERS:
		_reject_remote_peer(sender_id, "room_full")
		return

	if _players.has(sender_id):
		var existing: Dictionary = _players[sender_id].duplicate(true)
		existing["display_name"] = _sanitize_display_name(str(info.get("display_name", "Player")))
		existing["connected"] = true
		_players[sender_id] = existing
	else:
		var seat := _allocate_seat()
		if seat < 0:
			_reject_remote_peer(sender_id, "room_full")
			return
		var room_host := false
		if _dedicated_server and not _dedicated_owner_token.is_empty() \
				and str(info.get("owner_token", "")) == _dedicated_owner_token:
			room_host = not _has_registered_room_host()
		_players[sender_id] = _make_player_state(
			sender_id,
			seat,
			_sanitize_display_name(str(info.get("display_name", "Player"))),
			room_host
		)
	_broadcast_lobby_snapshot()


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_reject_player(reason: String) -> void:
	if _transport_mode == TransportMode.NAKAMA:
		var nakama_manager := _nakama_session_manager()
		if nakama_manager and nakama_manager.has_method("reject_local_player"):
			nakama_manager.call_deferred("reject_local_player", reason)
		return
	call_deferred("leave_session")


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_set_ready(ready: bool) -> void:
	if not multiplayer.is_server() or _run_active:
		return
	_server_set_ready(multiplayer.get_remote_sender_id(), ready)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_request_start_run() -> void:
	if not multiplayer.is_server() or _run_active:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _players.has(sender_id):
		return
	if not bool((_players[sender_id] as Dictionary).get("room_host", false)):
		return
	_server_start_session_run()


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_submit_local_result(result: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_server_accept_local_result(multiplayer.get_remote_sender_id(), result)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_submit_joint_breach(stage_index: int, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_server_accept_joint_breach(multiplayer.get_remote_sender_id(), stage_index, payload)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_submit_stage_cleared(stage_index: int) -> void:
	if not multiplayer.is_server():
		return
	_server_accept_stage_cleared(multiplayer.get_remote_sender_id(), stage_index)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_mark_player_eliminated() -> void:
	if not multiplayer.is_server():
		return
	_server_mark_player_eliminated(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_apply_lobby_snapshot(snapshot: Array) -> void:
	_apply_lobby_snapshot(snapshot)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_begin_run() -> void:
	_apply_begin_run()


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_assign_joint_defense(stage_index: int, payloads: Array, keep_input_open: bool) -> void:
	_apply_joint_defense_assignment(stage_index, payloads, keep_input_open)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_receive_joint_enemy(payload: Dictionary) -> void:
	_apply_joint_enemy(payload)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_close_joint_input() -> void:
	_apply_joint_input_closed()


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_apply_source_life_damage(event_id: String, amount: int, expected_life: int) -> void:
	_apply_source_life_damage(event_id, amount, expected_life)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_round_resolved(resolved_round: int) -> void:
	_apply_round_resolved(resolved_round)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_session_ended(reason: String) -> void:
	_apply_session_ended(reason)


func _server_set_ready(peer_id: int, ready: bool) -> void:
	if not _players.has(peer_id) or _run_active:
		return
	var player: Dictionary = _players[peer_id].duplicate(true)
	player["ready"] = ready
	_players[peer_id] = player
	_broadcast_lobby_snapshot()


func _server_accept_local_result(peer_id: int, result: Dictionary) -> bool:
	if not multiplayer.is_server() or not _run_active:
		return false
	if not _players.has(peer_id) or not _round_expected.has(peer_id):
		return false
	if _round_results.has(peer_id):
		return false

	var sanitized := _sanitize_local_result(result, peer_id, _round_number)
	if int(sanitized.get("round", 0)) != _round_number:
		return false

	var canonical_breaches: Array[Dictionary] = []
	var seen_original_uids: Dictionary = {}
	for payload_value in sanitized.get("breached_enemies", []):
		if canonical_breaches.size() >= MAX_ENEMIES_PER_REPORT:
			break
		if not (payload_value is Dictionary):
			continue
		var payload: Dictionary = payload_value
		var original_uid := str(payload.get("enemy_uid", ""))
		if not original_uid.is_empty() and seen_original_uids.has(original_uid):
			continue
		if not original_uid.is_empty():
			seen_original_uids[original_uid] = true
		payload = _sanitize_enemy_payload(payload, peer_id)
		if payload.is_empty():
			continue
		payload["enemy_uid"] = _make_ticket_uid(peer_id)
		canonical_breaches.append(payload)

	sanitized["breached_enemies"] = canonical_breaches
	sanitized["breached_count"] = canonical_breaches.size()
	sanitized["perfect"] = canonical_breaches.is_empty()

	var local_damage := 0
	for payload in canonical_breaches:
		local_damage += int(payload.get("base_damage", 1))
	var player: Dictionary = _players[peer_id].duplicate(true)
	var maximum_life := maxi(1, int(player.get("max_life", DEFAULT_MAX_LIFE)))
	var current_life := clampi(int(player.get("life", maximum_life)), 0, maximum_life)
	current_life = maxi(0, current_life - local_damage)
	player["life"] = current_life
	player["eliminated"] = current_life <= 0 or bool(player.get("eliminated", false))
	_players[peer_id] = player
	sanitized["life"] = current_life
	sanitized["eliminated"] = bool(player["eliminated"])

	_round_results[peer_id] = sanitized
	for payload in canonical_breaches:
		_round_breaches.append(payload.duplicate(true))
	_phase = SessionPhase.WAITING_LOCAL_RESULTS
	_broadcast_lobby_snapshot()
	_server_try_finish_local_barrier()
	return true


func _server_try_finish_local_barrier() -> void:
	if not multiplayer.is_server() or not _run_active:
		return
	if _phase == SessionPhase.JOINT_DEFENSE or _round_resolve_sent:
		return
	for peer_id_value in _round_expected.keys():
		if not _round_results.has(int(peer_id_value)):
			return

	if _round_expected.is_empty():
		_server_end_session("no_active_players")
		return

	_defenders = _choose_defenders()
	if _round_breaches.is_empty():
		_server_resolve_round()
		return
	if _defenders.is_empty():
		for payload in _round_breaches:
			_server_apply_final_breach_damage(payload)
		_server_resolve_round()
		return
	_server_start_joint_defense()


func _choose_defenders() -> Array[int]:
	var candidates: Array[Dictionary] = []
	for peer_id_value in _round_results.keys():
		var peer_id := int(peer_id_value)
		if not _players.has(peer_id):
			continue
		var player: Dictionary = _players[peer_id]
		var result: Dictionary = _round_results[peer_id]
		if bool(player.get("connected", false)) \
				and not bool(player.get("eliminated", false)) \
				and bool(result.get("perfect", false)):
			candidates.append(player.duplicate(true))
	candidates.sort_custom(_sort_player_states)

	var result_ids: Array[int] = []
	for candidate in candidates:
		if result_ids.size() >= 2:
			break
		result_ids.append(int(candidate.get("peer_id", 0)))
	return result_ids


func _server_start_joint_defense() -> void:
	_phase = SessionPhase.JOINT_DEFENSE
	_joint_payload_by_uid.clear()
	_stage_cleared.clear()
	_stage_zero_breached.clear()
	_stage_one_received.clear()
	_stage_one_breached.clear()
	_final_damage_uids.clear()

	var initial_payloads: Array = []
	for payload_value in _round_breaches:
		var payload: Dictionary = payload_value.duplicate(true)
		var uid := str(payload.get("enemy_uid", ""))
		if uid.is_empty() or _joint_payload_by_uid.has(uid):
			continue
		_joint_payload_by_uid[uid] = payload.duplicate(true)
		initial_payloads.append(payload)

	_stage_cleared[0] = false
	_dispatch_joint_assignment(_defenders[0], 0, initial_payloads, false)
	if _defenders.size() >= 2:
		_stage_cleared[1] = false
		_dispatch_joint_assignment(_defenders[1], 1, [], true)


func _server_accept_joint_breach(peer_id: int, stage_index: int, reported_payload: Dictionary) -> void:
	if not multiplayer.is_server() or _phase != SessionPhase.JOINT_DEFENSE:
		return
	if stage_index < 0 or stage_index >= _defenders.size():
		return
	if _defenders[stage_index] != peer_id:
		return

	var uid := str(reported_payload.get("enemy_uid", ""))
	if uid.is_empty():
		return

	if stage_index == 0:
		if not _joint_payload_by_uid.has(uid) or _stage_zero_breached.has(uid):
			return
		_stage_zero_breached[uid] = true
		var authoritative: Dictionary = _joint_payload_by_uid[uid]
		var forwarded := _merge_enemy_progress(authoritative, reported_payload, 1)
		_joint_payload_by_uid[uid] = forwarded.duplicate(true)
		if _has_available_second_defender():
			_stage_one_received[uid] = forwarded.duplicate(true)
			_dispatch_joint_enemy(_defenders[1], forwarded)
		else:
			_server_apply_final_breach_damage(forwarded)
		return

	if not _stage_one_received.has(uid) or _stage_one_breached.has(uid):
		return
	_stage_one_breached[uid] = true
	var stage_one_authoritative: Dictionary = _stage_one_received[uid]
	var final_payload := _merge_enemy_progress(stage_one_authoritative, reported_payload, 2)
	_stage_one_received[uid] = final_payload.duplicate(true)
	_server_apply_final_breach_damage(final_payload)


func _server_accept_stage_cleared(peer_id: int, stage_index: int) -> void:
	if not multiplayer.is_server() or _phase != SessionPhase.JOINT_DEFENSE:
		return
	if stage_index < 0 or stage_index >= _defenders.size():
		return
	if _defenders[stage_index] != peer_id:
		return
	if bool(_stage_cleared.get(stage_index, false)):
		return
	_stage_cleared[stage_index] = true

	if stage_index == 0:
		if _has_available_second_defender():
			_dispatch_close_joint_input(_defenders[1])
		else:
			_server_resolve_round()
		return

	if bool(_stage_cleared.get(0, false)):
		_server_resolve_round()


func _server_apply_final_breach_damage(payload: Dictionary) -> void:
	var uid := str(payload.get("enemy_uid", ""))
	if uid.is_empty() or _final_damage_uids.has(uid):
		return
	_final_damage_uids[uid] = true

	var source_peer_id := int(payload.get("source_player_id", 0))
	var damage := clampi(int(payload.get("base_damage", 1)), 1, MAX_BASE_DAMAGE)
	if not _players.has(source_peer_id):
		return

	var player: Dictionary = _players[source_peer_id].duplicate(true)
	var maximum_life := maxi(1, int(player.get("max_life", DEFAULT_MAX_LIFE)))
	var previous_life := clampi(int(player.get("life", maximum_life)), 0, maximum_life)
	var next_life := maxi(0, previous_life - damage)
	player["life"] = next_life
	player["eliminated"] = next_life <= 0 or bool(player.get("eliminated", false))
	_players[source_peer_id] = player

	var event_id := "%s:%d:joint-final:%s" % [_session_uid, _round_number, uid]
	_dispatch_source_life_damage(source_peer_id, event_id, damage, next_life)
	_broadcast_lobby_snapshot()


func _server_resolve_round() -> void:
	if _round_resolve_sent:
		return
	_round_resolve_sent = true
	var resolved_round := _round_number
	_phase = SessionPhase.ROUND_RESOLVED
	_broadcast_lobby_snapshot()

	if _living_connected_player_ids().is_empty():
		_server_end_session("all_players_eliminated")
		return

	_rpc_round_resolved.rpc(resolved_round)
	call_deferred("_apply_round_resolved", resolved_round)
	if _is_final_run_round(resolved_round):
		_server_end_session("run_completed")
		return
	_server_prepare_round(resolved_round + 1)


func _server_prepare_round(next_round: int) -> void:
	_round_number = maxi(1, next_round)
	_round_expected.clear()
	_round_results.clear()
	_round_breaches.clear()
	_round_resolve_sent = false
	_next_ticket_serial = 1
	_defenders.clear()
	_joint_payload_by_uid.clear()
	_stage_cleared.clear()
	_stage_zero_breached.clear()
	_stage_one_received.clear()
	_stage_one_breached.clear()
	_final_damage_uids.clear()
	for peer_id in _living_connected_player_ids():
		_round_expected[peer_id] = true
	_phase = SessionPhase.LOCAL_BATTLE


func _server_mark_player_eliminated(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	var player: Dictionary = _players[peer_id].duplicate(true)
	player["life"] = 0
	player["eliminated"] = true
	_players[peer_id] = player
	# 淘汰玩家不再阻塞当前本地结果屏障。正常路径会先提交 result；
	# 若 result 缺失，也必须让其余玩家继续结算。
	_round_expected.erase(peer_id)
	_broadcast_lobby_snapshot()
	_server_try_finish_local_barrier()


func _server_handle_defender_disconnect(peer_id: int) -> void:
	var stage_index := _defenders.find(peer_id)
	if stage_index < 0:
		return
	if stage_index == 0:
		for uid_value in _joint_payload_by_uid.keys():
			var uid := str(uid_value)
			if _stage_zero_breached.has(uid):
				continue
			_stage_zero_breached[uid] = true
			var payload: Dictionary = _joint_payload_by_uid[uid]
			if _has_available_second_defender():
				var forwarded := _merge_enemy_progress(payload, payload, 1)
				_stage_one_received[uid] = forwarded.duplicate(true)
				_dispatch_joint_enemy(_defenders[1], forwarded)
			else:
				_server_apply_final_breach_damage(payload)
		_stage_cleared[0] = true
		if _has_available_second_defender():
			_dispatch_close_joint_input(_defenders[1])
		else:
			_server_resolve_round()
		return

	for uid_value in _stage_one_received.keys():
		var uid := str(uid_value)
		if _stage_one_breached.has(uid):
			continue
		_stage_one_breached[uid] = true
		_server_apply_final_breach_damage(_stage_one_received[uid])
	_stage_cleared[1] = true
	if bool(_stage_cleared.get(0, false)):
		_server_resolve_round()


func _server_end_session(reason: String) -> void:
	if not _run_active and _phase == SessionPhase.ENDED:
		return
	_run_active = false
	_phase = SessionPhase.ENDED
	_rpc_session_ended.rpc(reason)
	call_deferred("_apply_session_ended", reason)


func _dispatch_joint_assignment(peer_id: int, stage_index: int, payloads: Array, keep_input_open: bool) -> void:
	if peer_id == get_local_player_id():
		call_deferred("_apply_joint_defense_assignment", stage_index, payloads.duplicate(true), keep_input_open)
	else:
		_rpc_assign_joint_defense.rpc_id(peer_id, stage_index, payloads, keep_input_open)


func _dispatch_joint_enemy(peer_id: int, payload: Dictionary) -> void:
	if peer_id == get_local_player_id():
		call_deferred("_apply_joint_enemy", payload.duplicate(true))
	else:
		_rpc_receive_joint_enemy.rpc_id(peer_id, payload)


func _dispatch_close_joint_input(peer_id: int) -> void:
	if peer_id == get_local_player_id():
		call_deferred("_apply_joint_input_closed")
	else:
		_rpc_close_joint_input.rpc_id(peer_id)


func _dispatch_source_life_damage(peer_id: int, event_id: String, amount: int, expected_life: int) -> void:
	if peer_id == get_local_player_id():
		call_deferred("_apply_source_life_damage", event_id, amount, expected_life)
	elif _players.has(peer_id) and bool((_players[peer_id] as Dictionary).get("connected", false)):
		_rpc_apply_source_life_damage.rpc_id(peer_id, event_id, amount, expected_life)


func _apply_begin_run() -> void:
	# Event ids intentionally remain stable within one run. A room may start
	# another run without reconnecting, so old idempotency keys must not leak.
	_applied_life_damage_events.clear()
	_run_active = true
	_phase = SessionPhase.LOCAL_BATTLE
	_round_number = 1
	connection_status_changed.emit("running")
	_track_validation_event("run_started", {"round": _round_number})
	run_start_requested.emit()


func _apply_joint_defense_assignment(stage_index: int, payloads: Array, keep_input_open: bool) -> void:
	_phase = SessionPhase.JOINT_DEFENSE
	var sanitized_payloads: Array = []
	for payload_value in payloads:
		if payload_value is Dictionary:
			var payload := _sanitize_enemy_payload(payload_value)
			if not payload.is_empty():
				sanitized_payloads.append(payload)
	joint_defense_assigned.emit(stage_index, sanitized_payloads.duplicate(true), keep_input_open)


func _apply_joint_enemy(payload: Dictionary) -> void:
	var sanitized := _sanitize_enemy_payload(payload)
	if sanitized.is_empty():
		return
	joint_enemy_received.emit(sanitized.duplicate(true))


func _apply_joint_input_closed() -> void:
	joint_input_closed.emit()


func _apply_source_life_damage(event_id: String, amount: int, _expected_life: int) -> void:
	if event_id.is_empty() or _applied_life_damage_events.has(event_id):
		return
	_applied_life_damage_events[event_id] = true
	var game_manager := _game_manager()
	if game_manager and game_manager.has_method("damage_run_life"):
		game_manager.damage_run_life(clampi(amount, 1, MAX_BASE_DAMAGE))


func _apply_round_resolved(resolved_round: int) -> void:
	if resolved_round < 1:
		return
	var is_final_round := _is_final_run_round(resolved_round)
	_round_number = resolved_round if is_final_round else resolved_round + 1
	_phase = SessionPhase.ROUND_RESOLVED if is_final_round else SessionPhase.LOCAL_BATTLE
	_track_validation_event("round_completed", {"round": resolved_round})
	cooperative_round_resolved.emit(resolved_round)


func _apply_session_ended(reason: String) -> void:
	_run_active = false
	_phase = SessionPhase.ENDED
	connection_status_changed.emit("lobby")
	session_ended.emit(reason)


func _broadcast_lobby_snapshot() -> void:
	if not multiplayer.is_server():
		return
	var snapshot := _build_players_snapshot()
	_rpc_apply_lobby_snapshot.rpc(snapshot)
	_emit_lobby_updated()


func _apply_lobby_snapshot(snapshot: Array) -> void:
	var next_players: Dictionary = {}
	for player_value in snapshot:
		if not (player_value is Dictionary):
			continue
		var player := _sanitize_player_state(player_value)
		var peer_id := int(player.get("peer_id", 0))
		if peer_id > 0:
			next_players[peer_id] = player
	_players = next_players
	_emit_lobby_updated()
	if not _run_active:
		connection_status_changed.emit("lobby")


func _emit_lobby_updated() -> void:
	lobby_updated.emit(_build_players_snapshot())


func _build_players_snapshot() -> Array:
	var snapshot: Array[Dictionary] = []
	for player_value in _players.values():
		if player_value is Dictionary:
			snapshot.append(_sanitize_player_state(player_value))
	snapshot.sort_custom(_sort_player_states)
	var result: Array = []
	for player in snapshot:
		result.append(player.duplicate(true))
	return result


func _sort_player_states(a: Dictionary, b: Dictionary) -> bool:
	var seat_a := int(a.get("seat", 9999))
	var seat_b := int(b.get("seat", 9999))
	if seat_a == seat_b:
		return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0))
	return seat_a < seat_b


func _make_player_state(
		peer_id: int,
		seat: int,
		display_name: String,
		room_host: bool = false
	) -> Dictionary:
	var maximum_life := _configured_max_life()
	return {
		"peer_id": peer_id,
		"seat": seat,
		"display_name": _sanitize_display_name(display_name),
		"room_host": room_host,
		"ready": false,
		"connected": true,
		"eliminated": false,
		"life": maximum_life,
		"max_life": maximum_life,
	}


func _sanitize_player_state(value: Dictionary) -> Dictionary:
	var maximum_life := clampi(int(value.get("max_life", DEFAULT_MAX_LIFE)), 1, MAX_COMBAT_STAT)
	return {
		"peer_id": maxi(0, int(value.get("peer_id", 0))),
		"seat": clampi(int(value.get("seat", MAX_PLAYERS)), 1, MAX_PLAYERS),
		"display_name": _sanitize_display_name(str(value.get("display_name", "Player"))),
		"room_host": bool(value.get("room_host", false)),
		"ready": bool(value.get("ready", false)),
		"connected": bool(value.get("connected", true)),
		"eliminated": bool(value.get("eliminated", false)),
		"life": clampi(int(value.get("life", maximum_life)), 0, maximum_life),
		"max_life": maximum_life,
	}


func _sanitize_local_result(result: Dictionary, source_peer_id: int, fallback_round: int) -> Dictionary:
	var breaches: Array = []
	var raw_breaches = result.get("breached_enemies", [])
	if raw_breaches is Array:
		for payload_value in raw_breaches:
			if breaches.size() >= MAX_ENEMIES_PER_REPORT:
				break
			if payload_value is Dictionary:
				var payload := _sanitize_enemy_payload(payload_value, source_peer_id)
				if not payload.is_empty():
					breaches.append(payload)
	return {
		"round": clampi(int(result.get("round", fallback_round)), 1, 1_000_000),
		"perfect": breaches.is_empty(),
		"breached_count": breaches.size(),
		"breached_enemies": breaches,
		"life": clampi(int(result.get("life", 0)), 0, MAX_COMBAT_STAT),
		"eliminated": bool(result.get("eliminated", false)),
	}


func _sanitize_enemy_payload(
		value: Dictionary,
		source_override: int = -1
	) -> Dictionary:
	if value.is_empty():
		return {}

	var max_hp := clampi(
		int(value.get("max_hp", value.get("hp", 1))),
		1,
		MAX_COMBAT_STAT
	)
	var source_peer_id := source_override if source_override >= 0 else int(value.get("source_player_id", 0))
	var payload := {
		"enemy_uid": _bounded_string(value.get("enemy_uid", ""), 160),
		"enemy_id": _bounded_string(value.get("enemy_id", ""), MAX_ENEMY_ID_LENGTH),
		"name": _bounded_string(value.get("name", "Enemy"), MAX_ENEMY_NAME_LENGTH),
		"type": clampi(int(value.get("type", value.get("enemy_type", 0))), 0, 3),
		"hp": max_hp,
		"max_hp": max_hp,
		"current_hp": clampi(int(value.get("current_hp", max_hp)), 1, max_hp),
		"atk": clampi(int(value.get("atk", 0)), 0, MAX_COMBAT_STAT),
		"def": clampi(int(value.get("def", 0)), 0, MAX_COMBAT_STAT),
		"attack_speed": clampf(float(value.get("attack_speed", 1.0)), 0.0, 1000.0),
		"move_speed": clampf(float(value.get("move_speed", 1.0)), 0.0, 1000.0),
		"attack_range": clampf(float(value.get("attack_range", 1.0)), 0.0, 1000.0),
		"search_range": clampf(float(value.get("search_range", 5.0)), 0.0, 1000.0),
		"collision_radius": clampf(float(value.get("collision_radius", 0.0)), 0.0, 10_000.0),
		"source_player_id": maxi(0, source_peer_id),
		"base_damage": clampi(int(value.get("base_damage", 1)), 1, MAX_BASE_DAMAGE),
		"transfer_count": clampi(int(value.get("transfer_count", 0)), 0, MAX_TRANSFER_COUNT),
	}
	if payload["enemy_id"].is_empty():
		return {}

	for optional_string_key in ["visual_id"]:
		if value.has(optional_string_key):
			payload[optional_string_key] = _bounded_string(value[optional_string_key], 128)
	for optional_collection_key in ["passives", "skills", "tags"]:
		if value.has(optional_collection_key):
			payload[optional_collection_key] = _sanitize_nested_variant(value[optional_collection_key], 0)
	return payload


func _merge_enemy_progress(
		authoritative: Dictionary,
		reported: Dictionary,
		expected_transfer_count: int
	) -> Dictionary:
	var result := _sanitize_enemy_payload(
		authoritative,
		int(authoritative.get("source_player_id", 0))
	)
	var previous_hp := maxi(1, int(result.get("current_hp", 1)))
	result["current_hp"] = clampi(int(reported.get("current_hp", previous_hp)), 1, previous_hp)
	result["enemy_uid"] = str(authoritative.get("enemy_uid", ""))
	result["source_player_id"] = int(authoritative.get("source_player_id", 0))
	result["base_damage"] = int(authoritative.get("base_damage", 1))
	result["transfer_count"] = clampi(expected_transfer_count, 0, MAX_TRANSFER_COUNT)
	return result


func _sanitize_nested_variant(value, depth: int):
	if depth > 3:
		return null
	if value is bool or value is int:
		return value
	if value is float:
		return clampf(value, -float(MAX_COMBAT_STAT), float(MAX_COMBAT_STAT))
	if value is String:
		return _bounded_string(value, 256)
	if value is Array:
		var result_array: Array = []
		for item in value:
			if result_array.size() >= MAX_NESTED_COLLECTION_SIZE:
				break
			var sanitized = _sanitize_nested_variant(item, depth + 1)
			if sanitized != null:
				result_array.append(sanitized)
		return result_array
	if value is Dictionary:
		var result_dictionary: Dictionary = {}
		for key_value in value.keys():
			if result_dictionary.size() >= MAX_NESTED_COLLECTION_SIZE:
				break
			var key := _bounded_string(key_value, 96)
			if key.is_empty():
				continue
			var sanitized = _sanitize_nested_variant(value[key_value], depth + 1)
			if sanitized != null:
				result_dictionary[key] = sanitized
		return result_dictionary
	return null


func _allocate_seat() -> int:
	var occupied: Dictionary = {}
	for player_value in _players.values():
		if player_value is Dictionary:
			occupied[int(player_value.get("seat", -1))] = true
	for seat in range(1, MAX_PLAYERS + 1):
		if not occupied.has(seat):
			_next_seat = maxi(_next_seat, seat + 1)
			return seat
	return -1


func _has_registered_room_host() -> bool:
	for player_value in _players.values():
		if player_value is Dictionary and bool(player_value.get("room_host", false)):
			return true
	return false


func _living_connected_player_ids() -> Array[int]:
	var states: Array[Dictionary] = []
	for player_value in _players.values():
		if not (player_value is Dictionary):
			continue
		var player: Dictionary = player_value
		if bool(player.get("connected", false)) and not bool(player.get("eliminated", false)):
			states.append(player)
	states.sort_custom(_sort_player_states)
	var ids: Array[int] = []
	for player in states:
		ids.append(int(player.get("peer_id", 0)))
	return ids


func _has_available_second_defender() -> bool:
	if _defenders.size() < 2:
		return false
	var peer_id := _defenders[1]
	return _players.has(peer_id) \
		and bool((_players[peer_id] as Dictionary).get("connected", false)) \
		and not bool((_players[peer_id] as Dictionary).get("eliminated", false))


func _make_ticket_uid(source_peer_id: int) -> String:
	var uid := "%s:%d:%d:%d" % [
		_session_uid,
		_round_number,
		source_peer_id,
		_next_ticket_serial,
	]
	_next_ticket_serial += 1
	return uid


func _configured_max_life() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var registry := tree.root.get_node_or_null("DataRegistry")
		if registry and registry.has_method("get_config"):
			return maxi(1, int(registry.get_config("roguelike_player_max_life", DEFAULT_MAX_LIFE)))
	return DEFAULT_MAX_LIFE


func _is_final_run_round(round_number: int) -> bool:
	var maximum_rounds := 15
	var game_manager := _game_manager()
	if game_manager:
		var configured_value = game_manager.get("max_run_rounds")
		if configured_value != null:
			maximum_rounds = maxi(1, int(configured_value))
	return round_number >= maximum_rounds


func _sanitize_display_name(value: String) -> String:
	var result := value.strip_edges()
	if result.is_empty():
		result = "Player"
	return _bounded_string(result, MAX_DISPLAY_NAME_LENGTH)


func _bounded_string(value, maximum_length: int) -> String:
	var result := str(value)
	if result.length() > maximum_length:
		result = result.substr(0, maximum_length)
	return result


func _reject_remote_peer(peer_id: int, reason: String) -> void:
	if peer_id <= 0:
		return
	_rpc_reject_player.rpc_id(peer_id, reason)
	if _transport_mode != TransportMode.NAKAMA:
		call_deferred("_disconnect_remote_peer", peer_id)


func _disconnect_remote_peer(peer_id: int) -> void:
	if _enet_peer and peer_id > 0:
		_enet_peer.disconnect_peer(peer_id)


func _server_peer_id() -> int:
	return maxi(1, _authority_peer_id)


func _battle_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("BattleManager")


func _game_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("GameManager")


func _public_network_helper() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("PublicNetworkHelper")


func _nakama_session_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("NakamaSessionManager")


func _track_validation_event(event_name: String, properties: Dictionary) -> void:
	if _transport_mode != TransportMode.NAKAMA:
		return
	var nakama_manager := _nakama_session_manager()
	if nakama_manager and nakama_manager.has_method("track_event"):
		nakama_manager.call("track_event", event_name, properties)


func handle_nakama_transport_lost(reason: String = "connection_lost") -> void:
	if _manual_leave or _transport_mode != TransportMode.NAKAMA:
		return
	_close_peer()
	_reset_runtime_state()
	connection_status_changed.emit("offline")
	session_ended.emit(reason)


func _cfg_value(key: String, default_value):
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var registry := tree.root.get_node_or_null("DataRegistry")
		if registry and registry.has_method("get_config"):
			return registry.get_config(key, default_value)
	return default_value


func _cfg_string(key: String, default_value: String) -> String:
	return str(_cfg_value(key, default_value)).strip_edges()


func _cfg_bool(key: String, default_value: bool) -> bool:
	return bool(_cfg_value(key, default_value))


func _cfg_float(key: String, default_value: float) -> float:
	return float(_cfg_value(key, default_value))


func _emit_public_endpoint_result(
		success: bool,
		external_address: String,
		port: int,
		error_code: int
	) -> void:
	public_endpoint_ready.emit(success, external_address, port, error_code)


func _on_public_mapping_completed(
		success: bool,
		external_address: String,
		port: int,
		error_code: int
	) -> void:
	if not _session_active or _transport_mode != TransportMode.PUBLIC_DIRECT \
			or not multiplayer.is_server():
		if success:
			_release_public_mapping()
		return
	_emit_public_endpoint_result(success, external_address, port, error_code)


func _release_public_mapping() -> void:
	var helper := _public_network_helper()
	if not helper or not helper.has_method("get_mapped_port") \
			or not helper.has_method("request_mapping_removal"):
		return
	var mapped_port := int(helper.call("get_mapped_port"))
	if mapped_port > 0:
		helper.call("request_mapping_removal", mapped_port)


func _handle_public_connection_failure() -> void:
	if not _session_active:
		return
	var failed_mode := _transport_mode
	var failed_generation := _transport_generation
	_awaiting_connection = false
	_connect_time_remaining = 0.0
	_close_peer()
	_reset_runtime_state()
	if failed_mode == TransportMode.PUBLIC_DIRECT:
		connection_status_changed.emit("direct_failed")
		direct_connection_timed_out.emit(failed_generation)
	else:
		connection_status_changed.emit("error")
		session_ended.emit("connection_failed")


func _close_peer() -> void:
	_awaiting_connection = false
	_connect_time_remaining = 0.0
	if _enet_peer:
		_enet_peer.close()
	_enet_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _reset_runtime_state() -> void:
	_phase = SessionPhase.OFFLINE
	_session_active = false
	_run_active = false
	_dedicated_server = false
	_session_uid = ""
	_next_seat = 2
	_transport_mode = TransportMode.OFFLINE
	_transport_generation = 0
	_awaiting_connection = false
	_connect_time_remaining = 0.0
	_dedicated_owner_token = ""
	_relay_owner_token = ""
	_authority_peer_id = SERVER_PEER_ID
	set_multiplayer_authority(SERVER_PEER_ID)
	_registration_sent = false
	_players.clear()
	_round_number = 0
	_round_expected.clear()
	_round_results.clear()
	_round_breaches.clear()
	_round_resolve_sent = false
	_next_ticket_serial = 1
	_defenders.clear()
	_joint_payload_by_uid.clear()
	_stage_cleared.clear()
	_stage_zero_breached.clear()
	_stage_one_received.clear()
	_stage_one_breached.clear()
	_final_damage_uids.clear()
	_applied_life_damage_events.clear()
