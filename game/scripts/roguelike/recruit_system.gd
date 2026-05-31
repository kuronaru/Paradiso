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

	func _init(c_id: String, lvl: int, cst: int) -> void:
		class_id = c_id
		job_name = ClassDefinitions.get_template(c_id).job_name
		level = lvl
		cost = cst


var current_options: Array[RecruitOption] = []
const OPTIONS_PER_RECRUIT := 4
const BASE_COST := 20
const RARE_COST_MULTIPLIER := 1.5


func generate_recruit_options(floor: int, party_size: int) -> Array[RecruitOption]:
	"""生成招募选项"""
	current_options.clear()

	var available_classes := ClassDefinitions.get_all_class_ids().duplicate()

	# 偶尔出现高等级选项
	var has_rare := randf() < 0.3

	for i in range(OPTIONS_PER_RECRUIT):
		var class_pool := available_classes.duplicate()
		class_pool.shuffle()

		if class_pool.is_empty():
			break

		var class_id: String = class_pool[0]
		# 避免过多重复职业的基础刷新机制
		# 这里简化为随机选取，完整版应有权重系统

		var level := 1
		if has_rare and i == 0:
			level = 2 + randi() % min(2, floor)
			has_rare = false  # 只出一个稀有

		var cost := _calculate_cost(level, party_size)
		var option := RecruitOption.new(class_id, level, cost)
		current_options.append(option)

	return current_options


func get_current_options() -> Array[RecruitOption]:
	return current_options


func remove_option(index: int) -> void:
	if index >= 0 and index < current_options.size():
		current_options.remove_at(index)


func clear_options() -> void:
	current_options.clear()


func _calculate_cost(level: int, _party_size: int) -> int:
	"""计算招募花费"""
	var base := BASE_COST
	if level > 1:
		base = int(base * RARE_COST_MULTIPLIER * level)
	return base
