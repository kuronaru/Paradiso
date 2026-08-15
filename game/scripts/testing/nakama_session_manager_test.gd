extends Node

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("NakamaSessionManager")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var manager := get_node_or_null("/root/NakamaSessionManager")
	t.assert_true(manager != null, "Nakama session manager autoload exists")
	if not manager:
		t.finish(get_tree())
		return

	t.assert_eq(manager.normalize_room_code(" ab-0i3dk "), "AB3DK", "ambiguous and separator characters are removed")
	t.assert_true(manager.is_valid_room_code("AB3D7K"), "six-character code is accepted")
	t.assert_false(manager.is_valid_room_code("AB0I7K"), "ambiguous characters are rejected")
	var generated: String = manager.generate_room_code()
	t.assert_eq(generated.length(), 6, "generated code has configured length")
	t.assert_true(manager.is_valid_room_code(generated), "generated code uses the accepted alphabet")
	t.assert_eq(manager.build_match_name("ab3d7k"), "paradiso-2-AB3D7K", "match name isolates protocol versions")
	t.assert_false(manager.is_configured(), "empty validation host keeps external networking disabled")
	t.assert_true(manager.get_build_version().begins_with("0.1.0"), "build version is exposed to invitation UI")
	t.finish(get_tree())
