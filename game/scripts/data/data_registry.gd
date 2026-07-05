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


func get_enemy_pool() -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for enemy_id in _sorted_keys(_enemies):
		result.append(_enemies[enemy_id].duplicate(true))
	return result


func get_enemy_scaling(scaling_id: String) -> Dictionary:
	return _get_record(_enemy_scaling, scaling_id, "enemy scaling")


func get_status_effect(status_id: String) -> Dictionary:
	return _get_record(_status_effects, status_id, "status effect")


func get_synergy(synergy_id: String) -> Dictionary:
	return _get_record(_synergies, synergy_id, "synergy")


func get_all_synergy_ids() -> Array[String]:
	return _sorted_keys(_synergies)


func get_wave(wave_id: String) -> Dictionary:
	return _get_record(_waves, wave_id, "wave")


func get_waves_for_battle(battle_id: String) -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for wave_id in _sorted_keys(_waves):
		var wave: Dictionary = _waves[wave_id]
		if str(wave.get("battle_id", "")) == battle_id:
			result.append(wave.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("wave_index", 0)) < int(b.get("wave_index", 0))
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
