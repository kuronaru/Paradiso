# deployment_system.gd — 部署系统
# 管理手牌、部署拖拽、选中单位控制
class_name DeploymentSystem
extends Node

signal unit_selected(unit: HeroUnit)
signal unit_deselected
signal drag_ended

var selected_unit: HeroUnit = null
var hand_cards: Array = []            # 手牌 [{class_id, level}]
var is_dragging: bool = false
var drag_card_index: int = -1
var drag_preview: Node = null

@onready var grid: GridSystem = null


func _ready() -> void:
	add_to_group("deployment_system")
	grid = BattleManager.grid
	if grid:
		grid.cell_clicked.connect(_on_cell_clicked)


signal hand_updated(cards: Array)

func setup_hand(party_data: Array) -> void:
	"""初始化手牌（从肉鸽队伍数据）"""
	hand_cards.clear()
	for member in party_data:
		hand_cards.append({"class_id": member["class_id"], "level": member["level"]})
	print("[Deployment] 手牌初始化: %d 张卡" % hand_cards.size())
	hand_updated.emit(hand_cards)


func can_deploy_card(class_id: String) -> bool:
	"""检查是否可以部署指定职业"""
	var ct := ClassDefinitions.get_template(class_id)
	return ResourceManager.can_afford(ct.deploy_cost)


func deploy_card(card_index: int, grid_pos: Vector2i) -> bool:
	"""部署手牌到网格"""
	if card_index < 0 or card_index >= hand_cards.size():
		return false
	if not grid:
		grid = BattleManager.grid
	if not grid:
		return false

	var card_data: Dictionary = hand_cards[card_index]
	var ct := ClassDefinitions.get_template(card_data["class_id"])

	if not ResourceManager.spend(ct.deploy_cost):
		print("[Deployment] DP不足，需要 %d" % ct.deploy_cost)
		return false

	if not grid.can_place_at(grid_pos):
		print("[Deployment] 无法部署到 (%d, %d)" % [grid_pos.x, grid_pos.y])
		ResourceManager.refund(ct.deploy_cost)
		return false

	var hero := HeroUnit.new()
	hero.setup(ct, card_data["level"])
	grid.place_unit(hero, grid_pos)

	hand_cards.remove_at(card_index)
	hand_updated.emit(hand_cards)
	print("[Deployment] 部署 %s 到 (%d, %d)" % [ct.job_name, grid_pos.x, grid_pos.y])
	return true


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


func _on_cell_clicked(grid_pos: Vector2i) -> void:
	"""网格点击处理"""
	if is_dragging:
		# 拖拽放置
		var deployed := false
		if drag_card_index >= 0:
			deployed = deploy_card(drag_card_index, grid_pos)
		is_dragging = false
		drag_card_index = -1
		if drag_preview:
			drag_preview.queue_free()
			drag_preview = null
		drag_ended.emit()
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


func toggle_selected_stance() -> void:
	if selected_unit and is_instance_valid(selected_unit):
		selected_unit.toggle_stance()


func use_selected_skill(skill_index: int) -> void:
	if selected_unit and is_instance_valid(selected_unit):
		var skills: Array = selected_unit.class_template.skill_ids
		if skill_index < skills.size():
			selected_unit.use_skill(skills[skill_index])


func retreat_selected() -> void:
	if selected_unit and is_instance_valid(selected_unit):
		selected_unit.retreat()
		# 把卡牌退回手牌
		if selected_unit.class_template:
			hand_cards.append({
				"class_id": selected_unit.class_template.class_id,
				"level": 1
			})
			hand_updated.emit(hand_cards)
		selected_unit = null
		unit_deselected.emit()
