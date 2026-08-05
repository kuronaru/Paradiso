# public_network_helper.gd — 公网端点探测与 UPnP UDP 端口映射
extends Node

signal mapping_completed(success: bool, external_address: String, port: int, error_code: int)
signal mapping_removed(port: int, error_code: int)

const OP_NONE := ""
const OP_MAP := "map"
const OP_UNMAP := "unmap"
const UPNP_SUCCESS := 0

var _worker: Thread = null
var _operation := OP_NONE
var _operation_port := 0
var _mapped_port := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if not _worker or _worker.is_alive():
		return
	var result = _worker.wait_to_finish()
	_worker = null
	var completed_operation := _operation
	var completed_port := _operation_port
	_operation = OP_NONE
	_operation_port = 0

	if not (result is Dictionary):
		result = {"success": false, "address": "", "error_code": ERR_CANT_RESOLVE}
	if completed_operation == OP_MAP:
		var success := bool(result.get("success", false))
		if success:
			_mapped_port = completed_port
		mapping_completed.emit(
			success,
			str(result.get("address", "")),
			completed_port,
			int(result.get("error_code", FAILED))
		)
	elif completed_operation == OP_UNMAP:
		if int(result.get("error_code", FAILED)) == UPNP_SUCCESS and _mapped_port == completed_port:
			_mapped_port = 0
		mapping_removed.emit(completed_port, int(result.get("error_code", FAILED)))


func request_port_mapping(port: int) -> bool:
	if is_busy() or port <= 0 or port > 65535:
		return false
	_operation = OP_MAP
	_operation_port = port
	_worker = Thread.new()
	var error := _worker.start(_map_udp_port.bind(port))
	if error == OK:
		return true
	_worker = null
	_operation = OP_NONE
	_operation_port = 0
	return false


func request_mapping_removal(port: int = _mapped_port) -> bool:
	if is_busy() or port <= 0 or port > 65535:
		return false
	_operation = OP_UNMAP
	_operation_port = port
	_worker = Thread.new()
	var error := _worker.start(_remove_udp_port.bind(port))
	if error == OK:
		return true
	_worker = null
	_operation = OP_NONE
	_operation_port = 0
	return false


func is_busy() -> bool:
	return _worker != null


func get_mapped_port() -> int:
	return _mapped_port


func get_preferred_local_address() -> String:
	for address in IP.get_local_addresses():
		var candidate := str(address)
		if candidate.begins_with("127.") or candidate == "::1" or candidate.contains(":"):
			continue
		return candidate
	return "127.0.0.1"


func _map_udp_port(port: int) -> Dictionary:
	var upnp := UPNP.new()
	var discovery_error := upnp.discover(2000, 2, "InternetGatewayDevice")
	if discovery_error != UPNP_SUCCESS:
		return {
			"success": false,
			"address": "",
			"error_code": discovery_error,
		}
	var mapping_error := upnp.add_port_mapping(port, port, "Paradiso", "UDP")
	if mapping_error != UPNP_SUCCESS:
		return {
			"success": false,
			"address": "",
			"error_code": mapping_error,
		}
	var external_address := upnp.query_external_address()
	if external_address.is_empty():
		upnp.delete_port_mapping(port, "UDP")
	return {
		"success": not external_address.is_empty(),
		"address": external_address,
		"error_code": UPNP_SUCCESS if not external_address.is_empty() else ERR_CANT_RESOLVE,
	}


func _remove_udp_port(port: int) -> Dictionary:
	var upnp := UPNP.new()
	var discovery_error := upnp.discover(2000, 2, "InternetGatewayDevice")
	if discovery_error != UPNP_SUCCESS:
		return {"error_code": discovery_error}
	return {"error_code": upnp.delete_port_mapping(port, "UDP")}
