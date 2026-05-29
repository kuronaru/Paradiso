# class_definitions.gd — 预定义职业模板工厂
# 用DND+明日方舟世界观，硬编码五种职业模板
class_name ClassDefinitions
extends RefCounted

static var _cache: Dictionary = {}


static func get_template(class_id: String) -> ClassTemplate:
	"""获取职业模板（带缓存）"""
	if _cache.has(class_id):
		return _cache[class_id]

	var template := ClassTemplate.new()

	match class_id:
		"warrior":
			template.class_id = "warrior"
			template.job_name = "战士"
			template.deploy_cost = 8
			template.attack_mode = ClassTemplate.AttackMode.MELEE_SINGLE
			template.target_type = ClassTemplate.TargetType.GROUND
			template.range_shape = ClassTemplate.RangeShape.CIRCLE
			template.attack_range = 1.0
			template.search_range = 4.0
			template.base_hp = 200
			template.base_atk = 18
			template.base_def = 12
			template.attack_speed = 1.2
			template.move_speed = 2.0
			template.stance_defense_bonus = 2.0
			template.stance_range_bonus = 1.0
			template.stance_is_rooted = true
			template.march_move_speed_bonus = 1.3
			template.march_attack_penalty = 0.7
			template.target_priority = ClassTemplate.TargetPriority.NEAREST
			template.skill_ids = ["shield_wall", "taunt"]

		"ranger":
			template.class_id = "ranger"
			template.job_name = "游侠"
			template.deploy_cost = 10
			template.attack_mode = ClassTemplate.AttackMode.RANGED_SINGLE
			template.target_type = ClassTemplate.TargetType.BOTH
			template.range_shape = ClassTemplate.RangeShape.CIRCLE
			template.attack_range = 4.0
			template.search_range = 6.0
			template.base_hp = 120
			template.base_atk = 22
			template.base_def = 4
			template.attack_speed = 0.8
			template.move_speed = 2.5
			template.stance_defense_bonus = 1.2
			template.stance_range_bonus = 2.0
			template.stance_is_rooted = true
			template.march_move_speed_bonus = 1.5
			template.march_attack_penalty = 0.6
			template.target_priority = ClassTemplate.TargetPriority.LOWEST_HP
			template.skill_ids = ["barrage", "snipe"]

		"mage":
			template.class_id = "mage"
			template.job_name = "法师"
			template.deploy_cost = 15
			template.attack_mode = ClassTemplate.AttackMode.MAGIC_AOE
			template.target_type = ClassTemplate.TargetType.BOTH
			template.range_shape = ClassTemplate.RangeShape.CIRCLE
			template.attack_range = 3.0
			template.search_range = 7.0
			template.base_hp = 80
			template.base_atk = 30
			template.base_def = 2
			template.attack_speed = 0.5
			template.move_speed = 1.5
			template.stance_defense_bonus = 1.0
			template.stance_range_bonus = 2.0
			template.stance_is_rooted = true
			template.march_move_speed_bonus = 1.2
			template.march_attack_penalty = 0.8
			template.target_priority = ClassTemplate.TargetPriority.HIGHEST_ATK
			template.skill_ids = ["fireball", "arcane_nova"]

		"priest":
			template.class_id = "priest"
			template.job_name = "牧师"
			template.deploy_cost = 10
			template.attack_mode = ClassTemplate.AttackMode.HEAL
			template.target_type = ClassTemplate.TargetType.GROUND
			template.range_shape = ClassTemplate.RangeShape.CIRCLE
			template.attack_range = 4.0
			template.search_range = 6.0
			template.base_hp = 100
			template.base_atk = 20    # 治疗量基数
			template.base_def = 5
			template.attack_speed = 0.7
			template.move_speed = 1.8
			template.stance_defense_bonus = 1.3
			template.stance_range_bonus = 1.8
			template.stance_is_rooted = true
			template.march_move_speed_bonus = 1.3
			template.march_attack_penalty = 0.6
			template.target_priority = ClassTemplate.TargetPriority.LOWEST_HP
			template.skill_ids = ["heal_wave", "blessing"]

		"rogue":
			template.class_id = "rogue"
			template.job_name = "盗贼"
			template.deploy_cost = 7
			template.attack_mode = ClassTemplate.AttackMode.MELEE_SINGLE
			template.target_type = ClassTemplate.TargetType.GROUND
			template.range_shape = ClassTemplate.RangeShape.CIRCLE
			template.attack_range = 1.0
			template.search_range = 4.0
			template.base_hp = 110
			template.base_atk = 25
			template.base_def = 3
			template.attack_speed = 1.5
			template.move_speed = 3.0
			template.stance_defense_bonus = 1.0
			template.stance_range_bonus = 1.0
			template.stance_is_rooted = false
			template.march_move_speed_bonus = 2.0
			template.march_attack_penalty = 0.9
			template.target_priority = ClassTemplate.TargetPriority.LOWEST_HP
			template.skill_ids = ["shadow_strike", "poison_blade"]

		_:
			push_warning("Unknown class_id: %s, returning warrior default" % class_id)
			return get_template("warrior")

	_cache[class_id] = template
	return template


static func get_all_class_ids() -> Array[String]:
	return ["warrior", "ranger", "mage", "priest", "rogue"]


static func get_random_classes(count: int, exclude: Array = []) -> Array:
	"""随机获取count个不重复的职业模板"""
	var pool: Array[String] = []
	for id in get_all_class_ids():
		if id not in exclude:
			pool.append(id)
	pool.shuffle()
	var result: Array = []
	for i in range(min(count, pool.size())):
		result.append(get_template(pool[i]))
	return result
