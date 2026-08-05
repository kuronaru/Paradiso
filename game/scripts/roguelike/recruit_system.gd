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

	## 初始化实例数据。
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
const RECRUIT_COST_BY_TIER := {
	1: 2,
	2: 3,
	3: 4,
}

var tavern_level: int = 1
var upgrade_discount: int = 0
var is_frozen: bool = false


## 生成招募选项
func generate_recruit_options(_round_number: int, _party_size: int) -> Array[RecruitOption]:
	"""生成招募选项"""
	if is_frozen and not current_options.is_empty():
		return current_options

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


## 获取当前选项。
func get_current_options() -> Array[RecruitOption]:
	for option in current_options:
		option.cost = _calculate_cost(option.class_id, option.level)
	return current_options


## 移除选项。
func remove_option(index: int) -> void:
	if index >= 0 and index < current_options.size():
		current_options.remove_at(index)


## 清理选项。
func clear_options() -> void:
	current_options.clear()
	is_frozen = false


## 重置单局酒馆状态。
func reset_run() -> void:
	"""重置单局酒馆状态。"""
	tavern_level = clampi(1 + GameManager.get_roguelike_relic_modifier("starting_tavern_level_bonus"), 1, _cfg_int("tavern_max_level", MAX_TAVERN_LEVEL))
	upgrade_discount = 0
	is_frozen = false
	clear_options()


## 每经过一回合，当前升级费用减少1。
func advance_round() -> void:
	"""每经过一回合，当前升级费用减少1。"""
	if tavern_level < _cfg_int("tavern_max_level", MAX_TAVERN_LEVEL):
		upgrade_discount += 1


## 获取消耗。
func get_refresh_cost() -> int:
	var cost := GameManager.apply_roguelike_relic_refresh_cost(_cfg_int("tavern_refresh_cost", REFRESH_COST))
	if SynergyManager and SynergyManager.has_method("get_tavern_refresh_cost"):
		cost = SynergyManager.get_tavern_refresh_cost(cost)
	return cost


## 获取选项槽位数量。
func get_option_slot_count() -> int:
	var slots := _cfg_dict("tavern_option_slots_by_level")
	return int(slots.get(str(tavern_level), OPTION_SLOTS_BY_LEVEL.get(tavern_level, 3)))


## 判断酒馆是否已达最高等级。
func is_max_level() -> bool:
	return tavern_level >= _cfg_int("tavern_max_level", MAX_TAVERN_LEVEL)


## 获取消耗。
func get_upgrade_cost() -> int:
	if is_max_level():
		return 0
	var base_costs := _cfg_dict("tavern_upgrade_base_costs")
	var base_cost := int(base_costs.get(str(tavern_level), UPGRADE_BASE_COSTS.get(tavern_level, 0)))
	return max(_cfg_int("tavern_min_upgrade_cost", MIN_UPGRADE_COST), base_cost - upgrade_discount)


## 升级酒馆等级。
func upgrade_tavern() -> bool:
	if is_max_level():
		return false
	tavern_level += 1
	upgrade_discount = 0
	return true


## 切换酒馆冻结状态。
func toggle_frozen() -> bool:
	is_frozen = not is_frozen
	return is_frozen


## 设置酒馆冻结状态。
func set_frozen(frozen: bool) -> void:
	is_frozen = frozen


## 计算招募花费
func _calculate_cost(_class_id: String, level: int) -> int:
	"""计算招募花费"""
	var tier := clampi(level, 1, 3)
	var configured_costs := _cfg_dict("tavern_recruit_cost_by_tier")
	var cost := int(configured_costs.get(str(tier), RECRUIT_COST_BY_TIER[tier]))
	if SynergyManager and SynergyManager.has_method("get_recruit_cost_discount"):
		cost -= SynergyManager.get_recruit_cost_discount()
	return maxi(1, cost)


## 构建可用选项池。
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


## 获取星级所需的酒馆等级。
func _required_shop_level_for_star(star_level: int) -> int:
	var required := _cfg_dict("tavern_required_shop_level_by_star")
	var star := clampi(star_level, 1, 3)
	return int(required.get(str(star), 1 if star == 1 else (3 if star == 2 else 5)))


func _cfg_int(key: String, default_value: int) -> int:
	var registry := _registry()
	if registry and registry.has_method("get_config"):
		return int(registry.get_config(key, default_value))
	return default_value


func _cfg_dict(key: String) -> Dictionary:
	var registry := _registry()
	if registry and registry.has_method("get_config_section"):
		return registry.get_config_section(key)
	return {}


func _registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("DataRegistry")
