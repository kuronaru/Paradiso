# art_registry.gd - Runtime access to visual assets with a small cache.
extends Node

const VISUALS_PATH := "res://data/unit_visuals.json"

var _loaded := false
var _visuals: Dictionary = {}
var _resource_cache: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	_visuals = _load_dictionary(VISUALS_PATH)
	_loaded = true


func reload() -> void:
	_loaded = false
	_resource_cache.clear()
	load_all()


func ensure_loaded() -> void:
	if not _loaded:
		load_all()


func get_unit_visual(visual_id: String) -> Dictionary:
	ensure_loaded()
	if _visuals.has(visual_id):
		return _visuals[visual_id].duplicate(true)
	push_warning("ArtRegistry missing visual id: %s" % visual_id)
	return {}


func get_unit_visual_config(visual_id: String) -> UnitVisualConfig:
	var visual := get_unit_visual(visual_id)
	var config_path := str(visual.get("visual_config", visual.get("config", "")))
	if config_path == "":
		push_warning("ArtRegistry visual id has no config path: %s" % visual_id)
		return null
	return get_resource(config_path) as UnitVisualConfig


func get_resource(path: String) -> Resource:
	ensure_loaded()
	if path == "":
		return null
	if _resource_cache.has(path):
		return _resource_cache[path]
	if not ResourceLoader.exists(path):
		push_warning("ArtRegistry missing resource: %s" % path)
		return null
	var resource := load(path)
	if resource:
		_resource_cache[path] = resource
	return resource


func get_texture(path: String) -> Texture2D:
	return get_resource(path) as Texture2D


func get_sprite_frames(path: String) -> SpriteFrames:
	return get_resource(path) as SpriteFrames


func _load_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ArtRegistry file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("ArtRegistry cannot open: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_warning("ArtRegistry expected Dictionary: %s" % path)
	return {}
