# projectile_attack_test.gd - Verifies that basic attacks resolve through projectiles.
extends SceneTree

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("ProjectileAttack")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame

	var unit_script = load("res://scripts/units/unit_base.gd")
	t.assert_true(unit_script != null, "UnitBase script loads")
	if not unit_script:
		t.finish(self)
		return

	var attacker = unit_script.new()
	var target = unit_script.new()
	root.add_child(attacker)
	root.add_child(target)
	await process_frame

	attacker.global_position = Vector2(100.0, 100.0)
	attacker.attack = 20
	attacker.attack_speed = 10.0
	attacker.projectile_speed = 640.0
	attacker.projectile_visual_radius = 4.0
	attacker.target = target
	target.global_position = Vector2(260.0, 100.0)
	target.max_hp = 100
	target.current_hp = 100
	target.defense = 0

	attacker.perform_attack()
	t.assert_eq(target.current_hp, 100, "basic attack does not damage immediately")
	t.assert_eq(_projectile_count(), 1, "basic attack creates one projectile")

	await create_timer(0.25).timeout
	t.assert_eq(target.current_hp, 100, "projectile has not hit before traveling enough distance")

	await create_timer(0.35).timeout
	t.assert_eq(target.current_hp, 80, "projectile applies damage after reaching target at fixed speed")
	t.assert_eq(_projectile_count(), 0, "projectile is destroyed after hit")

	attacker.queue_free()
	target.queue_free()
	await process_frame
	t.finish(self)


func _projectile_count() -> int:
	var count := 0
	for child in root.get_children():
		var script = child.get_script()
		if script and script.resource_path == "res://scripts/combat/projectile.gd":
			count += 1
	return count
