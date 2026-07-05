# class_definitions.gd — 预定义角色模板工厂
# 用 DND 职业/小分支作为角色基础数值定义，并兼容旧五职业 ID。
class_name ClassDefinitions
extends RefCounted

static var _cache: Dictionary = {}

const LEGACY_ALIASES := {
	"warrior": "fighter_champion",
	"ranger": "ranger_hunter",
	"mage": "wizard_evocation",
	"priest": "cleric_life_domain",
	"rogue": "rogue_thief",
}

const CHARACTER_IDS: Array[String] = [
	"barbarian_berserker",
	"barbarian_totem_warrior",
	"barbarian_ancestral_guardian",
	"bard_lore",
	"bard_valor",
	"bard_glamour",
	"cleric_life_domain",
	"cleric_light_domain",
	"cleric_war_domain",
	"druid_moon",
	"druid_land",
	"druid_spores",
	"fighter_champion",
	"fighter_battle_master",
	"fighter_eldritch_knight",
	"monk_open_hand",
	"monk_shadow",
	"monk_four_elements",
	"paladin_devotion",
	"paladin_vengeance",
	"paladin_ancients",
	"ranger_hunter",
	"ranger_beast_master",
	"ranger_gloom_stalker",
	"rogue_thief",
	"rogue_assassin",
	"rogue_arcane_trickster",
	"sorcerer_draconic",
	"sorcerer_wild_magic",
	"sorcerer_storm",
	"warlock_blade",
	"warlock_tome",
	"warlock_chain",
	"wizard_evocation",
	"wizard_abjuration",
	"wizard_divination",
	"artificer_alchemist",
	"artificer_armorer",
	"artificer_artillerist",
]

const CLASS_GROUP_ORDER: Array[String] = [
	"anmarit",
	"laferida",
	"naka",
]

const CHARACTER_DATA := {
	"barbarian_berserker": {
		"job_name": "见习狂战士", "class_group": "naka", "subclass_id": "berserker",
		"stat_tags": ["STR", "CON"], "alignment_tags": ["CHAOTIC", "NEUTRAL"],
		"deploy_cost": 9, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 4.2, "base_hp": 220, "base_atk": 25, "base_def": 8,
		"attack_speed": 0.95, "move_speed": 2.15, "stance_defense_bonus": 1.45, "stance_range_bonus": 1.0,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.35, "march_attack_penalty": 0.78,
		"target_priority": "nearest", "skill_ids": ["heavy_cleave"], "shop_level": 1, "base_cost": 2,
		"tavern_passive": "低血爆发"
	},
	"barbarian_totem_warrior": {
		"job_name": "图腾护卫", "class_group": "naka", "subclass_id": "totem_warrior",
		"stat_tags": ["CON", "WIS"], "alignment_tags": ["NEUTRAL", "GOOD"],
		"deploy_cost": 10, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 4.0, "base_hp": 255, "base_atk": 18, "base_def": 13,
		"attack_speed": 0.82, "move_speed": 1.95, "stance_defense_bonus": 1.90, "stance_range_bonus": 1.0,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.70,
		"target_priority": "nearest", "skill_ids": ["guardian_totem"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "前排承压"
	},
	"barbarian_ancestral_guardian": {
		"job_name": "祖灵守卫", "class_group": "naka", "subclass_id": "ancestral_guardian",
		"stat_tags": ["STR", "WIS"], "alignment_tags": ["LAWFUL", "GOOD"],
		"deploy_cost": 11, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 4.5, "base_hp": 235, "base_atk": 21, "base_def": 11,
		"attack_speed": 0.90, "move_speed": 2.05, "stance_defense_bonus": 1.70, "stance_range_bonus": 1.0,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.30, "march_attack_penalty": 0.75,
		"target_priority": "nearest", "skill_ids": ["ancestral_guard"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "友军护持"
	},
	"bard_lore": {
		"job_name": "学识歌者", "class_group": "laferida", "subclass_id": "lore",
		"stat_tags": ["CHA", "INT"], "alignment_tags": ["NEUTRAL", "GOOD"],
		"deploy_cost": 10, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 3.6, "search_range": 6.2, "base_hp": 105, "base_atk": 18, "base_def": 4,
		"attack_speed": 0.82, "move_speed": 2.00, "stance_defense_bonus": 1.15, "stance_range_bonus": 1.55,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.30, "march_attack_penalty": 0.65,
		"target_priority": "highest_atk", "skill_ids": ["inspired_phrase"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "技能鼓舞"
	},
	"bard_valor": {
		"job_name": "勇气歌者", "class_group": "laferida", "subclass_id": "valor",
		"stat_tags": ["CHA", "STR"], "alignment_tags": ["LAWFUL", "GOOD"],
		"deploy_cost": 10, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.2, "search_range": 4.8, "base_hp": 155, "base_atk": 19, "base_def": 8,
		"attack_speed": 0.95, "move_speed": 2.10, "stance_defense_bonus": 1.45, "stance_range_bonus": 1.05,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.30, "march_attack_penalty": 0.75,
		"target_priority": "nearest", "skill_ids": ["war_song_beat"], "shop_level": 1, "base_cost": 2,
		"tavern_passive": "近战激励"
	},
	"bard_glamour": {
		"job_name": "迷魅歌者", "class_group": "laferida", "subclass_id": "glamour",
		"stat_tags": ["CHA", "DEX"], "alignment_tags": ["CHAOTIC", "NEUTRAL"],
		"deploy_cost": 11, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 4.0, "search_range": 6.5, "base_hp": 95, "base_atk": 20, "base_def": 3,
		"attack_speed": 0.90, "move_speed": 2.25, "stance_defense_bonus": 1.10, "stance_range_bonus": 1.60,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.40, "march_attack_penalty": 0.65,
		"target_priority": "random", "skill_ids": ["charming_note"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "扰乱敌阵"
	},
	"cleric_life_domain": {
		"job_name": "生命助祭", "class_group": "laferida", "subclass_id": "life_domain",
		"stat_tags": ["WIS", "CON"], "alignment_tags": ["LAWFUL", "GOOD"],
		"deploy_cost": 10, "attack_mode": "heal", "target_type": "ground", "range_shape": "circle",
		"attack_range": 4.0, "search_range": 6.0, "base_hp": 125, "base_atk": 21, "base_def": 6,
		"attack_speed": 0.72, "move_speed": 1.85, "stance_defense_bonus": 1.30, "stance_range_bonus": 1.80,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.65,
		"target_priority": "lowest_hp", "skill_ids": ["quick_heal"], "shop_level": 1, "base_cost": 3,
		"tavern_passive": "治疗续航"
	},
	"cleric_light_domain": {
		"job_name": "光明助祭", "class_group": "laferida", "subclass_id": "light_domain",
		"stat_tags": ["WIS", "CHA"], "alignment_tags": ["GOOD", "NEUTRAL"],
		"deploy_cost": 11, "attack_mode": "magic_aoe", "target_type": "both", "range_shape": "circle",
		"attack_range": 3.2, "search_range": 6.0, "base_hp": 110, "base_atk": 23, "base_def": 4,
		"attack_speed": 0.62, "move_speed": 1.90, "stance_defense_bonus": 1.20, "stance_range_bonus": 1.70,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.70,
		"target_priority": "nearest", "skill_ids": ["glimmer_bolt"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "光明支援"
	},
	"cleric_war_domain": {
		"job_name": "战争助祭", "class_group": "laferida", "subclass_id": "war_domain",
		"stat_tags": ["WIS", "STR"], "alignment_tags": ["LAWFUL", "GOOD"],
		"deploy_cost": 12, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.2, "search_range": 4.8, "base_hp": 160, "base_atk": 20, "base_def": 9,
		"attack_speed": 0.90, "move_speed": 1.95, "stance_defense_bonus": 1.55, "stance_range_bonus": 1.05,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.72,
		"target_priority": "nearest", "skill_ids": ["battle_blessing"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "前线祝福"
	},
	"druid_moon": {
		"job_name": "月环德鲁伊", "class_group": "anmarit", "subclass_id": "moon",
		"stat_tags": ["WIS", "CON"], "alignment_tags": ["NEUTRAL"],
		"deploy_cost": 11, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.1, "search_range": 4.8, "base_hp": 210, "base_atk": 19, "base_def": 10,
		"attack_speed": 0.88, "move_speed": 2.05, "stance_defense_bonus": 1.65, "stance_range_bonus": 1.05,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.30, "march_attack_penalty": 0.75,
		"target_priority": "nearest", "skill_ids": ["moon_guard"], "shop_level": 1, "base_cost": 3,
		"tavern_passive": "自然前排"
	},
	"druid_land": {
		"job_name": "大地德鲁伊", "class_group": "anmarit", "subclass_id": "land",
		"stat_tags": ["WIS", "CON"], "alignment_tags": ["NEUTRAL", "GOOD"],
		"deploy_cost": 12, "attack_mode": "magic_aoe", "target_type": "ground", "range_shape": "area",
		"attack_range": 3.5, "search_range": 6.0, "base_hp": 145, "base_atk": 22, "base_def": 7,
		"attack_speed": 0.62, "move_speed": 1.80, "stance_defense_bonus": 1.25, "stance_range_bonus": 1.70,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.20, "march_attack_penalty": 0.70,
		"target_priority": "nearest", "skill_ids": ["entangle_roots"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "地形控制"
	},
	"druid_spores": {
		"job_name": "孢子德鲁伊", "class_group": "anmarit", "subclass_id": "spores",
		"stat_tags": ["WIS", "INT"], "alignment_tags": ["NEUTRAL", "EVIL"],
		"deploy_cost": 13, "attack_mode": "magic_aoe", "target_type": "ground", "range_shape": "circle",
		"attack_range": 3.2, "search_range": 6.2, "base_hp": 130, "base_atk": 25, "base_def": 5,
		"attack_speed": 0.58, "move_speed": 1.85, "stance_defense_bonus": 1.15, "stance_range_bonus": 1.65,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.70,
		"target_priority": "nearest", "skill_ids": ["spore_cloud"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "持续伤害"
	},
	"fighter_champion": {
		"job_name": "冠军剑士", "class_group": "naka", "subclass_id": "champion",
		"stat_tags": ["STR", "CON"], "alignment_tags": ["LAWFUL", "NEUTRAL"],
		"deploy_cost": 8, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 4.2, "base_hp": 205, "base_atk": 20, "base_def": 12,
		"attack_speed": 1.12, "move_speed": 2.05, "stance_defense_bonus": 1.80, "stance_range_bonus": 1.0,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.30, "march_attack_penalty": 0.75,
		"target_priority": "nearest", "skill_ids": ["precise_slash"], "shop_level": 1, "base_cost": 2,
		"tavern_passive": "稳定前排"
	},
	"fighter_battle_master": {
		"job_name": "战斗教官", "class_group": "naka", "subclass_id": "battle_master",
		"stat_tags": ["STR", "DEX"], "alignment_tags": ["LAWFUL", "GOOD"],
		"deploy_cost": 9, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.1, "search_range": 4.5, "base_hp": 185, "base_atk": 22, "base_def": 10,
		"attack_speed": 1.05, "move_speed": 2.15, "stance_defense_bonus": 1.65, "stance_range_bonus": 1.0,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.35, "march_attack_penalty": 0.75,
		"target_priority": "highest_atk", "skill_ids": ["suppress_order"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "破防压制"
	},
	"fighter_eldritch_knight": {
		"job_name": "奥法骑士", "class_group": "naka", "subclass_id": "eldritch_knight",
		"stat_tags": ["STR", "INT"], "alignment_tags": ["LAWFUL", "NEUTRAL"],
		"deploy_cost": 11, "attack_mode": "melee_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 1.2, "search_range": 4.8, "base_hp": 175, "base_atk": 23, "base_def": 9,
		"attack_speed": 0.95, "move_speed": 2.05, "stance_defense_bonus": 1.55, "stance_range_bonus": 1.10,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.30, "march_attack_penalty": 0.78,
		"target_priority": "nearest", "skill_ids": ["arcane_cleave"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "法武护盾"
	},
	"monk_open_hand": {
		"job_name": "散打武僧", "class_group": "laferida", "subclass_id": "open_hand",
		"stat_tags": ["DEX", "WIS"], "alignment_tags": ["LAWFUL", "NEUTRAL"],
		"deploy_cost": 8, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 4.5, "base_hp": 145, "base_atk": 18, "base_def": 5,
		"attack_speed": 1.65, "move_speed": 2.85, "stance_defense_bonus": 1.25, "stance_range_bonus": 1.0,
		"stance_is_rooted": false, "march_move_speed_bonus": 1.60, "march_attack_penalty": 0.82,
		"target_priority": "nearest", "skill_ids": ["flurry_punch"], "shop_level": 1, "base_cost": 2,
		"tavern_passive": "高速连击"
	},
	"monk_shadow": {
		"job_name": "暗影武僧", "class_group": "laferida", "subclass_id": "shadow",
		"stat_tags": ["DEX", "WIS"], "alignment_tags": ["CHAOTIC", "NEUTRAL"],
		"deploy_cost": 9, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 5.5, "base_hp": 130, "base_atk": 22, "base_def": 4,
		"attack_speed": 1.45, "move_speed": 3.05, "stance_defense_bonus": 1.15, "stance_range_bonus": 1.0,
		"stance_is_rooted": false, "march_move_speed_bonus": 1.75, "march_attack_penalty": 0.85,
		"target_priority": "lowest_hp", "skill_ids": ["shadow_step_strike"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "残血切入"
	},
	"monk_four_elements": {
		"job_name": "四象武僧", "class_group": "laferida", "subclass_id": "four_elements",
		"stat_tags": ["DEX", "WIS"], "alignment_tags": ["LAWFUL", "GOOD"],
		"deploy_cost": 10, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 2.8, "search_range": 5.8, "base_hp": 125, "base_atk": 21, "base_def": 4,
		"attack_speed": 1.10, "move_speed": 2.55, "stance_defense_bonus": 1.20, "stance_range_bonus": 1.35,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.50, "march_attack_penalty": 0.75,
		"target_priority": "nearest", "skill_ids": ["elemental_palm"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "元素打断"
	},
	"paladin_devotion": {
		"job_name": "奉献侍卫", "class_group": "laferida", "subclass_id": "devotion",
		"stat_tags": ["STR", "CHA"], "alignment_tags": ["LAWFUL", "GOOD"],
		"deploy_cost": 12, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 4.3, "base_hp": 230, "base_atk": 20, "base_def": 14,
		"attack_speed": 0.85, "move_speed": 1.85, "stance_defense_bonus": 1.95, "stance_range_bonus": 1.0,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.20, "march_attack_penalty": 0.70,
		"target_priority": "nearest", "skill_ids": ["devotion_guard"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "光环护盾"
	},
	"paladin_vengeance": {
		"job_name": "复仇侍卫", "class_group": "laferida", "subclass_id": "vengeance",
		"stat_tags": ["STR", "CHA"], "alignment_tags": ["LAWFUL", "NEUTRAL"],
		"deploy_cost": 12, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.1, "search_range": 4.8, "base_hp": 205, "base_atk": 25, "base_def": 11,
		"attack_speed": 0.90, "move_speed": 1.95, "stance_defense_bonus": 1.65, "stance_range_bonus": 1.0,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.75,
		"target_priority": "highest_atk", "skill_ids": ["vengeance_smite"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "精英审判"
	},
	"paladin_ancients": {
		"job_name": "古贤侍卫", "class_group": "laferida", "subclass_id": "ancients",
		"stat_tags": ["STR", "WIS"], "alignment_tags": ["GOOD", "NEUTRAL"],
		"deploy_cost": 13, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 4.5, "base_hp": 220, "base_atk": 19, "base_def": 13,
		"attack_speed": 0.82, "move_speed": 1.85, "stance_defense_bonus": 1.85, "stance_range_bonus": 1.0,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.20, "march_attack_penalty": 0.70,
		"target_priority": "nearest", "skill_ids": ["ancient_prayer"], "shop_level": 4, "base_cost": 4,
		"tavern_passive": "自然祝祷"
	},
	"ranger_hunter": {
		"job_name": "猎人斥候", "class_group": "laferida", "subclass_id": "hunter",
		"stat_tags": ["DEX", "WIS"], "alignment_tags": ["NEUTRAL", "GOOD"],
		"deploy_cost": 10, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 4.2, "search_range": 6.2, "base_hp": 120, "base_atk": 23, "base_def": 4,
		"attack_speed": 0.88, "move_speed": 2.55, "stance_defense_bonus": 1.20, "stance_range_bonus": 1.70,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.50, "march_attack_penalty": 0.68,
		"target_priority": "lowest_hp", "skill_ids": ["aimed_shot"], "shop_level": 1, "base_cost": 2,
		"tavern_passive": "远程输出"
	},
	"ranger_beast_master": {
		"job_name": "兽王训导", "class_group": "laferida", "subclass_id": "beast_master",
		"stat_tags": ["DEX", "WIS"], "alignment_tags": ["NEUTRAL", "GOOD"],
		"deploy_cost": 11, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 4.0, "search_range": 6.0, "base_hp": 135, "base_atk": 20, "base_def": 5,
		"attack_speed": 0.95, "move_speed": 2.45, "stance_defense_bonus": 1.25, "stance_range_bonus": 1.60,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.45, "march_attack_penalty": 0.70,
		"target_priority": "nearest", "skill_ids": ["coordinated_assault"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "协同攻击"
	},
	"ranger_gloom_stalker": {
		"job_name": "幽域追踪者", "class_group": "laferida", "subclass_id": "gloom_stalker",
		"stat_tags": ["DEX", "WIS"], "alignment_tags": ["CHAOTIC", "NEUTRAL"],
		"deploy_cost": 12, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 4.5, "search_range": 6.8, "base_hp": 110, "base_atk": 27, "base_def": 3,
		"attack_speed": 0.82, "move_speed": 2.65, "stance_defense_bonus": 1.10, "stance_range_bonus": 1.80,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.55, "march_attack_penalty": 0.68,
		"target_priority": "lowest_hp", "skill_ids": ["darkwood_arrow"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "残血追击"
	},
	"rogue_thief": {
		"job_name": "快手盗贼", "class_group": "anmarit", "subclass_id": "thief",
		"stat_tags": ["DEX", "INT"], "alignment_tags": ["CHAOTIC", "NEUTRAL"],
		"deploy_cost": 7, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 4.5, "base_hp": 115, "base_atk": 22, "base_def": 3,
		"attack_speed": 1.55, "move_speed": 3.00, "stance_defense_bonus": 1.05, "stance_range_bonus": 1.0,
		"stance_is_rooted": false, "march_move_speed_bonus": 1.90, "march_attack_penalty": 0.90,
		"target_priority": "lowest_hp", "skill_ids": ["quick_stab"], "shop_level": 1, "base_cost": 3,
		"tavern_passive": "低费近战"
	},
	"rogue_assassin": {
		"job_name": "见习刺客", "class_group": "anmarit", "subclass_id": "assassin",
		"stat_tags": ["DEX", "STR"], "alignment_tags": ["CHAOTIC", "EVIL"],
		"deploy_cost": 9, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.0, "search_range": 5.0, "base_hp": 105, "base_atk": 28, "base_def": 2,
		"attack_speed": 1.30, "move_speed": 3.15, "stance_defense_bonus": 1.0, "stance_range_bonus": 1.0,
		"stance_is_rooted": false, "march_move_speed_bonus": 2.00, "march_attack_penalty": 0.90,
		"target_priority": "lowest_hp", "skill_ids": ["backstab"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "斩杀输出"
	},
	"rogue_arcane_trickster": {
		"job_name": "诡术学徒", "class_group": "anmarit", "subclass_id": "arcane_trickster",
		"stat_tags": ["DEX", "INT"], "alignment_tags": ["CHAOTIC", "NEUTRAL"],
		"deploy_cost": 10, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 3.0, "search_range": 5.8, "base_hp": 100, "base_atk": 24, "base_def": 3,
		"attack_speed": 1.10, "move_speed": 2.80, "stance_defense_bonus": 1.05, "stance_range_bonus": 1.45,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.65, "march_attack_penalty": 0.80,
		"target_priority": "random", "skill_ids": ["illusion_dagger"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "幻术骚扰"
	},
	"sorcerer_draconic": {
		"job_name": "龙裔术士", "class_group": "naka", "subclass_id": "draconic",
		"stat_tags": ["CHA", "CON"], "alignment_tags": ["NEUTRAL", "LAWFUL"],
		"deploy_cost": 13, "attack_mode": "magic_aoe", "target_type": "both", "range_shape": "fan",
		"attack_range": 3.0, "search_range": 5.8, "base_hp": 145, "base_atk": 29, "base_def": 6,
		"attack_speed": 0.52, "move_speed": 1.75, "stance_defense_bonus": 1.20, "stance_range_bonus": 1.55,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.20, "march_attack_penalty": 0.78,
		"target_priority": "nearest", "skill_ids": ["drake_spark"], "shop_level": 3, "base_cost": 4,
		"tavern_passive": "扇形法术"
	},
	"sorcerer_wild_magic": {
		"job_name": "狂野术士", "class_group": "naka", "subclass_id": "wild_magic",
		"stat_tags": ["CHA", "INT"], "alignment_tags": ["CHAOTIC", "NEUTRAL"],
		"deploy_cost": 12, "attack_mode": "magic_aoe", "target_type": "both", "range_shape": "circle",
		"attack_range": 3.5, "search_range": 6.5, "base_hp": 95, "base_atk": 32, "base_def": 2,
		"attack_speed": 0.48, "move_speed": 1.95, "stance_defense_bonus": 1.0, "stance_range_bonus": 1.80,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.82,
		"target_priority": "random", "skill_ids": ["unstable_bolt"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "随机爆发"
	},
	"sorcerer_storm": {
		"job_name": "风暴术士", "class_group": "naka", "subclass_id": "storm",
		"stat_tags": ["CHA", "DEX"], "alignment_tags": ["CHAOTIC", "GOOD"],
		"deploy_cost": 13, "attack_mode": "magic_aoe", "target_type": "both", "range_shape": "circle",
		"attack_range": 3.8, "search_range": 6.2, "base_hp": 105, "base_atk": 30, "base_def": 3,
		"attack_speed": 0.58, "move_speed": 2.20, "stance_defense_bonus": 1.05, "stance_range_bonus": 1.70,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.35, "march_attack_penalty": 0.78,
		"target_priority": "nearest", "skill_ids": ["arc_spell"], "shop_level": 4, "base_cost": 4,
		"tavern_passive": "连锁法术"
	},
	"warlock_blade": {
		"job_name": "魔刃契徒", "class_group": "anmarit", "subclass_id": "blade",
		"stat_tags": ["CHA", "CON"], "alignment_tags": ["EVIL", "NEUTRAL"],
		"deploy_cost": 10, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.1, "search_range": 4.5, "base_hp": 165, "base_atk": 23, "base_def": 7,
		"attack_speed": 0.95, "move_speed": 2.05, "stance_defense_bonus": 1.40, "stance_range_bonus": 1.05,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.30, "march_attack_penalty": 0.78,
		"target_priority": "nearest", "skill_ids": ["pact_blade_slash"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "吸血近战"
	},
	"warlock_tome": {
		"job_name": "魔典契徒", "class_group": "anmarit", "subclass_id": "tome",
		"stat_tags": ["CHA", "INT"], "alignment_tags": ["EVIL", "NEUTRAL"],
		"deploy_cost": 12, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 4.0, "search_range": 6.2, "base_hp": 100, "base_atk": 28, "base_def": 3,
		"attack_speed": 0.70, "move_speed": 1.85, "stance_defense_bonus": 1.05, "stance_range_bonus": 1.75,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.78,
		"target_priority": "highest_atk", "skill_ids": ["curse_rune"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "诅咒增伤"
	},
	"warlock_chain": {
		"job_name": "魔宠契徒", "class_group": "anmarit", "subclass_id": "chain",
		"stat_tags": ["CHA", "WIS"], "alignment_tags": ["EVIL", "NEUTRAL"],
		"deploy_cost": 11, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 3.8, "search_range": 6.0, "base_hp": 115, "base_atk": 24, "base_def": 4,
		"attack_speed": 0.82, "move_speed": 1.95, "stance_defense_bonus": 1.10, "stance_range_bonus": 1.60,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.75,
		"target_priority": "nearest", "skill_ids": ["familiar_assist"], "shop_level": 4, "base_cost": 4,
		"tavern_passive": "魔宠协击"
	},
	"wizard_evocation": {
		"job_name": "塑能法师", "class_group": "naka", "subclass_id": "evocation",
		"stat_tags": ["INT", "WIS"], "alignment_tags": ["CHAOTIC", "NEUTRAL"],
		"deploy_cost": 15, "attack_mode": "magic_aoe", "target_type": "both", "range_shape": "circle",
		"attack_range": 3.2, "search_range": 7.0, "base_hp": 82, "base_atk": 32, "base_def": 2,
		"attack_speed": 0.50, "move_speed": 1.50, "stance_defense_bonus": 1.0, "stance_range_bonus": 1.90,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.20, "march_attack_penalty": 0.80,
		"target_priority": "highest_atk", "skill_ids": ["flame_bolt"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "范围法术"
	},
	"wizard_abjuration": {
		"job_name": "防护法师", "class_group": "naka", "subclass_id": "abjuration",
		"stat_tags": ["INT", "CON"], "alignment_tags": ["LAWFUL", "GOOD"],
		"deploy_cost": 14, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 3.8, "search_range": 6.5, "base_hp": 105, "base_atk": 20, "base_def": 5,
		"attack_speed": 0.68, "move_speed": 1.55, "stance_defense_bonus": 1.15, "stance_range_bonus": 1.75,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.20, "march_attack_penalty": 0.75,
		"target_priority": "lowest_hp", "skill_ids": ["shield_spell"], "shop_level": 4, "base_cost": 4,
		"tavern_passive": "后排护盾"
	},
	"wizard_divination": {
		"job_name": "预言法师", "class_group": "naka", "subclass_id": "divination",
		"stat_tags": ["INT", "WIS"], "alignment_tags": ["LAWFUL", "NEUTRAL"],
		"deploy_cost": 13, "attack_mode": "ranged_single", "target_type": "both", "range_shape": "circle",
		"attack_range": 4.0, "search_range": 7.2, "base_hp": 90, "base_atk": 22, "base_def": 3,
		"attack_speed": 0.72, "move_speed": 1.65, "stance_defense_bonus": 1.05, "stance_range_bonus": 1.80,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.20, "march_attack_penalty": 0.75,
		"target_priority": "highest_atk", "skill_ids": ["portent"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "预兆辅助"
	},
	"artificer_alchemist": {
		"job_name": "炼金学徒", "class_group": "naka", "subclass_id": "alchemist",
		"stat_tags": ["INT", "CON"], "alignment_tags": ["NEUTRAL", "GOOD"],
		"deploy_cost": 11, "attack_mode": "heal", "target_type": "ground", "range_shape": "circle",
		"attack_range": 3.8, "search_range": 6.0, "base_hp": 120, "base_atk": 20, "base_def": 6,
		"attack_speed": 0.70, "move_speed": 1.75, "stance_defense_bonus": 1.25, "stance_range_bonus": 1.60,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.20, "march_attack_penalty": 0.70,
		"target_priority": "lowest_hp", "skill_ids": ["healing_elixir"], "shop_level": 2, "base_cost": 3,
		"tavern_passive": "炼金治疗"
	},
	"artificer_armorer": {
		"job_name": "铸甲学徒", "class_group": "naka", "subclass_id": "armorer",
		"stat_tags": ["INT", "CON"], "alignment_tags": ["LAWFUL", "NEUTRAL"],
		"deploy_cost": 12, "attack_mode": "melee_single", "target_type": "ground", "range_shape": "circle",
		"attack_range": 1.1, "search_range": 4.5, "base_hp": 195, "base_atk": 18, "base_def": 15,
		"attack_speed": 0.78, "move_speed": 1.70, "stance_defense_bonus": 2.05, "stance_range_bonus": 1.0,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.15, "march_attack_penalty": 0.70,
		"target_priority": "nearest", "skill_ids": ["armor_reinforce"], "shop_level": 3, "base_cost": 3,
		"tavern_passive": "装甲防护"
	},
	"artificer_artillerist": {
		"job_name": "炮术学徒", "class_group": "naka", "subclass_id": "artillerist",
		"stat_tags": ["INT", "DEX"], "alignment_tags": ["CHAOTIC", "NEUTRAL"],
		"deploy_cost": 13, "attack_mode": "magic_aoe", "target_type": "both", "range_shape": "area",
		"attack_range": 4.0, "search_range": 6.5, "base_hp": 105, "base_atk": 30, "base_def": 4,
		"attack_speed": 0.55, "move_speed": 1.80, "stance_defense_bonus": 1.05, "stance_range_bonus": 1.75,
		"stance_is_rooted": true, "march_move_speed_bonus": 1.25, "march_attack_penalty": 0.78,
		"target_priority": "nearest", "skill_ids": ["light_cannon"], "shop_level": 4, "base_cost": 4,
		"tavern_passive": "炮击范围"
	},
}


## 提供canonicalize职业id静态数据或工具逻辑。
static func canonicalize_class_id(class_id: String) -> String:
	if CHARACTER_DATA.has(class_id):
		return class_id
	return str(LEGACY_ALIASES.get(class_id, "fighter_champion"))


## 获取角色模板（带缓存）
static func get_template(class_id: String) -> ClassTemplate:
	"""获取角色模板（带缓存）"""
	var canonical_id := canonicalize_class_id(class_id)
	if _cache.has(canonical_id):
		return _cache[canonical_id]

	var data: Dictionary = CHARACTER_DATA.get(canonical_id, CHARACTER_DATA["fighter_champion"])
	var template := ClassTemplate.new()
	template.class_id = canonical_id
	template.job_name = str(data.get("job_name", canonical_id))
	template.class_group = str(data.get("class_group", "naka"))
	template.subclass_id = str(data.get("subclass_id", "champion"))
	template.stat_tags = _string_array(data.get("stat_tags", []))
	template.alignment_tags = _string_array(data.get("alignment_tags", []))
	template.deploy_cost = int(data.get("deploy_cost", 10))
	template.attack_mode = _attack_mode(str(data.get("attack_mode", "melee_single")))
	template.target_type = _target_type(str(data.get("target_type", "ground")))
	template.range_shape = _range_shape(str(data.get("range_shape", "circle")))
	template.attack_range = float(data.get("attack_range", 1.5))
	template.search_range = float(data.get("search_range", 5.0))
	template.base_hp = int(data.get("base_hp", 100))
	template.base_atk = int(data.get("base_atk", 15))
	template.base_def = int(data.get("base_def", 5))
	template.attack_speed = float(data.get("attack_speed", 1.0))
	template.move_speed = float(data.get("move_speed", 2.0))
	template.collision_radius = float(data.get("collision_radius", 12.0))
	template.stance_defense_bonus = float(data.get("stance_defense_bonus", 1.5))
	template.stance_range_bonus = float(data.get("stance_range_bonus", 1.5))
	template.stance_can_move = bool(data.get("stance_can_move", false))
	template.stance_is_rooted = bool(data.get("stance_is_rooted", true))
	template.march_move_speed_bonus = float(data.get("march_move_speed_bonus", 1.5))
	template.march_attack_penalty = float(data.get("march_attack_penalty", 0.5))
	template.target_priority = _target_priority(str(data.get("target_priority", "nearest")))
	template.skill_ids = _string_array(data.get("skill_ids", []))
	_cache[canonical_id] = template
	return template


## 获取酒馆招募数据。
static func get_tavern_data(class_id: String) -> Dictionary:
	var canonical_id := canonicalize_class_id(class_id)
	var data: Dictionary = CHARACTER_DATA.get(canonical_id, CHARACTER_DATA["fighter_champion"])
	return {
		"shop_level": int(data.get("shop_level", 1)),
		"base_cost": int(data.get("base_cost", 2)),
		"passive": str(data.get("tavern_passive", "")),
	}


## 获取全部职业ids。
static func get_all_class_ids() -> Array[String]:
	return CHARACTER_IDS.duplicate()


## 随机获取count个不重复的角色模板
static func get_random_classes(count: int, exclude: Array = []) -> Array:
	"""随机获取count个不重复的角色模板"""
	var pool: Array[String] = []
	for id in get_all_class_ids():
		if id not in exclude:
			pool.append(id)
	pool.shuffle()
	var result: Array = []
	for i in range(min(count, pool.size())):
		result.append(get_template(pool[i]))
	return result


## 获取职业分组标签。
static func get_class_group_label(class_group: String) -> String:
	match class_group:
		"anmarit":
			return "安马里特"
		"laferida":
			return "拉费里达"
		"naka":
			return "纳卡"
	return class_group


## 获取模板color。
static func get_template_color(class_id: String) -> Color:
	var ct := get_template(class_id)
	match ct.class_group:
		"anmarit":
			return Color(0.42, 0.56, 0.28, 1.0)
		"laferida":
			return Color(0.26, 0.66, 0.42, 1.0)
		"naka":
			return Color(0.84, 0.32, 0.18, 1.0)
	return Color(0.48, 0.52, 0.58, 1.0)


## 提供stringarray静态数据或工具逻辑。
static func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


## 提供攻击mode静态数据或工具逻辑。
static func _attack_mode(value: String) -> int:
	match value:
		"ranged_single":
			return ClassTemplate.AttackMode.RANGED_SINGLE
		"magic_aoe":
			return ClassTemplate.AttackMode.MAGIC_AOE
		"heal":
			return ClassTemplate.AttackMode.HEAL
		"piercing_line":
			return ClassTemplate.AttackMode.PIERCING_LINE
		_:
			return ClassTemplate.AttackMode.MELEE_SINGLE


## 提供目标type静态数据或工具逻辑。
static func _target_type(value: String) -> int:
	match value:
		"air":
			return ClassTemplate.TargetType.AIR
		"both":
			return ClassTemplate.TargetType.BOTH
		_:
			return ClassTemplate.TargetType.GROUND


## 提供范围形状静态数据或工具逻辑。
static func _range_shape(value: String) -> int:
	match value:
		"fan":
			return ClassTemplate.RangeShape.FAN
		"line":
			return ClassTemplate.RangeShape.LINE
		"global":
			return ClassTemplate.RangeShape.GLOBAL
		"area":
			return ClassTemplate.RangeShape.AREA
		_:
			return ClassTemplate.RangeShape.CIRCLE


## 提供目标priority静态数据或工具逻辑。
static func _target_priority(value: String) -> int:
	match value:
		"lowest_hp":
			return ClassTemplate.TargetPriority.LOWEST_HP
		"highest_atk":
			return ClassTemplate.TargetPriority.HIGHEST_ATK
		"farthest":
			return ClassTemplate.TargetPriority.FARTHEST
		"random":
			return ClassTemplate.TargetPriority.RANDOM
		_:
			return ClassTemplate.TargetPriority.NEAREST
