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


## 提供initregistry静态数据或工具逻辑。
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

	# === 基础角色技能：野蛮人 ===
	_add_skill("heavy_cleave", "重斩", "对近处敌人造成145%物理伤害",
		8.0, 4, 1.45, 1.0, 0.0, 0.0, 0.0)
	_add_skill("guardian_totem", "护身图腾", "自身防御提升180%，持续5秒",
		14.0, 5, 0.0, 0.0, 0.0, 1.8, 5.0)
	_add_skill("ancestral_guard", "祖灵护持", "治疗周围友军70%攻击力的生命值",
		12.0, 5, 0.0, 2.0, 0.7, 0.0, 0.0)

	# === 基础角色技能：吟游诗人 ===
	_add_skill("inspired_phrase", "鼓舞短句", "对敌人造成110%法术伤害，数值定位为技能队辅助",
		10.0, 4, 1.1, 0.0, 0.0, 0.0, 0.0)
	_add_skill("war_song_beat", "战歌节拍", "自身防御提升140%，持续6秒",
		12.0, 4, 0.0, 0.0, 0.0, 1.4, 6.0)
	_add_skill("charming_note", "迷惑音节", "对小范围敌人造成100%法术伤害",
		11.0, 5, 1.0, 1.4, 0.0, 0.0, 0.0)

	# === 基础角色技能：牧师 ===
	_add_skill("quick_heal", "快速治疗", "治疗周围友军130%攻击力的生命值",
		6.0, 5, 0.0, 3.0, 1.3, 0.0, 0.0)
	_add_skill("glimmer_bolt", "微光弹", "造成120%范围法术伤害，并治疗附近友军45%攻击力",
		8.0, 6, 1.2, 1.4, 0.45, 0.0, 0.0)
	_add_skill("battle_blessing", "战前祝福", "自身防御提升150%，持续5秒",
		12.0, 5, 0.0, 0.0, 0.0, 1.5, 5.0)

	# === 基础角色技能：德鲁伊 ===
	_add_skill("moon_guard", "月形守护", "自身防御提升160%，持续5秒，并造成80%近身范围伤害",
		13.0, 5, 0.8, 1.2, 0.0, 1.6, 5.0)
	_add_skill("entangle_roots", "缠根术", "对目标区域造成100%法术伤害",
		10.0, 6, 1.0, 1.8, 0.0, 0.0, 0.0)
	_add_skill("spore_cloud", "孢子云", "对小范围敌人造成135%法术伤害",
		9.0, 6, 1.35, 1.6, 0.0, 0.0, 0.0)

	# === 基础角色技能：战士 ===
	_add_skill("precise_slash", "精准斩", "对当前目标造成160%物理伤害",
		7.0, 4, 1.6, 0.0, 0.0, 0.0, 0.0)
	_add_skill("suppress_order", "压制指令", "对近处敌人造成120%范围物理伤害",
		9.0, 5, 1.2, 1.2, 0.0, 0.0, 0.0)
	_add_skill("arcane_cleave", "魔力劈砍", "造成130%范围伤害，并提升自身防御130%持续4秒",
		10.0, 6, 1.3, 1.0, 0.0, 1.3, 4.0)

	# === 基础角色技能：武僧 ===
	_add_skill("flurry_punch", "连环拳", "对当前目标造成190%物理伤害",
		6.0, 4, 1.9, 0.0, 0.0, 0.0, 0.0)
	_add_skill("shadow_step_strike", "影步击", "对低生命目标造成175%物理伤害",
		8.0, 5, 1.75, 0.0, 0.0, 0.0, 0.0)
	_add_skill("elemental_palm", "四象掌", "对目标区域造成125%法术伤害",
		9.0, 5, 1.25, 1.2, 0.0, 0.0, 0.0)

	# === 基础角色技能：圣武士 ===
	_add_skill("devotion_guard", "奉献守护", "治疗周围友军75%攻击力，并提升自身防御140%持续5秒",
		12.0, 6, 0.0, 2.0, 0.75, 1.4, 5.0)
	_add_skill("vengeance_smite", "复仇圣击", "对高威胁目标造成180%神圣伤害",
		10.0, 6, 1.8, 0.0, 0.0, 0.0, 0.0)
	_add_skill("ancient_prayer", "古贤祝祷", "治疗周围友军65%攻击力，并提升自身防御135%持续5秒",
		13.0, 6, 0.0, 2.4, 0.65, 1.35, 5.0)

	# === 基础角色技能：游侠 ===
	_add_skill("aimed_shot", "瞄准射击", "对当前目标造成170%远程物理伤害",
		7.0, 5, 1.7, 0.0, 0.0, 0.0, 0.0)
	_add_skill("coordinated_assault", "协同突击", "对当前目标造成150%远程物理伤害",
		8.0, 5, 1.5, 0.0, 0.0, 0.0, 0.0)
	_add_skill("darkwood_arrow", "暗林一箭", "对低生命目标造成200%远程物理伤害",
		9.0, 6, 2.0, 0.0, 0.0, 0.0, 0.0)

	# === 基础角色技能：游荡者 ===
	_add_skill("quick_stab", "快手刺击", "对当前目标造成145%物理伤害",
		6.0, 3, 1.45, 0.0, 0.0, 0.0, 0.0)
	_add_skill("backstab", "背刺", "对低生命目标造成210%物理伤害",
		8.0, 5, 2.1, 0.0, 0.0, 0.0, 0.0)
	_add_skill("illusion_dagger", "幻术匕首", "对目标区域造成120%法术伤害",
		9.0, 5, 1.2, 1.0, 0.0, 0.0, 0.0)

	# === 基础角色技能：术士 ===
	_add_skill("drake_spark", "龙息火花", "对前方区域造成160%法术伤害",
		10.0, 7, 1.6, 1.6, 0.0, 0.0, 0.0)
	_add_skill("unstable_bolt", "紊乱法弹", "对随机目标附近造成175%法术伤害",
		9.0, 7, 1.75, 1.2, 0.0, 0.0, 0.0)
	_add_skill("arc_spell", "电弧术", "对目标附近敌人造成145%法术伤害",
		8.0, 7, 1.45, 1.5, 0.0, 0.0, 0.0)

	# === 基础角色技能：契术师 ===
	_add_skill("pact_blade_slash", "契刃斩", "造成140%法术伤害，并治疗自身50%攻击力",
		9.0, 5, 1.4, 0.0, 0.5, 0.0, 0.0)
	_add_skill("curse_rune", "诅咒符文", "对高威胁目标造成130%法术伤害",
		8.0, 6, 1.3, 0.0, 0.0, 0.0, 0.0)
	_add_skill("familiar_assist", "魔宠协击", "对当前目标造成155%法术伤害",
		7.0, 5, 1.55, 0.0, 0.0, 0.0, 0.0)

	# === 基础角色技能：法师 ===
	_add_skill("flame_bolt", "火焰弹", "对目标区域造成190%法术伤害",
		8.0, 8, 1.9, 1.8, 0.0, 0.0, 0.0)
	_add_skill("shield_spell", "护盾术", "治疗周围友军80%攻击力，并提升自身防御140%持续5秒",
		12.0, 7, 0.0, 2.0, 0.8, 1.4, 5.0)
	_add_skill("portent", "预兆", "对高威胁目标造成115%法术伤害",
		8.0, 5, 1.15, 0.0, 0.0, 0.0, 0.0)

	# === 基础角色技能：奇械师 ===
	_add_skill("healing_elixir", "治疗药剂", "治疗周围友军100%攻击力的生命值",
		8.0, 6, 0.0, 2.4, 1.0, 0.0, 0.0)
	_add_skill("armor_reinforce", "装甲加固", "自身防御提升200%，持续5秒",
		13.0, 5, 0.0, 0.0, 0.0, 2.0, 5.0)
	_add_skill("light_cannon", "简易炮击", "对目标区域造成170%混合伤害",
		10.0, 7, 1.7, 1.7, 0.0, 0.0, 0.0)


## 提供添加技能静态数据或工具逻辑。
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


## 获取技能。
static func get_skill(skill_id: String) -> SkillData:
	_init_registry()
	if _skill_registry.has(skill_id):
		return _skill_registry[skill_id]
	push_warning("Unknown skill_id: %s" % skill_id)
	return null
