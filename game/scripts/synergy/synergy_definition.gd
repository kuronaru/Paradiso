# synergy_definition.gd — 羁绊数据定义
class_name SynergyDefinition
extends RefCounted

enum SynergyType {
	MAIN_NATION,
	MINOR_STAT,
	MINOR_ALIGNMENT,
	MINOR_TRAIT,
}

var synergy_id: String = ""
var display_name: String = ""
var short_name: String = ""
var type: SynergyType = SynergyType.MAIN_NATION
var tag: String = ""
var thresholds: Array[int] = []
var order: int = 0
var description: String = ""
var scalable_modifiers: Array[Dictionary] = []
var fixed_modifiers: Array[Dictionary] = []
var mechanic_id: String = ""
var main_effect: Dictionary = {}
var modifier_scope: String = "global"
var count_scope: String = "deployed"


## 初始化实例数据。
func _init(
		p_id: String = "",
		p_name: String = "",
		p_short: String = "",
		p_type: SynergyType = SynergyType.MAIN_NATION,
		p_tag: String = "",
		p_thresholds: Array[int] = [],
		p_order: int = 0,
		p_description: String = "",
		p_scalable: Array[Dictionary] = [],
		p_fixed: Array[Dictionary] = [],
		p_mechanic_id: String = "",
		p_main_effect: Dictionary = {},
		p_modifier_scope: String = "global",
		p_count_scope: String = "deployed") -> void:
	synergy_id = p_id
	display_name = p_name
	short_name = p_short
	type = p_type
	tag = p_tag
	thresholds = p_thresholds.duplicate()
	order = p_order
	description = p_description
	scalable_modifiers = p_scalable.duplicate(true)
	fixed_modifiers = p_fixed.duplicate(true)
	mechanic_id = p_mechanic_id
	main_effect = p_main_effect.duplicate(true)
	modifier_scope = p_modifier_scope
	count_scope = p_count_scope


## 获取激活档位。
func get_active_tier(count: int) -> int:
	var result := 0
	for threshold in thresholds:
		if count >= threshold:
			result = threshold
	return result


## 获取下一threshold。
func get_next_threshold(count: int) -> int:
	for threshold in thresholds:
		if count < threshold:
			return threshold
	return thresholds[-1] if not thresholds.is_empty() else 0


## 获取maxthreshold。
func get_max_threshold() -> int:
	return thresholds[-1] if not thresholds.is_empty() else 0
