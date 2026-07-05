# skill_data.gd - Skill records loaded from DataRegistry.
class_name SkillData
extends RefCounted

var skill_id: String = ""
var skill_name: String = ""
var description: String = ""
var cooldown: float = 0.0
var dp_cost: int = 0
var damage_multiplier: float = 1.0
var aoe_radius: float = 0.0
var heal_amount: float = 0.0
var buff_defense: float = 0.0
var duration: float = 0.0
var cast_type: String = "instant"
var target_rule: String = "current_target"
var icon: String = ""
var tags: Array[String] = []
var effects: Array[Dictionary] = []

static var _skill_registry: Dictionary = {}
static var _initialized: bool = false


static func reload_registry() -> void:
	_skill_registry.clear()
	_initialized = false
	_init_registry()


static func get_skill(skill_id: String) -> SkillData:
	_init_registry()
	if _skill_registry.has(skill_id):
		return _skill_registry[skill_id]
	push_warning("Unknown skill_id: %s" % skill_id)
	return null


static func get_all_skill_ids() -> Array[String]:
	_init_registry()
	var ids: Array[String] = []
	for id in _skill_registry.keys():
		ids.append(str(id))
	ids.sort()
	return ids


static func _init_registry() -> void:
	if _initialized:
		return
	_initialized = true

	var registry := _registry()
	if registry and registry.has_method("get_all_skill_ids") and registry.has_method("get_skill"):
		for id in registry.get_all_skill_ids():
			var data: Dictionary = registry.get_skill(str(id))
			if not data.is_empty():
				_skill_registry[str(id)] = _from_dictionary(data)

	if _skill_registry.is_empty():
		var fallback := {
			"skill_id": "basic_strike",
			"name": "基础攻击",
			"description": "造成100%攻击力伤害",
			"cooldown": 1.0,
			"dp_cost": 0,
			"damage_multiplier": 1.0,
			"aoe_radius": 0.0,
			"heal_amount": 0.0,
			"buff_defense": 0.0,
			"duration": 0.0,
		}
		_skill_registry["basic_strike"] = _from_dictionary(fallback)


static func _from_dictionary(data: Dictionary) -> SkillData:
	var skill := SkillData.new()
	skill.skill_id = str(data.get("skill_id", ""))
	skill.skill_name = str(data.get("skill_name", data.get("name", skill.skill_id)))
	skill.description = str(data.get("description", ""))
	skill.cooldown = float(data.get("cooldown", 0.0))
	skill.dp_cost = int(data.get("dp_cost", 0))
	skill.damage_multiplier = float(data.get("damage_multiplier", 0.0))
	skill.aoe_radius = float(data.get("aoe_radius", 0.0))
	skill.heal_amount = float(data.get("heal_amount", 0.0))
	skill.buff_defense = float(data.get("buff_defense", 0.0))
	skill.duration = float(data.get("duration", 0.0))
	skill.cast_type = str(data.get("cast_type", "instant"))
	skill.target_rule = str(data.get("target_rule", "current_target"))
	skill.icon = str(data.get("icon", ""))
	skill.tags = _string_array(data.get("tags", []))
	skill.effects = _dictionary_array(data.get("effects", []))
	return skill


static func _registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("DataRegistry")


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


static func _dictionary_array(value) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				result.append(item.duplicate(true))
	return result
