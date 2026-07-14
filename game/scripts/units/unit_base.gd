# unit_base.gd — 单位基类
# 所有战场单位（玩家角色 + 敌人）的基础抽象
class_name UnitBase
extends Node2D

const M = "Unit"
const COLLISION_LAYER_PLAYER := 1
const COLLISION_LAYER_ENEMY := 2

signal died(unit: Node)
signal hp_changed(current: int, max_hp: int)
signal stance_changed(is_stationed: bool)

enum Stance {
	MARCH,      ## 行进 — 可移动，攻击力降低，范围缩小
	STATIONED   ## 驻扎 — 定身/缓速，防御提升，范围扩大
}

enum MovementState {
	STANDING,   ## 站立 — 必定位于一个网格中心，并占用该格
	MOVING,     ## 移动 — 目标是一个网格中心，途中按地面圆形碰撞移动
	WAITING     ## 等待 — 移动受阻后回到站立格，保留路径信息等待重试
}

## 网格位置
var grid_position: Vector2i = Vector2i.ZERO
var movement_state: MovementState = MovementState.STANDING
var movement_origin_grid_position: Vector2i = Vector2i.ZERO
var movement_target_grid_position: Vector2i = Vector2i.ZERO

## 基础属性
var unit_name: String = ""
var level: int = 1
var max_hp: int = 100
var current_hp: int = 100
var attack: int = 10
var defense: int = 5
var attack_speed: float = 1.0
var move_speed: float = 2.0
var attack_range: float = 1.5
var search_range: float = 5.0

## 等级换算后的基础属性；羁绊/姿态变化都从这里重算，避免重复叠乘
var base_max_hp: int = 100
var base_attack: int = 10
var base_defense: int = 5
var base_attack_speed: float = 1.0
var base_move_speed: float = 2.0
var base_attack_range: float = 1.5
var base_search_range: float = 5.0

## 当前羁绊数值修正
var synergy_modifiers: Dictionary = {}
var intrinsic_passives: Array = []
var passive_effects: Array = []

## 职业数据
var class_template: ClassTemplate = null

## 当前姿态
var stance: Stance = Stance.MARCH
var target: Node = null
var is_alive: bool = true

## 冷却计时器
var attack_cooldown: float = 0.0
var skill_cooldowns: Dictionary = {}  # {skill_id: remaining_time}

## 主羁绊运行时状态
var combat_statuses: Dictionary = {}
var status_move_speed_multiplier: float = 1.0
var law_damage_share_guard: bool = false

## 团队标识
@export var team: String = "player"   # "player" | "enemy"

## AI控制器
var ai_controller: UnitAI = null
## AI是否启用（静态部署时为false，波次开始后激活）
var ai_enabled: bool = true

## 可视化（占位）
@export var color: Color = Color.WHITE
@export var unit_radius: float = 24.0
@export var collision_radius: float = 0.0
@export var ground_anchor_offset: Vector2 = Vector2.ZERO
@export var show_body_debug_ring: bool = true
@export var show_collision_debug_ring: bool = true
@export var show_attack_range_debug_ring: bool = true
@export var floating_number_rise: float = 28.0
@export var floating_number_duration: float = 0.65
@export var visual_id: String = ""
@export var projectile_visual_scene: PackedScene = null
@export var projectile_texture: Texture2D = null
@export var projectile_speed: float = 640.0
@export var projectile_visual_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var projectile_visual_radius: float = 6.0
@export var projectile_launch_offset: Vector2 = Vector2.ZERO
@export var projectile_hit_offset: Vector2 = Vector2.ZERO
## 血条节点
var hp_bar_bg: ColorRect = null
var hp_bar_fill: ColorRect = null
var body_placeholder: ColorRect = null
var body_sprite: Sprite2D = null
var animated_body_sprite: AnimatedSprite2D = null
var visual_node: Node2D = null
var visual_default_animation: String = "idle"
var visual_walk_animation: String = "walk"
var visual_flip_when_moving_left: bool = true
var last_visual_position: Vector2 = Vector2.ZERO
var ground_collision_area: Area2D = null
var ground_collision_shape: CollisionShape2D = null
var body_debug_ring: Line2D = null
var body_debug_ring_radius: float = -1.0
var collision_debug_ring: Line2D = null
var attack_range_debug_ring: Line2D = null
var attack_range_debug_ring_radius: float = -1.0


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	_setup_ground_collision()
	_setup_visual()
	_setup_body_debug_ring()
	_setup_collision_debug_ring()
	_setup_attack_range_debug_ring()
	_setup_ai()
	last_visual_position = global_position
	hp_changed.connect(_update_hp_bar)
	_update_hp_bar(current_hp, max_hp)


## 每帧更新运行状态。
func _process(delta: float) -> void:
	if not is_alive:
		return
	_update_combat_statuses(delta)
	_notify_passives("on_tick", {"delta": delta})
	# 更新冷却
	if attack_cooldown > 0:
		attack_cooldown -= delta
	for skill_id in skill_cooldowns:
		skill_cooldowns[skill_id] = max(0.0, skill_cooldowns[skill_id] - delta)
	# 执行AI（仅在启用时）
	if ai_enabled and ai_controller:
		ai_controller.execute(delta)
	_update_visual_animation()
	_update_body_debug_ring()
	_update_attack_range_debug_ring()


## 从职业模板初始化
func setup(class_data: ClassTemplate, lvl: int = 1) -> void:
	"""从职业模板初始化"""
	class_template = class_data
	level = clampi(lvl, 1, GameManager.get_max_character_level())
	unit_name = class_data.job_name
	visual_id = class_data.visual_id
	var level_scale := 1.0 + float(level - 1) * 0.05
	base_max_hp = int(round(class_data.base_hp * level_scale))
	base_attack = int(round(class_data.base_atk * level_scale))
	base_defense = int(round(class_data.base_def * level_scale))
	base_attack_speed = class_data.attack_speed
	base_move_speed = class_data.move_speed
	base_attack_range = class_data.attack_range
	base_search_range = class_data.search_range
	collision_radius = class_data.collision_radius
	max_hp = base_max_hp
	current_hp = max_hp
	attack = base_attack
	defense = base_defense
	attack_speed = base_attack_speed
	move_speed = base_move_speed
	attack_range = base_attack_range
	search_range = base_search_range
	synergy_modifiers = _default_synergy_modifiers()
	combat_statuses.clear()
	status_move_speed_multiplier = 1.0
	law_damage_share_guard = false
	# 初始化技能冷却
	for sid in class_data.skill_ids:
		skill_cooldowns[sid] = 0.0
	refresh_ground_collision()
	_apply_visual_config(visual_id)
	_rebuild_passive_list()


## 敌人或测试单位直接写属性后，同步基础属性缓存
func set_base_stats_from_current() -> void:
	"""敌人或测试单位直接写属性后，同步基础属性缓存"""
	base_max_hp = max_hp
	base_attack = attack
	base_defense = defense
	base_attack_speed = attack_speed
	base_move_speed = move_speed
	base_attack_range = attack_range
	base_search_range = search_range
	if synergy_modifiers.is_empty():
		synergy_modifiers = _default_synergy_modifiers()
	combat_statuses.clear()
	status_move_speed_multiplier = 1.0
	law_damage_share_guard = false
	_rebuild_passive_list()


## 应用全队羁绊数值修正
func apply_synergy_modifiers(modifiers: Dictionary) -> void:
	"""应用全队羁绊数值修正"""
	if team != "player":
		return
	apply_passive_modifiers(modifiers)


func apply_passive_modifiers(modifiers: Dictionary) -> void:
	synergy_modifiers = _default_synergy_modifiers()
	for key in modifiers:
		synergy_modifiers[key] = modifiers[key]
	_recalculate_stats(true)


## 处理默认羁绊修正逻辑。
func _default_synergy_modifiers() -> Dictionary:
	return {
		"max_hp_multiplier": 1.0,
		"attack_multiplier": 1.0,
		"defense_multiplier": 1.0,
		"attack_speed_multiplier": 1.0,
		"move_speed_multiplier": 1.0,
		"damage_multiplier": 1.0,
		"skill_damage_multiplier": 1.0,
		"heal_multiplier": 1.0,
		"incoming_heal_multiplier": 1.0,
		"armor_pierce": 0.0,
		"crit_chance": 0.0,
		"crit_damage_multiplier": 1.0,
		"skill_cooldown_reduction": 0.0,
		"life_steal_percent": 0.0,
		"search_range_bonus": 0.0,
	}


func setup_intrinsic_passives_from_configs(configs) -> void:
	var passives: Array = []
	if not (configs is Array):
		set_intrinsic_passives(passives)
		return
	for raw_config in configs:
		var config := {}
		if raw_config is Dictionary:
			config = raw_config.duplicate(true)
		else:
			config = {"passive_id": str(raw_config)}
		var script_path := str(config.get("script", config.get("script_path", "")))
		var passive_script = load(script_path) if script_path != "" else load("res://scripts/passives/unit_passive.gd")
		if passive_script == null:
			push_warning("Failed to load passive script: %s" % script_path)
			continue
		var passive = passive_script.new()
		if passive and passive.has_method("setup"):
			passive.setup(self, config)
			passives.append(passive)
	set_intrinsic_passives(passives)


func set_intrinsic_passives(passives: Array) -> void:
	intrinsic_passives.clear()
	for passive in passives:
		if passive:
			intrinsic_passives.append(passive)
	_rebuild_passive_list()


func add_intrinsic_passive(passive) -> void:
	if not passive:
		return
	intrinsic_passives.append(passive)
	_rebuild_passive_list()


func clear_intrinsic_passives() -> void:
	intrinsic_passives.clear()
	_rebuild_passive_list()


## 获取当前单位拥有的战斗被动。
func get_combat_passives() -> Array:
	return passive_effects


func _get_extra_combat_passives() -> Array:
	return []


func _rebuild_passive_list() -> void:
	passive_effects.clear()
	passive_effects.append_array(intrinsic_passives)
	passive_effects.append_array(_get_extra_combat_passives())
	_refresh_passive_modifiers()


func _refresh_passive_modifiers() -> void:
	var merged := _default_synergy_modifiers()
	for passive in passive_effects:
		if not passive or not passive.has_method("get_modifiers"):
			continue
		var modifiers: Dictionary = passive.get_modifiers()
		for stat in modifiers.keys():
			_merge_passive_modifier(merged, str(stat), float(modifiers[stat]))
	apply_passive_modifiers(merged)


func _merge_passive_modifier(target: Dictionary, stat: String, value: float) -> void:
	if stat == "":
		return
	var multiply_stats := [
		"max_hp_multiplier",
		"attack_multiplier",
		"defense_multiplier",
		"attack_speed_multiplier",
		"move_speed_multiplier",
		"damage_multiplier",
		"skill_damage_multiplier",
		"heal_multiplier",
		"incoming_heal_multiplier",
		"crit_damage_multiplier",
	]
	if stat in multiply_stats:
		target[stat] = float(target.get(stat, 1.0)) * value
	else:
		target[stat] = float(target.get(stat, 0.0)) + value


## 将战斗事件分发给当前单位的被动。
func _notify_passives(event_name: String, context: Dictionary) -> void:
	for passive in get_combat_passives():
		if passive and passive.has_method(event_name):
			passive.call(event_name, context)


## 处理recalculatestats逻辑。
func _recalculate_stats(preserve_hp_ratio: bool) -> void:
	var old_max_hp := max_hp
	var hp_ratio := float(current_hp) / float(max(old_max_hp, 1))
	max_hp = maxi(1, int(round(float(base_max_hp) * float(synergy_modifiers.get("max_hp_multiplier", 1.0)))))
	attack = maxi(1, int(round(float(base_attack) * float(synergy_modifiers.get("attack_multiplier", 1.0)))))
	defense = maxi(0, int(round(float(base_defense) * float(synergy_modifiers.get("defense_multiplier", 1.0)))))
	max_hp += _get_status_flat_bonus("max_hp_bonus")
	attack += _get_status_flat_bonus("attack_bonus")
	defense += _get_status_flat_bonus("defense_bonus")
	attack_speed = max(0.05, base_attack_speed * float(synergy_modifiers.get("attack_speed_multiplier", 1.0)))
	move_speed = max(0.0, base_move_speed * float(synergy_modifiers.get("move_speed_multiplier", 1.0)))
	attack_range = base_attack_range
	search_range = base_search_range + float(synergy_modifiers.get("search_range_bonus", 0.0))

	if stance == Stance.STATIONED and class_template:
		defense = maxi(0, int(round(float(defense) * class_template.stance_defense_bonus)))
		attack_range *= class_template.stance_range_bonus
		if class_template.stance_is_rooted:
			move_speed = 0.0
	move_speed = max(0.0, move_speed * status_move_speed_multiplier)

	if preserve_hp_ratio:
		current_hp = clampi(int(round(float(max_hp) * hp_ratio)), 1 if is_alive else 0, max_hp)
	else:
		current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)


## 创建基本的占位可视化（含血条）
func _setup_visual() -> void:
	"""创建基本的占位可视化（含血条）"""
	var bar_width := unit_radius * 2.0
	var bar_height := 6.0
	var bar_y := -unit_radius - bar_height - 4.0

	# 血条背景
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.size = Vector2(bar_width, bar_height)
	hp_bar_bg.position = Vector2(-unit_radius, bar_y)
	hp_bar_bg.color = Color(0.15, 0.15, 0.15, 0.85)
	add_child(hp_bar_bg)

	# 血条填充
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.size = Vector2(bar_width, bar_height)
	hp_bar_fill.position = Vector2(-unit_radius, bar_y)
	# 颜色在 _update_hp_bar 中根据 team 设置
	add_child(hp_bar_fill)

	# Unit placeholder, kept as a fallback when art is missing.
	body_placeholder = ColorRect.new()
	body_placeholder.name = "BodyPlaceholder"
	body_placeholder.size = Vector2(unit_radius * 2, unit_radius * 2)
	body_placeholder.position = -Vector2(unit_radius, unit_radius)
	body_placeholder.color = color
	add_child(body_placeholder)

	body_sprite = Sprite2D.new()
	body_sprite.name = "BodySprite"
	body_sprite.z_index = 10
	add_child(body_sprite)

	animated_body_sprite = AnimatedSprite2D.new()
	animated_body_sprite.name = "AnimatedBodySprite"
	animated_body_sprite.z_index = 10
	add_child(animated_body_sprite)
	_apply_visual_config(visual_id)

	# 名称标签
	var label := Label.new()
	label.text = unit_name
	label.add_theme_font_size_override("font_size", 10)
	label.position = Vector2(-20, unit_radius + 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


func _apply_visual_config(next_visual_id: String) -> void:
	if next_visual_id == "":
		_set_placeholder_visible(true)
		return
	var registry := _art_registry()
	if not registry or not registry.has_method("get_unit_visual_config"):
		return
	var config: UnitVisualConfig = registry.get_unit_visual_config(next_visual_id)
	if not config:
		_set_placeholder_visible(true)
		return

	visual_default_animation = config.idle_animation
	visual_walk_animation = config.walk_animation
	visual_flip_when_moving_left = config.flip_when_moving_left
	var has_visual := false
	if config.texture:
		_apply_texture_visual(config.texture, config.sprite_offset, config.sprite_scale)
		has_visual = true
	if config.sprite_frames:
		_apply_sprite_frames_visual(config.sprite_frames, config.sprite_offset, config.sprite_scale)
		has_visual = true
	if has_visual:
		_set_placeholder_visible(false)
		_show_idle_visual()
		return

	_set_placeholder_visible(true)


func _apply_texture_visual(texture: Texture2D, offset: Vector2, scale_value: Vector2) -> void:
	if not body_sprite:
		return
	body_sprite.texture = texture
	body_sprite.centered = true
	body_sprite.position = offset
	body_sprite.scale = scale_value
	body_sprite.visible = false
	visual_node = body_sprite


func _apply_sprite_frames_visual(frames: SpriteFrames, offset: Vector2, scale_value: Vector2) -> void:
	if not animated_body_sprite:
		return
	animated_body_sprite.sprite_frames = frames
	animated_body_sprite.position = offset
	animated_body_sprite.scale = scale_value
	animated_body_sprite.visible = false
	visual_node = animated_body_sprite


func _update_visual_animation() -> void:
	var moved := global_position.distance_squared_to(last_visual_position) > 1.0
	if moved:
		var delta_pos := global_position - last_visual_position
		_set_visual_flip(delta_pos.x < 0.0)
	var should_walk := is_moving() or moved
	if should_walk and _play_animated_visual(visual_walk_animation):
		last_visual_position = global_position
		return
	if should_walk and _play_animated_visual(visual_default_animation):
		last_visual_position = global_position
		return
	_show_idle_visual()
	last_visual_position = global_position


func _play_animated_visual(animation_name: String) -> bool:
	if not animated_body_sprite or not animated_body_sprite.sprite_frames:
		return false
	if animation_name == "" or not animated_body_sprite.sprite_frames.has_animation(animation_name):
		return false
	if body_sprite:
		body_sprite.visible = false
	animated_body_sprite.visible = true
	visual_node = animated_body_sprite
	if animated_body_sprite.animation != animation_name or not animated_body_sprite.is_playing():
		animated_body_sprite.play(animation_name)
	return true


func _show_idle_visual() -> void:
	if animated_body_sprite and animated_body_sprite.sprite_frames and animated_body_sprite.sprite_frames.has_animation(visual_default_animation):
		_play_animated_visual(visual_default_animation)
		return
	if body_sprite and body_sprite.texture:
		body_sprite.visible = true
		visual_node = body_sprite
		if animated_body_sprite:
			animated_body_sprite.visible = false
			animated_body_sprite.stop()
		return
	if animated_body_sprite and animated_body_sprite.sprite_frames:
		animated_body_sprite.visible = true
		animated_body_sprite.stop()
		animated_body_sprite.frame = 0
		visual_node = animated_body_sprite
		return
	_set_placeholder_visible(true)


func _set_visual_flip(flip_left: bool) -> void:
	if not visual_flip_when_moving_left:
		return
	if body_sprite:
		body_sprite.flip_h = flip_left
	if animated_body_sprite:
		animated_body_sprite.flip_h = flip_left


func _set_placeholder_visible(visible_value: bool) -> void:
	if body_placeholder:
		body_placeholder.visible = visible_value
	if body_sprite and visible_value:
		body_sprite.visible = false
	if animated_body_sprite and visible_value:
		animated_body_sprite.visible = false
	if visible_value:
		visual_node = null


func _art_registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("ArtRegistry")


## 初始化AI。
func _setup_ai() -> void:
	ai_controller = UnitAI.new()
	ai_controller.owner_unit = self
	add_child(ai_controller)


## 初始化地面碰撞。
func _setup_ground_collision() -> void:
	ground_collision_area = Area2D.new()
	ground_collision_area.name = "GroundCollisionArea"
	ground_collision_area.position = ground_anchor_offset
	add_child(ground_collision_area)

	ground_collision_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = get_collision_radius()
	ground_collision_shape.shape = circle
	ground_collision_area.add_child(ground_collision_shape)
	_configure_collision_layers()


## 刷新地面碰撞。
func refresh_ground_collision() -> void:
	if not ground_collision_shape:
		return
	if ground_collision_area:
		ground_collision_area.position = ground_anchor_offset
	var circle := ground_collision_shape.shape as CircleShape2D
	if circle:
		circle.radius = get_collision_radius()
	_configure_collision_layers()
	_update_body_debug_ring(true)
	_update_collision_debug_ring()
	_update_attack_range_debug_ring(true)


## 处理configure碰撞layers逻辑。
func _configure_collision_layers() -> void:
	if not ground_collision_area:
		return
	if team == "player":
		ground_collision_area.collision_layer = COLLISION_LAYER_PLAYER
		ground_collision_area.collision_mask = COLLISION_LAYER_ENEMY
	else:
		ground_collision_area.collision_layer = COLLISION_LAYER_ENEMY
		ground_collision_area.collision_mask = COLLISION_LAYER_PLAYER


## 初始化碰撞调试圆环。
func _setup_collision_debug_ring() -> void:
	collision_debug_ring = Line2D.new()
	collision_debug_ring.name = "CollisionDebugRing"
	collision_debug_ring.width = 2.0
	collision_debug_ring.closed = true
	collision_debug_ring.antialiased = true
	collision_debug_ring.z_index = 50
	add_child(collision_debug_ring)
	_update_collision_debug_ring()


## 更新碰撞调试圆环。
func _update_collision_debug_ring() -> void:
	if not collision_debug_ring:
		return
	collision_debug_ring.visible = show_collision_debug_ring
	collision_debug_ring.position = ground_anchor_offset
	collision_debug_ring.default_color = _get_collision_debug_ring_color()
	var radius := get_collision_radius()
	var points := PackedVector2Array()
	var segments := 64
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	collision_debug_ring.points = points


## 获取碰撞调试圆环color。
func _get_collision_debug_ring_color() -> Color:
	if team == "player":
		return Color(0.15, 0.85, 1.0, 0.85)
	return Color(1.0, 0.35, 0.18, 0.85)


## 初始化角色本体半径调试圆环。
func _setup_body_debug_ring() -> void:
	body_debug_ring = Line2D.new()
	body_debug_ring.name = "BodyDebugRing"
	body_debug_ring.width = 1.5
	body_debug_ring.closed = true
	body_debug_ring.antialiased = true
	body_debug_ring.z_index = 48
	add_child(body_debug_ring)
	_update_body_debug_ring(true)


## 更新角色本体半径调试圆环。
func _update_body_debug_ring(force_rebuild: bool = false) -> void:
	if not body_debug_ring:
		return
	var visible := _should_show_body_debug_ring()
	body_debug_ring.visible = visible
	if not visible:
		return

	body_debug_ring.position = ground_anchor_offset
	body_debug_ring.default_color = _get_body_debug_ring_color()
	var radius := get_body_radius()
	if not force_rebuild and is_equal_approx(radius, body_debug_ring_radius):
		return

	body_debug_ring_radius = radius
	var points := PackedVector2Array()
	var segments := 64
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	body_debug_ring.points = points


## 判断是否显示角色本体半径调试圆环。
func _should_show_body_debug_ring() -> bool:
	var grid: GridSystem = BattleManager.grid
	return show_body_debug_ring and grid != null and grid.debug_unit_body_radii


## 获取角色本体半径调试圆环颜色。
func _get_body_debug_ring_color() -> Color:
	if team == "player":
		return Color(1.0, 1.0, 1.0, 0.65)
	return Color(1.0, 0.9, 0.2, 0.65)


## 初始化攻击范围调试圆环。
func _setup_attack_range_debug_ring() -> void:
	attack_range_debug_ring = Line2D.new()
	attack_range_debug_ring.name = "AttackRangeDebugRing"
	attack_range_debug_ring.width = 1.5
	attack_range_debug_ring.closed = true
	attack_range_debug_ring.antialiased = true
	attack_range_debug_ring.z_index = 45
	add_child(attack_range_debug_ring)
	_update_attack_range_debug_ring(true)


## 更新攻击范围调试圆环。
func _update_attack_range_debug_ring(force_rebuild: bool = false) -> void:
	if not attack_range_debug_ring:
		return
	var visible := _should_show_attack_range_debug_ring()
	attack_range_debug_ring.visible = visible
	if not visible:
		return

	attack_range_debug_ring.position = ground_anchor_offset
	attack_range_debug_ring.default_color = _get_attack_range_debug_ring_color()
	var radius := get_attack_range_world_radius()
	if not force_rebuild and is_equal_approx(radius, attack_range_debug_ring_radius):
		return

	attack_range_debug_ring_radius = radius
	var points := PackedVector2Array()
	var segments := 96
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	attack_range_debug_ring.points = points


## 判断是否需要攻击范围调试圆环。
func _should_show_attack_range_debug_ring() -> bool:
	var grid: GridSystem = BattleManager.grid
	return show_attack_range_debug_ring and grid != null and grid.debug_attack_ranges


## 获取攻击范围调试圆环color。
func _get_attack_range_debug_ring_color() -> Color:
	if team == "player":
		return Color(0.6, 1.0, 0.25, 0.45)
	return Color(1.0, 0.55, 0.2, 0.45)


## 更新血条显示
func _update_hp_bar(_current: int, _max_hp: int) -> void:
	"""更新血条显示"""
	if not hp_bar_fill:
		return
	var ratio: float = clamp(float(current_hp) / max(max_hp, 1), 0.0, 1.0)
	hp_bar_fill.size.x = unit_radius * 2.0 * ratio
	# 玩家蓝色，敌人红色
	if team == "player":
		hp_bar_fill.color = Color(0.25, 0.6, 1.0, 0.9)
	else:
		hp_bar_fill.color = Color(1.0, 0.2, 0.2, 0.9)


## 获取队伍。
func get_team() -> String:
	return team


## 获取碰撞radius。
func get_collision_radius() -> float:
	if collision_radius > 0.0:
		return collision_radius
	return unit_radius * 2.0 / 3.0


## 获取角色本体外轮廓半径。
func get_body_radius() -> float:
	return unit_radius


## 获取指定地面坐标到角色本体外轮廓的距离。
func get_body_outline_distance_from_ground(from_ground_position: Vector2) -> float:
	return maxf(0.0, from_ground_position.distance_to(get_ground_position()) - get_body_radius())


## 获取攻击范围世界坐标radius。
func get_attack_range_world_radius() -> float:
	var grid: GridSystem = BattleManager.grid
	var world_cell_size := grid.cell_size if grid else 64.0
	return attack_range * world_cell_size


## 获取地面位置。
func get_ground_position() -> Vector2:
	return global_position + ground_anchor_offset


## 判断接触单位状态。
func is_touching_unit(other: UnitBase) -> bool:
	if not other:
		return false
	var radius_sum := get_collision_radius() + other.get_collision_radius()
	return get_ground_position().distance_squared_to(other.get_ground_position()) <= radius_sum * radius_sum


## 判断standing状态。
func is_standing() -> bool:
	return movement_state == MovementState.STANDING


## 判断移动状态。
func is_moving() -> bool:
	return movement_state == MovementState.MOVING


## 判断waiting状态。
func is_waiting() -> bool:
	return movement_state == MovementState.WAITING


## 开始网格移动。
func begin_grid_move(target_grid_pos: Vector2i) -> void:
	movement_state = MovementState.MOVING
	movement_origin_grid_position = grid_position
	movement_target_grid_position = target_grid_pos


## 开始网格wait。
func begin_grid_wait(preferred_grid_pos: Vector2i) -> void:
	movement_state = MovementState.WAITING
	movement_origin_grid_position = preferred_grid_pos
	movement_target_grid_position = preferred_grid_pos


## 完成网格移动。
func finish_grid_move(final_grid_pos: Vector2i) -> void:
	movement_state = MovementState.STANDING
	grid_position = final_grid_pos
	movement_origin_grid_position = final_grid_pos
	movement_target_grid_position = final_grid_pos


## 受到伤害
func take_damage(amount: int, armor_pierce: float = 0.0) -> int:
	"""受到伤害"""
	return receive_attack_damage(amount, armor_pierce, null)


## 受到一次来自攻击者的伤害。
func receive_attack_damage(amount: int, armor_pierce: float = 0.0, attacker: UnitBase = null) -> int:
	if not is_alive or amount <= 0:
		return 0
	var receive_context := {
		"attacker": attacker,
		"amount": amount,
		"armor_pierce": armor_pierce,
		"canceled": false,
	}
	_notify_passives("before_receive_attack", receive_context)
	if bool(receive_context.get("canceled", false)):
		return 0
	var incoming_amount := maxi(1, int(receive_context.get("amount", amount)))
	var incoming_armor_pierce := float(receive_context.get("armor_pierce", armor_pierce))
	var effective_defense := int(round(float(defense) * (1.0 - clampf(incoming_armor_pierce, 0.0, 0.95))))
	var actual: int = max(1, incoming_amount - effective_defense)
	var damage_context := {
		"attacker": attacker,
		"damage": actual,
		"skip_hp_loss": false,
	}
	_notify_passives("before_apply_attack_damage", damage_context)
	actual = maxi(0, int(damage_context.get("damage", actual)))
	if actual <= 0:
		return 0
	var skip_hp_loss := bool(damage_context.get("skip_hp_loss", false))
	if not skip_hp_loss:
		_apply_hp_loss(actual, Color(1.0, 0.2, 0.2, 1.0))
	_notify_passives("after_receive_attack", {
		"attacker": attacker,
		"damage_dealt": actual,
		"skip_hp_loss": skip_hp_loss,
	})
	return actual


## 直接扣除生命值。
func _apply_hp_loss(amount: int, text_color: Color) -> void:
	var actual := maxi(1, amount)
	current_hp = max(0, current_hp - actual)
	_show_floating_number(-actual, text_color)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		_die()


## 恢复生命
func heal(amount: int) -> int:
	"""恢复生命"""
	var scaled_amount := int(round(float(amount) * float(synergy_modifiers.get("incoming_heal_multiplier", 1.0))))
	var actual: int = min(scaled_amount, max_hp - current_hp)
	if actual <= 0:
		return 0
	current_hp += actual
	_show_floating_number(actual, Color(0.2, 1.0, 0.35, 1.0))
	hp_changed.emit(current_hp, max_hp)
	return actual


## 清除主羁绊运行时状态。
func clear_combat_statuses() -> void:
	var had_status_bonuses := combat_statuses.has("tro_poem_sources")
	combat_statuses.clear()
	law_damage_share_guard = false
	var had_slow := not is_equal_approx(status_move_speed_multiplier, 1.0)
	status_move_speed_multiplier = 1.0
	if had_slow or had_status_bonuses:
		_recalculate_stats(true)


## 是否处于燃烧状态。
func has_burning_status() -> bool:
	if not combat_statuses.has("naka_burning"):
		return false
	var burning: Dictionary = combat_statuses.get("naka_burning", {})
	return float(burning.get("remaining", 0.0)) > 0.0


## 受到无视防御的状态伤害。
func take_status_damage(amount: int, text_color: Color = Color(0.95, 0.75, 0.25, 1.0)) -> int:
	if not is_alive or amount <= 0:
		return 0
	var actual := maxi(1, amount)
	current_hp = max(0, current_hp - actual)
	_show_floating_number(-actual, text_color)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		_die()
	return actual


## 应用安马里特瘴毒。
func apply_anmarit_poison(attacker: UnitBase, effect: Dictionary) -> void:
	if not _can_receive_hostile_status(attacker):
		return
	var add_amount := maxf(1.0, float(attacker.attack) * float(effect.get("poison_attack_ratio", 0.0)))
	var poison: Dictionary = combat_statuses.get("anmarit_poison", {})
	poison["amount"] = minf(float(poison.get("amount", 0.0)) + add_amount, float(max_hp) * 30.0)
	poison["dot_ratio"] = float(effect.get("poison_dot_ratio", 0.24))
	poison["decay_per_second"] = float(effect.get("poison_decay_per_second", 0.16))
	poison["tick_interval"] = maxf(0.1, float(effect.get("poison_tick_interval", 1.0)))
	poison["tick_timer"] = minf(float(poison.get("tick_timer", poison["tick_interval"])), float(poison["tick_interval"]))
	poison["aoe_radius"] = maxf(0.0, float(effect.get("poison_aoe_radius", 0.0)))
	combat_statuses["anmarit_poison"] = poison


## 应用拉费里达自然值。
func apply_laferida_nature(attacker: UnitBase, effect: Dictionary) -> void:
	if not _can_receive_hostile_status(attacker):
		return
	var nature: Dictionary = combat_statuses.get("laferida_nature", {})
	var gain := maxf(float(effect.get("nature_min_gain", 12.0)), float(attacker.attack) * float(effect.get("nature_gain_ratio", 0.80)))
	var threshold := maxf(1.0, float(effect.get("nature_threshold", 100.0)))
	nature["value"] = float(nature.get("value", 0.0)) + gain
	nature["source_attack"] = maxf(float(nature.get("source_attack", 0.0)), float(attacker.attack))

	if float(nature["value"]) >= threshold:
		var source_attack := float(nature.get("source_attack", attacker.attack))
		nature["value"] = 0.0
		nature["source_attack"] = 0.0
		_apply_laferida_slow(float(effect.get("slow_percent", 0.20)), float(effect.get("slow_duration", 2.5)))
		if int(effect.get("tier", 0)) >= 6:
			var damage_multiplier := float(effect.get("nature_damage_multiplier", 0.0))
			if damage_multiplier > 0.0:
				take_status_damage(int(round(source_attack * damage_multiplier)), Color(0.32, 0.90, 0.48, 1.0))
				if not is_alive:
					return
	combat_statuses["laferida_nature"] = nature


## 应用纳卡灼烧值。
func apply_naka_burn(attacker: UnitBase, effect: Dictionary) -> void:
	if not _can_receive_hostile_status(attacker):
		return
	var burn_value: Dictionary = combat_statuses.get("naka_burn_value", {})
	var gain := maxf(float(effect.get("burn_min_gain", 14.0)), float(attacker.attack) * float(effect.get("burn_gain_ratio", 0.85)))
	var threshold := maxf(1.0, float(effect.get("burn_threshold", 100.0)))
	burn_value["value"] = float(burn_value.get("value", 0.0)) + gain
	if float(burn_value["value"]) >= threshold:
		burn_value["value"] = 0.0
		_ignite_naka_burning(attacker, effect)
	combat_statuses["naka_burn_value"] = burn_value


## 应用窥探禁忌标记。
func apply_moon_forbidden_mark(attacker: UnitBase, effect: Dictionary, try_execute: bool = true) -> void:
	if not _can_receive_hostile_status(attacker):
		return
	var mark: Dictionary = combat_statuses.get("moon_forbidden_mark", {})
	var duration := maxf(0.1, float(effect.get("forbidden_mark_duration", 3.0)))
	var burst_damage := float(attacker.attack) * float(effect.get("forbidden_death_burst_multiplier", 0.0))
	var execute_threshold := float(attacker.attack) * float(effect.get("forbidden_execute_attack_ratio", 0.0))
	mark["remaining"] = maxf(float(mark.get("remaining", 0.0)), duration)
	mark["burst_damage"] = maxf(float(mark.get("burst_damage", 0.0)), burst_damage)
	mark["burst_radius"] = maxf(float(mark.get("burst_radius", 0.0)), float(effect.get("forbidden_burst_radius", 1.0)))
	mark["execute_threshold"] = maxf(float(mark.get("execute_threshold", 0.0)), execute_threshold)
	combat_statuses["moon_forbidden_mark"] = mark
	if try_execute:
		_try_moon_forbidden_execute(mark)


## 应用十一长诗祝福。
func apply_tro_poem_blessing(source: UnitBase, effect: Dictionary) -> void:
	if not is_alive or not is_instance_valid(source) or not source.is_alive or source.team != team:
		return
	var ratio := maxf(0.0, float(effect.get("poem_stat_share_ratio", 0.0)))
	if ratio <= 0.0:
		return
	var duration := maxf(0.1, float(effect.get("poem_aura_duration", 0.8)))
	var source_max_hp := source._get_tro_poem_source_max_hp()
	var source_attack := source._get_tro_poem_source_attack()
	var source_defense := source._get_tro_poem_source_defense()
	var sources: Dictionary = combat_statuses.get("tro_poem_sources", {})
	sources[str(source.get_instance_id())] = {
		"remaining": duration,
		"max_hp_bonus": maxi(0, int(round(float(source_max_hp) * ratio))),
		"attack_bonus": maxi(0, int(round(float(source_attack) * ratio))),
		"defense_bonus": maxi(0, int(round(float(source_defense) * ratio))),
	}
	combat_statuses["tro_poem_sources"] = sources
	_recalculate_stats(true)


## 减少技能冷却。
func reduce_skill_cooldowns(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for skill_id in skill_cooldowns:
		skill_cooldowns[skill_id] = max(0.0, float(skill_cooldowns[skill_id]) - seconds)


## 更新主羁绊状态。
func _update_combat_statuses(delta: float) -> void:
	_update_anmarit_poison(delta)
	if not is_alive:
		return
	_update_naka_burning(delta)
	if not is_alive:
		return
	_update_laferida_slow(delta)
	_update_moon_forbidden_mark(delta)
	_update_kroen_counter(delta)
	_update_tro_poem_sources(delta)


## 更新安马里特瘴毒。
func _update_anmarit_poison(delta: float) -> void:
	if not combat_statuses.has("anmarit_poison"):
		return
	var poison: Dictionary = combat_statuses.get("anmarit_poison", {})
	var amount := float(poison.get("amount", 0.0))
	if amount <= 1.0:
		combat_statuses.erase("anmarit_poison")
		return

	var decay := clampf(float(poison.get("decay_per_second", 0.16)), 0.0, 0.95)
	amount *= pow(1.0 - decay, delta)
	poison["amount"] = amount

	var interval := maxf(0.1, float(poison.get("tick_interval", 1.0)))
	var tick_timer := float(poison.get("tick_timer", interval)) - delta
	if tick_timer <= 0.0:
		var tick_damage := maxi(1, int(round(amount * float(poison.get("dot_ratio", 0.24)))))
		var aoe_radius := float(poison.get("aoe_radius", 0.0))
		if aoe_radius > 0.0:
			_deal_status_area_damage(tick_damage, aoe_radius, team, Color(0.50, 0.86, 0.22, 1.0))
		else:
			take_status_damage(tick_damage, Color(0.50, 0.86, 0.22, 1.0))
		if not is_alive:
			return
		tick_timer += interval
	poison["tick_timer"] = tick_timer
	combat_statuses["anmarit_poison"] = poison


## 更新纳卡燃烧。
func _update_naka_burning(delta: float) -> void:
	if not combat_statuses.has("naka_burning"):
		return
	var burning: Dictionary = combat_statuses.get("naka_burning", {})
	var remaining := float(burning.get("remaining", 0.0)) - delta
	if remaining <= 0.0:
		combat_statuses.erase("naka_burning")
		return

	var interval := maxf(0.1, float(burning.get("tick_interval", 1.0)))
	var tick_timer := float(burning.get("tick_timer", interval)) - delta
	if tick_timer <= 0.0:
		take_status_damage(maxi(1, int(round(float(burning.get("dot_damage", 1.0))))), Color(1.0, 0.44, 0.16, 1.0))
		if not is_alive:
			return
		tick_timer += interval
	burning["remaining"] = remaining
	burning["tick_timer"] = tick_timer
	combat_statuses["naka_burning"] = burning


## 更新拉费里达减速。
func _update_laferida_slow(delta: float) -> void:
	if not combat_statuses.has("laferida_slow"):
		return
	var slow: Dictionary = combat_statuses.get("laferida_slow", {})
	var remaining := float(slow.get("remaining", 0.0)) - delta
	if remaining <= 0.0:
		combat_statuses.erase("laferida_slow")
		status_move_speed_multiplier = 1.0
		_recalculate_stats(true)
		return
	slow["remaining"] = remaining
	combat_statuses["laferida_slow"] = slow


## 更新窥探禁忌标记。
func _update_moon_forbidden_mark(delta: float) -> void:
	if not combat_statuses.has("moon_forbidden_mark"):
		return
	var mark: Dictionary = combat_statuses.get("moon_forbidden_mark", {})
	var remaining := float(mark.get("remaining", 0.0)) - delta
	if remaining <= 0.0:
		combat_statuses.erase("moon_forbidden_mark")
		return
	mark["remaining"] = remaining
	combat_statuses["moon_forbidden_mark"] = mark
	_try_moon_forbidden_execute(mark)


## 更新不灭战壕闪避后的增伤状态。
func _update_kroen_counter(delta: float) -> void:
	if not combat_statuses.has("kroen_counter"):
		return
	var counter: Dictionary = combat_statuses.get("kroen_counter", {})
	var remaining := float(counter.get("remaining", 0.0)) - delta
	if remaining <= 0.0:
		combat_statuses.erase("kroen_counter")
		return
	counter["remaining"] = remaining
	combat_statuses["kroen_counter"] = counter


## 更新十一长诗祝福来源。
func _update_tro_poem_sources(delta: float) -> void:
	if not combat_statuses.has("tro_poem_sources"):
		return
	var sources: Dictionary = combat_statuses.get("tro_poem_sources", {})
	var changed := false
	for source_id in sources.keys():
		var source_data: Dictionary = sources.get(source_id, {})
		source_data["remaining"] = float(source_data.get("remaining", 0.0)) - delta
		if float(source_data.get("remaining", 0.0)) <= 0.0:
			sources.erase(source_id)
			changed = true
		else:
			sources[source_id] = source_data
	if sources.is_empty():
		combat_statuses.erase("tro_poem_sources")
		changed = true
	else:
		combat_statuses["tro_poem_sources"] = sources
	if changed:
		_recalculate_stats(true)


## 应用拉费里达减速状态。
func _apply_laferida_slow(slow_percent: float, duration: float) -> void:
	var multiplier := 1.0 - clampf(slow_percent, 0.0, 0.95)
	var slow: Dictionary = combat_statuses.get("laferida_slow", {})
	slow["remaining"] = maxf(float(slow.get("remaining", 0.0)), maxf(0.1, duration))
	slow["move_speed_multiplier"] = minf(float(slow.get("move_speed_multiplier", 1.0)), multiplier)
	combat_statuses["laferida_slow"] = slow
	status_move_speed_multiplier = float(slow["move_speed_multiplier"])
	_recalculate_stats(true)


## 点燃纳卡燃烧。
func _ignite_naka_burning(attacker: UnitBase, effect: Dictionary) -> void:
	var burning: Dictionary = combat_statuses.get("naka_burning", {})
	var interval := maxf(0.1, float(effect.get("burn_tick_interval", 1.0)))
	burning["remaining"] = maxf(float(burning.get("remaining", 0.0)), float(effect.get("burn_duration", 4.0)))
	burning["dot_damage"] = maxf(float(burning.get("dot_damage", 0.0)), float(attacker.attack) * float(effect.get("burn_dot_ratio", 0.16)))
	burning["tick_interval"] = interval
	burning["tick_timer"] = minf(float(burning.get("tick_timer", interval)), interval)
	combat_statuses["naka_burning"] = burning


## 对范围内单位造成状态伤害。
func _deal_status_area_damage(amount: int, radius: float, target_team: String, text_color: Color, exclude_unit: UnitBase = null) -> void:
	var grid: GridSystem = BattleManager.grid
	if not grid:
		if exclude_unit != self:
			take_status_damage(amount, text_color)
		return
	var targets := grid.get_units_in_range(grid_position, radius, target_team)
	if targets.is_empty():
		take_status_damage(amount, text_color)
		return
	for candidate in targets:
		if not is_instance_valid(candidate) or not (candidate is UnitBase):
			continue
		var combat_unit := candidate as UnitBase
		if combat_unit == exclude_unit:
			continue
		if combat_unit.is_alive:
			combat_unit.take_status_damage(amount, text_color)


## 是否能接收来自攻击者的负面状态。
func _can_receive_hostile_status(attacker: UnitBase) -> bool:
	return is_alive and is_instance_valid(attacker) and attacker.is_alive and attacker.team != team


## 尝试触发窥探禁忌处决。
func _try_moon_forbidden_execute(mark: Dictionary) -> void:
	if not is_alive:
		return
	var threshold := float(mark.get("execute_threshold", 0.0))
	if threshold <= 0.0 or float(current_hp) > threshold:
		return
	take_status_damage(current_hp, Color(0.74, 0.44, 1.0, 1.0))


## 触发窥探禁忌死亡爆发。
func _trigger_moon_forbidden_death_burst() -> void:
	if team != "enemy" or not combat_statuses.has("moon_forbidden_mark"):
		return
	var mark: Dictionary = combat_statuses.get("moon_forbidden_mark", {})
	if float(mark.get("remaining", 0.0)) <= 0.0:
		return
	var damage := maxi(0, int(round(float(mark.get("burst_damage", 0.0)))))
	if damage <= 0:
		return
	_deal_status_area_damage(damage, maxf(0.0, float(mark.get("burst_radius", 1.0))), team, Color(0.72, 0.34, 1.0, 1.0), self)


## 获取状态提供的固定属性。
func _get_status_flat_bonus(key: String) -> int:
	var total := 0
	var sources: Dictionary = combat_statuses.get("tro_poem_sources", {})
	for source_id in sources.keys():
		var source_data: Dictionary = sources.get(source_id, {})
		total += int(source_data.get(key, 0))
	return total


## 获取十一长诗的非递归生命基准。
func _get_tro_poem_source_max_hp() -> int:
	return maxi(1, int(round(float(base_max_hp) * float(synergy_modifiers.get("max_hp_multiplier", 1.0)))))


## 获取十一长诗的非递归攻击基准。
func _get_tro_poem_source_attack() -> int:
	return maxi(1, int(round(float(base_attack) * float(synergy_modifiers.get("attack_multiplier", 1.0)))))


## 获取十一长诗的非递归防御基准。
func _get_tro_poem_source_defense() -> int:
	var value := maxi(0, int(round(float(base_defense) * float(synergy_modifiers.get("defense_multiplier", 1.0)))))
	if stance == Stance.STATIONED and class_template:
		value = maxi(0, int(round(float(value) * class_template.stance_defense_bonus)))
	return value


## 显示伤害/治疗飘字：从单位中心向上跳起后淡出
func _show_floating_number(amount: int, text_color: Color) -> void:
	"""显示伤害/治疗飘字：从单位中心向上跳起后淡出"""
	if not SettingsManager.show_floating_numbers:
		return
	var label := Label.new()
	label.text = "%+d" % amount
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(unit_radius * 3.0, 28.0)
	label.position = -label.size * 0.5
	label.z_index = 100
	add_child(label)

	var start_pos := label.position
	var end_pos := start_pos + Vector2(0.0, -floating_number_rise)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", end_pos, floating_number_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, floating_number_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(label.queue_free)


## 显示状态飘字。
func _show_floating_text(text: String, text_color: Color) -> void:
	if not SettingsManager.show_floating_numbers:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(unit_radius * 3.0, 28.0)
	label.position = -label.size * 0.5
	label.z_index = 100
	add_child(label)

	var start_pos := label.position
	var end_pos := start_pos + Vector2(0.0, -floating_number_rise)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", end_pos, floating_number_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, floating_number_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(label.queue_free)


## 处理die逻辑。
func _die() -> void:
	if not is_alive:
		return
	_trigger_moon_forbidden_death_burst()
	is_alive = false
	died.emit(self)
	if team == "player":
		BattleManager.unregister_player_unit(self)
	else:
		BattleManager.unregister_enemy_unit(self)
	BattleManager.unit_died.emit(self)
	# 死亡后延迟移除
	var timer := get_tree().create_timer(0.3)
	timer.timeout.connect(_remove_from_grid)


## 激活AI行为（波次开始/实时部署时调用）
func activate_ai() -> void:
	"""激活AI行为（波次开始/实时部署时调用）"""
	ai_enabled = true


## 暂停AI行为（静态部署时调用）
func deactivate_ai() -> void:
	"""暂停AI行为（静态部署时调用）"""
	ai_enabled = false


## 移除网格。
func _remove_from_grid() -> void:
	var g: GridSystem = BattleManager.grid
	if g:
		g.remove_unit(self)
	queue_free()


## 切换行进/驻扎状态
func toggle_stance() -> void:
	"""切换行进/驻扎状态"""
	if stance == Stance.MARCH:
		stance = Stance.STATIONED
	else:
		stance = Stance.MARCH
	_recalculate_stats(true)
	stance_changed.emit(stance == Stance.STATIONED)


## 使用技能
func use_skill(skill_id: String) -> bool:
	"""使用技能"""
	var sd := SkillData.get_skill(skill_id)
	if not sd:
		return false
	if skill_cooldowns.get(skill_id, 0.0) > 0:
		return false
	if not ResourceManager.spend(sd.dp_cost):
		return false
	# 执行技能效果
	_execute_skill(sd)
	var cooldown_reduction := clampf(float(synergy_modifiers.get("skill_cooldown_reduction", 0.0)), 0.0, 0.40)
	skill_cooldowns[skill_id] = max(0.1, sd.cooldown * (1.0 - cooldown_reduction))
	_notify_passives("after_skill_used", {
		"skill_id": skill_id,
		"skill": sd,
	})
	return true


## 执行技能逻辑
func _execute_skill(sd: SkillData) -> void:
	"""执行技能逻辑"""
	var grid: GridSystem = BattleManager.grid
	if not grid:
		return

	if sd.damage_multiplier > 0:
		# 伤害技能
		if sd.aoe_radius > 0:
			# AOE伤害
			var targets := grid.get_units_in_range(grid_position, sd.aoe_radius, _enemy_team())
			for t in targets:
				if t.has_method("take_damage"):
					_deal_damage_to_target(t, attack * sd.damage_multiplier, true)
		else:
			# 单体伤害
			if target and is_instance_valid(target) and target.has_method("take_damage"):
				_deal_damage_to_target(target, attack * sd.damage_multiplier, true)

	if sd.heal_amount > 0:
		# 治疗技能
		var targets := grid.get_units_in_range(grid_position, sd.aoe_radius, team)
		for t in targets:
			if t.has_method("heal"):
				t.heal(_calculate_heal(attack * sd.heal_amount))

	if sd.buff_defense > 0:
		# Buff技能
		defense = int(defense * sd.buff_defense)
		if sd.duration > 0:
			var timer := get_tree().create_timer(sd.duration)
			timer.timeout.connect(func(): _recalculate_stats(true))

	if sd.duration > 0 and sd.buff_defense == 0:
		# 通用持续效果
		pass

	Log.i(M, "[%s] 使用了技能: %s" % [unit_name, sd.skill_name])


## 处理敌人队伍逻辑。
func _enemy_team() -> String:
	return "enemy" if team == "player" else "player"


## 执行普攻
func perform_attack() -> void:
	"""执行普攻"""
	if attack_cooldown > 0:
		return
	if not target or not is_instance_valid(target):
		return
	var interval := 999.0 if attack_speed <= 0 else 1.0 / attack_speed
	attack_cooldown = interval

	var target_snapshot := target
	var attack_snapshot := float(attack)
	if class_template and class_template.attack_mode == ClassTemplate.AttackMode.HEAL:
		if target_snapshot.has_method("heal"):
			_launch_basic_attack_projectile(target_snapshot, true, attack_snapshot)
	else:
		if target_snapshot.has_method("take_damage"):
			_launch_basic_attack_projectile(target_snapshot, false, attack_snapshot)


## 发射一次普通攻击投射物，命中后再结算伤害或治疗。
func _launch_basic_attack_projectile(target_unit: Node, is_heal_projectile: bool, base_amount: float) -> void:
	if not target_unit or not is_instance_valid(target_unit):
		return
	var projectile_script = load("res://scripts/combat/projectile.gd")
	if not projectile_script:
		_resolve_basic_attack_projectile_hit(target_unit, is_heal_projectile, base_amount)
		return

	var projectile = projectile_script.new()
	if not projectile:
		_resolve_basic_attack_projectile_hit(target_unit, is_heal_projectile, base_amount)
		return

	var parent := _get_projectile_parent()
	parent.add_child(projectile)
	projectile.setup({
		"source": self,
		"target": target_unit,
		"on_hit": Callable(self, "_resolve_basic_attack_projectile_hit").bind(target_unit, is_heal_projectile, base_amount),
		"speed": projectile_speed,
		"start_position": global_position + projectile_launch_offset,
		"target_offset": projectile_hit_offset,
		"visual_scene": projectile_visual_scene,
		"visual_texture": projectile_texture,
		"visual_color": projectile_visual_color,
		"visual_radius": projectile_visual_radius,
	})


## 处理普通攻击投射物命中。
func _resolve_basic_attack_projectile_hit(target_unit: Node, is_heal_projectile: bool, base_amount: float) -> void:
	if not target_unit or not is_instance_valid(target_unit):
		return
	if target_unit is UnitBase and not (target_unit as UnitBase).is_alive:
		return
	if is_heal_projectile:
		if target_unit.has_method("heal"):
			target_unit.heal(_calculate_heal(base_amount))
	elif target_unit.has_method("take_damage"):
		_deal_damage_to_target(target_unit, base_amount, false)


## 投射物挂在战斗场景节点下，避免跟随发射者移动或被发射者缩放影响。
func _get_projectile_parent() -> Node:
	if BattleManager.grid:
		return BattleManager.grid
	if get_parent():
		return get_parent()
	return get_tree().root


## 对目标造成一次攻击/技能伤害并触发主羁绊命中效果。
func _deal_damage_to_target(target_unit: Node, base_amount: float, is_skill: bool) -> int:
	if not target_unit or not is_instance_valid(target_unit) or not target_unit.has_method("take_damage"):
		return 0
	var damage := _calculate_damage(base_amount, is_skill)
	var target_combat_unit: UnitBase = target_unit as UnitBase if target_unit is UnitBase else null
	if target_combat_unit:
		var damage_context := {
			"target": target_combat_unit,
			"base_amount": base_amount,
			"damage": damage,
			"is_skill": is_skill,
		}
		_notify_passives("before_deal_damage", damage_context)
		damage = maxi(1, int(damage_context.get("damage", damage)))
	var dealt: int = target_combat_unit.receive_attack_damage(damage, _get_armor_pierce(), self) if target_combat_unit else target_unit.take_damage(damage, _get_armor_pierce())
	_apply_life_steal(dealt)
	if target_combat_unit:
		_notify_passives("after_deal_damage", {
			"target": target_combat_unit,
			"damage_dealt": dealt,
			"is_skill": is_skill,
		})
	return dealt


## 计算伤害。
func _calculate_damage(base_amount: float, is_skill: bool) -> int:
	var amount := base_amount * float(synergy_modifiers.get("damage_multiplier", 1.0))
	if is_skill:
		amount *= float(synergy_modifiers.get("skill_damage_multiplier", 1.0))
	if combat_statuses.has("kroen_counter"):
		var counter: Dictionary = combat_statuses.get("kroen_counter", {})
		amount *= float(counter.get("damage_multiplier", 1.0))
	if randf() < clampf(float(synergy_modifiers.get("crit_chance", 0.0)), 0.0, 0.75):
		amount *= 1.5 * float(synergy_modifiers.get("crit_damage_multiplier", 1.0))
	return maxi(1, int(round(amount)))


## 计算治疗。
func _calculate_heal(base_amount: float) -> int:
	var amount := base_amount * float(synergy_modifiers.get("heal_multiplier", 1.0))
	return maxi(1, int(round(amount)))


## 获取护甲穿透。
func _get_armor_pierce() -> float:
	return clampf(float(synergy_modifiers.get("armor_pierce", 0.0)), 0.0, 0.95)


## 应用lifesteal。
func _apply_life_steal(damage_dealt: int) -> void:
	if team != "player" or damage_dealt <= 0:
		return
	var percent := clampf(float(synergy_modifiers.get("life_steal_percent", 0.0)), 0.0, 0.50)
	if percent <= 0:
		return
	heal(int(round(float(damage_dealt) * percent)))
