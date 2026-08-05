# dedicated_room_server.gd — 单房间、无渲染的 ENet 中继权威进程
extends SceneTree

var _relay_port := 0
var _room_code := ""
var _owner_token := ""
var _idle_timeout_seconds := 120.0
var _last_player_activity_msec := 0
var _manager: Node = null


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--relay-port="):
			_relay_port = int(argument.trim_prefix("--relay-port="))
		elif argument.begins_with("--room-code="):
			_room_code = argument.trim_prefix("--room-code=").strip_edges().to_upper()
		elif argument.begins_with("--owner-token="):
			_owner_token = argument.trim_prefix("--owner-token=")
		elif argument.begins_with("--idle-timeout="):
			_idle_timeout_seconds = maxf(
				10.0,
				float(argument.trim_prefix("--idle-timeout="))
			)
	call_deferred("_start_relay")


func _start_relay() -> void:
	await process_frame
	_manager = root.get_node_or_null("MultiplayerRunManager")
	if not _manager:
		push_error("MultiplayerRunManager autoload is unavailable.")
		quit(2)
		return
	if _relay_port <= 0 or _relay_port > 65535 or _room_code.is_empty() \
			or _owner_token.is_empty():
		push_error("Missing relay-port, room-code, or owner-token.")
		quit(2)
		return
	var error := int(_manager.call(
		"host_dedicated_session",
		_relay_port,
		_room_code,
		_owner_token
	))
	if error != OK:
		push_error("Unable to open relay port %d (error %d)." % [_relay_port, error])
		quit(error)
		return
	_last_player_activity_msec = Time.get_ticks_msec()
	_manager.lobby_updated.connect(_on_lobby_updated)
	_manager.session_ended.connect(_on_session_ended)
	print("PARADISO_RELAY_READY room=%s port=%d" % [_room_code, _relay_port])
	_monitor_idle_timeout()


func _monitor_idle_timeout() -> void:
	while _manager and bool(_manager.call("is_session_active")):
		await create_timer(1.0).timeout
		var players = _manager.call("get_players_snapshot")
		if players is Array and not players.is_empty():
			_last_player_activity_msec = Time.get_ticks_msec()
			continue
		var idle_seconds := (
			float(Time.get_ticks_msec() - _last_player_activity_msec) / 1000.0
		)
		if idle_seconds >= _idle_timeout_seconds:
			print("PARADISO_RELAY_IDLE_TIMEOUT room=%s" % _room_code)
			quit()
			return


func _on_lobby_updated(players: Array) -> void:
	if not players.is_empty():
		_last_player_activity_msec = Time.get_ticks_msec()


func _on_session_ended(_reason: String) -> void:
	# Give reliable ENet packets a short window to reach every client.
	await create_timer(2.0).timeout
	quit()
