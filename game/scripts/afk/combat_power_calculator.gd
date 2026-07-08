# combat_power_calculator.gd — AFK小队数值计算
# 只负责把存档角色数据转为AFK模式使用的攻击力和羁绊展示信息。
class_name CombatPowerCalculator
extends RefCounted


## 获取AFK界面当前展示的小队。
static func build_display_party(owned_characters: Array, max_count: int) -> Array:
	var result: Array = []
	for card in owned_characters:
		if result.size() >= max_count:
			break
		if card is Dictionary:
			result.append((card as Dictionary).duplicate(true))
	if not result.is_empty():
		return result

	for class_id in ClassDefinitions.get_all_class_ids():
		if result.size() >= max_count:
			break
		result.append({
			"class_id": class_id,
			"level": 1
		})
	return result


## 计算AFK小队总攻击力。
static func calculate_team_attack(party: Array) -> int:
	var total: int = 0
	for card in party:
		if not (card is Dictionary):
			continue
		var card_data := card as Dictionary
		var class_id := ClassDefinitions.canonicalize_class_id(str(card_data.get("class_id", ClassDefinitions.FALLBACK_CLASS_ID)))
		var level := int(card_data.get("level", 1))
		total += calculate_character_attack(ClassDefinitions.get_template(class_id), level)
	return total


## 计算单名英雄在AFK模式中的攻击力。
static func calculate_character_attack(ct: ClassTemplate, level: int) -> int:
	var level_scale := 1.0 + float(maxi(1, level) - 1) * 0.05
	return int(round(float(ct.base_atk) * level_scale))


## 当前楼层的推荐攻击力。
static func get_required_attack(floor: int) -> int:
	return 90 + maxi(0, floor - 1) * 24


## 预览挂机金币收益。
static func get_preview_reward_gold(floor: int) -> int:
	return 18 + maxi(0, floor - 1) * 4


## 格式化小队羁绊概览。
static func format_synergy_summary(party: Array) -> String:
	var group_counts: Dictionary = {}
	for card in party:
		if not (card is Dictionary):
			continue
		var card_data := card as Dictionary
		var class_id := ClassDefinitions.canonicalize_class_id(str(card_data.get("class_id", ClassDefinitions.FALLBACK_CLASS_ID)))
		var ct := ClassDefinitions.get_template(class_id)
		group_counts[ct.class_group] = int(group_counts.get(ct.class_group, 0)) + 1

	var parts: Array[String] = []
	for group in group_counts.keys():
		parts.append("%s x%d" % [ClassDefinitions.get_class_group_label(str(group)), int(group_counts[group])])
	return "无" if parts.is_empty() else "，".join(parts)
