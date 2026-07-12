# smoke_scene_loader.gd - Loads core scenes headlessly and checks for script/node errors.
extends SceneTree

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

const SCENES := [
	"res://scenes/start_menu.tscn",
	"res://scenes/afk_hub.tscn",
	"res://scenes/main.tscn",
	"res://scenes/combat_test.tscn",
	"res://scenes/encyclopedia.tscn",
	"res://scenes/roguelike_relic_select.tscn",
]

var t := TestAssertions.new("SmokeSceneLoader")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	for scene_path in SCENES:
		await _load_scene(scene_path)
	t.finish(self)


func _load_scene(scene_path: String) -> void:
	paused = false
	var resource := load(scene_path)
	t.assert_true(resource is PackedScene, "scene loads as PackedScene: %s" % scene_path)
	if not (resource is PackedScene):
		return

	var scene := (resource as PackedScene).instantiate()
	t.assert_true(scene != null, "scene instantiates: %s" % scene_path)
	if not scene:
		return

	root.add_child(scene)
	await process_frame
	await process_frame
	t.assert_true(is_instance_valid(scene), "scene remains valid after ready: %s" % scene_path)

	if scene_path.ends_with("main.tscn"):
		t.assert_true(scene.get_node_or_null("GridSystem") != null, "main has GridSystem")
		t.assert_true(scene.get_node_or_null("DeploymentSystem") != null, "main has DeploymentSystem")
		t.assert_true(scene.get_node_or_null("RoguelikeManager") != null, "main has RoguelikeManager")
	if scene_path.ends_with("combat_test.tscn"):
		t.assert_true(scene.get_node_or_null("CombatTestRunner") != null, "combat_test has runner")
		t.assert_true(scene.get_node_or_null("CombatTestControls") != null, "combat_test has controls")

	scene.queue_free()
	await process_frame
	paused = false

