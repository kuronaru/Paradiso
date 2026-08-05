# public_room_client.gd — 中央公网房间服务的轻量 HTTP JSON 客户端
extends Node

signal room_created(room)
signal room_joined(room)
signal room_updated(room)
signal relay_requested(room)
signal room_closed
signal request_failed(operation, message, status_code)

const OP_CREATE := "create"
const OP_JOIN := "join"
const OP_POLL := "poll"
const OP_RELAY := "relay"
const OP_HEARTBEAT := "heartbeat"
const OP_CLOSE := "close"

var _request: HTTPRequest = null
var _queue: Array[Dictionary] = []
var _active_request: Dictionary = {}
var _room: Dictionary = {}
var _room_code := ""
var _host_token := ""
var _room_token := ""
var _is_room_host := false
var _poll_time_remaining := 0.0
var _heartbeat_time_remaining := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_request = HTTPRequest.new()
	_request.name = "RoomServiceRequest"
	_request.timeout = maxf(1.0, _cfg_float("public_room_request_timeout", 5.0))
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)
	set_process(true)


func _process(delta: float) -> void:
	if _room_code.is_empty():
		return
	var interval := maxf(0.25, _cfg_float("public_room_poll_interval", 1.0))
	_poll_time_remaining -= maxf(0.0, delta)
	if _poll_time_remaining <= 0.0:
		_poll_time_remaining = interval
		if not _has_queued_operation(OP_POLL):
			poll_room()
	if not _is_room_host:
		return
	_heartbeat_time_remaining -= maxf(0.0, delta)
	if _heartbeat_time_remaining <= 0.0:
		_heartbeat_time_remaining = maxf(2.0, interval * 3.0)
		if not _has_queued_operation(OP_HEARTBEAT):
			heartbeat()


func create_public_room(
		host_name: String,
		direct_address: String,
		direct_port: int,
		direct_available: bool,
		max_players: int = 4
	) -> void:
	reset_room()
	_enqueue(
		OP_CREATE,
		HTTPClient.METHOD_POST,
		"/v1/rooms",
		{
			"host_name": host_name.strip_edges(),
			"max_players": clampi(max_players, 2, 4),
			"direct_address": direct_address.strip_edges(),
			"direct_port": direct_port,
			"direct_available": direct_available,
		}
	)


func join_public_room(room_code: String, display_name: String) -> void:
	reset_room()
	var normalized_code := room_code.strip_edges().to_upper()
	_enqueue(
		OP_JOIN,
		HTTPClient.METHOD_POST,
		"/v1/rooms/%s/join" % normalized_code.uri_encode(),
		{"display_name": display_name.strip_edges()},
		"",
		normalized_code
	)


func poll_room() -> void:
	if _room_code.is_empty():
		return
	_enqueue(
		OP_POLL,
		HTTPClient.METHOD_GET,
		"/v1/rooms/%s" % _room_code.uri_encode()
	)


func request_relay() -> void:
	var token := _host_token if _is_room_host else _room_token
	if _room_code.is_empty() or token.is_empty():
		request_failed.emit(OP_RELAY, "缺少房间凭证，无法申请中继。", 0)
		return
	if _has_queued_operation(OP_RELAY):
		return
	_enqueue(
		OP_RELAY,
		HTTPClient.METHOD_POST,
		"/v1/rooms/%s/relay" % _room_code.uri_encode(),
		{},
		token
	)


func heartbeat(status: String = "") -> void:
	if _room_code.is_empty() or _host_token.is_empty():
		return
	var body := {}
	if not status.is_empty():
		body["status"] = status
	_enqueue(
		OP_HEARTBEAT,
		HTTPClient.METHOD_POST,
		"/v1/rooms/%s/heartbeat" % _room_code.uri_encode(),
		body,
		_host_token
	)


func close_room() -> void:
	if _room_code.is_empty() or _host_token.is_empty():
		reset_room()
		room_closed.emit()
		return
	_enqueue(
		OP_CLOSE,
		HTTPClient.METHOD_DELETE,
		"/v1/rooms/%s" % _room_code.uri_encode(),
		{},
		_host_token
	)


func reset_room() -> void:
	_queue.clear()
	if _request and not _active_request.is_empty():
		_request.cancel_request()
	_active_request.clear()
	_room.clear()
	_room_code = ""
	_host_token = ""
	_room_token = ""
	_is_room_host = false
	_poll_time_remaining = 0.0
	_heartbeat_time_remaining = 0.0


func has_room() -> bool:
	return not _room_code.is_empty()


func is_room_host() -> bool:
	return _is_room_host


func get_room_code() -> String:
	return _room_code


func get_host_token() -> String:
	return _host_token


func get_room_token() -> String:
	return _room_token


func get_room_snapshot() -> Dictionary:
	return _room.duplicate(true)


func _enqueue(
		operation: String,
		method: HTTPClient.Method,
		path: String,
		body: Dictionary = {},
		token: String = "",
		pending_room_code: String = ""
	) -> void:
	_queue.append({
		"operation": operation,
		"method": method,
		"path": path,
		"body": body.duplicate(true),
		"token": token,
		"pending_room_code": pending_room_code,
	})
	_start_next_request()


func _start_next_request() -> void:
	if not _request or not _active_request.is_empty() or _queue.is_empty():
		return
	_active_request = _queue.pop_front()
	var headers := PackedStringArray(["Accept: application/json"])
	var token := str(_active_request.get("token", ""))
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	var body := ""
	var method := int(_active_request.get("method", HTTPClient.METHOD_GET))
	if method != HTTPClient.METHOD_GET:
		headers.append("Content-Type: application/json")
		body = JSON.stringify(_active_request.get("body", {}))
	var error := _request.request(
		_service_url() + str(_active_request.get("path", "")),
		headers,
		method,
		body
	)
	if error == OK:
		return
	var failed_operation := str(_active_request.get("operation", "request"))
	_active_request.clear()
	request_failed.emit(failed_operation, "无法连接公网房间服务（错误码 %d）。" % error, 0)
	call_deferred("_start_next_request")


func _on_request_completed(
		result: int,
		response_code: int,
		_headers: PackedStringArray,
		body: PackedByteArray
	) -> void:
	if _active_request.is_empty():
		return
	var request_info := _active_request.duplicate(true)
	_active_request.clear()
	var operation := str(request_info.get("operation", "request"))
	var payload = JSON.parse_string(body.get_string_from_utf8())
	if not (payload is Dictionary):
		payload = {}
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var message := str(payload.get("error", "房间服务请求失败。"))
		if result != HTTPRequest.RESULT_SUCCESS and response_code == 0:
			message = "无法连接公网房间服务（结果码 %d）。" % result
		request_failed.emit(operation, message, response_code)
		call_deferred("_start_next_request")
		return
	_apply_success(operation, payload, request_info)
	call_deferred("_start_next_request")


func _apply_success(operation: String, payload: Dictionary, request_info: Dictionary) -> void:
	match operation:
		OP_CREATE:
			_room = payload.duplicate(true)
			_room_code = str(payload.get("room_code", "")).to_upper()
			_host_token = str(payload.get("host_token", ""))
			_room_token = str(payload.get("room_token", ""))
			_is_room_host = true
			_reset_poll_timers()
			room_created.emit(_room.duplicate(true))
		OP_JOIN:
			_room = payload.duplicate(true)
			_room_code = str(payload.get(
				"room_code",
				request_info.get("pending_room_code", "")
			)).to_upper()
			_room_token = str(payload.get("room_token", ""))
			_is_room_host = false
			_reset_poll_timers()
			room_joined.emit(_room.duplicate(true))
		OP_POLL:
			_room = payload.duplicate(true)
			room_updated.emit(_room.duplicate(true))
		OP_RELAY:
			_room = payload.duplicate(true)
			relay_requested.emit(_room.duplicate(true))
			room_updated.emit(_room.duplicate(true))
		OP_HEARTBEAT:
			_room = payload.duplicate(true)
			room_updated.emit(_room.duplicate(true))
		OP_CLOSE:
			reset_room()
			room_closed.emit()


func _reset_poll_timers() -> void:
	_poll_time_remaining = maxf(0.25, _cfg_float("public_room_poll_interval", 1.0))
	_heartbeat_time_remaining = 0.0


func _has_queued_operation(operation: String) -> bool:
	if str(_active_request.get("operation", "")) == operation:
		return true
	for value in _queue:
		if value is Dictionary and str(value.get("operation", "")) == operation:
			return true
	return false


func _service_url() -> String:
	return _cfg_string("public_room_service_url", "http://127.0.0.1:8787").trim_suffix("/")


func _cfg_value(key: String, default_value):
	var registry := get_node_or_null("/root/DataRegistry")
	if registry and registry.has_method("get_config"):
		return registry.get_config(key, default_value)
	return default_value


func _cfg_string(key: String, default_value: String) -> String:
	return str(_cfg_value(key, default_value)).strip_edges()


func _cfg_float(key: String, default_value: float) -> float:
	return float(_cfg_value(key, default_value))
