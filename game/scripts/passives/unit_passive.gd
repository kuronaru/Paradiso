class_name UnitPassive
extends RefCounted

var passive_id: String = ""
var display_name: String = ""
var unit: UnitBase = null
var hero: UnitBase = null
var modifiers: Dictionary = {}


func setup(p_unit: UnitBase, config: Dictionary = {}) -> void:
	unit = p_unit
	hero = p_unit
	passive_id = str(config.get("passive_id", ""))
	display_name = str(config.get("display_name", passive_id))
	var raw_modifiers = config.get("modifiers", {})
	modifiers = raw_modifiers.duplicate(true) if raw_modifiers is Dictionary else {}


func is_active() -> bool:
	return is_instance_valid(unit) and unit.is_alive


func get_modifiers() -> Dictionary:
	return modifiers.duplicate(true)


func on_tick(_context: Dictionary) -> void:
	pass


func before_deal_damage(_context: Dictionary) -> void:
	pass


func after_deal_damage(_context: Dictionary) -> void:
	pass


func before_receive_attack(_context: Dictionary) -> void:
	pass


func before_apply_attack_damage(_context: Dictionary) -> void:
	pass


func after_receive_attack(_context: Dictionary) -> void:
	pass


func after_basic_attack(_context: Dictionary) -> void:
	pass


func before_death(_context: Dictionary) -> void:
	pass


func after_skill_used(_context: Dictionary) -> void:
	pass
