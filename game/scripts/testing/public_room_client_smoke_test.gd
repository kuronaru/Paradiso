# public_room_client_smoke_test.gd — Godot HTTP client against a live room service.
extends SceneTree

const TIMEOUT_SECONDS := 10.0

var client: Node = null
var assertions := 0
var failed := false
var finishing := false
var phase := "create"
var elapsed := 0.0
var service_url := "http://127.0.0.1:18787"


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--service-url="):
			service_url = argument.trim_prefix("--service-url=").trim_suffix("/")
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var registry := root.get_node_or_null("DataRegistry")
	client = root.get_node_or_null("PublicRoomClient")
	if not registry or not client:
		_finish(false, "required autoload is unavailable")
		return
	registry._config["public_room_service_url"] = service_url
	registry._config["public_room_poll_interval"] = 5.0
	client.room_created.connect(_on_room_created)
	client.room_joined.connect(_on_room_joined)
	client.room_updated.connect(_on_room_updated)
	client.request_failed.connect(_on_request_failed)
	client.create_public_room("HttpHost", "203.0.113.9", 24567, true, 4)
	_watch_timeout()


func _watch_timeout() -> void:
	while not finishing:
		await create_timer(0.1).timeout
		elapsed += 0.1
		if elapsed >= TIMEOUT_SECONDS:
			_finish(false, "room HTTP client timed out in phase %s" % phase)
			return


func _on_room_created(room: Dictionary) -> void:
	if phase != "create":
		return
	if str(room.get("status", "")) != "DIRECT":
		_finish(false, "created room did not publish DIRECT transport")
		return
	var room_code := str(room.get("room_code", ""))
	if room_code.length() != 6 or str(room.get("host_token", "")).is_empty():
		_finish(false, "created room omitted code or host token")
		return
	assertions += 2
	phase = "join"
	client.reset_room()
	client.join_public_room(room_code, "HttpGuest")


func _on_room_joined(room: Dictionary) -> void:
	if phase != "join":
		return
	if int(room.get("player_count", 0)) != 2 \
			or str(room.get("room_token", "")).is_empty():
		_finish(false, "join response omitted reservation or room token")
		return
	assertions += 2
	phase = "poll"
	client.poll_room()


func _on_room_updated(room: Dictionary) -> void:
	if phase != "poll":
		return
	if int(room.get("player_count", 0)) != 2:
		_finish(false, "poll returned inconsistent player count")
		return
	assertions += 1
	_finish(true, "create, join, and poll completed (%d assertions)" % assertions)


func _on_request_failed(operation: String, message: String, status_code: int) -> void:
	_finish(
		false,
		"%s failed: %s (HTTP %d)" % [operation, message, status_code]
	)


func _finish(success: bool, message: String) -> void:
	if finishing:
		return
	finishing = true
	failed = not success
	print("[%s] PublicRoomClientSmoke: %s" % ["PASS" if success else "FAIL", message])
	if client:
		client.reset_room()
	await create_timer(0.1).timeout
	quit(0 if success else 1)
