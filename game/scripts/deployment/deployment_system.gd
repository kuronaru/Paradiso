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


func _ready() -> void:
	add_to_group("deployment_system")
	grid = BattleManager.grid
	if grid:
		grid.cell_clicked.connect(_on_cell_clicked)


func _process(_delta: float) -> void:
	"""拖拽中持续刷新预览位置"""
	if is_dragging:
		_update_drag_preview()


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


func setup_hand(party_data: Array) -> void:
	"""初始化手牌（从肉鸽队伍数据）"""
	hand_cards.clear()
	for member in party_data:
		hand_cards.append({"class_id": member["class_id"], "level": member["level"]})
	Log.i(M, "手牌初始化: %d 张卡" % hand_cards.size())
	hand_updated.emit(hand_cards)


func can_deploy_card(class_id: String) -> bool:
	"""检查是否可以部署指定职业"""
	var ct := ClassDefinitions.get_template(class_id)
	return ResourceManager.can_afford(ct.deploy_cost)


func can_deploy_now() -> bool:
	"""检查当前战斗阶段是否允许部署"""
	return BattleManager.state in [
		BattleManager.BattleState.PREPARING,
		BattleManager.BattleState.IN_PROGRESS,
		BattleManager.BattleState.WAVE_BREAK,
	]


func begin_drag(card_index: int) -> bool:
	"""开始拖拽手牌，将卡牌从手牌队列中临时移除"""
	if card_index < 0 or card_index >= hand_cards.size():
		return false
	if not can_deploy_now():
		return false

	if is_dragging:
		cancel_drag()

	var card_data: Dictionary = hand_cards[card_index]
	if not can_deploy_card(card_data["class_id"]):
		return false

	drag_card_data = card_data.duplicate(true)
	drag_original_index = card_index
	drag_card_index = card_index
	is_dragging = true
	drag_over_grid = false
	drag_preview_mode = ""

	# 拖拽期间手牌栏不显示这张卡；取消或部署失败时再插回原位置
	hand_cards.remove_at(card_index)
	hand_updated.emit(hand_cards)
	_update_drag_preview()
	return true


func cancel_drag() -> void:
	"""取消拖拽，将卡牌放回原来的手牌位置"""
	if not is_dragging:
		return
	_restore_dragged_card()
	_clear_drag_state()
	drag_ended.emit()


func deploy_card(card_index: int, grid_pos: Vector2i) -> bool:
	"""部署手牌到网格"""
	if card_index < 0 or card_index >= hand_cards.size():
		return false

	var card_data: Dictionary = hand_cards[card_index]
	if not _deploy_card_data(card_data, grid_pos):
		return false

	hand_cards.remove_at(card_index)
	hand_updated.emit(hand_cards)
	return true


func _deploy_card_data(card_data: Dictionary, grid_pos: Vector2i) -> bool:
	"""根据卡牌数据创建角色并放置到网格"""
	if not grid:
		grid = BattleManager.grid
	if not grid:
		return false
	if not card_data.has("class_id") or not card_data.has("level"):
		return false

	var ct := ClassDefinitions.get_template(card_data["class_id"])

	if not grid.can_place_at(grid_pos):
		Log.w(M, "无法部署到 (%d, %d)" % [grid_pos.x, grid_pos.y])
		return false

	if not ResourceManager.spend(ct.deploy_cost):
		Log.w(M, "DP不足，需要 %d" % ct.deploy_cost)
		return false

	var hero := HeroUnit.new()
	hero.setup(ct, card_data["level"])
	if not grid.place_unit(hero, grid_pos):
		ResourceManager.refund(ct.deploy_cost)
		BattleManager.unregister_player_unit(hero)
		hero.queue_free()
		return false

	Log.i(M, "部署 %s 到 (%d, %d)" % [ct.job_name, grid_pos.x, grid_pos.y])
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
		_finish_drag_at(grid_pos)
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


func _finish_drag() -> void:
	"""根据鼠标当前位置完成拖拽：网格内部署，手牌区或其他区域取消"""
	if drag_over_grid:
		_finish_drag_at(drag_grid_pos)
	else:
		cancel_drag()


func _finish_drag_at(grid_pos: Vector2i) -> void:
	"""在指定网格位置结束拖拽并尝试部署"""
	if not is_dragging:
		return

	var deployed := _deploy_card_data(drag_card_data, grid_pos)
	if not deployed:
		_restore_dragged_card()
	_clear_drag_state()
	drag_ended.emit()


func _restore_dragged_card() -> void:
	"""将正在拖拽的卡牌恢复到原手牌位置"""
	if drag_card_data.is_empty():
		return

	var restore_index := clampi(drag_original_index, 0, hand_cards.size())
	hand_cards.insert(restore_index, drag_card_data.duplicate(true))
	hand_updated.emit(hand_cards)


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


func _show_card_drag_preview(mouse_pos: Vector2) -> void:
	"""显示跟随鼠标移动的卡牌预览"""
	if drag_preview_mode != "card":
		_replace_drag_preview(_create_card_preview())
		drag_preview_mode = "card"
	drag_preview.global_position = mouse_pos - drag_preview.size * 0.5
	drag_preview.modulate = Color.WHITE


func _show_unit_drag_preview(grid_pos: Vector2i) -> void:
	"""显示吸附在网格中心的角色色块预览"""
	if drag_preview_mode != "unit":
		_replace_drag_preview(_create_unit_preview())
		drag_preview_mode = "unit"

	var center := _grid_cell_to_screen(grid_pos)
	drag_preview.global_position = center - drag_preview.size * 0.5
	drag_preview.modulate = Color(1, 1, 1, 0.85) if grid.can_place_at(grid_pos) else Color(1, 0.35, 0.35, 0.75)


func _replace_drag_preview(new_preview: Control) -> void:
	"""替换当前拖拽预览节点"""
	if drag_preview and is_instance_valid(drag_preview):
		drag_preview.queue_free()
	drag_preview = new_preview
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview.z_index = 4096
	_get_drag_preview_parent().add_child(drag_preview)


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
	label.text = "%s\nDP:%d\nLv.%d" % [ct.job_name, ct.deploy_cost, drag_card_data["level"]]
	card.add_child(label)
	return card


func _create_unit_preview() -> Control:
	"""创建战斗形象形态的拖拽预览（当前以色块占位）"""
	var size := Vector2(48, 48)
	var root := Control.new()
	root.size = size
	root.custom_minimum_size = size

	var rect := ColorRect.new()
	rect.size = size
	rect.color = Color(0.3, 0.6, 1.0, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	return root


func _get_drag_preview_parent() -> Node:
	"""获取拖拽预览挂载节点，优先放到UI画布上"""
	var tree := get_tree()
	if tree:
		var canvas := _find_node_by_name(tree.root, "UICanvas")
		if canvas:
			return canvas
	return get_tree().root


func _find_node_by_name(node: Node, target_name: String) -> Node:
	"""递归查找指定名称的节点"""
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found:
			return found
	return null


func _get_card_preview_size() -> Vector2:
	"""获取卡牌预览尺寸，默认与手牌卡牌一致"""
	var bar := _get_deployment_bar()
	if bar:
		return bar.card_size
	return Vector2(80, 100)


func _is_mouse_over_hand_area(mouse_pos: Vector2) -> bool:
	"""检查鼠标是否位于底部手牌区域"""
	var bar := _get_deployment_bar()
	return bar != null and bar.is_visible_in_tree() and bar.get_global_rect().has_point(mouse_pos)


func _get_deployment_bar() -> DeploymentBar:
	"""获取手牌栏节点"""
	var tree := get_tree()
	if not tree:
		return null
	var nodes := tree.get_nodes_in_group("deployment_bar")
	if nodes.size() > 0 and nodes[0] is DeploymentBar:
		return nodes[0] as DeploymentBar
	return null


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


func _grid_cell_to_screen(grid_pos: Vector2i) -> Vector2:
	"""将网格中心点转换为屏幕坐标，用于UI预览定位"""
	var local_center := grid.grid_to_world(grid_pos)
	return grid.get_global_transform_with_canvas() * local_center
