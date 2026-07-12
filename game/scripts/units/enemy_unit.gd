# enemy_unit.gd — 敌人单位
# 继承UnitBase，增加敌人模板数据定义
class_name EnemyUnit
extends UnitBase

enum EnemyType {
	MELEE,       ## 近战杂兵
	RANGED,      ## 远程
	BRUTE,       ## 重装
	BOSS         ## Boss
}

var enemy_type: EnemyType = EnemyType.MELEE
var enemy_id: String = ""
var enemy_template_name: String = ""


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	team = "enemy"
	super._ready()


## 从敌人模板字典初始化
func setup_from_template(template: Dictionary) -> void:
	"""从敌人模板字典初始化"""
	enemy_id = str(template.get("enemy_id", ""))
	enemy_template_name = template.get("name", "Unknown")
	enemy_type = _enemy_type_from_value(template.get("type", template.get("enemy_type", EnemyType.MELEE)))
	unit_name = enemy_template_name

	max_hp = template.get("hp", 80)
	current_hp = max_hp
	attack = template.get("atk", 10)
	defense = template.get("def", 3)
	attack_speed = template.get("attack_speed", 1.0)
	move_speed = template.get("move_speed", 1.5)
	collision_radius = float(template.get("collision_radius", 0.0))
	attack_range = template.get("attack_range", 1.5)
	search_range = template.get("search_range", 5.0)
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
			unit_radius = 32.0
		EnemyType.BOSS:
			color = Color(0.8, 0.1, 0.5)
			unit_radius = 40.0

	refresh_ground_collision()

	# 没有class_template时用默认索敌
	for child in get_children():
		if child is ColorRect:
			child.color = color
			child.size = Vector2(unit_radius * 2, unit_radius * 2)
			child.position = -Vector2(unit_radius, unit_radius)

	BattleManager.register_enemy_unit(self)
	hp_changed.emit(current_hp, max_hp)


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
