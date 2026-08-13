# class_definitions.gd - Class template factory backed by DataRegistry.
class_name ClassDefinitions
extends RefCounted

static var _cache: Dictionary = {}

const FALLBACK_CLASS_ID := "fighter_champion"
const LEGACY_ALIASES := {
	"warrior": "fighter_champion",
	"ranger": "ranger_hunter",
	"mage": "wizard_evocation",
	"priest": "cleric_life_domain",
	"rogue": "rogue_thief",
}

const CLASS_GROUP_ORDER: Array[String] = [
	"anmarit",
	"laferida",
	"naka",
	"remolino_law",
	"moon_cult",
	"kroen_trench",
	"tro_poem",
]


static func clear_cache() -> void:
	_cache.clear()


static func canonicalize_class_id(class_id: String) -> String:
	var trimmed := class_id.strip_edges()
	if trimmed == "":
		return FALLBACK_CLASS_ID
	if _has_raw_class_id(trimmed):
		return trimmed
	var alias := str(LEGACY_ALIASES.get(trimmed, FALLBACK_CLASS_ID))
	return alias if _has_raw_class_id(alias) else FALLBACK_CLASS_ID


static func has_class_id(class_id: String) -> bool:
	var trimmed := class_id.strip_edges()
	return _has_raw_class_id(trimmed) or LEGACY_ALIASES.has(trimmed)


static func get_template(class_id: String) -> ClassTemplate:
	var canonical_id := canonicalize_class_id(class_id)
	if _cache.has(canonical_id):
		return _cache[canonical_id]

	var data := _get_class_data(canonical_id)
	if data.is_empty():
		data = _fallback_class_data(canonical_id)

	var template := ClassTemplate.new()
	template.class_id = canonical_id
	template.job_name = str(data.get("job_name", data.get("name", canonical_id)))
	template.class_group = str(data.get("class_group", "naka"))
	template.subclass_id = str(data.get("subclass_id", "champion"))
	template.visual_id = str(data.get("visual_id", "sample_visual"))
	template.stat_tags = _string_array(data.get("stat_tags", []))
	template.alignment_tags = _string_array(data.get("alignment_tags", []))
	template.trait_tags = _string_array(data.get("trait_tags", []))
	var auto_data := _get_autochess_hero_data(canonical_id)
	template.trait_tier = clampi(int(auto_data.get("trait_tier", data.get("shop_level", 1))), 1, 6)
	template.autochess_synergy_ids = _string_array(auto_data.get("autochess_synergy_ids", []))
	template.auto_trait_ids = _string_array(auto_data.get("trait_ids", []))
	template.deploy_cost = int(data.get("deploy_cost", 10))
	template.attack_mode = _attack_mode(str(data.get("attack_mode", "melee_single")))
	template.target_type = _target_type(str(data.get("target_type", "ground")))
	template.range_shape = _range_shape(str(data.get("range_shape", "circle")))
	template.attack_range = float(data.get("attack_range", 1.5))
	template.search_range = float(data.get("search_range", 5.0))
	template.base_hp = int(data.get("base_hp", data.get("hp", 100)))
	template.base_atk = int(data.get("base_atk", data.get("atk", 15)))
	template.base_def = int(data.get("base_def", data.get("def", 5)))
	template.attack_speed = float(data.get("attack_speed", 1.0))
	template.move_speed = float(data.get("move_speed", 2.0))
	template.collision_radius = float(data.get("collision_radius", 12.0))
	template.stance_defense_bonus = float(data.get("stance_defense_bonus", 1.5))
	template.stance_range_bonus = float(data.get("stance_range_bonus", 1.5))
	template.stance_can_move = _bool_value(data.get("stance_can_move", false), false)
	template.stance_is_rooted = _bool_value(data.get("stance_is_rooted", true), true)
	template.march_move_speed_bonus = float(data.get("march_move_speed_bonus", 1.5))
	template.march_attack_penalty = float(data.get("march_attack_penalty", 0.5))
	template.target_priority = _target_priority(str(data.get("target_priority", "nearest")))
	template.skill_ids = _string_array(data.get("skill_ids", []))
	_cache[canonical_id] = template
	return template


static func get_tavern_data(class_id: String) -> Dictionary:
	var canonical_id := canonicalize_class_id(class_id)
	var data := _get_class_data(canonical_id)
	if data.is_empty():
		data = _fallback_class_data(canonical_id)
	var hero_tier := clampi(int(_get_autochess_hero_data(canonical_id).get("trait_tier", data.get("shop_level", 1))), 1, 6)
	return {
		"shop_level": hero_tier,
		"base_cost": int(data.get("base_cost", 2)),
		"passive": str(data.get("tavern_passive", "")),
	}


static func get_autochess_data(class_id: String) -> Dictionary:
	return _get_autochess_hero_data(canonicalize_class_id(class_id))


static func get_all_class_ids() -> Array[String]:
	var registry := _registry()
	if registry and registry.has_method("get_all_class_ids"):
		var ids: Array[String] = registry.get_all_class_ids()
		if not ids.is_empty():
			return ids
	return [FALLBACK_CLASS_ID]


static func get_random_classes(count: int, exclude: Array = []) -> Array:
	var pool: Array[String] = []
	for id in get_all_class_ids():
		if id not in exclude:
			pool.append(id)
	pool.shuffle()
	var result: Array = []
	for i in range(min(count, pool.size())):
		result.append(get_template(pool[i]))
	return result


static func get_class_group_label(class_group: String) -> String:
	match class_group:
		"anmarit":
			return "瘴林威胁"
		"laferida":
			return "扭曲生命"
		"naka":
			return "龙焰吐息"
		"remolino_law":
			return "骑士律法"
		"moon_cult":
			return "窥探禁忌"
		"kroen_trench":
			return "不灭战壕"
		"tro_poem":
			return "十一长诗"
	return class_group


static func get_template_color(class_id: String) -> Color:
	var ct := get_template(class_id)
	match ct.class_group:
		"anmarit":
			return Color(0.42, 0.56, 0.28, 1.0)
		"laferida":
			return Color(0.26, 0.66, 0.42, 1.0)
		"naka":
			return Color(0.84, 0.32, 0.18, 1.0)
		"remolino_law":
			return Color(0.72, 0.72, 0.82, 1.0)
		"moon_cult":
			return Color(0.56, 0.34, 0.76, 1.0)
		"kroen_trench":
			return Color(0.62, 0.54, 0.38, 1.0)
		"tro_poem":
			return Color(0.32, 0.58, 0.86, 1.0)
	return Color(0.48, 0.52, 0.58, 1.0)


static func _registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("DataRegistry")


static func _has_raw_class_id(class_id: String) -> bool:
	var registry := _registry()
	return bool(registry and registry.has_method("has_class_data") and registry.has_class_data(class_id))


static func _get_class_data(class_id: String) -> Dictionary:
	var registry := _registry()
	if registry and registry.has_method("get_class_data"):
		return registry.get_class_data(class_id)
	return {}


static func _get_autochess_hero_data(class_id: String) -> Dictionary:
	var registry := _registry()
	if registry and registry.has_method("get_autochess_hero"):
		return registry.get_autochess_hero(class_id)
	return {}


static func _fallback_class_data(class_id: String) -> Dictionary:
	return {
		"class_id": class_id,
		"job_name": class_id,
		"class_group": "remolino_law",
		"subclass_id": "champion",
		"stat_tags": ["STR", "CON"],
		"alignment_tags": ["NEUTRAL"],
		"deploy_cost": 10,
		"attack_mode": "melee_single",
		"target_type": "ground",
		"range_shape": "circle",
		"attack_range": 1.5,
		"search_range": 5.0,
		"base_hp": 100,
		"base_atk": 15,
		"base_def": 5,
		"attack_speed": 1.0,
		"move_speed": 2.0,
		"skill_ids": [],
	}


static func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	elif value is PackedStringArray:
		for item in value:
			result.append(str(item))
	elif str(value).strip_edges() != "":
		for item in str(value).split(",", false):
			result.append(item.strip_edges())
	return result


static func _bool_value(value, default_value: bool) -> bool:
	if value is bool:
		return value
	var text := str(value).strip_edges().to_lower()
	if text in ["true", "1", "yes", "y"]:
		return true
	if text in ["false", "0", "no", "n"]:
		return false
	return default_value


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


static func _target_type(value: String) -> int:
	match value:
		"air":
			return ClassTemplate.TargetType.AIR
		"both":
			return ClassTemplate.TargetType.BOTH
		_:
			return ClassTemplate.TargetType.GROUND


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
