# map_generator.gd — 肉鸽地图生成器
# 生成每层的路线节点
class_name MapGenerator
extends RefCounted

enum NodeType {
	BATTLE,     ## 普通战斗
	ELITE,      ## 精英战斗
	BOSS,       ## Boss战
	SHOP,       ## 商店/酒馆
	REST,       ## 休息点
}

const FLOOR_LAYOUTS := {
	1: ["battle", "battle", "shop", "boss"],
	2: ["battle", "elite", "battle", "shop", "boss"],
	3: ["elite", "battle", "shop", "elite", "boss"],
}


## 生成单层地图路线
func generate_floor_map(_floor: int) -> Array:
	"""生成单层地图路线"""
	var layout: Array = FLOOR_LAYOUTS.get(_floor, FLOOR_LAYOUTS[1])
	var nodes: Array = []

	for node_type in layout:
		nodes.append(_create_node(node_type, _floor))

	return nodes


## 创建单个节点数据
func _create_node(type: String, _floor: int) -> Dictionary:
	"""创建单个节点数据"""
	var node := {"type": type}

	match type:
		"battle":
			node["enemy_pool"] = _get_enemy_pool_for_floor(_floor, false)
			node["waves"] = 2 + _floor
		"elite":
			node["enemy_pool"] = _get_enemy_pool_for_floor(_floor, true)
			node["waves"] = 2 + _floor
		"boss":
			node["enemy_pool"] = _get_boss_pool(_floor)
			node["waves"] = 3
		"shop":
			node["shop_discount"] = 0.8 + (_floor - 1) * 0.05
		"rest":
			pass

	return node


## 根据楼层获取敌人池
func _get_enemy_pool_for_floor(_floor: int, is_elite: bool) -> Array:
	"""根据楼层获取敌人池"""
	var pool := EnemyUnit.get_enemy_pool()
	var filtered: Array = []

	# 过滤并增强敌人
	for enemy_template in pool:
		var etype = enemy_template.get("type", EnemyUnit.EnemyType.MELEE)
		if etype == EnemyUnit.EnemyType.BOSS:
			continue  # Boss不出现在普通战斗

		var scaled: Dictionary = enemy_template.duplicate(true)
		# 楼层强化
		var scaling := _scaling("map_floor")
		var hp_scale := float(scaling.get("base_multiplier", 1.0)) + float(_floor - 1) * float(scaling.get("hp_per_floor", 0.3))
		var atk_scale := float(scaling.get("base_multiplier", 1.0)) + float(_floor - 1) * float(scaling.get("atk_per_floor", 0.3))
		var def_scale := float(scaling.get("base_multiplier", 1.0)) + float(_floor - 1) * float(scaling.get("def_per_floor", 0.3))
		if is_elite:
			var elite_multiplier := float(scaling.get("elite_multiplier", 1.5))
			hp_scale *= elite_multiplier
			atk_scale *= elite_multiplier
			def_scale *= elite_multiplier

		scaled["hp"] = int(scaled["hp"] * hp_scale)
		scaled["atk"] = int(scaled["atk"] * atk_scale)
		scaled["def"] = int(scaled["def"] * def_scale)
		filtered.append(scaled)

	return filtered


## 获取Boss池
func _get_boss_pool(_floor: int) -> Array:
	"""获取Boss池"""
	var pool := EnemyUnit.get_enemy_pool()
	var bosses: Array = []
	for template in pool:
		if template.get("type") == EnemyUnit.EnemyType.BOSS:
			var scaled: Dictionary = template.duplicate(true)
			var scaling := _scaling("map_floor")
			var hp_scale := float(scaling.get("base_multiplier", 1.0)) + float(_floor - 1) * float(scaling.get("boss_hp_per_floor", 0.5))
			var atk_scale := float(scaling.get("base_multiplier", 1.0)) + float(_floor - 1) * float(scaling.get("boss_atk_per_floor", 0.5))
			scaled["hp"] = int(scaled["hp"] * hp_scale)
			scaled["atk"] = int(scaled["atk"] * atk_scale)
			bosses.append(scaled)

	if bosses.is_empty():
		# 回退：用食人魔加强版
		for template in pool:
			if template.get("name") == "食人魔":
				var scaled: Dictionary = template.duplicate(true)
				var scaling := _scaling("map_floor")
				scaled["hp"] = scaled["hp"] * int(float(scaling.get("fallback_boss_hp_floor_base", 2.0)) + float(_floor))
				scaled["atk"] = scaled["atk"] * int(scaling.get("fallback_boss_atk_multiplier", 2.0))
				scaled["name"] = "食人魔首领"
				bosses.append(scaled)
				break

	return bosses


func _scaling(scaling_id: String) -> Dictionary:
	var registry := _registry()
	if registry and registry.has_method("get_enemy_scaling"):
		var data: Dictionary = registry.get_enemy_scaling(scaling_id)
		if not data.is_empty():
			return data
	return {}


func _registry() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("DataRegistry")
