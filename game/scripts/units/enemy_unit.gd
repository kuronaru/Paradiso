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
var enemy_template_name: String = ""


func _ready() -> void:
	team = "enemy"
	super._ready()


func setup_from_template(template: Dictionary) -> void:
	"""从敌人模板字典初始化"""
	enemy_template_name = template.get("name", "Unknown")
	enemy_type = template.get("type", EnemyType.MELEE)
	unit_name = enemy_template_name

	max_hp = template.get("hp", 80)
	current_hp = max_hp
	attack = template.get("atk", 10)
	defense = template.get("def", 3)
	attack_speed = template.get("attack_speed", 1.0)
	move_speed = template.get("move_speed", 1.5)
	attack_range = template.get("attack_range", 1.5)
	search_range = template.get("search_range", 5.0)
	set_base_stats_from_current()

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

	# 没有class_template时用默认索敌
	for child in get_children():
		if child is ColorRect:
			child.color = color
			child.size = Vector2(unit_radius * 2, unit_radius * 2)
			child.position = -Vector2(unit_radius, unit_radius)

	BattleManager.register_enemy_unit(self)
	hp_changed.emit(current_hp, max_hp)


## 预定义敌人模板
static func get_enemy_pool() -> Array:
	return [
		{
			"name": "哥布林",
			"type": EnemyType.MELEE,
			"hp": 60, "atk": 8, "def": 2,
			"attack_speed": 1.2, "move_speed": 2.0,
			"attack_range": 1.0, "search_range": 4.0
		},
		{
			"name": "骷髅兵",
			"type": EnemyType.MELEE,
			"hp": 80, "atk": 12, "def": 4,
			"attack_speed": 1.0, "move_speed": 1.5,
			"attack_range": 1.0, "search_range": 5.0
		},
		{
			"name": "骷髅弓手",
			"type": EnemyType.RANGED,
			"hp": 50, "atk": 15, "def": 1,
			"attack_speed": 0.8, "move_speed": 1.5,
			"attack_range": 4.0, "search_range": 6.0
		},
		{
			"name": "食人魔",
			"type": EnemyType.BRUTE,
			"hp": 200, "atk": 25, "def": 8,
			"attack_speed": 0.5, "move_speed": 1.0,
			"attack_range": 1.5, "search_range": 4.0
		},
		{
			"name": "石像鬼",
			"type": EnemyType.RANGED,
			"hp": 70, "atk": 18, "def": 3,
			"attack_speed": 1.0, "move_speed": 3.0,
			"attack_range": 3.0, "search_range": 7.0
		},
		{
			"name": "巨龙Boss",
			"type": EnemyType.BOSS,
			"hp": 500, "atk": 40, "def": 12,
			"attack_speed": 0.4, "move_speed": 0.8,
			"attack_range": 3.0, "search_range": 8.0
		},
	]
