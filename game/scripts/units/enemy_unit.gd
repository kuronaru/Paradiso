# enemy_unit.gd — 敌人单位
# 继承UnitBase，增加敌人模板数据定义
class_name EnemyUnit
extends UnitBase

const REFERENCE_BODY_RADIUS := 24.0
const REFERENCE_COLLISION_RADIUS := 12.0
const BODY_RADIUS_CELL_RATIO := 0.4
const COLLISION_RADIUS_CELL_RATIO := 0.25

enum EnemyType {
	MELEE,       ## 近战杂兵
	RANGED,      ## 远程
	BRUTE,       ## 重装
	BOSS         ## Boss
}

var enemy_type: EnemyType = EnemyType.MELEE
var enemy_id: String = ""
var enemy_template_name: String = ""
var chapter_id: String = ""
var rarity: String = "common"
var target_priority: String = "nearest"
var enemy_uid: String = ""
var source_player_id: int = 1
var base_damage: int = 1
var transfer_count: int = 0
var spawn_template: Dictionary = {}
var _resolved: bool = false
var reference_body_radius: float = REFERENCE_BODY_RADIUS
var reference_collision_radius: float = REFERENCE_COLLISION_RADIUS
var applied_geometry_scale: float = -1.0


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	team = "enemy"
	sync_geometry_to_grid(_current_grid_cell_size())
	super._ready()


## 从敌人模板字典初始化
func setup_from_template(template: Dictionary) -> void:
	"""从敌人模板字典初始化"""
	reference_body_radius = REFERENCE_BODY_RADIUS
	reference_collision_radius = REFERENCE_COLLISION_RADIUS
	spawn_template = template.duplicate(true)
	enemy_id = str(template.get("enemy_id", ""))
	enemy_template_name = template.get("name", "Unknown")
	chapter_id = str(template.get("chapter_id", ""))
	rarity = str(template.get("rarity", "common"))
	target_priority = str(template.get("target_priority", "nearest")).strip_edges().to_lower()
	enemy_type = _enemy_type_from_value(template.get("type", template.get("enemy_type", EnemyType.MELEE)))
	enemy_uid = str(template.get("enemy_uid", ""))
	source_player_id = int(template.get("source_player_id", 1))
	base_damage = maxi(1, int(template.get("base_damage", _cfg_int("enemy_base_damage", 1))))
	transfer_count = maxi(0, int(template.get("transfer_count", 0)))
	_resolved = false
	unit_name = enemy_template_name

	max_hp = int(template.get("max_hp", template.get("hp", 80)))
	current_hp = clampi(int(template.get("current_hp", max_hp)), 1, max_hp)
	attack = template.get("atk", 10)
	defense = template.get("def", 3)
	attack_speed = template.get("attack_speed", 1.0)
	move_speed = template.get("move_speed", 1.5)
	var configured_collision_radius := float(template.get("collision_radius", 0.0))
	attack_range = template.get("attack_range", 1.5)
	search_range = template.get("search_range", 5.0)
	airborne = bool(template.get("is_airborne", false))
	set_base_stats_from_current()
	setup_intrinsic_passives_from_configs(template.get("passives", []))

	# 颜色根据类型
	match enemy_type:
		EnemyType.MELEE:
			color = Color(1.0, 0.3, 0.3)
		EnemyType.RANGED:
			color = Color(1.0, 0.6, 0.2)
		EnemyType.BRUTE:
			color = Color(0.8, 0.2, 0.2)
			reference_body_radius = 32.0
		EnemyType.BOSS:
			color = Color(0.8, 0.1, 0.5)
			reference_body_radius = 40.0
	var configured_color := str(template.get("visual_color", ""))
	if configured_color != "":
		color = Color.from_string(configured_color, color)
	reference_body_radius *= maxf(0.35, float(template.get("body_radius_scale", 1.0)))

	var type_scale := reference_body_radius / REFERENCE_BODY_RADIUS
	reference_collision_radius = configured_collision_radius if configured_collision_radius > 0.0 else REFERENCE_COLLISION_RADIUS * type_scale
	applied_geometry_scale = -1.0
	sync_geometry_to_grid(_current_grid_cell_size())

	# 没有class_template时用默认索敌
	for child in get_children():
		if child is ColorRect:
			child.color = color
			child.size = Vector2(unit_radius * 2, unit_radius * 2)
			child.position = -Vector2(unit_radius, unit_radius)

	BattleManager.register_enemy_unit(self)
	hp_changed.emit(current_hp, max_hp)


## Keep enemy art, body outline and collision proportional to the live grid size.
func sync_geometry_to_grid(cell_size: float) -> void:
	var safe_cell_size := maxf(cell_size, 1.0)
	var type_scale := reference_body_radius / REFERENCE_BODY_RADIUS
	var next_body_radius := safe_cell_size * BODY_RADIUS_CELL_RATIO * type_scale
	var geometry_scale := next_body_radius / reference_body_radius
	if is_equal_approx(geometry_scale, applied_geometry_scale):
		return
	applied_geometry_scale = geometry_scale
	unit_radius = next_body_radius
	collision_radius = safe_cell_size * COLLISION_RADIUS_CELL_RATIO * reference_collision_radius / REFERENCE_COLLISION_RADIUS
	set_visual_scale_multiplier(geometry_scale)
	refresh_unit_geometry()


func _current_grid_cell_size() -> float:
	var current_grid: GridSystem = BattleManager.grid
	return current_grid.cell_size if current_grid else 64.0


## 构建可通过 RPC 传输的敌人快照。
func to_transfer_payload() -> Dictionary:
	var payload := spawn_template.duplicate(true)
	payload["enemy_uid"] = enemy_uid
	payload["enemy_id"] = enemy_id
	payload["name"] = enemy_template_name
	payload["chapter_id"] = chapter_id
	payload["rarity"] = rarity
	payload["target_priority"] = target_priority
	payload["type"] = int(enemy_type)
	payload["hp"] = max_hp
	payload["max_hp"] = max_hp
	payload["current_hp"] = current_hp
	payload["atk"] = attack
	payload["def"] = defense
	payload["attack_speed"] = attack_speed
	payload["move_speed"] = move_speed
	payload["attack_range"] = attack_range
	payload["search_range"] = search_range
	payload["is_airborne"] = airborne
	payload["source_player_id"] = source_player_id
	payload["base_damage"] = base_damage
	payload["transfer_count"] = transfer_count
	return payload


func get_target_priority() -> String:
	return target_priority


func mark_resolved() -> void:
	_resolved = true
	is_alive = false
	deactivate_ai()


func is_resolved() -> bool:
	return _resolved


## 获取敌人池。
static func get_enemy_pool() -> Array:
	var registry := _registry()
	if registry and registry.has_method("get_enemy_pool"):
		var pool: Array = []
		for template in registry.get_enemy_pool():
			var converted: Dictionary = template.duplicate(true)
			converted["type"] = _enemy_type_from_value(converted.get("type", converted.get("enemy_type", EnemyType.MELEE)))
			pool.append(converted)
		if not pool.is_empty():
			return pool
	return [
		{
			"enemy_id": "fallback_enemy",
			"name": "测试敌人",
			"type": EnemyType.MELEE,
			"hp": 80, "atk": 10, "def": 3,
			"attack_speed": 1.0, "move_speed": 1.5,
			"attack_range": 1.0, "search_range": 5.0
		},
	]


static func _enemy_type_from_value(value) -> EnemyType:
	if value is int:
		return value
	match str(value).strip_edges().to_lower():
		"ranged":
			return EnemyType.RANGED
		"brute":
			return EnemyType.BRUTE
		"boss":
			return EnemyType.BOSS
		_:
			return EnemyType.MELEE


static func _registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("DataRegistry")


func _cfg_int(key: String, default_value: int) -> int:
	var registry := _registry()
	if registry and registry.has_method("get_config"):
		return int(registry.get_config(key, default_value))
	return default_value
