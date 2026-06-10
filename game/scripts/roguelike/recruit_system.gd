# recruit_system.gd — 酒馆招募系统
# 管理招募选项的生成、刷新和购买
class_name RecruitSystem
extends Node

const M = "Recruit"

class RecruitOption:
	var class_id: String
	var job_name: String
	var level: int
	var cost: int
	var shop_level: int
	var tavern_passive: String

	func _init(c_id: String, lvl: int, cst: int, s_level: int, passive: String) -> void:
		class_id = c_id
		job_name = ClassDefinitions.get_template(c_id).job_name
		level = lvl
		cost = cst
		shop_level = s_level
		tavern_passive = passive


var current_options: Array[RecruitOption] = []
const MAX_TAVERN_LEVEL := 6
const MIN_UPGRADE_COST := 1
const REFRESH_COST := 1
const UPGRADE_BASE_COSTS := {
	1: 5,
	2: 8,
	3: 12,
	4: 16,
	5: 22,
}
const OPTION_SLOTS_BY_LEVEL := {
	1: 3,
	2: 3,
	3: 4,
	4: 4,
	5: 5,
	6: 5,
}

var tavern_level: int = 1
var upgrade_discount: int = 0


func generate_recruit_options(_round_number: int, _party_size: int) -> Array[RecruitOption]:
	"""生成招募选项"""
	current_options.clear()

	var available_options := _build_available_option_pool()
	if available_options.is_empty():
		return current_options

	available_options.shuffle()
	var slots := get_option_slot_count()
	for i in range(slots):
		var data: Dictionary = available_options[i % available_options.size()]
		var option := RecruitOption.new(
			str(data["class_id"]),
			int(data["level"]),
			int(data["cost"]),
			int(data["shop_level"]),
			str(data["tavern_passive"])
		)
		current_options.append(option)

	return current_options


func get_current_options() -> Array[RecruitOption]:
	return current_options


func remove_option(index: int) -> void:
	if index >= 0 and index < current_options.size():
		current_options.remove_at(index)


func clear_options() -> void:
	current_options.clear()


func reset_run() -> void:
	"""重置单局酒馆状态。"""
	tavern_level = 1
	upgrade_discount = 0
	clear_options()


func advance_round() -> void:
	"""每经过一回合，当前升级费用减少1。"""
	if tavern_level < MAX_TAVERN_LEVEL:
		upgrade_discount += 1


func get_refresh_cost() -> int:
	return REFRESH_COST


func get_option_slot_count() -> int:
	return int(OPTION_SLOTS_BY_LEVEL.get(tavern_level, 3))


func is_max_level() -> bool:
	return tavern_level >= MAX_TAVERN_LEVEL


func get_upgrade_cost() -> int:
	if is_max_level():
		return 0
	var base_cost := int(UPGRADE_BASE_COSTS.get(tavern_level, 0))
	return max(MIN_UPGRADE_COST, base_cost - upgrade_discount)


func upgrade_tavern() -> bool:
	if is_max_level():
		return false
	tavern_level += 1
	upgrade_discount = 0
	return true


func _calculate_cost(class_id: String, level: int) -> int:
	"""计算招募花费"""
	var data: Dictionary = ClassDefinitions.get_tavern_data(class_id)
	var base_cost := int(data.get("base_cost", 2))
	match clampi(level, 1, 3):
		1:
			return base_cost
		2:
			return max(4, base_cost + 2)
		_:
			return max(6, base_cost + 4)


func _build_available_option_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for class_id in ClassDefinitions.get_all_class_ids():
		var data: Dictionary = ClassDefinitions.get_tavern_data(class_id)
		if data.is_empty():
			continue

		var class_shop_level := int(data.get("shop_level", 1))
		for star_level in range(1, 4):
			var required_shop_level := maxi(class_shop_level, _required_shop_level_for_star(star_level))
			if required_shop_level > tavern_level:
				continue
			pool.append({
				"class_id": class_id,
				"level": star_level,
				"shop_level": required_shop_level,
				"cost": _calculate_cost(class_id, star_level),
				"tavern_passive": str(data.get("passive", ""))
			})
	return pool


func _required_shop_level_for_star(star_level: int) -> int:
	match clampi(star_level, 1, 3):
		1:
			return 1
		2:
			return 3
		_:
			return 5
