extends Node

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("MinorSynergySmoke")
var grid: GridSystem


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	_reset_battle_state()
	grid = GridSystem.new()
	grid.draw_grid = false
	grid.debug_unit_body_radii = false
	grid.debug_attack_ranges = false
	grid.debug_collision_prediction = false
	add_child(grid)

	_test_dex_extra_attack()
	_test_constitution_heal_pulse()
	_test_flying_ground_melee_immunity()
	_test_support_global_damage_reduction()

	SynergyManager.clear_test_synergy_override()
	_reset_battle_state()
	t.finish(get_tree())


func _test_dex_extra_attack() -> void:
	_clear_units()
	SynergyManager.set_test_synergy_override([{"id": "stat_dex", "count": 3, "layer": 999}])
	var attacker := _spawn_hero("rogue_assassin", Vector2i(1, 1))
	var enemy := _spawn_enemy(Vector2i(3, 1), 2000, 0, 10)
	SynergyManager.recalculate()
	var before := enemy.current_hp
	attacker._deal_damage_to_target(enemy, float(attacker.attack), false)
	var dealt := before - enemy.current_hp
	t.assert_true(dealt >= attacker.attack * 2, "DEX 999 guarantees at least one extra basic attack")


func _test_constitution_heal_pulse() -> void:
	_clear_units()
	SynergyManager.set_test_synergy_override([{"id": "stat_con", "count": 3, "layer": 999}])
	var defender := _spawn_hero("fighter_champion", Vector2i(1, 1))
	var ally := _spawn_hero("barbarian_berserker", Vector2i(2, 1))
	var enemy := _spawn_enemy(Vector2i(3, 1), 1000, 0, 50)
	SynergyManager.recalculate()
	ally.current_hp = maxi(1, ally.max_hp / 2)
	var before := ally.current_hp
	defender.receive_attack_damage(50, 0.0, enemy)
	t.assert_true(ally.current_hp > before, "CON tier 3 heals nearby allies after the member is hit")


func _test_flying_ground_melee_immunity() -> void:
	_clear_units()
	SynergyManager.set_test_synergy_override([{"id": "trait_flying", "count": 1, "layer": 20}])
	var flyer := _spawn_hero("sorcerer_storm", Vector2i(1, 1))
	var enemy := _spawn_enemy(Vector2i(2, 1), 1000, 0, 50)
	SynergyManager.recalculate()
	t.assert_true(flyer.airborne, "FLYING member is marked airborne")
	var before := flyer.current_hp
	var dealt := flyer.receive_attack_damage(50, 0.0, enemy)
	t.assert_eq(dealt, 0, "ground melee attack is canceled against an airborne member")
	t.assert_eq(flyer.current_hp, before, "airborne member loses no HP to ground melee")


func _test_support_global_damage_reduction() -> void:
	_clear_units()
	SynergyManager.set_test_synergy_override([{"id": "trait_support", "count": 2, "layer": 40}])
	var non_support := _spawn_hero("fighter_champion", Vector2i(1, 1))
	var enemy := _spawn_enemy(Vector2i(2, 1), 1000, 0, 100)
	SynergyManager.recalculate()
	var raw_after_defense := maxi(1, 100 - non_support.defense)
	var dealt := non_support.receive_attack_damage(100, 0.0, enemy)
	t.assert_eq(dealt, maxi(1, int(round(float(raw_after_defense) * 0.8))), "support reduces damage taken by non-support allies by 20 percent")


func _spawn_hero(class_id: String, cell: Vector2i) -> HeroUnit:
	var hero := HeroUnit.new()
	hero.star_level = 1
	hero.setup(ClassDefinitions.get_template(class_id), 1)
	grid.place_unit(hero, cell)
	return hero


func _spawn_enemy(cell: Vector2i, hp: int, defense: int, attack: int) -> EnemyUnit:
	var enemy := EnemyUnit.new()
	enemy.setup_from_template({
		"enemy_id": "synergy_dummy_%d" % cell.x,
		"name": "羁绊测试假人",
		"type": "melee",
		"hp": hp,
		"atk": attack,
		"def": defense,
		"attack_speed": 1.0,
		"move_speed": 0.0,
		"attack_range": 1.0,
		"search_range": 5.0,
	})
	grid.place_unit(enemy, cell)
	return enemy


func _clear_units() -> void:
	if not grid:
		return
	for unit in grid.all_units.duplicate():
		if is_instance_valid(unit):
			grid.remove_unit(unit)
			unit.queue_free()
	grid.all_units.clear()
	grid.occupancy.clear()
	grid.movement_reservations.clear()
	BattleManager.player_units.clear()
	BattleManager.enemy_units.clear()


func _reset_battle_state() -> void:
	BattleManager.player_units.clear()
	BattleManager.enemy_units.clear()
	BattleManager.wave_enemies.clear()
	BattleManager.enemy_pool.clear()
	BattleManager.state = BattleManager.BattleState.IN_PROGRESS
	ResourceManager.reset_dp(100, 100)
