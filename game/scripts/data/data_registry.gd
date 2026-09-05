# data_registry.gd - Runtime access to exported balance data.
extends Node

const DATA_PATHS := {
	"config": "res://data/config.json",
	"classes": "res://data/classes.json",
	"skills": "res://data/skills.json",
	"status_effects": "res://data/status_effects.json",
	"enemies": "res://data/enemies.json",
	"enemy_scaling": "res://data/enemy_scaling.json",
	"synergies": "res://data/synergies.json",
	"minor_synergies": "res://data/minor_synergies.json",
	"synergy_availability": "res://data/synergy_availability.json",
	"auto_trait_templates": "res://data/auto_trait_templates.json",
	"auto_traits": "res://data/auto_traits.json",
	"autochess_heroes": "res://data/autochess_heroes.json",
	"autochess_equipment": "res://data/autochess_equipment.json",
	"waves": "res://data/waves.json",
}

var _loaded := false
var _config: Dictionary = {}
var _classes: Dictionary = {}
var _skills: Dictionary = {}
var _status_effects: Dictionary = {}
var _enemies: Dictionary = {}
var _enemy_scaling: Dictionary = {}
var _synergies: Dictionary = {}
var _synergy_availability: Dictionary = {}
var _auto_trait_templates: Dictionary = {}
var _auto_traits: Dictionary = {}
var _autochess_heroes: Dictionary = {}
var _autochess_equipment: Dictionary = {}
var _waves: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	_config = _load_dictionary(DATA_PATHS["config"])
	_classes = _load_table(DATA_PATHS["classes"], "class_id")
	_skills = _load_table(DATA_PATHS["skills"], "skill_id")
	_status_effects = _load_table(DATA_PATHS["status_effects"], "status_id")
	_enemies = _load_table(DATA_PATHS["enemies"], "enemy_id")
	_enemy_scaling = _load_table(DATA_PATHS["enemy_scaling"], "scaling_id")
	_synergies = _load_table(DATA_PATHS["synergies"], "synergy_id")
	var minor_synergies := _load_table(DATA_PATHS["minor_synergies"], "synergy_id")
	for synergy_id in minor_synergies.keys():
		_synergies[synergy_id] = minor_synergies[synergy_id]
	_synergy_availability = _load_dictionary(DATA_PATHS["synergy_availability"])
	_auto_trait_templates = _load_table(DATA_PATHS["auto_trait_templates"], "template_id")
	_auto_traits = _load_table(DATA_PATHS["auto_traits"], "trait_id")
	_autochess_heroes = _load_table(DATA_PATHS["autochess_heroes"], "hero_id")
	_autochess_equipment = _load_table(DATA_PATHS["autochess_equipment"], "equipment_id")
	_waves = _load_table(DATA_PATHS["waves"], "wave_id")
	_loaded = true


func reload() -> void:
	_loaded = false
	load_all()


func ensure_loaded() -> void:
	if not _loaded:
		load_all()


func get_config(key: String, default_value = null):
	ensure_loaded()
	return _config.get(key, default_value)


func get_config_section(key: String) -> Dictionary:
	ensure_loaded()
	var value = _config.get(key, {})
	return value.duplicate(true) if value is Dictionary else {}


func has_class_data(class_id: String) -> bool:
	ensure_loaded()
	return _classes.has(class_id)


func get_class_data(class_id: String) -> Dictionary:
	return _get_record(_classes, class_id, "class")


func get_all_class_ids() -> Array[String]:
	return _sorted_keys(_classes)


func get_all_classes() -> Dictionary:
	ensure_loaded()
	return _classes.duplicate(true)


func get_skill(skill_id: String) -> Dictionary:
	return _get_record(_skills, skill_id, "skill")


func get_all_skill_ids() -> Array[String]:
	return _sorted_keys(_skills)


func get_enemy(enemy_id: String) -> Dictionary:
	return _get_record(_enemies, enemy_id, "enemy")


func get_enemy_pool(include_hidden: bool = false) -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for enemy_id in _sorted_keys(_enemies):
		var enemy: Dictionary = _enemies[enemy_id]
		if not include_hidden and bool(enemy.get("hidden", false)):
			continue
		result.append(enemy.duplicate(true))
	return result


func get_enemy_scaling(scaling_id: String) -> Dictionary:
	return _get_record(_enemy_scaling, scaling_id, "enemy scaling")


func get_status_effect(status_id: String) -> Dictionary:
	return _get_record(_status_effects, status_id, "status effect")


func get_synergy(synergy_id: String) -> Dictionary:
	return _get_record(_synergies, synergy_id, "synergy")


func get_all_synergy_ids() -> Array[String]:
	return _sorted_keys(_synergies)


func get_enabled_synergy_ids() -> Array[String]:
	ensure_loaded()
	var configured = _synergy_availability.get("enabled", [])
	if not (configured is Array) or configured.is_empty():
		return get_all_synergy_ids()
	var result: Array[String] = []
	for value in configured:
		var synergy_id := str(value)
		if _synergies.has(synergy_id):
			result.append(synergy_id)
	return result


func get_disabled_synergy_ids() -> Array[String]:
	ensure_loaded()
	var result: Array[String] = []
	var configured = _synergy_availability.get("disabled", [])
	if configured is Array:
		for value in configured:
			var synergy_id := str(value)
			if _synergies.has(synergy_id):
				result.append(synergy_id)
	return result


func is_synergy_enabled(synergy_id: String) -> bool:
	return synergy_id in get_enabled_synergy_ids()


func is_synergy_stackable(synergy_id: String) -> bool:
	var data := get_synergy(synergy_id)
	return not data.is_empty() and bool(data.get("stackable", true))


func get_auto_trait_template(template_id: String) -> Dictionary:
	return _get_record(_auto_trait_templates, template_id, "auto trait template")


func get_all_auto_trait_template_ids() -> Array[String]:
	return _sorted_keys(_auto_trait_templates)


func get_auto_trait(trait_id: String) -> Dictionary:
	return _get_record(_auto_traits, trait_id, "auto trait")


func get_all_auto_trait_ids() -> Array[String]:
	return _sorted_keys(_auto_traits)


func get_autochess_hero(hero_id: String) -> Dictionary:
	return _get_record(_autochess_heroes, hero_id, "autochess hero")


func get_all_autochess_hero_ids() -> Array[String]:
	return _sorted_keys(_autochess_heroes)


func get_autochess_equipment(equipment_id: String) -> Dictionary:
	return _get_record(_autochess_equipment, equipment_id, "autochess equipment")


func get_all_autochess_equipment_ids() -> Array[String]:
	return _sorted_keys(_autochess_equipment)


func get_wave(wave_id: String) -> Dictionary:
	return _get_record(_waves, wave_id, "wave")


func get_all_wave_ids() -> Array[String]:
	return _sorted_keys(_waves)


func get_waves_for_battle(battle_id: String) -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for wave_id in _sorted_keys(_waves):
		var wave: Dictionary = _waves[wave_id]
		if str(wave.get("battle_id", "")) == battle_id:
			result.append(wave.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_wave := int(a.get("wave_index", 0))
		var b_wave := int(b.get("wave_index", 0))
		if a_wave != b_wave:
			return a_wave < b_wave
		return int(a.get("order", 0)) < int(b.get("order", 0))
	)
	return result


func _get_record(source: Dictionary, id: String, label: String) -> Dictionary:
	ensure_loaded()
	if source.has(id):
		return source[id].duplicate(true)
	push_warning("DataRegistry missing %s id: %s" % [label, id])
	return {}


func _load_dictionary(path: String) -> Dictionary:
	var parsed = _load_json(path)
	if parsed is Dictionary:
		return parsed
	push_warning("DataRegistry expected Dictionary: %s" % path)
	return {}


func _load_table(path: String, id_field: String) -> Dictionary:
	var parsed = _load_json(path)
	var result: Dictionary = {}
	if parsed is Dictionary:
		for key in parsed.keys():
			var row = parsed[key]
			if row is Dictionary:
				_add_enabled_row(result, str(key), row, id_field)
	elif parsed is Array:
		for row in parsed:
			if row is Dictionary:
				_add_enabled_row(result, str(row.get(id_field, "")), row, id_field)
	else:
		push_warning("DataRegistry expected table data: %s" % path)
	return result


func _add_enabled_row(target: Dictionary, key: String, row: Dictionary, id_field: String) -> void:
	if not bool(row.get("enabled", true)):
		return
	var record := row.duplicate(true)
	var id := str(record.get(id_field, key))
	if id == "":
		push_warning("DataRegistry skipped row without %s" % id_field)
		return
	record[id_field] = id
	target[id] = record


func _load_json(path: String):
	if not FileAccess.file_exists(path):
		push_warning("DataRegistry file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("DataRegistry cannot open: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_warning("DataRegistry cannot parse JSON: %s" % path)
		return {}
	return parsed


func _sorted_keys(source: Dictionary) -> Array[String]:
	ensure_loaded()
	var result: Array[String] = []
	for key in source.keys():
		result.append(str(key))
	result.sort()
	return result
