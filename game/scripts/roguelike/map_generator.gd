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
	var type_counts := {}

	for node_type in layout:
		var type_name := str(node_type)
		type_counts[type_name] = int(type_counts.get(type_name, 0)) + 1
		nodes.append(_create_node(type_name, _floor, int(type_counts[type_name])))

	return nodes


## 为线性回合模式复用同一套章节遭遇数据。
func build_encounter_node(floor_number: int, node_type: String, occurrence: int = 1) -> Dictionary:
	return _create_node(node_type, floor_number, occurrence)


## 创建单个节点数据
func _create_node(type: String, _floor: int, occurrence: int = 1) -> Dictionary:
	"""创建单个节点数据"""
	var node := {"type": type}

	match type:
		"battle":
			_configure_combat_node(node, "f%d_battle%d" % [_floor, occurrence], _floor, false)
		"elite":
			_configure_combat_node(node, "f%d_elite%d" % [_floor, occurrence], _floor, true)
		"boss":
			_configure_combat_node(node, "f%d_boss" % _floor, _floor, false, true)
		"shop":
			node["shop_discount"] = 0.8 + (_floor - 1) * 0.05
		"rest":
			pass

	return node


## 将数据表中的固定波次绑定到地图节点；缺失时回退到章节敌人池。
func _configure_combat_node(node: Dictionary, battle_id: String, floor_number: int, is_elite: bool, is_boss: bool = false) -> void:
	var scripted_waves := _get_scripted_waves(battle_id, floor_number)
	node["battle_id"] = battle_id
	if not scripted_waves.is_empty():
		node["scripted_waves"] = scripted_waves
		node["waves"] = scripted_waves.size()
		node["enemy_pool"] = _unique_templates_from_waves(scripted_waves)
		return
	node["enemy_pool"] = _get_boss_pool(floor_number) if is_boss else _get_enemy_pool_for_floor(floor_number, is_elite)
	node["waves"] = 3 if is_boss else 2 + floor_number


## 把 waves.json 中同 wave_index 的记录展开为按出生顺序排列的敌人模板。
func _get_scripted_waves(battle_id: String, floor_number: int) -> Array:
	var registry := _registry()
	if not registry or not registry.has_method("get_waves_for_battle"):
		return []
	var records: Array = registry.get_waves_for_battle(battle_id)
	if records.is_empty():
		return []
	var grouped := {}
	for record_value in records:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var wave_index := maxi(1, int(record.get("wave_index", 1)))
		var enemy_id := str(record.get("enemy_id", ""))
		var template: Dictionary = registry.get_enemy(enemy_id)
		if template.is_empty():
			continue
		if not grouped.has(wave_index):
			grouped[wave_index] = []
		var wave: Array = grouped[wave_index]
		for _i in range(maxi(1, int(record.get("count", 1)))):
			wave.append(_scale_enemy_template(template, floor_number))
		grouped[wave_index] = wave
	var result: Array = []
	var indexes: Array = grouped.keys()
	indexes.sort()
	for wave_index in indexes:
		var wave: Array = grouped[wave_index]
		if not wave.is_empty():
			result.append(wave)
	return result


func _unique_templates_from_waves(scripted_waves: Array) -> Array:
	var result: Array = []
	var seen := {}
	for wave_value in scripted_waves:
		if not (wave_value is Array):
			continue
		for template_value in wave_value:
			if not (template_value is Dictionary):
				continue
			var template: Dictionary = template_value
			var enemy_id := str(template.get("enemy_id", ""))
			if enemy_id == "" or seen.has(enemy_id):
				continue
			seen[enemy_id] = true
			result.append(template.duplicate(true))
	return result


## 根据楼层获取敌人池
func _get_enemy_pool_for_floor(_floor: int, is_elite: bool) -> Array:
	"""根据楼层获取敌人池"""
	var pool := EnemyUnit.get_enemy_pool()
	var filtered: Array = []

	var chapter_id := _chapter_id_for_floor(_floor)
	# 过滤并增强敌人
	for enemy_template in pool:
		var etype = enemy_template.get("type", EnemyUnit.EnemyType.MELEE)
		if etype == EnemyUnit.EnemyType.BOSS:
			continue  # Boss不出现在普通战斗
		if str(enemy_template.get("chapter_id", "")) != chapter_id:
			continue
		var rarity := str(enemy_template.get("rarity", "common"))
		if rarity == "summon" or (not is_elite and rarity != "common"):
			continue
		filtered.append(_scale_enemy_template(enemy_template, _floor))

	return filtered


## 获取Boss池
func _get_boss_pool(_floor: int) -> Array:
	"""获取Boss池"""
	var pool := EnemyUnit.get_enemy_pool()
	var bosses: Array = []
	for template in pool:
		if template.get("type") == EnemyUnit.EnemyType.BOSS \
				and str(template.get("chapter_id", "")) == _chapter_id_for_floor(_floor):
			bosses.append(_scale_enemy_template(template, _floor))

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


func _scale_enemy_template(template: Dictionary, floor_number: int) -> Dictionary:
	var scaled := template.duplicate(true)
	var scaling := _scaling("map_floor")
	var offset := float(maxi(0, floor_number - 1))
	var is_boss: bool = str(template.get("rarity", "")) == "boss" \
		or template.get("type", EnemyUnit.EnemyType.MELEE) == EnemyUnit.EnemyType.BOSS
	var hp_step := float(scaling.get("boss_hp_per_floor", 0.5)) if is_boss else float(scaling.get("hp_per_floor", 0.3))
	var atk_step := float(scaling.get("boss_atk_per_floor", 0.5)) if is_boss else float(scaling.get("atk_per_floor", 0.3))
	var def_step := float(scaling.get("def_per_floor", 0.3))
	var base_multiplier := float(scaling.get("base_multiplier", 1.0))
	scaled["hp"] = maxi(1, int(round(float(scaled.get("hp", 80)) * (base_multiplier + offset * hp_step))))
	scaled["atk"] = maxi(0, int(round(float(scaled.get("atk", 10)) * (base_multiplier + offset * atk_step))))
	scaled["def"] = maxi(0, int(round(float(scaled.get("def", 3)) * (base_multiplier + offset * def_step))))
	return scaled


func _chapter_id_for_floor(floor_number: int) -> String:
	match clampi(floor_number, 1, 3):
		1:
			return "corrupted_border"
		2:
			return "city_of_dead"
		_:
			return "abyssal_court"


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
