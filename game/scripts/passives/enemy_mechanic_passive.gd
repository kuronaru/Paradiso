class_name EnemyMechanicPassive
extends UnitPassive

var mechanic_id: String = ""
var params: Dictionary = {}
var dynamic_modifiers: Dictionary = {}
var phase: int = 1
var action_timer: float = 0.0
var secondary_timer: float = 0.0
var flight_remaining: float = 0.0
var summons_created: int = 0
var attack_count: int = 0
var shield_remaining: int = 0
var last_target_id: int = 0
var focus_stacks: int = 0
var plague_hits: Dictionary = {}
var gargoyle_grounded: bool = false


func setup(p_unit: UnitBase, config: Dictionary = {}) -> void:
	super.setup(p_unit, config)
	mechanic_id = str(config.get("mechanic_id", passive_id))
	var raw_params = config.get("params", {})
	params = raw_params.duplicate(true) if raw_params is Dictionary else {}
	match mechanic_id:
		"banshee_wail", "inquisitor_question":
			action_timer = float(params.get("interval", 5.0))
		"plaguecrown_phases":
			action_timer = float(params.get("summon_interval", 7.0))
			secondary_timer = 0.1
		"black_knight_shield":
			shield_remaining = maxi(1, int(round(float(unit.max_hp) * float(params.get("shield_max_hp_ratio", 0.3)))))
		"imp_swoop":
			flight_remaining = float(params.get("flight_duration", 2.5))
			_set_airborne(true)
		"black_dragon_phases":
			action_timer = float(params.get("breath_interval", 7.0))


func get_modifiers() -> Dictionary:
	var result := super.get_modifiers()
	for key in dynamic_modifiers.keys():
		result[key] = dynamic_modifiers[key]
	return result


func on_tick(context: Dictionary) -> void:
	if not is_active():
		return
	var delta := maxf(0.0, float(context.get("delta", 0.0)))
	match mechanic_id:
		"banshee_wail":
			_tick_banshee(delta)
		"inquisitor_question":
			_tick_inquisitor(delta)
		"plaguecrown_phases":
			_tick_plaguecrown(delta)
		"cemetery_knight_phases":
			_tick_cemetery_knight()
		"imp_swoop":
			_tick_imp(delta)
		"gargoyle_stance":
			_tick_gargoyle()
		"black_dragon_phases":
			_tick_black_dragon(delta)


func before_deal_damage(context: Dictionary) -> void:
	if mechanic_id != "bonebow_focus":
		return
	var target_unit := context.get("target", null) as UnitBase
	if not target_unit:
		return
	var target_id := target_unit.get_instance_id()
	if target_id == last_target_id:
		focus_stacks = mini(int(params.get("max_stacks", 3)), focus_stacks + 1)
	else:
		last_target_id = target_id
		focus_stacks = 0
	var multiplier := 1.0 + float(focus_stacks) * float(params.get("damage_per_stack", 0.12))
	context["damage"] = maxi(1, int(round(float(context.get("damage", 1)) * multiplier)))


func after_deal_damage(context: Dictionary) -> void:
	if mechanic_id != "ghoul_bloodscent" or not is_active():
		return
	var target_unit := context.get("target", null) as UnitBase
	if not target_unit or target_unit.max_hp <= 0:
		return
	var hp_ratio := float(target_unit.current_hp) / float(target_unit.max_hp)
	if hp_ratio <= float(params.get("hp_threshold", 0.5)):
		unit.heal(maxi(1, int(round(float(context.get("damage_dealt", 0)) * float(params.get("life_steal_ratio", 0.25))))))


func before_receive_attack(context: Dictionary) -> void:
	if mechanic_id not in ["shieldguard_front", "cemetery_knight_phases"]:
		return
	if mechanic_id == "cemetery_knight_phases" and phase > 1:
		return
	var attacker := context.get("attacker", null) as UnitBase
	if not attacker or not _is_front_attack(attacker):
		return
	var multiplier := float(params.get("front_damage_multiplier", 0.65))
	context["amount"] = maxi(1, int(round(float(context.get("amount", 1)) * multiplier)))


func before_apply_attack_damage(context: Dictionary) -> void:
	if mechanic_id != "black_knight_shield" or shield_remaining <= 0:
		return
	var incoming := maxi(0, int(context.get("damage", 0)))
	var absorbed := mini(shield_remaining, incoming)
	shield_remaining -= absorbed
	context["damage"] = incoming - absorbed
	if absorbed > 0:
		unit._show_floating_text("护盾 -%d" % absorbed, Color(0.58, 0.38, 0.95, 1.0))
	if shield_remaining <= 0:
		unit._show_floating_text("破誓甲碎裂", Color(1.0, 0.26, 0.22, 1.0))
		_set_dynamic_modifiers({
			"attack_multiplier": float(params.get("broken_attack_multiplier", 1.45)),
			"attack_speed_multiplier": float(params.get("broken_attack_speed_multiplier", 1.4)),
			"defense_multiplier": float(params.get("broken_defense_multiplier", 0.7)),
		})


func after_basic_attack(context: Dictionary) -> void:
	var target_unit := context.get("target", null) as UnitBase
	if not target_unit or not is_instance_valid(target_unit):
		return
	match mechanic_id:
		"plague_strikes":
			_apply_plague_hit(target_unit)
		"butcher_sweep":
			attack_count += 1
			if attack_count % maxi(1, int(params.get("trigger_every", 3))) == 0:
				_perform_butcher_sweep(target_unit)


func before_death(_context: Dictionary) -> void:
	if mechanic_id != "slime_split" or not is_instance_valid(unit):
		return
	unit._show_floating_text("分裂", Color(0.48, 0.86, 0.32, 1.0))
	_queue_reinforcements(
		str(params.get("spawn_enemy_id", "corrupted_slime_small")),
		maxi(1, int(params.get("spawn_count", 2)))
	)


func get_debug_state() -> Dictionary:
	return {
		"mechanic_id": mechanic_id,
		"phase": phase,
		"shield_remaining": shield_remaining,
		"focus_stacks": focus_stacks,
		"summons_created": summons_created,
		"airborne": unit.airborne if is_instance_valid(unit) else false,
	}


func _apply_plague_hit(target_unit: UnitBase) -> void:
	var target_id := target_unit.get_instance_id()
	var hits := int(plague_hits.get(target_id, 0)) + 1
	var required := maxi(1, int(params.get("required_hits", 3)))
	if hits >= required:
		hits = 0
		target_unit.apply_timed_combat_modifier(
			"enemy_plague",
			float(params.get("duration", 4.0)),
			{"incoming_heal_multiplier": float(params.get("incoming_heal_multiplier", 0.65))}
		)
		target_unit._show_floating_text("疫病", Color(0.58, 0.82, 0.22, 1.0))
	plague_hits[target_id] = hits


func _perform_butcher_sweep(primary_target: UnitBase) -> void:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	unit._show_floating_text("屠案横扫", Color(1.0, 0.48, 0.18, 1.0))
	var targets := grid.get_units_in_range(primary_target.grid_position, float(params.get("radius", 1.5)), "player")
	for candidate in targets:
		var combat_unit := candidate as UnitBase
		if combat_unit and combat_unit.is_alive:
			combat_unit.receive_attack_damage(
				maxi(1, int(round(float(unit.attack) * float(params.get("damage_multiplier", 0.75))))),
				0.0,
				unit
			)


func _tick_banshee(delta: float) -> void:
	action_timer -= delta
	if action_timer > 0.0:
		return
	action_timer += maxf(0.2, float(params.get("interval", 6.0)))
	unit._show_floating_text("葬城哀嚎", Color(0.50, 0.65, 1.0, 1.0))
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	for candidate in grid.get_units_in_range(unit.grid_position, float(params.get("radius", 2.5)), "player"):
		var target_unit := candidate as UnitBase
		if target_unit:
			target_unit.apply_timed_combat_modifier(
				"banshee_wail",
				float(params.get("duration", 3.0)),
				{"attack_speed_multiplier": float(params.get("attack_speed_multiplier", 0.72))}
			)


func _tick_inquisitor(delta: float) -> void:
	action_timer -= delta
	if action_timer > 0.0:
		return
	action_timer += maxf(0.2, float(params.get("interval", 5.0)))
	var target_unit := _select_player_by_attack()
	if not target_unit:
		return
	unit._show_floating_text("失序诘问", Color(0.92, 0.38, 0.82, 1.0))
	target_unit.apply_timed_combat_modifier(
		"inquisitor_question",
		float(params.get("duration", 3.0)),
		{"attack_multiplier": float(params.get("attack_multiplier", 0.72))}
	)


func _tick_plaguecrown(delta: float) -> void:
	var hp_ratio := _hp_ratio()
	if hp_ratio <= 0.3 and phase < 3:
		phase = 3
		unit._show_floating_text("狂暴阶段", Color(1.0, 0.22, 0.18, 1.0))
		_set_dynamic_modifiers({
			"attack_speed_multiplier": float(params.get("rage_attack_speed_multiplier", 1.55)),
			"move_speed_multiplier": float(params.get("rage_move_speed_multiplier", 1.45)),
		})
	elif hp_ratio <= 0.6 and phase < 2:
		phase = 2
		unit._show_floating_text("瘟冠破裂", Color(0.58, 0.92, 0.24, 1.0))
		_apply_area_modifier(
			"plaguecrown_slow",
			float(params.get("slow_radius", 2.0)),
			float(params.get("slow_duration", 2.5)),
			{"move_speed_multiplier": float(params.get("slow_multiplier", 0.7))},
			"player"
		)

	secondary_timer -= delta
	if secondary_timer <= 0.0 and phase < 3:
		secondary_timer += 0.5
		_apply_goblin_aura()

	action_timer -= delta
	if action_timer <= 0.0 and phase < 3 and summons_created < int(params.get("max_summons", 4)):
		action_timer += maxf(1.0, float(params.get("summon_interval", 7.0)))
		unit._show_floating_text("黑羽集结", Color(0.72, 0.88, 0.24, 1.0))
		_queue_reinforcements(str(params.get("summon_enemy_id", "plague_goblin")), 1)


func _apply_goblin_aura() -> void:
	for candidate in BattleManager.enemy_units:
		var ally := candidate as EnemyUnit
		if not ally or ally == unit or not ally.is_alive:
			continue
		if "goblin" not in ally.spawn_template.get("tags", []):
			continue
		if _grid_distance(unit, ally) > float(params.get("aura_radius", 3.0)):
			continue
		ally.apply_timed_combat_modifier(
			"plaguecrown_command",
			float(params.get("aura_duration", 0.8)),
			{"attack_speed_multiplier": float(params.get("aura_attack_speed_multiplier", 1.2))}
		)


func _tick_cemetery_knight() -> void:
	var hp_ratio := _hp_ratio()
	if hp_ratio <= 0.35 and phase < 3:
		phase = 3
		unit._show_floating_text("失誓冲锋", Color(0.42, 0.70, 1.0, 1.0))
		_set_dynamic_modifiers({
			"attack_speed_multiplier": float(params.get("rage_attack_speed_multiplier", 1.5)),
			"move_speed_multiplier": float(params.get("rage_move_speed_multiplier", 1.6)),
			"defense_multiplier": float(params.get("rage_defense_multiplier", 0.7)),
		})
	elif hp_ratio <= 0.65 and phase < 2:
		phase = 2
		unit._show_floating_text("亡军召回", Color(0.40, 0.72, 1.0, 1.0))
		_queue_reinforcements(
			str(params.get("summon_enemy_id", "skeleton_shieldguard")),
			maxi(1, int(params.get("summon_count", 2)))
		)


func _tick_imp(delta: float) -> void:
	if flight_remaining <= 0.0:
		return
	flight_remaining -= delta
	if flight_remaining <= 0.0:
		_set_airborne(false)
		unit._show_floating_text("落地", Color(0.86, 0.42, 0.72, 1.0))


func _tick_gargoyle() -> void:
	var should_ground := unit.ai_controller != null and unit.ai_controller.state == "attacking"
	if should_ground == gargoyle_grounded:
		return
	gargoyle_grounded = should_ground
	_set_airborne(not should_ground)
	_set_dynamic_modifiers({
		"defense_multiplier": float(params.get("grounded_defense_multiplier", 1.35)) if should_ground else 1.0,
	})
	unit._show_floating_text("落地守势" if should_ground else "巡空", Color(0.60, 0.46, 0.82, 1.0))


func _tick_black_dragon(delta: float) -> void:
	var hp_ratio := _hp_ratio()
	if hp_ratio <= 0.35 and phase < 3:
		phase = 3
		_set_airborne(false)
		unit._show_floating_text("断翼俯冲", Color(1.0, 0.20, 0.30, 1.0))
		_set_dynamic_modifiers({
			"attack_speed_multiplier": float(params.get("rage_attack_speed_multiplier", 1.45)),
			"move_speed_multiplier": float(params.get("rage_move_speed_multiplier", 1.35)),
		})
		action_timer = float(params.get("dive_interval", 5.0))
	elif hp_ratio <= 0.7 and phase < 2:
		phase = 2
		_set_airborne(true)
		flight_remaining = float(params.get("air_duration", 3.0))
		unit._show_floating_text("王庭升空", Color(0.72, 0.30, 0.92, 1.0))
		_queue_reinforcements(
			str(params.get("summon_enemy_id", "bloodpact_imp")),
			maxi(1, int(params.get("summon_count", 3)))
		)

	if phase == 2 and flight_remaining > 0.0:
		flight_remaining -= delta
		if flight_remaining <= 0.0:
			_set_airborne(false)
			unit._show_floating_text("黑龙落地", Color(0.68, 0.32, 0.86, 1.0))

	action_timer -= delta
	if action_timer > 0.0:
		return
	if phase < 3:
		action_timer += maxf(1.0, float(params.get("breath_interval", 7.0)))
		_perform_dragon_breath()
	else:
		action_timer += maxf(1.0, float(params.get("dive_interval", 5.0)))
		_perform_dragon_dive()


func _perform_dragon_breath() -> void:
	var target_unit := unit.target as UnitBase
	if not target_unit or not is_instance_valid(target_unit):
		return
	unit._show_floating_text("门扉吐息", Color(0.88, 0.24, 0.72, 1.0))
	var width := maxi(0, int(params.get("breath_width", 1)))
	for candidate in BattleManager.player_units:
		var hero_unit := candidate as UnitBase
		if not hero_unit or not hero_unit.is_alive:
			continue
		if abs(hero_unit.grid_position.y - target_unit.grid_position.y) <= width:
			hero_unit.receive_attack_damage(
				maxi(1, int(round(float(unit.attack) * float(params.get("breath_damage_multiplier", 1.1))))),
				0.0,
				unit
			)


func _perform_dragon_dive() -> void:
	var target_unit := _select_farthest_player()
	if not target_unit:
		return
	unit._show_floating_text("俯冲", Color(1.0, 0.24, 0.28, 1.0))
	target_unit.receive_attack_damage(
		maxi(1, int(round(float(unit.attack) * float(params.get("dive_damage_multiplier", 1.25))))),
		0.0,
		unit
	)


func _apply_area_modifier(status_id: String, radius: float, duration: float, values: Dictionary, team: String) -> void:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	for candidate in grid.get_units_in_range(unit.grid_position, radius, team):
		var target_unit := candidate as UnitBase
		if target_unit:
			target_unit.apply_timed_combat_modifier(status_id, duration, values)


func _queue_reinforcements(enemy_id: String, count: int) -> void:
	if enemy_id == "" or count <= 0 or not DataRegistry:
		return
	var template: Dictionary = DataRegistry.get_enemy(enemy_id)
	if template.is_empty():
		return
	for _i in range(count):
		if BattleManager.queue_enemy_reinforcement(template, unit.grid_position):
			summons_created += 1


func _set_dynamic_modifiers(values: Dictionary) -> void:
	if dynamic_modifiers == values:
		return
	dynamic_modifiers = values.duplicate(true)
	if is_instance_valid(unit):
		unit._refresh_passive_modifiers()


func _set_airborne(value: bool) -> void:
	if not is_instance_valid(unit) or unit.airborne == value:
		return
	unit.airborne = value
	unit.refresh_ground_collision()


func _is_front_attack(attacker: UnitBase) -> bool:
	if attacker.grid_position != unit.grid_position:
		return attacker.grid_position.x <= unit.grid_position.x
	return attacker.global_position.x <= unit.global_position.x


func _hp_ratio() -> float:
	return float(unit.current_hp) / float(maxi(1, unit.max_hp))


func _grid_distance(a: UnitBase, b: UnitBase) -> float:
	var grid: GridSystem = BattleManager.grid
	return grid.get_distance(a.grid_position, b.grid_position) if grid else a.global_position.distance_to(b.global_position) / 64.0


func _select_player_by_attack() -> UnitBase:
	var best: UnitBase = null
	for candidate in BattleManager.player_units:
		var target_unit := candidate as UnitBase
		if not target_unit or not target_unit.is_alive:
			continue
		if not best or target_unit.attack > best.attack:
			best = target_unit
	return best


func _select_farthest_player() -> UnitBase:
	var best: UnitBase = null
	var best_distance := -1.0
	for candidate in BattleManager.player_units:
		var target_unit := candidate as UnitBase
		if not target_unit or not target_unit.is_alive:
			continue
		var distance := _grid_distance(unit, target_unit)
		if distance > best_distance:
			best = target_unit
			best_distance = distance
	return best
