# hero_unit.gd — 玩家英雄单位
class_name HeroUnit
extends UnitBase

const SynergyPassiveScript = preload("res://scripts/passives/synergy_passive.gd")
const AutoTraitCombatPassiveScript = preload("res://scripts/passives/auto_trait_combat_passive.gd")

signal soul_state_changed(in_soul_state: bool, remaining: float)

var deploy_cost: int = 10
var is_selected: bool = false
var star_level: int = 1
var deployed_grid_position: Vector2i = Vector2i.ZERO
var run_card_data: Dictionary = {}
var synergy_passives: Array = []
var auto_trait_passives: Array = []
var is_in_soul_state: bool = false
var soul_time_remaining: float = 0.0
var soul_origin_grid_position: Vector2i = Vector2i.ZERO
var soul_label: Label = null

@export var hero_color: Color = Color(0.3, 0.6, 1.0)


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	team = "player"
	super._ready()


## 灵魂状态仍需逐帧更新复活倒计时。
func _process(delta: float) -> void:
	if is_in_soul_state:
		_update_soul_state(delta)
		return
	super._process(delta)


## 初始化单位或组件数据。
func setup(class_data: ClassTemplate, lvl: int = 1) -> void:
	super.setup(class_data, lvl)
	deploy_cost = class_data.deploy_cost
	color = hero_color
	for child in get_children():
		if child is ColorRect:
			child.color = color
	BattleManager.register_player_unit(self)
	if SynergyManager and SynergyManager.has_method("get_active_synergy_passive_effects"):
		sync_synergy_passives(SynergyManager.get_active_synergy_passive_effects())
	sync_auto_trait_passives()

	# 根据战斗状态决定初始AI行为
	# PREPARING → 静态部署（角色静止）
	# IN_PROGRESS / WAVE_BREAK → 实时部署（立即行动）
	match BattleManager.state:
		BattleManager.BattleState.PREPARING:
			deactivate_ai()
		_:
			activate_ai()


## 同步当前已激活羁绊提供给该英雄的被动。
func sync_synergy_passives(active_synergy_effects: Dictionary) -> void:
	synergy_passives.clear()
	airborne = false
	if not class_template:
		_rebuild_passive_list()
		return
	for synergy_id in active_synergy_effects.keys():
		var effect_data = active_synergy_effects.get(synergy_id, {})
		if not (effect_data is Dictionary):
			continue
		var tag := str(effect_data.get("tag", ""))
		var is_main := bool(effect_data.get("is_main", false))
		var synergy_type := int(effect_data.get("type", 0))
		var is_member := _matches_synergy(str(synergy_id), synergy_type, tag, is_main)
		var mechanics_enabled := is_member and str(effect_data.get("mechanic_id", "")) != ""
		var modifiers: Dictionary = {}
		_merge_synergy_modifier_set(modifiers, effect_data.get("global_modifiers", {}))
		if is_member:
			_merge_synergy_modifier_set(modifiers, effect_data.get("member_modifiers", {}))
			if star_level >= 2:
				_merge_synergy_modifier_set(modifiers, effect_data.get("advanced_member_modifiers", {}))
		var resolved_effect = effect_data.get("effect", {})
		if not mechanics_enabled and modifiers.is_empty():
			continue
		var passive = SynergyPassiveScript.new()
		passive.setup(self, {
			"tag": tag,
			"effect": resolved_effect,
			"modifiers": modifiers,
			"mechanics_enabled": mechanics_enabled,
			"passive_id": "synergy_%s" % synergy_id,
			"display_name": str(effect_data.get("display_name", synergy_id)),
		})
		synergy_passives.append(passive)
		if mechanics_enabled and tag == "FLYING":
			airborne = true
	_rebuild_passive_list()


func _matches_synergy(synergy_id: String, synergy_type: int, tag: String, is_main: bool) -> bool:
	var uses_test_override := SynergyManager and SynergyManager.has_method("is_test_synergy_override_enabled") and SynergyManager.is_test_synergy_override_enabled()
	if class_template and not class_template.autochess_synergy_ids.is_empty() and not uses_test_override:
		if SynergyManager and SynergyManager.has_method("hero_has_synergy"):
			return SynergyManager.hero_has_synergy(self, synergy_id)
		return synergy_id in class_template.autochess_synergy_ids
	if is_main:
		return class_template.class_group == tag
	match synergy_type:
		SynergyDefinition.SynergyType.MINOR_STAT:
			return tag in class_template.stat_tags
		SynergyDefinition.SynergyType.MINOR_ALIGNMENT:
			return tag in class_template.alignment_tags
		SynergyDefinition.SynergyType.MINOR_TRAIT:
			if tag == "ADVANCED":
				return star_level >= 2
			return tag in class_template.trait_tags
	return false


func _merge_synergy_modifier_set(target_modifiers: Dictionary, source_value) -> void:
	if not (source_value is Dictionary):
		return
	var multiply_stats := [
		"max_hp_multiplier", "attack_multiplier", "defense_multiplier",
		"attack_speed_multiplier", "move_speed_multiplier", "damage_multiplier",
		"skill_damage_multiplier", "heal_multiplier", "incoming_heal_multiplier",
		"crit_damage_multiplier", "damage_taken_multiplier", "revive_time_multiplier",
		"shield_multiplier",
	]
	var source: Dictionary = source_value
	for stat in source.keys():
		if str(stat) in multiply_stats:
			target_modifiers[stat] = float(target_modifiers.get(stat, 1.0)) * float(source[stat])
		else:
			target_modifiers[stat] = float(target_modifiers.get(stat, 0.0)) + float(source[stat])


func _get_extra_combat_passives() -> Array:
	var result := synergy_passives.duplicate()
	result.append_array(auto_trait_passives)
	return result


func sync_auto_trait_passives() -> void:
	auto_trait_passives.clear()
	if class_template and not class_template.auto_trait_ids.is_empty():
		var passive = AutoTraitCombatPassiveScript.new()
		passive.setup(self)
		auto_trait_passives.append(passive)
	_rebuild_passive_list()


## 处理未被界面消费的输入事件。
func _unhandled_input(event: InputEvent) -> void:
	if not is_selected or not is_alive:
		return
	if not (event is InputEventKey and event.pressed):
		return

	match event.keycode:
		KEY_Q:
			var skills := class_template.skill_ids
			if skills.size() >= 1:
				use_skill(skills[0])
		KEY_W:
			var skills := class_template.skill_ids
			if skills.size() >= 2:
				use_skill(skills[1])
		KEY_E:
			var skills := class_template.skill_ids
			if skills.size() >= 3:
				use_skill(skills[2])
		KEY_SPACE:
			toggle_stance()
		KEY_R:
			retreat()


## 切换姿态。
func toggle_stance() -> void:
	super.toggle_stance()
	Log.d(M, "[%s] 切换姿态: %s" % [unit_name, "驻扎" if stance == Stance.STATIONED else "行进"])


## 标记英雄的部署卡牌和格子。
func mark_deployed(card_data: Dictionary, grid_pos: Vector2i) -> void:
	run_card_data = card_data.duplicate(true)
	deployed_grid_position = grid_pos
	sync_auto_trait_passives()


## 准备单位进入下一回合。
func prepare_for_next_round() -> void:
	is_in_soul_state = false
	soul_time_remaining = 0.0
	is_alive = true
	visible = true
	modulate = Color.WHITE
	_set_ground_collision_enabled(true)
	_set_soul_label_visible(false)
	target = null
	attack_cooldown = 0.0
	clear_combat_statuses()
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
	deactivate_ai()
	if ai_controller and ai_controller.has_method("reset_ai_state"):
		ai_controller.reset_ai_state()


## 战斗中被击倒：进入灵魂状态并在战斗内等待复活。
func _die() -> void:
	if not is_alive:
		return

	_notify_passives("before_death", {})
	is_alive = false
	is_in_soul_state = true
	target = null
	current_hp = 0
	hp_changed.emit(current_hp, max_hp)
	deactivate_ai()
	if ai_controller and ai_controller.has_method("reset_ai_state"):
		ai_controller.reset_ai_state()
	var grid: GridSystem = BattleManager.grid
	soul_origin_grid_position = grid.world_to_grid(get_ground_position()) if grid else grid_position
	grid_position = soul_origin_grid_position
	_clear_grid_presence()
	soul_time_remaining = maxf(
		0.1,
		_cfg_float("hero_revive_delay", 5.0) * float(synergy_modifiers.get("revive_time_multiplier", 1.0))
	)
	visible = true
	modulate = Color(0.55, 0.78, 1.0, 0.42)
	_set_ground_collision_enabled(false)
	_update_soul_label()
	died.emit(self)
	BattleManager.unit_died.emit(self)
	soul_state_changed.emit(true, soul_time_remaining)


## 清理击倒英雄的战场占位。
func _clear_grid_presence() -> void:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return
	for occupied_pos in grid.occupancy.keys():
		if grid.occupancy[occupied_pos] == self:
			grid.free_cell(occupied_pos)
	grid.release_move_reservation(self)


## 推进灵魂倒计时；据点都被占时保持灵魂并短间隔重试。
func _update_soul_state(delta: float) -> void:
	if BattleManager.state != BattleManager.BattleState.IN_PROGRESS:
		return
	soul_time_remaining = maxf(0.0, soul_time_remaining - delta)
	_update_soul_label()
	soul_state_changed.emit(true, soul_time_remaining)
	if soul_time_remaining > 0.0:
		return
	if not _try_revive():
		soul_time_remaining = 0.25


## 原地优先，否则从最近的可用我方据点复活。
func _try_revive() -> bool:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return false
	var revive_pos := grid.find_revive_cell(soul_origin_grid_position, self) \
		if grid.has_method("find_revive_cell") else grid.find_nearest_open_player_cell(global_position, soul_origin_grid_position, self)
	if revive_pos.x < 0 or revive_pos.y < 0:
		return false

	grid.occupy_cell(revive_pos, self)
	grid_position = revive_pos
	global_position = grid.grid_to_world(revive_pos)
	finish_grid_move(revive_pos)
	is_in_soul_state = false
	is_alive = true
	visible = true
	modulate = Color.WHITE
	target = null
	attack_cooldown = 0.0
	clear_combat_statuses()
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
	_set_ground_collision_enabled(true)
	_set_soul_label_visible(false)
	if ai_controller and ai_controller.has_method("reset_ai_state"):
		ai_controller.reset_ai_state()
	activate_ai()
	soul_state_changed.emit(false, 0.0)
	Log.i(M, "[%s] 从灵魂状态复活于 (%d, %d)" % [unit_name, revive_pos.x, revive_pos.y])
	return true


func _update_soul_label() -> void:
	if not soul_label:
		soul_label = Label.new()
		soul_label.name = "SoulCountdown"
		soul_label.position = Vector2(-42.0, -unit_radius - 42.0)
		soul_label.size = Vector2(84.0, 28.0)
		soul_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		soul_label.add_theme_font_size_override("font_size", 14)
		soul_label.add_theme_color_override("font_color", Color(0.62, 0.86, 1.0))
		soul_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.12, 0.95))
		soul_label.add_theme_constant_override("outline_size", 3)
		soul_label.z_index = 110
		add_child(soul_label)
	soul_label.visible = true
	soul_label.text = "灵魂 %.1fs" % soul_time_remaining


func _set_soul_label_visible(next_visible: bool) -> void:
	if soul_label:
		soul_label.visible = next_visible


func _set_ground_collision_enabled(enabled: bool) -> void:
	if ground_collision_area:
		ground_collision_area.monitoring = enabled
		ground_collision_area.monitorable = enabled


## 撤回已部署英雄。
func retreat() -> void:
	if not is_alive:
		return
	var refund_amount := int(deploy_cost * _cfg_float("retreat_refund_ratio", 0.5))
	ResourceManager.refund(refund_amount)
	Log.i(M, "[%s] 撤退，返还 %d DP" % [unit_name, refund_amount])
	BattleManager.unregister_player_unit(self)
	BattleManager.unit_retreated.emit(self)
	var grid: GridSystem = BattleManager.grid
	if grid:
		grid.remove_unit(self)
	queue_free()


func _cfg_float(key: String, default_value: float) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var registry := tree.root.get_node_or_null("DataRegistry")
		if registry and registry.has_method("get_config"):
			return float(registry.get_config(key, default_value))
	return default_value
