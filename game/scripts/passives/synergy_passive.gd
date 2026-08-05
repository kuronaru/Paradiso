class_name SynergyPassive
extends UnitPassive

const COLOR_POISON := Color(0.50, 0.86, 0.22, 1.0)
const COLOR_NATURE := Color(0.32, 0.90, 0.48, 1.0)
const COLOR_BURN := Color(1.0, 0.28, 0.08, 1.0)
const COLOR_FORBIDDEN := Color(0.72, 0.34, 1.0, 1.0)
const COLOR_LAW := Color(0.96, 0.90, 0.62, 1.0)
const COLOR_LAW_SHARE := Color(0.92, 0.86, 0.58, 1.0)
const COLOR_DODGE := Color(0.68, 0.88, 1.0, 1.0)
const COLOR_COOLDOWN := Color(0.50, 0.82, 1.0, 1.0)
const COLOR_HEAL := Color(0.30, 1.0, 0.52, 1.0)
const COLOR_EVIL := Color(0.86, 0.18, 0.42, 1.0)
const COLOR_TELEPORT := Color(0.82, 0.42, 1.0, 1.0)

var synergy_tag: String = ""
var effect: Dictionary = {}
var mechanics_enabled: bool = false
var _aura_timer: float = 0.0
var _chaotic_idle_elapsed: float = 0.0


func setup(p_hero: UnitBase, config: Dictionary = {}) -> void:
	super.setup(p_hero, config)
	synergy_tag = str(config.get("tag", ""))
	var raw_effect = config.get("effect", {})
	if raw_effect is Dictionary:
		effect = raw_effect.duplicate(true)
	else:
		effect = {}
	var raw_modifiers = config.get("modifiers", {})
	if raw_modifiers is Dictionary:
		modifiers = raw_modifiers.duplicate(true)
	else:
		modifiers = {}
	mechanics_enabled = bool(config.get("mechanics_enabled", false))
	passive_id = str(config.get("passive_id", "synergy_%s" % synergy_tag))
	display_name = str(config.get("display_name", passive_id))


func get_modifiers() -> Dictionary:
	return modifiers.duplicate(true)


func on_tick(context: Dictionary) -> void:
	if not mechanics_enabled or not is_active():
		return
	var delta := float(context.get("delta", 0.0))
	match synergy_tag:
		"tro_poem":
			_update_tro_poem_aura(delta)
		"STR":
			_update_strength_aura(delta)
		"CHAOTIC":
			_update_chaotic_reposition(delta)


func before_deal_damage(context: Dictionary) -> void:
	if not mechanics_enabled:
		return
	var target := context.get("target", null) as UnitBase
	if not _can_affect_enemy(target):
		return
	match synergy_tag:
		"naka":
			_apply_naka_pre_damage(context, target)
		"moon_cult":
			_apply_moon_pre_damage(context, target)
		"FLYING":
			if not target.airborne:
				context["damage"] = maxi(1, int(round(float(context.get("damage", 0)) * float(effect.get("ground_damage_multiplier", 1.5)))))
		"SUPPORT":
			var multiplier := float(effect.get("advanced_member_damage_multiplier", 1.4)) if hero is HeroUnit and (hero as HeroUnit).star_level >= 2 else float(effect.get("member_damage_multiplier", 1.2))
			context["damage"] = maxi(1, int(round(float(context.get("damage", 0)) * multiplier)))


func after_deal_damage(context: Dictionary) -> void:
	if not mechanics_enabled:
		return
	var target := context.get("target", null) as UnitBase
	var damage_dealt := int(context.get("damage_dealt", 0))
	if damage_dealt <= 0 or not _can_affect_enemy(target):
		return
	match synergy_tag:
		"anmarit":
			target.apply_anmarit_poison(hero, effect)
		"laferida":
			target.apply_laferida_nature(hero, effect)
		"naka":
			_apply_naka_on_hit(target)
		"moon_cult":
			target.apply_moon_forbidden_mark(hero, effect)
		"DEX":
			_try_dex_extra_attacks(context, target)


func before_receive_attack(context: Dictionary) -> void:
	if not mechanics_enabled or not is_active():
		return
	var attacker := context.get("attacker", null) as UnitBase
	if synergy_tag == "FLYING":
		if not _is_hostile_attack(attacker) or attacker.airborne:
			return
		if attacker.is_ground_melee_attacker():
			context["canceled"] = true
			context["cancel_reason"] = "airborne"
			hero._show_floating_text("空中闪避", COLOR_DODGE)
		else:
			context["amount"] = maxi(1, int(round(float(context.get("amount", 0)) * float(effect.get("ground_ranged_damage_multiplier", 0.6)))))
		return
	if synergy_tag != "kroen_trench":
		return
	if not _is_hostile_attack(attacker) or _tier() < 3:
		return
	var chance := float(effect.get("trench_dodge_chance", 0.0))
	chance += hero.move_speed * float(effect.get("trench_move_speed_dodge_ratio", 0.035))
	chance = clampf(chance, 0.0, float(effect.get("trench_dodge_final_cap", 0.45)))
	if randf() > chance:
		return
	hero._show_floating_text("闪避", COLOR_DODGE)
	if _tier() >= 6:
		_apply_kroen_counter()
	context["canceled"] = true
	context["cancel_reason"] = "dodge"


func before_apply_attack_damage(context: Dictionary) -> void:
	if not mechanics_enabled or synergy_tag != "remolino_law" or not _has_hero():
		return
	var attacker := context.get("attacker", null) as UnitBase
	var actual_damage := int(context.get("damage", 0))
	if hero.law_damage_share_guard or actual_damage <= 0:
		return
	if not _is_hostile_attack(attacker):
		return
	if _tier() < 3 or not bool(effect.get("law_share_enabled", false)):
		return
	var members := _get_alive_members(synergy_tag)
	if members.is_empty():
		return
	var hp_percent := float(actual_damage) / float(max(hero.max_hp, 1))
	for member in members:
		if not is_instance_valid(member) or not member.is_alive:
			continue
		var shared_damage := maxi(1, int(round(float(member.max_hp) * hp_percent)))
		_take_law_shared_damage(member, shared_damage)
	context["skip_hp_loss"] = true


func after_receive_attack(context: Dictionary) -> void:
	if not mechanics_enabled or not _has_hero():
		return
	if synergy_tag == "CON":
		_trigger_constitution_heal(context)
		return
	if synergy_tag != "remolino_law":
		return
	var attacker := context.get("attacker", null) as UnitBase
	if not _is_hostile_attack(attacker) or _tier() < 6:
		return
	var ratio := maxf(0.0, float(effect.get("law_retaliation_attack_ratio", 0.0)))
	if ratio <= 0.0:
		return
	var attack_sum := 0
	for member in _get_alive_members(synergy_tag):
		attack_sum += member.attack
	var damage := maxi(1, int(round(float(attack_sum) * ratio)))
	attacker.take_status_damage(damage, COLOR_LAW)


func after_skill_used(_context: Dictionary) -> void:
	if not mechanics_enabled or not is_active():
		return
	if synergy_tag == "CHAOTIC":
		_chaotic_idle_elapsed = 0.0
		return
	if synergy_tag == "INT":
		var base_refund := float(effect.get("cooldown_refund_base", 0.0))
		var layers_per_step := maxi(1, int(effect.get("cooldown_refund_layers_per_step", 200)))
		var steps := int(effect.get("layer", 0)) / layers_per_step
		var seconds := minf(
			float(effect.get("cooldown_refund_max", 5.0)),
			base_refund + float(steps) * float(effect.get("cooldown_refund_per_step", 1.0))
		)
		hero.reduce_skill_cooldowns(seconds)
		if seconds > 0.0:
			hero._show_floating_text("-%s秒CD" % snappedf(seconds, 0.1), COLOR_COOLDOWN)
		return
	if synergy_tag != "tro_poem" or _tier() < 6:
		return
	var chance := clampf(float(effect.get("poem_cooldown_chance", 0.0)), 0.0, 1.0)
	if chance <= 0.0 or randf() > chance:
		return
	var seconds := maxf(0.0, float(effect.get("poem_cooldown_seconds", 0.0)))
	if seconds <= 0.0:
		return
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	for candidate in grid.get_units_in_range(hero.grid_position, hero.attack_range, hero.team):
		if not is_instance_valid(candidate) or not (candidate is UnitBase):
			continue
		var ally := candidate as UnitBase
		if ally.is_alive:
			ally.reduce_skill_cooldowns(seconds)
			ally._show_floating_text("-CD", COLOR_COOLDOWN)


func after_basic_attack(_context: Dictionary) -> void:
	if mechanics_enabled and synergy_tag == "CHAOTIC":
		_chaotic_idle_elapsed = 0.0


func before_death(_context: Dictionary) -> void:
	if not mechanics_enabled or synergy_tag != "EVIL" or not _has_hero():
		return
	var chance := clampf(float(effect.get("death_burst_chance", 0.0)), 0.0, 1.0)
	if chance <= 0.0 or randf() >= chance:
		return
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	var damage := maxi(1, int(round(float(hero.attack) * float(effect.get("death_burst_attack_ratio", 10.0)))))
	for candidate in grid.get_units_in_range(hero.grid_position, float(effect.get("death_burst_radius", 1.5)), "enemy" if hero.team == "player" else "player"):
		if candidate is UnitBase and (candidate as UnitBase).is_alive:
			(candidate as UnitBase).take_status_damage(damage, COLOR_EVIL)
	hero._show_floating_text("邪爆", COLOR_EVIL)


func _try_dex_extra_attacks(context: Dictionary, target: UnitBase) -> void:
	if bool(context.get("is_skill", false)) or bool(context.get("is_extra_attack", false)):
		return
	var chance := maxf(0.0, float(effect.get("extra_attack_chance", 0.0)))
	var attacks := int(floor(chance))
	if randf() < chance - float(attacks):
		attacks += 1
	for _index in range(attacks):
		if not is_instance_valid(target) or not target.is_alive:
			break
		hero._deal_damage_to_target(target, float(hero.attack), false, true)


func _trigger_constitution_heal(context: Dictionary) -> void:
	if int(context.get("damage_dealt", 0)) <= 0:
		return
	var ratio := maxf(0.0, float(effect.get("heal_max_hp_ratio", 0.0)))
	if ratio <= 0.0:
		return
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	var amount := maxi(1, int(round(float(hero.max_hp) * ratio)))
	for candidate in grid.get_units_in_range(hero.grid_position, float(effect.get("heal_radius", 2.0)), hero.team):
		if candidate is UnitBase and (candidate as UnitBase).is_alive:
			(candidate as UnitBase).heal(amount)
	hero._show_floating_text("体质恢复", COLOR_HEAL)


func _update_strength_aura(delta: float) -> void:
	_aura_timer -= delta
	if _aura_timer > 0.0:
		return
	_aura_timer = maxf(0.1, float(effect.get("aura_interval", 0.25)))
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	var neighbor_count := 0
	for candidate in grid.get_units_in_range(hero.grid_position, float(effect.get("neighbor_radius", 1.0)), hero.team):
		if candidate is HeroUnit and (candidate as HeroUnit).is_alive:
			var candidate_template := (candidate as HeroUnit).class_template
			if candidate_template and "STR" in candidate_template.stat_tags:
				neighbor_count += 1
	var multiplier := 1.0 + float(neighbor_count) * float(effect.get("attack_speed_per_neighbor", 0.0))
	if is_equal_approx(float(hero.combat_statuses.get("strength_attack_speed_multiplier", 1.0)), multiplier):
		return
	hero.combat_statuses["strength_attack_speed_multiplier"] = multiplier
	hero._recalculate_stats(true)


func _update_chaotic_reposition(delta: float) -> void:
	_chaotic_idle_elapsed += delta
	if _chaotic_idle_elapsed < float(effect.get("idle_seconds", 10.0)):
		return
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	var enemy_team := "enemy" if hero.team == "player" else "player"
	if not grid.get_units_in_range(hero.grid_position, hero.attack_range, enemy_team).is_empty():
		return
	var best_cell := GridSystem.INVALID_GRID_POS
	var best_distance := INF
	for x in range(grid.grid_width):
		for y in range(grid.grid_height):
			var cell := Vector2i(x, y)
			if cell != hero.grid_position and not grid.can_place_at(cell):
				continue
			var can_attack := false
			for enemy_value in BattleManager.enemy_units:
				if not (enemy_value is UnitBase) or not (enemy_value as UnitBase).is_alive:
					continue
				if grid.get_distance(cell, (enemy_value as UnitBase).grid_position) <= hero.attack_range:
					can_attack = true
					break
			if not can_attack:
				continue
			var distance := grid.get_distance(hero.grid_position, cell)
			if distance < best_distance:
				best_distance = distance
				best_cell = cell
	if best_cell == GridSystem.INVALID_GRID_POS or best_cell == hero.grid_position:
		return
	if not grid.move_unit(hero, best_cell):
		return
	hero.global_position = grid.grid_to_world(best_cell)
	if hero.ai_controller and hero.ai_controller.has_method("reset_ai_state"):
		hero.ai_controller.reset_ai_state()
	hero.combat_statuses["chaotic_reposition_boost"] = {
		"remaining": float(effect.get("boost_duration", 3.0)),
		"attack_multiplier": float(effect.get("boost_attack_multiplier", 1.0)),
		"defense_multiplier": float(effect.get("boost_defense_multiplier", 1.0)),
	}
	hero._recalculate_stats(true)
	hero._show_floating_text("混沌转移", COLOR_TELEPORT)
	_chaotic_idle_elapsed = 0.0


func _apply_naka_pre_damage(context: Dictionary, target: UnitBase) -> void:
	if _tier() < 6 or not target.has_burning_status():
		return
	var damage := int(context.get("damage", 0))
	context["damage"] = maxi(1, int(round(float(damage) * float(effect.get("burning_damage_multiplier", 1.0)))))


func _apply_moon_pre_damage(context: Dictionary, target: UnitBase) -> void:
	if _tier() < 3:
		return
	var damage := int(context.get("damage", 0))
	context["damage"] = maxi(1, int(round(float(damage) * float(effect.get("forbidden_damage_taken_multiplier", 1.0)))))
	target.apply_moon_forbidden_mark(hero, effect, false)


func _apply_naka_on_hit(target: UnitBase) -> void:
	if not target.is_alive:
		return
	target.apply_naka_burn(hero, effect)
	if target.is_alive and target.has_burning_status() and _tier() >= 6:
		_try_naka_explosion(target)


func _try_naka_explosion(target: UnitBase) -> void:
	var chance := clampf(float(effect.get("explosion_chance", 0.0)), 0.0, 1.0)
	if chance <= 0.0 or randf() > chance:
		return
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	var radius := maxf(0.0, float(effect.get("explosion_radius", 1.0)))
	var explosion_damage := maxi(1, int(round(float(hero.attack) * float(effect.get("explosion_damage_multiplier", 1.20)))))
	for candidate in grid.get_units_in_range(target.grid_position, radius, target.team):
		if not is_instance_valid(candidate) or not (candidate is UnitBase):
			continue
		var combat_unit := candidate as UnitBase
		if combat_unit.is_alive:
			combat_unit.take_status_damage(explosion_damage, COLOR_BURN)


func _apply_kroen_counter() -> void:
	var duration := maxf(0.0, float(effect.get("trench_counter_duration", 0.0)))
	if duration <= 0.0:
		return
	var counter: Dictionary = hero.combat_statuses.get("kroen_counter", {})
	counter["remaining"] = maxf(float(counter.get("remaining", 0.0)), duration)
	counter["damage_multiplier"] = maxf(float(counter.get("damage_multiplier", 1.0)), float(effect.get("trench_counter_damage_multiplier", 1.0)))
	hero.combat_statuses["kroen_counter"] = counter


func _update_tro_poem_aura(delta: float) -> void:
	if _tier() < 3:
		return
	var interval := maxf(0.1, float(effect.get("poem_aura_interval", 0.5)))
	var timer := float(hero.combat_statuses.get("tro_poem_aura_timer", 0.0)) - delta
	if timer > 0.0:
		hero.combat_statuses["tro_poem_aura_timer"] = timer
		return
	timer += interval
	hero.combat_statuses["tro_poem_aura_timer"] = timer
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	for candidate in grid.get_units_in_range(hero.grid_position, hero.attack_range, hero.team):
		if not is_instance_valid(candidate) or not (candidate is UnitBase):
			continue
		var ally := candidate as UnitBase
		if ally.is_alive:
			ally.apply_tro_poem_blessing(hero, effect)


func _take_law_shared_damage(member: UnitBase, amount: int) -> void:
	if not member.is_alive:
		return
	member.law_damage_share_guard = true
	member._apply_hp_loss(amount, COLOR_LAW_SHARE)
	member.law_damage_share_guard = false


func _get_alive_members(tag: String) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for candidate in BattleManager.player_units:
		if not is_instance_valid(candidate) or not (candidate is UnitBase):
			continue
		var unit := candidate as UnitBase
		if unit.is_alive and unit.team == hero.team and unit.class_template and unit.class_template.class_group == tag:
			result.append(unit)
	return result


func _can_affect_enemy(target: UnitBase) -> bool:
	return is_active() and is_instance_valid(target) and target.is_alive and target.team != hero.team


func _is_hostile_attack(attacker: UnitBase) -> bool:
	return _has_hero() and is_instance_valid(attacker) and attacker.is_alive and attacker.team != hero.team


func _has_hero() -> bool:
	return is_instance_valid(hero)


func _tier() -> int:
	return int(effect.get("tier", 0))
