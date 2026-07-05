# deployment_system.gd — 部署系统
# 管理手牌、部署拖拽、选中单位控制
class_name DeploymentSystem
extends Node

const M = "Deploy"

signal unit_selected(unit: HeroUnit)
signal unit_deselected
signal drag_ended
signal hand_updated(cards: Array)

var selected_unit: HeroUnit = null
var selected_card_index: int = -1     # 当前高亮选中的手牌下标（点击网格部署）
var hand_cards: Array = []            # 手牌 [{class_id, level}]
var is_dragging: bool = false
var drag_card_index: int = -1         # 兼容旧点击部署流程的当前拖拽下标
var drag_original_index: int = -1     # 拖拽卡牌在手牌中的原始位置
var drag_card_data: Dictionary = {}   # 正在拖拽的卡牌数据
var drag_preview: Control = null      # 当前拖拽预览节点
var drag_preview_mode: String = ""    # "card" / "unit"，避免重复重建预览
var drag_grid_pos: Vector2i = Vector2i.ZERO
var drag_over_grid: bool = false

@onready var grid: GridSystem = null
var _resolving_roster_promotions: bool = false


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	add_to_group("deployment_system")
	grid = BattleManager.grid
	if grid:
		grid.cell_clicked.connect(_on_cell_clicked)
		grid.unit_clicked.connect(_on_unit_clicked)


## 拖拽中持续刷新预览位置
func _process(_delta: float) -> void:
	"""拖拽中持续刷新预览位置"""
	if is_dragging:
		_update_drag_preview()


## 处理拖拽释放与右键取消
func _input(event: InputEvent) -> void:
	"""处理拖拽释放与右键取消"""
	if not is_dragging:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_drag()
	elif event is InputEventMouseMotion:
		_update_drag_preview()


## 初始化手牌（从肉鸽队伍数据）
func setup_hand(party_data: Array) -> void:
	"""初始化手牌（从肉鸽队伍数据）"""
	if GameManager.is_roguelike_run and not _resolving_roster_promotions:
		if _resolve_run_roster_promotions():
			party_data = GameManager.get_battle_party_data()

	selected_card_index = -1
	hand_cards.clear()
	for member in party_data:
		var card: Dictionary = member.duplicate(true)
		card["class_id"] = member["class_id"]
		card["level"] = member["level"]
		card["star_level"] = member.get("star_level", 1)
		hand_cards.append(card)
	Log.i(M, "手牌初始化: %d 张卡" % hand_cards.size())
	hand_updated.emit(hand_cards)


## 从当前肉鸽队伍重新同步手牌，处理三合一消耗其他手牌的情况。
func _sync_hand_from_run_party() -> void:
	setup_hand(GameManager.get_battle_party_data())


## 扫描手牌和已部署英雄，处理同名三合一升星。
func _resolve_run_roster_promotions() -> bool:
	if _resolving_roster_promotions:
		return false
	if not GameManager.is_roguelike_run:
		return false
	if BattleManager.state != BattleManager.BattleState.PREPARING:
		return false

	_resolving_roster_promotions = true
	var changed := false
	while _try_promote_one_run_roster_group():
		changed = true
	_resolving_roster_promotions = false
	return changed


func _try_promote_one_run_roster_group() -> bool:
	var groups := {}

	for i in range(GameManager.party.size()):
		var member = GameManager.party[i]
		if member is Dictionary:
			_append_merge_candidate(groups, "hand", member as Dictionary, i, null)

	for unit in BattleManager.player_units.duplicate():
		if unit is HeroUnit and is_instance_valid(unit):
			var hero := unit as HeroUnit
			_append_merge_candidate(groups, "field", _card_data_from_unit(hero), -1, hero)

	for key in groups.keys():
		var group: Array = groups[key]
		if group.size() >= 3:
			var selected: Array = []
			for i in range(3):
				selected.append(group[i])
			return _promote_run_merge_group(selected)
	return false


func _append_merge_candidate(groups: Dictionary, source: String, card_data: Dictionary, hand_index: int, unit: HeroUnit) -> void:
	if not _is_merge_candidate_card(card_data):
		return
	var key := _get_merge_key(card_data)
	if not groups.has(key):
		groups[key] = []
	var group: Array = groups[key]
	group.append({
		"source": source,
		"card": card_data.duplicate(true),
		"hand_index": hand_index,
		"unit": unit
	})


func _is_merge_candidate_card(card_data: Dictionary) -> bool:
	if card_data.is_empty():
		return false
	var class_id := ClassDefinitions.canonicalize_class_id(str(card_data.get("class_id", "")))
	if not ClassDefinitions.has_class_id(class_id):
		return false
	if bool(card_data.get("merge_locked", false)):
		return false
	if int(card_data.get("upgrade_tier", 1)) > 1:
		return false
	var star := clampi(int(card_data.get("star_level", card_data.get("level", 1))), 1, GameManager.ROGUELIKE_MAX_CARD_STAR)
	return star < GameManager.ROGUELIKE_MAX_CARD_STAR


func _get_merge_key(card_data: Dictionary) -> String:
	var class_id := ClassDefinitions.canonicalize_class_id(str(card_data.get("class_id", "")))
	var star := clampi(int(card_data.get("star_level", card_data.get("level", 1))), 1, GameManager.ROGUELIKE_MAX_CARD_STAR)
	var shop_level := maxi(1, int(card_data.get("shop_level", 1)))
	return "%s|%d|%d" % [class_id, star, shop_level]


func _promote_run_merge_group(group: Array) -> bool:
	if group.size() < 3:
		return false

	var first_entry: Dictionary = group[0]
	var first_card: Dictionary = first_entry.get("card", {})
	var class_id := ClassDefinitions.canonicalize_class_id(str(first_card.get("class_id", "")))
	var source_star := clampi(int(first_card.get("star_level", first_card.get("level", 1))), 1, GameManager.ROGUELIKE_MAX_CARD_STAR)
	var shop_level := maxi(1, int(first_card.get("shop_level", 1)))
	var promoted_star := source_star + 1

	var hand_indices: Array[int] = []
	for entry in group:
		var candidate: Dictionary = entry
		if str(candidate.get("source", "")) == "hand":
			hand_indices.append(int(candidate.get("hand_index", -1)))

	var hand_size_after_merge := GameManager.party.size() - hand_indices.size()
	if hand_size_after_merge + 1 > GameManager.get_roguelike_max_hand_cards():
		return false

	hand_indices.sort()
	for i in range(hand_indices.size() - 1, -1, -1):
		var hand_index := int(hand_indices[i])
		if hand_index >= 0 and hand_index < GameManager.party.size():
			GameManager.party.remove_at(hand_index)

	for entry in group:
		var candidate: Dictionary = entry
		if str(candidate.get("source", "")) != "field":
			continue
		var unit = candidate.get("unit")
		if unit is HeroUnit and is_instance_valid(unit):
			_remove_deployed_unit_for_promotion(unit as HeroUnit)

	var promoted := GameManager.add_to_party(class_id, promoted_star, shop_level, 2)
	if promoted:
		Log.i(M, "三合一升星: %s 等阶%d %d星 -> %d星" % [class_id, shop_level, source_star, promoted_star])
	return promoted


func _remove_deployed_unit_for_promotion(unit: HeroUnit) -> void:
	if not unit or not is_instance_valid(unit):
		return
	if selected_unit == unit:
		selected_unit.is_selected = false
		selected_unit = null
		unit_deselected.emit()
	if not grid:
		grid = BattleManager.grid
	if grid:
		grid.remove_unit(unit)
	BattleManager.unregister_player_unit(unit)
	BattleManager.unit_retreated.emit(unit)
	unit.queue_free()


## 检查是否可以部署指定职业
func can_deploy_card(class_id: String) -> bool:
	"""检查是否可以部署指定职业"""
	if BattleManager.state == BattleManager.BattleState.PREPARING:
		return ClassDefinitions.has_class_id(str(class_id))
	var ct := ClassDefinitions.get_template(class_id)
	return ResourceManager.can_afford(_get_deploy_cost(ct))


## 检查当前战斗阶段是否允许部署
func can_deploy_now() -> bool:
	"""检查当前战斗阶段是否允许部署"""
	return BattleManager.state in [
		BattleManager.BattleState.PREPARING,
		BattleManager.BattleState.IN_PROGRESS,
		BattleManager.BattleState.WAVE_BREAK,
	]


## 获取deployed数量。
func get_deployed_count() -> int:
	var count := 0
	for unit in BattleManager.player_units:
		if is_instance_valid(unit) and unit is HeroUnit:
			count += 1
	return count


## 判断是否可以deploymore。
func can_deploy_more() -> bool:
	return get_deployed_count() < GameManager.ROGUELIKE_MAX_DEPLOYED_UNITS


## 开始拖拽手牌，将卡牌从手牌队列中临时移除
func begin_drag(card_index: int) -> bool:
	"""开始拖拽手牌，将卡牌从手牌队列中临时移除"""
	if card_index < 0 or card_index >= hand_cards.size():
		return false
	if not can_deploy_now():
		return false

	if is_dragging:
		cancel_drag()

	var card_data: Dictionary = hand_cards[card_index]
	if not _is_valid_hand_card(card_data):
		return false

	drag_card_data = card_data.duplicate(true)
	drag_original_index = card_index
	drag_card_index = card_index
	selected_card_index = -1
	is_dragging = true
	drag_over_grid = false
	drag_preview_mode = ""

	# 拖拽期间手牌栏不显示这张卡；取消或部署失败时再插回原位置
	hand_cards.remove_at(card_index)
	hand_updated.emit(hand_cards)
	_update_drag_preview()
	return true


## 高亮选中一张手牌，用于随后点击网格部署
func select_card(card_index: int) -> bool:
	"""高亮选中一张手牌，用于随后点击网格部署"""
	if card_index < 0 or card_index >= hand_cards.size():
		selected_card_index = -1
		return false
	if not can_deploy_now():
		selected_card_index = -1
		return false

	selected_card_index = card_index
	return true


## 清除当前高亮选中的手牌
func clear_selected_card() -> void:
	"""清除当前高亮选中的手牌"""
	selected_card_index = -1


## 取消拖拽，将卡牌放回原来的手牌位置
func cancel_drag() -> void:
	"""取消拖拽，将卡牌放回原来的手牌位置"""
	if not is_dragging:
		return
	_restore_dragged_card()
	_clear_drag_state()
	drag_ended.emit()


## 部署手牌到网格
func deploy_card(card_index: int, grid_pos: Vector2i) -> bool:
	"""部署手牌到网格"""
	if card_index < 0 or card_index >= hand_cards.size():
		return false

	var card_data: Dictionary = hand_cards[card_index]
	var synced_from_party := false
	if _get_swappable_hero_at(grid_pos):
		var swapped_card := _swap_card_data_with_unit(card_data, grid_pos)
		if swapped_card.is_empty():
			return false
		if GameManager.is_roguelike_run:
			synced_from_party = true
		else:
			hand_cards[card_index] = swapped_card
	elif can_deploy_more():
		if not _deploy_card_data(card_data, grid_pos):
			return false
		if GameManager.is_roguelike_run:
			synced_from_party = true
		else:
			hand_cards.remove_at(card_index)
	else:
		return false
	if selected_card_index == card_index:
		selected_card_index = -1
	elif selected_card_index > card_index:
		selected_card_index -= 1
	if synced_from_party:
		_sync_hand_from_run_party()
	else:
		hand_updated.emit(hand_cards)
	return true


## 根据卡牌数据创建角色并放置到网格
func _deploy_card_data(card_data: Dictionary, grid_pos: Vector2i) -> bool:
	"""根据卡牌数据创建角色并放置到网格"""
	if not grid:
		grid = BattleManager.grid
	if not grid:
		return false
	if not card_data.has("class_id") or not card_data.has("level"):
		return false

	var ct := ClassDefinitions.get_template(card_data["class_id"])
	var deploy_cost := _get_deploy_cost(ct)

	if not can_deploy_more():
		Log.w(M, "部署人数已达上限 %d" % GameManager.ROGUELIKE_MAX_DEPLOYED_UNITS)
		return false

	if not grid.can_place_at(grid_pos):
		Log.w(M, "无法部署到 (%d, %d)" % [grid_pos.x, grid_pos.y])
		return false

	var spends_dp := _should_spend_deploy_cost()
	if spends_dp and not ResourceManager.spend(deploy_cost):
		Log.w(M, "DP不足，需要 %d" % deploy_cost)
		return false

	var hero := HeroUnit.new()
	hero.star_level = int(card_data.get("star_level", 1))
	hero.setup(ct, card_data["level"])
	hero.deploy_cost = deploy_cost if spends_dp else 0
	if not grid.place_unit(hero, grid_pos):
		if spends_dp:
			ResourceManager.refund(deploy_cost)
		BattleManager.unregister_player_unit(hero)
		hero.queue_free()
		return false

	if GameManager.is_roguelike_run and not GameManager.remove_from_party_card(card_data):
		if spends_dp:
			ResourceManager.refund(deploy_cost)
		BattleManager.unregister_player_unit(hero)
		grid.remove_unit(hero)
		hero.queue_free()
		Log.w(M, "部署失败：手牌数据未同步")
		return false

	hero.mark_deployed(card_data, grid_pos)
	BattleManager.unit_deployed.emit(hero)
	if GameManager.is_roguelike_run:
		_resolve_run_roster_promotions()
	Log.i(M, "部署 %s 到 (%d, %d)" % [ct.job_name, grid_pos.x, grid_pos.y])
	return true


## 用手牌替换场上指定英雄，并返回被换下英雄的卡牌数据。
func _swap_card_data_with_unit(card_data: Dictionary, grid_pos: Vector2i) -> Dictionary:
	if not grid:
		grid = BattleManager.grid
	if not grid:
		return {}
	if not card_data.has("class_id") or not card_data.has("level"):
		return {}

	var target := _get_swappable_hero_at(grid_pos)
	if not target:
		Log.w(M, "替换部署只能放置到已有英雄的位置")
		return {}

	var swapped_card := _card_data_from_unit(target)
	if swapped_card.is_empty():
		return {}

	var ct := ClassDefinitions.get_template(card_data["class_id"])
	var deploy_cost := _get_deploy_cost(ct)
	var spends_dp := _should_spend_deploy_cost()
	if spends_dp and not ResourceManager.spend(deploy_cost):
		Log.w(M, "DP不足，替换部署需要%d" % deploy_cost)
		return {}

	if GameManager.is_roguelike_run and not GameManager.remove_from_party_card(card_data):
		if spends_dp:
			ResourceManager.refund(deploy_cost)
		Log.w(M, "替换部署失败：手牌数据未同步")
		return {}

	_remove_deployed_unit_for_promotion(target)

	var returned_card := _return_card_to_hand_data(swapped_card)
	if returned_card.is_empty():
		if GameManager.is_roguelike_run:
			GameManager.return_card_to_party(card_data)
		if spends_dp:
			ResourceManager.refund(deploy_cost)
		Log.w(M, "替换部署失败：手牌区已满")
		return {}

	var replacement := HeroUnit.new()
	replacement.star_level = int(card_data.get("star_level", 1))
	replacement.setup(ct, card_data["level"])
	replacement.deploy_cost = deploy_cost if spends_dp else 0

	if not grid.place_unit(replacement, grid_pos):
		BattleManager.unregister_player_unit(replacement)
		replacement.queue_free()
		return {}

	replacement.mark_deployed(card_data, grid_pos)
	BattleManager.unit_deployed.emit(replacement)
	if GameManager.is_roguelike_run:
		_resolve_run_roster_promotions()
	Log.i(M, "替换部署 %s 到 (%d, %d)，换下 %s" % [ct.job_name, grid_pos.x, grid_pos.y, returned_card.get("class_id", "")])
	return returned_card


## 获取替换部署时目标格上的英雄。
func _get_swappable_hero_at(grid_pos: Vector2i) -> HeroUnit:
	if not grid or not grid.occupancy.has(grid_pos):
		return null
	var unit = grid.occupancy[grid_pos]
	if unit is HeroUnit and is_instance_valid(unit):
		return unit as HeroUnit
	return null


## 判断当前拖拽卡牌是否能释放到指定格子。
func _can_drop_drag_at(grid_pos: Vector2i) -> bool:
	if not grid:
		return false
	if _get_swappable_hero_at(grid_pos):
		return true
	return can_deploy_more() and grid.can_place_at(grid_pos)


## 准备阶段暂时不检查或消耗部署DP。
func _should_spend_deploy_cost() -> bool:
	return BattleManager.state != BattleManager.BattleState.PREPARING


## 判断手牌数据是否足以进入拖拽流程；DP 留到落点时校验。
func _is_valid_hand_card(card_data: Dictionary) -> bool:
	if not card_data.has("class_id") or not card_data.has("level"):
		return false
	return ClassDefinitions.has_class_id(str(card_data.get("class_id", "")))


## 将一张卡归还到肉鸽队伍，并返回手牌区应显示的最终卡牌数据。
func _return_card_to_hand_data(card_data: Dictionary) -> Dictionary:
	if not GameManager.is_roguelike_run:
		return _normalize_hand_card_data(card_data)

	var before_instance_ids := {}
	for member in GameManager.party:
		if member is Dictionary:
			var instance_id := int((member as Dictionary).get("instance_id", -1))
			if instance_id >= 0:
				before_instance_ids[instance_id] = true

	if not GameManager.return_card_to_party(card_data):
		return {}

	_resolve_run_roster_promotions()

	var returned_card := {}
	for member in GameManager.party:
		if not (member is Dictionary):
			continue
		var card := member as Dictionary
		var instance_id := int(card.get("instance_id", -1))
		if instance_id >= 0 and not before_instance_ids.has(instance_id):
			returned_card = card.duplicate(true)
	if not returned_card.is_empty():
		return _normalize_hand_card_data(returned_card)
	return _normalize_hand_card_data(card_data)


## 规范化手牌区需要的基础字段，避免换下卡缺少等阶、金卡或实例数据。
func _normalize_hand_card_data(card_data: Dictionary) -> Dictionary:
	if card_data.is_empty():
		return {}
	var normalized := card_data.duplicate(true)
	var class_id := ClassDefinitions.canonicalize_class_id(str(normalized.get("class_id", "fighter_champion")))
	var star := clampi(int(normalized.get("star_level", normalized.get("level", 1))), 1, GameManager.ROGUELIKE_MAX_CARD_STAR)
	normalized["class_id"] = class_id
	normalized["star_level"] = star
	normalized["level"] = GameManager.get_effective_level_for_star(class_id, star)
	normalized["shop_level"] = maxi(1, int(normalized.get("shop_level", 1)))
	normalized["upgrade_tier"] = maxi(1, int(normalized.get("upgrade_tier", 1)))
	normalized["merge_locked"] = bool(normalized.get("merge_locked", false)) or int(normalized["upgrade_tier"]) > 1
	normalized["is_golden"] = bool(normalized.get("is_golden", false)) or bool(normalized["merge_locked"])
	return normalized


## 获取deploy消耗。
func _get_deploy_cost(ct: ClassTemplate) -> int:
	if SynergyManager and SynergyManager.has_method("get_discounted_deploy_cost"):
		return SynergyManager.get_discounted_deploy_cost(ct.deploy_cost)
	return ct.deploy_cost


## 点击格子选中玩家单位
func select_unit_at(grid_pos: Vector2i) -> void:
	"""点击格子选中玩家单位"""
	if not grid:
		return

	if selected_unit:
		selected_unit.is_selected = false
		selected_unit = null
		unit_deselected.emit()

	if grid.occupancy.has(grid_pos):
		var unit = grid.occupancy[grid_pos]
		if unit is HeroUnit and unit.is_alive:
			selected_unit = unit
			unit.is_selected = true
			unit_selected.emit(unit)


## 战场单位点击处理；不依赖网格坐标
func _on_unit_clicked(unit: Node) -> void:
	"""战场单位点击处理；不依赖网格坐标"""
	var unit_valid := is_instance_valid(unit)
	var unit_type := unit.get_class() if unit_valid else "<invalid>"
	Log.d(M, "收到战场单位点击信号: unit=%s valid=%s type=%s" % [unit, unit_valid, unit_type])

	if selected_card_index >= 0 and unit is HeroUnit:
		if deploy_card(selected_card_index, (unit as HeroUnit).grid_position):
			clear_selected_card()
		return

	if selected_unit:
		selected_unit.is_selected = false
		selected_unit = null
		unit_deselected.emit()

	if not (unit is HeroUnit):
		Log.d(M, "战场单位点击未选中角色: 目标不是HeroUnit")
		return

	var hero := unit as HeroUnit
	if hero.is_alive:
		Log.d(M, "发送角色选中信号: name=%s pos=%s" % [hero.unit_name, hero.global_position])
		selected_unit = hero
		hero.is_selected = true
		unit_selected.emit(hero)
	else:
		Log.d(M, "战场单位点击未选中角色: 角色已死亡 name=%s" % hero.unit_name)


## 网格点击处理
func _on_cell_clicked(grid_pos: Vector2i) -> void:
	"""网格点击处理"""
	if is_dragging:
		_finish_drag_at(grid_pos)
	elif selected_card_index >= 0:
		# 已经高亮选中手牌时，点击空格部署；点击已有英雄格时执行替换。
		if _can_drop_drag_at(grid_pos) and deploy_card(selected_card_index, grid_pos):
			clear_selected_card()
	elif BattleManager.state == BattleManager.BattleState.PREPARING:
		# 准备阶段：点击空地尝试部署第一张可部署的卡
		if hand_cards.size() > 0 and grid.is_deploy_zone(grid_pos) and not grid.is_occupied(grid_pos):
			# 找DP够用的第一张卡
			for i in range(hand_cards.size()):
				if can_deploy_card(hand_cards[i]["class_id"]):
					deploy_card(i, grid_pos)
					break
		else:
			select_unit_at(grid_pos)
	else:
		select_unit_at(grid_pos)


## 切换选中姿态。
func toggle_selected_stance() -> void:
	if selected_unit and is_instance_valid(selected_unit):
		selected_unit.toggle_stance()


## 使用选中技能。
func use_selected_skill(skill_index: int) -> void:
	if selected_unit and is_instance_valid(selected_unit):
		var skills: Array = selected_unit.class_template.skill_ids
		if skill_index < skills.size():
			selected_unit.use_skill(skills[skill_index])


## 处理retreat选中逻辑。
func retreat_selected() -> void:
	if selected_unit and is_instance_valid(selected_unit):
		if GameManager.is_roguelike_run and hand_cards.size() >= GameManager.get_roguelike_max_hand_cards():
			Log.w(M, "手牌区已满，无法撤回角色")
			return
		var card_data := _card_data_from_unit(selected_unit)
		selected_unit.retreat()
		# 把卡牌退回手牌
		if card_data.size() > 0:
			var returned_card := _return_card_to_hand_data(card_data)
			if not returned_card.is_empty():
				if GameManager.is_roguelike_run:
					_sync_hand_from_run_party()
				else:
					hand_cards.append(returned_card)
					hand_updated.emit(hand_cards)
		selected_unit = null
		unit_deselected.emit()


## 处理卡牌数据单位逻辑。
func _card_data_from_unit(unit: HeroUnit) -> Dictionary:
	if not unit:
		return {}
	if not unit.run_card_data.is_empty():
		return unit.run_card_data.duplicate(true)
	if unit.class_template:
		return {
			"class_id": unit.class_template.class_id,
			"level": unit.level,
			"star_level": unit.star_level
		}
	return {}


## 根据鼠标当前位置完成拖拽：网格内部署，手牌区或其他区域取消
func _finish_drag() -> void:
	"""根据鼠标当前位置完成拖拽：网格内部署，手牌区或其他区域取消"""
	if drag_over_grid:
		_finish_drag_at(drag_grid_pos)
	else:
		cancel_drag()


## 在指定网格位置结束拖拽并尝试部署
func _finish_drag_at(grid_pos: Vector2i) -> void:
	"""在指定网格位置结束拖拽并尝试部署"""
	if not is_dragging:
		return

	var deployed := false
	if _get_swappable_hero_at(grid_pos):
		var swapped_card := _swap_card_data_with_unit(drag_card_data, grid_pos)
		if not swapped_card.is_empty():
			if GameManager.is_roguelike_run:
				_sync_hand_from_run_party()
			else:
				var restore_index := clampi(drag_original_index, 0, hand_cards.size())
				hand_cards.insert(restore_index, swapped_card)
				hand_updated.emit(hand_cards)
			deployed = true
	elif can_deploy_more():
		deployed = _deploy_card_data(drag_card_data, grid_pos)
		if deployed and GameManager.is_roguelike_run:
			_sync_hand_from_run_party()
	if not deployed:
		_restore_dragged_card()
	_clear_drag_state()
	drag_ended.emit()


## 将正在拖拽的卡牌恢复到原手牌位置
func _restore_dragged_card() -> void:
	"""将正在拖拽的卡牌恢复到原手牌位置"""
	if drag_card_data.is_empty():
		return

	var restore_index := clampi(drag_original_index, 0, hand_cards.size())
	hand_cards.insert(restore_index, drag_card_data.duplicate(true))
	hand_updated.emit(hand_cards)


## 清理拖拽状态和预览节点
func _clear_drag_state() -> void:
	"""清理拖拽状态和预览节点"""
	is_dragging = false
	drag_card_index = -1
	drag_original_index = -1
	drag_card_data = {}
	drag_over_grid = false
	drag_preview_mode = ""
	if drag_preview and is_instance_valid(drag_preview):
		drag_preview.queue_free()
	drag_preview = null


## 根据鼠标区域切换卡牌预览或战斗形象预览
func _update_drag_preview() -> void:
	"""根据鼠标区域切换卡牌预览或战斗形象预览"""
	if not is_dragging or drag_card_data.is_empty():
		return

	var mouse_pos := get_viewport().get_mouse_position()
	if _is_mouse_over_hand_area(mouse_pos):
		# 鼠标在手牌区域：显示卡牌UI，松开后取消部署
		drag_over_grid = false
		_show_card_drag_preview(mouse_pos)
		return

	var maybe_grid_pos = _get_mouse_grid_position()
	if maybe_grid_pos is Vector2i and grid and grid.is_deploy_zone(maybe_grid_pos):
		# 鼠标在部署网格：显示无血条/名称的战斗形象，吸附到格子中心
		var grid_pos: Vector2i = maybe_grid_pos
		drag_grid_pos = grid_pos
		drag_over_grid = true
		_show_unit_drag_preview(grid_pos)
	else:
		drag_over_grid = false
		_show_card_drag_preview(mouse_pos)


## 显示跟随鼠标移动的卡牌预览
func _show_card_drag_preview(mouse_pos: Vector2) -> void:
	"""显示跟随鼠标移动的卡牌预览"""
	if drag_preview_mode != "card":
		_replace_drag_preview(_create_card_preview())
		drag_preview_mode = "card"
	drag_preview.global_position = mouse_pos - drag_preview.size * 0.5
	drag_preview.modulate = Color.WHITE


## 显示吸附在网格中心的角色色块预览
func _show_unit_drag_preview(grid_pos: Vector2i) -> void:
	"""显示吸附在网格中心的角色色块预览"""
	if drag_preview_mode != "unit":
		_replace_drag_preview(_create_unit_preview())
		drag_preview_mode = "unit"

	var center := _grid_cell_to_screen(grid_pos)
	drag_preview.global_position = center - drag_preview.size * 0.5
	drag_preview.modulate = Color(1, 1, 1, 0.85) if _can_drop_drag_at(grid_pos) else Color(1, 0.35, 0.35, 0.75)


## 替换当前拖拽预览节点
func _replace_drag_preview(new_preview: Control) -> void:
	"""替换当前拖拽预览节点"""
	if drag_preview and is_instance_valid(drag_preview):
		drag_preview.queue_free()
	drag_preview = new_preview
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview.z_index = 4096
	_get_drag_preview_parent().add_child(drag_preview)


## 创建卡牌形态的拖拽预览
func _create_card_preview() -> Control:
	"""创建卡牌形态的拖拽预览"""
	var size := _get_card_preview_size()
	var card := PanelContainer.new()
	card.size = size
	card.custom_minimum_size = size

	var label := Label.new()
	label.size = size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)

	var ct := ClassDefinitions.get_template(drag_card_data["class_id"])
	label.text = "%s\n%d星 Lv.%d\nDP:%d" % [
		ct.job_name,
		int(drag_card_data.get("star_level", 1)),
		drag_card_data["level"],
		ct.deploy_cost
	]
	card.add_child(label)
	return card


## 创建战斗形象形态的拖拽预览（当前以色块占位）
func _create_unit_preview() -> Control:
	"""创建战斗形象形态的拖拽预览（当前以色块占位）"""
	var size := Vector2(48, 48)
	var root := Control.new()
	root.size = size
	root.custom_minimum_size = size

	var rect := ColorRect.new()
	rect.size = size
	rect.color = ClassDefinitions.get_template_color(str(drag_card_data.get("class_id", "fighter_champion")))
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	return root


## 获取拖拽预览挂载节点，优先放到UI画布上
func _get_drag_preview_parent() -> Node:
	"""获取拖拽预览挂载节点，优先放到UI画布上"""
	var tree := get_tree()
	if tree:
		var canvas := _find_node_by_name(tree.root, "UICanvas")
		if canvas:
			return canvas
	return get_tree().root


## 递归查找指定名称的节点
func _find_node_by_name(node: Node, target_name: String) -> Node:
	"""递归查找指定名称的节点"""
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found:
			return found
	return null


## 获取卡牌预览尺寸，默认与手牌卡牌一致
func _get_card_preview_size() -> Vector2:
	"""获取卡牌预览尺寸，默认与手牌卡牌一致"""
	var bar := _get_deployment_bar()
	if bar:
		return bar.card_size
	return Vector2(80, 100)


## 检查鼠标是否位于底部手牌区域
func _is_mouse_over_hand_area(mouse_pos: Vector2) -> bool:
	"""检查鼠标是否位于底部手牌区域"""
	var bar := _get_deployment_bar()
	return bar != null and bar.is_visible_in_tree() and bar.get_global_rect().has_point(mouse_pos)


## 获取手牌栏节点
func _get_deployment_bar() -> DeploymentBar:
	"""获取手牌栏节点"""
	var tree := get_tree()
	if not tree:
		return null
	var nodes := tree.get_nodes_in_group("deployment_bar")
	if nodes.size() > 0 and nodes[0] is DeploymentBar:
		return nodes[0] as DeploymentBar
	return null


## 获取鼠标所在网格坐标；不在网格内时返回null
func _get_mouse_grid_position():
	"""获取鼠标所在网格坐标；不在网格内时返回null"""
	if not grid:
		grid = BattleManager.grid
	if not grid:
		return null

	var local_pos := grid.get_local_mouse_position()
	var grid_rect := Rect2(
		grid.grid_offset,
		Vector2(grid.grid_width * grid.cell_size, grid.grid_height * grid.cell_size)
	)
	if not grid_rect.has_point(local_pos):
		return null
	return grid.world_to_grid(local_pos)


## 将网格中心点转换为屏幕坐标，用于UI预览定位
func _grid_cell_to_screen(grid_pos: Vector2i) -> Vector2:
	"""将网格中心点转换为屏幕坐标，用于UI预览定位"""
	var local_center := grid.grid_to_world(grid_pos)
	return grid.get_global_transform_with_canvas() * local_center
