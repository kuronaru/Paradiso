# Browser-friendly Nakama session and relayed-match transport adapter.
extends Node

signal state_changed(state: String)
signal room_joined(room_code: String, is_host: bool)
signal room_left(reason: String)
signal request_failed(operation: String, message: String, diagnostic_id: String)
signal persistence_warning(message: String)

const DEVICE_ID_PATH := "user://nakama_device_id.txt"
const ROOM_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const DEFAULT_CODE_LENGTH := 6
const MAX_CREATE_ATTEMPTS := 3

enum State {
	OFFLINE,
	AUTHENTICATING,
	CONNECTING,
	JOINING,
	IN_ROOM,
	ERROR,
}

var _state: State = State.OFFLINE
var _client = null
var _session = null
var _socket = null
var _bridge = null
var _room_code := ""
var _display_name := "Player"
var _create_intent := false
var _create_attempts := 0
var _intent_serial := 0
var _intentional_close := false
var _session_device_id := ""
var _diagnostic_serial := 0
var _pending_events: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_web_build():
		track_event("page_started", {})
		if not OS.is_userfs_persistent():
			persistence_warning.emit("浏览器未提供持久化存储，本次身份与存档可能在关闭页面后丢失。")


func is_web_build() -> bool:
	return OS.has_feature("web")


func is_configured() -> bool:
	if not bool(_cfg("nakama_enabled", true)):
		return false
	var host := str(_cfg("nakama_host", "")).strip_edges()
	var scheme := str(_cfg("nakama_scheme", "https")).strip_edges().to_lower()
	if host.is_empty():
		return false
	return not is_web_build() or scheme == "https"


func get_state_name() -> String:
	return State.keys()[_state].to_lower()


func get_room_code() -> String:
	return _room_code


func get_build_version() -> String:
	return str(_cfg("web_build_version", "dev")).strip_edges()


func get_publish_url() -> String:
	return str(_cfg("web_publish_url", "")).strip_edges()


func get_feedback_url() -> String:
	return str(_cfg("web_feedback_url", "")).strip_edges()


func normalize_room_code(value: String) -> String:
	var result := ""
	for character in value.strip_edges().to_upper():
		if ROOM_ALPHABET.contains(character):
			result += character
	return result.substr(0, _room_code_length())


func is_valid_room_code(value: String) -> bool:
	var normalized := normalize_room_code(value)
	return normalized.length() == _room_code_length() and normalized == value.strip_edges().to_upper()


func generate_room_code() -> String:
	var result := ""
	for _index in range(_room_code_length()):
		result += ROOM_ALPHABET[randi_range(0, ROOM_ALPHABET.length() - 1)]
	return result


func build_match_name(room_code: String) -> String:
	return "paradiso-%d-%s" % [_protocol_version(), normalize_room_code(room_code)]


func create_room(display_name: String) -> void:
	if _state != State.OFFLINE and _state != State.ERROR:
		_fail("create", "当前正在连接或已经加入房间。")
		return
	if not is_configured():
		_fail("configure", "Nakama 尚未配置，请填写 Validation 环境的 HTTPS 主机地址。")
		return
	_display_name = _sanitize_name(display_name)
	_create_intent = true
	_create_attempts = 0
	_room_code = generate_room_code()
	_begin_join_intent()


func join_room(room_code: String, display_name: String) -> void:
	if _state != State.OFFLINE and _state != State.ERROR:
		_fail("join", "当前正在连接或已经加入房间。")
		return
	var normalized := normalize_room_code(room_code)
	if normalized.length() != _room_code_length():
		_fail("join", "请输入有效的 %d 位房间码。" % _room_code_length())
		return
	if not is_configured():
		_fail("configure", "Nakama 尚未配置，请填写 Validation 环境的 HTTPS 主机地址。")
		return
	_display_name = _sanitize_name(display_name)
	_create_intent = false
	_room_code = normalized
	_begin_join_intent()


func _begin_join_intent() -> void:
	_intent_serial += 1
	var serial := _intent_serial
	_intentional_close = false
	_join_room_async(serial)


func _join_room_async(serial: int) -> void:
	if not await _ensure_connection(serial):
		return
	if serial != _intent_serial:
		return
	_set_state(State.JOINING)
	_bridge = NakamaMultiplayerBridge.new(_socket)
	_bridge.multiplayer_peer.peer_disconnected.connect(_on_bridge_peer_disconnected.bind(serial))
	_bridge.match_joined.connect(_on_bridge_match_joined.bind(serial), CONNECT_ONE_SHOT)
	_bridge.match_join_error.connect(_on_bridge_match_join_error.bind(serial), CONNECT_ONE_SHOT)
	_bridge.join_named_match(build_match_name(_room_code))


func _ensure_connection(serial: int) -> bool:
	if _socket != null and _socket.is_connected_to_host() and _session != null and _session.valid:
		return true
	var nakama := get_node_or_null("/root/Nakama")
	if not nakama:
		_fail("initialize", "Nakama SDK 未加载。")
		return false
	_set_state(State.AUTHENTICATING)
	var scheme := str(_cfg("nakama_scheme", "https")).strip_edges().to_lower()
	_client = nakama.create_client(
		str(_cfg("nakama_server_key", "defaultkey")),
		str(_cfg("nakama_host", "")).strip_edges(),
		int(_cfg("nakama_port", 443)),
		scheme,
		int(_cfg("nakama_connect_timeout", 8))
	)
	_session = await _client.authenticate_device_async(_load_or_create_device_id(), null, true)
	if serial != _intent_serial:
		return false
	if _is_exception(_session) or not bool(_session.valid):
		_fail("authenticate", _exception_message(_session, "匿名登录失败。"))
		return false
	_flush_pending_events()
	track_event("authentication_succeeded", {"persistent": OS.is_userfs_persistent()})

	_set_state(State.CONNECTING)
	_socket = nakama.create_socket_from(_client)
	_socket.closed.connect(_on_socket_closed)
	_socket.connection_error.connect(_on_socket_connection_error)
	_socket.received_error.connect(_on_socket_received_error)
	var result = await _socket.connect_async(_session, true, int(_cfg("nakama_connect_timeout", 8)))
	if serial != _intent_serial:
		return false
	if _is_exception(result) or not _socket.is_connected_to_host():
		_fail("connect", _exception_message(result, "无法建立 Nakama WebSocket 连接。"))
		return false
	return true


func _on_bridge_match_joined(serial: int) -> void:
	if serial != _intent_serial or _bridge == null:
		return
	var local_id := int(_bridge.multiplayer_peer.get_unique_id())
	var became_host := local_id == 1
	if _create_intent and not became_host:
		_intentional_close = true
		await _bridge.leave()
		_intentional_close = false
		_bridge = null
		_create_attempts += 1
		if _create_attempts >= MAX_CREATE_ATTEMPTS:
			_fail("create", "连续生成的房间码均已占用，请重试。")
			return
		_room_code = generate_room_code()
		_join_room_async(serial)
		return
	if not _create_intent and became_host:
		_intentional_close = true
		await _bridge.leave()
		_intentional_close = false
		_bridge = null
		_fail("join", "房间不存在，或房主已经离开。")
		return

	multiplayer.multiplayer_peer = _bridge.multiplayer_peer
	var manager := get_node_or_null("/root/MultiplayerRunManager")
	if not manager or not manager.has_method("attach_nakama_session"):
		await leave_room("manager_unavailable")
		_fail("initialize", "联机规则管理器未加载。")
		return
	var attach_result := int(manager.call(
		"attach_nakama_session", _room_code, _display_name, became_host, 1
	))
	if attach_result != OK:
		await leave_room("attach_failed")
		_fail("join", "无法把 Nakama 房间接入游戏，错误码 %d。" % attach_result)
		return
	_set_state(State.IN_ROOM)
	track_event("room_created" if became_host else "room_joined", {
		"room_code": _room_code,
		"peer_id": local_id,
	})
	room_joined.emit(_room_code, became_host)


func _on_bridge_match_join_error(exception, serial: int) -> void:
	if serial != _intent_serial:
		return
	_bridge = null
	_fail("create" if _create_intent else "join", _exception_message(exception, "加入房间失败。"))


func leave_room(reason: String = "left") -> void:
	if _state == State.OFFLINE and _bridge == null and _socket == null:
		return
	_intent_serial += 1
	_intentional_close = true
	track_event("room_left", {"reason": reason})
	if _bridge != null:
		await _bridge.leave()
	_bridge = null
	if _socket != null:
		_socket.close()
	_socket = null
	_client = null
	_session = null
	_room_code = ""
	_set_state(State.OFFLINE)
	room_left.emit(reason)
	_intentional_close = false


func reject_local_player(reason: String) -> void:
	var message: String = str({
		"room_full": "房间已满（最多 4 人）。",
		"run_started": "游戏已经开始，本轮不支持中途加入。",
		"version_mismatch": "客户端协议版本不一致。",
	}.get(reason, "房主拒绝了本次加入。"))
	await leave_room(reason)
	_fail("join", str(message))


func handle_transport_lost(reason: String = "connection_lost") -> void:
	if _intentional_close:
		return
	_intent_serial += 1
	_intentional_close = true
	if _socket != null and _socket.is_connected_to_host():
		_socket.close()
	_bridge = null
	_socket = null
	_room_code = ""
	_set_state(State.ERROR)
	track_event("unexpected_disconnect", {"reason": reason})
	var manager := get_node_or_null("/root/MultiplayerRunManager")
	if manager and manager.has_method("handle_nakama_transport_lost"):
		manager.call("handle_nakama_transport_lost", reason)
	_fail("connection", "网络连接已断开。")
	_intentional_close = false


func _on_bridge_peer_disconnected(peer_id: int, serial: int) -> void:
	if _intentional_close or serial != _intent_serial or _bridge == null:
		return
	var local_id := int(_bridge.multiplayer_peer.get_unique_id())
	if local_id != 1 and peer_id == 1:
		handle_transport_lost("host_left")


func track_event(event_name: String, properties: Dictionary = {}) -> void:
	var payload := properties.duplicate(true)
	payload["build_version"] = get_build_version()
	payload["protocol_version"] = _protocol_version()
	if not _room_code.is_empty():
		payload["room_code"] = _room_code
	print("[validation_event] %s %s" % [event_name, JSON.stringify(payload)])
	if _client != null and _session != null and bool(_session.valid):
		_send_event_async(event_name, payload)
	elif _pending_events.size() < 32:
		_pending_events.append({"name": event_name, "properties": payload})


func _flush_pending_events() -> void:
	var events := _pending_events.duplicate(true)
	_pending_events.clear()
	for event in events:
		_send_event_async(str(event.get("name", "validation_event")), event.get("properties", {}))


func _send_event_async(event_name: String, properties: Dictionary) -> void:
	var result = await _client.event_async(_session, event_name, properties)
	if _is_exception(result):
		push_warning("Nakama telemetry failed: %s" % _exception_message(result, "unknown"))


func _on_socket_closed() -> void:
	if not _intentional_close:
		handle_transport_lost("socket_closed")


func _on_socket_connection_error(error) -> void:
	if not _intentional_close:
		handle_transport_lost("socket_error_%s" % str(error))


func _on_socket_received_error(error) -> void:
	if _intentional_close:
		return
	var diagnostic := _next_diagnostic_id()
	request_failed.emit("socket", str(error), diagnostic)


func _set_state(next_state: State) -> void:
	_state = next_state
	state_changed.emit(get_state_name())


func _fail(operation: String, message: String) -> void:
	_set_state(State.ERROR)
	var diagnostic := _next_diagnostic_id()
	track_event("network_error", {
		"operation": operation,
		"diagnostic_id": diagnostic,
		"message": message,
	})
	request_failed.emit(operation, message, diagnostic)


func _next_diagnostic_id() -> String:
	_diagnostic_serial += 1
	return "NET-%d-%03d" % [int(Time.get_unix_time_from_system()), _diagnostic_serial]


func _load_or_create_device_id() -> String:
	if not _session_device_id.is_empty():
		return _session_device_id
	if FileAccess.file_exists(DEVICE_ID_PATH):
		var file := FileAccess.open(DEVICE_ID_PATH, FileAccess.READ)
		if file:
			var stored := file.get_as_text().strip_edges()
			if stored.length() >= 16:
				_session_device_id = stored
				return _session_device_id
	_session_device_id = _generate_device_id()
	var output := FileAccess.open(DEVICE_ID_PATH, FileAccess.WRITE)
	if output:
		output.store_string(_session_device_id)
	elif is_web_build():
		persistence_warning.emit("浏览器无法保存匿名身份，本次将使用临时会话。")
	return _session_device_id


func _generate_device_id() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


func _is_exception(value) -> bool:
	return value != null and value.has_method("is_exception") and bool(value.is_exception())


func _exception_message(value, fallback: String) -> String:
	if value == null:
		return fallback
	if value.has_method("get_exception"):
		var exception = value.get_exception()
		if exception != null:
			var message := str(exception.get("message")).strip_edges()
			if not message.is_empty() and message != "<null>":
				return message
	var direct_message = value.get("message") if value is Object else null
	if direct_message != null and not str(direct_message).strip_edges().is_empty():
		return str(direct_message)
	return fallback


func _sanitize_name(value: String) -> String:
	var result := value.strip_edges()
	if result.is_empty():
		result = "Player"
	return result.substr(0, 32)


func _room_code_length() -> int:
	return clampi(int(_cfg("web_room_code_length", DEFAULT_CODE_LENGTH)), 4, 10)


func _protocol_version() -> int:
	var manager := get_node_or_null("/root/MultiplayerRunManager")
	if manager and manager.has_method("get_protocol_version"):
		return int(manager.call("get_protocol_version"))
	return 2


func _cfg(key: String, fallback):
	var registry := get_node_or_null("/root/DataRegistry")
	if registry and registry.has_method("get_config"):
		return registry.call("get_config", key, fallback)
	return fallback
