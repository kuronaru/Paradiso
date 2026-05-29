# skill_data.gd — 技能数据定义
class_name SkillData
extends RefCounted

var skill_id: String = ""
var skill_name: String = ""
var description: String = ""
var cooldown: float = 0.0          # 冷却时间（秒）
var dp_cost: int = 0               # 施放消耗DP
var damage_multiplier: float = 1.0 # 伤害倍率（基于角色攻击力）
var aoe_radius: float = 0.0        # 范围效果半径（0=单体）
var heal_amount: float = 0.0       # 治疗量（基于角色攻击力）
var buff_defense: float = 0.0      # 防御增益
var duration: float = 0.0          # 持续时间（0=瞬间）


static var _skill_registry: Dictionary = {}
static var _initialized: bool = false


static func _init_registry() -> void:
	if _initialized:
		return
	_initialized = true

	# === 战士技能 ===
	_add_skill("shield_wall", "盾墙", "提升自身防御力200%，持续5秒",
		15.0, 5, 0.0, 0.0, 0.0, 2.0, 5.0)

	_add_skill("taunt", "嘲讽", "嘲讽范围内所有敌人，强制攻击自己3秒",
		12.0, 3, 0.0, 2.0, 0.0, 0.0, 3.0)

	# === 游侠技能 ===
	_add_skill("barrage", "箭雨", "对目标区域造成150%攻击力的范围伤害",
		10.0, 8, 1.5, 1.5, 0.0, 0.0, 0.0)

	_add_skill("snipe", "狙击", "对最远目标造成250%单体伤害",
		8.0, 6, 2.5, 0.0, 0.0, 0.0, 0.0)

	# === 法师技能 ===
	_add_skill("fireball", "火球术", "对目标区域造成200%魔法伤害",
		8.0, 10, 2.0, 2.0, 0.0, 0.0, 0.0)

	_add_skill("arcane_nova", "奥术新星", "以自身为中心造成300%范围伤害",
		20.0, 15, 3.0, 3.0, 0.0, 0.0, 0.0)

	# === 牧师技能 ===
	_add_skill("heal_wave", "治愈波浪", "为范围内友方单位恢复150%攻击力的生命值",
		6.0, 8, 0.0, 2.0, 1.5, 0.0, 0.0)

	_add_skill("blessing", "祝福", "为目标提升50%攻击力，持续8秒",
		16.0, 5, 0.0, 0.0, 0.0, 0.0, 8.0)

	# === 盗贼技能 ===
	_add_skill("shadow_strike", "暗影突袭", "瞬移至最远敌人身后并造成200%伤害",
		14.0, 5, 2.0, 0.0, 0.0, 0.0, 0.0)

	_add_skill("poison_blade", "淬毒之刃", "下次攻击附加持续伤害，每秒20%攻击力持续4秒",
		10.0, 3, 1.0, 0.0, 0.0, 0.0, 0.0)


static func _add_skill(id: String, name: String, desc: String,
		cd: float, cost: int, dmg_mult: float, aoe: float,
		heal: float, buff_def: float, dur: float) -> void:
	var s := SkillData.new()
	s.skill_id = id
	s.skill_name = name
	s.description = desc
	s.cooldown = cd
	s.dp_cost = cost
	s.damage_multiplier = dmg_mult
	s.aoe_radius = aoe
	s.heal_amount = heal
	s.buff_defense = buff_def
	s.duration = dur
	_skill_registry[id] = s


static func get_skill(skill_id: String) -> SkillData:
	_init_registry()
	if _skill_registry.has(skill_id):
		return _skill_registry[skill_id]
	push_warning("Unknown skill_id: %s" % skill_id)
	return null
