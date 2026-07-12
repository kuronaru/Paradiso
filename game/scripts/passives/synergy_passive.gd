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

var synergy_tag: String = ""
var effect: Dictionary = {}
var mechanics_enabled: bool = false


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
	if not mechanics_enabled or synergy_tag != "tro_poem" or not is_active():
		return
	_update_tro_poem_aura(float(context.get("delta", 0.0)))


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


func before_receive_attack(context: Dictionary) -> void:
	if not mechanics_enabled or synergy_tag != "kroen_trench" or not is_active():
		return
	var attacker := context.get("attacker", null) as UnitBase
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
	if not mechanics_enabled or synergy_tag != "remolino_law" or not _has_hero():
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
	if not mechanics_enabled or synergy_tag != "tro_poem" or not is_active() or _tier() < 6:
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
