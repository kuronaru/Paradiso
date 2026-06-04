# deployment_bar.gd — 底部部署卡牌栏
# 显示手牌，支持点击选中部署与按住/拖动部署
class_name DeploymentBar
extends Control

const M = "DeployBar"

signal card_clicked(card_index: int, class_id: String)

@export var card_size: Vector2 = Vector2(80, 100)
@export var spacing: float = 8.0
@export var bar_height: float = 120.0
@export var selected_raise_ratio: float = 0.25
@export var drag_hold_time: float = 0.18
@export var drag_distance_threshold: float = 16.0

var cards: Array = []                # 卡牌按钮节点
var card_base_positions: Array = []  # 卡牌未选中时的位置
var card_shades: Array = []          # DP不足时覆盖在卡牌上方的暗色遮罩
var card_labels: Array = []          # 卡牌文字节点，用于刷新DP进度
var deployment_system: DeploymentSystem = null

## 拖拽状态视觉提示
var drag_highlight_index: int = -1

## 鼠标按下后的待判定状态：短按为选中，长按/拖动为拖拽
var press_card_index: int = -1
var press_started_at_msec: int = 0
var press_start_mouse_pos: Vector2 = Vector2.ZERO
var press_started_drag: bool = false


func _ready() -> void:
	# 确保 Control 占据底部区域
	add_to_group("deployment_bar")
	_setup_layout()

	# 找到DeploymentSystem
	var tree := get_tree()
	if tree:
		var nodes := tree.get_nodes_in_group("deployment_system")
		if nodes.size() > 0:
			deployment_system = nodes[0]
			deployment_system.unit_selected.connect(_on_unit_selected)
			deployment_system.unit_deselected.connect(_on_unit_deselected)
			deployment_system.hand_updated.connect(_on_hand_updated)
			deployment_system.drag_ended.connect(_on_drag_ended)

	# DP变化也刷新按钮状态
	ResourceManager.dp_changed.connect(_on_dp_changed)
	_refresh_ui()


func _setup_layout() -> void:
	"""设置锚定在底部"""
	# 锚定到左下和右下
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	# 偏移：从底部向上 bar_height
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -bar_height
	offset_bottom = 0.0


func _refresh_ui() -> void:
	"""重建卡牌按钮"""
	# 清除旧的
	for card in cards:
		card.queue_free()
	cards.clear()
	card_base_positions.clear()
	card_shades.clear()
	card_labels.clear()
	drag_highlight_index = -1

	if not deployment_system:
		return

	var hand := deployment_system.hand_cards
	var start_x := 16.0
	var btn_y := 10.0  # 相对于 DeploymentBar 顶部偏移

	for i in range(hand.size()):
		var card_data = hand[i]
		var ct := ClassDefinitions.get_template(card_data["class_id"])
		var base_position := Vector2(start_x + i * (card_size.x + spacing), btn_y)

		var btn := Button.new()
		btn.size = card_size
		btn.clip_contents = true
		btn.position = base_position
		btn.flat = false

		# 遮罩从顶部向下覆盖卡牌；DP增加时高度变小，露出底部正常颜色
		var shade := ColorRect.new()
		shade.size = card_size
		shade.position = Vector2.ZERO
		shade.color = Color(0.05, 0.05, 0.06, 0.68)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.z_index = 1
		btn.add_child(shade)

		var label := Label.new()
		label.size = card_size
		label.text = _get_card_text(ct, card_data)
		label.add_theme_font_size_override("font_size", 11)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = 2
		btn.add_child(label)

		var idx := i
		# 左键短按为选中；按住一定时间或拖动一定距离后才开始拖拽
		btn.gui_input.connect(func(event: InputEvent): _on_card_gui_input(event, idx))

		add_child(btn)
		cards.append(btn)
		card_base_positions.append(base_position)
		card_shades.append(shade)
		card_labels.append(label)

	_update_button_states()


func _update_button_states() -> void:
	"""根据 DP、战斗状态和选中状态更新按钮表现"""
	if not deployment_system:
		return

	var can_deploy_now := deployment_system.can_deploy_now()
	var selected_index := deployment_system.selected_card_index

	for i in range(min(cards.size(), deployment_system.hand_cards.size())):
		var card_data = deployment_system.hand_cards[i]
		var ct := ClassDefinitions.get_template(card_data["class_id"])
		var deploy_cost := _get_deploy_cost(ct)
		var progress := _get_deploy_progress(deploy_cost) if can_deploy_now else 0.0
		var can_afford := ResourceManager.can_afford(deploy_cost)

		# 战斗阶段不可部署时禁用按钮；DP不足时仍允许点击选中，但不会开始拖拽
		cards[i].disabled = not can_deploy_now
		_update_card_progress_visual(i, progress, can_afford and can_deploy_now)
		_update_card_selection_visual(i, i == selected_index)

		# 高亮当前拖拽选中的卡
		if i == drag_highlight_index:
			cards[i].modulate = Color(1.3, 1.3, 0.6, 1.0)
		elif i == selected_index:
			cards[i].modulate = Color(1.18, 1.18, 1.05, 1.0)
		else:
			cards[i].modulate = Color.WHITE


func _update_card_selection_visual(index: int, is_selected: bool) -> void:
	"""更新选中卡牌的上提位置"""
	if index < 0 or index >= cards.size() or index >= card_base_positions.size():
		return

	var btn := cards[index] as Button
	var base_position: Vector2 = card_base_positions[index]
	var raise_height := card_size.y * selected_raise_ratio
	btn.position = base_position + Vector2(0.0, -raise_height if is_selected else 0.0)
	btn.z_index = 20 if is_selected else 0


func _get_card_text(ct: ClassTemplate, card_data: Dictionary) -> String:
	"""生成卡牌文字，包含部署DP进度"""
	var deploy_cost := _get_deploy_cost(ct)
	var current_dp: int = min(ResourceManager.current_dp, deploy_cost)
	var star_level: int = int(card_data.get("star_level", 1))
	return "%s\n%d星 Lv.%d\n%s\nDP:%d/%d" % [
		ct.job_name,
		star_level,
		card_data["level"],
		_get_synergy_line(ct),
		current_dp,
		deploy_cost
	]


func _get_deploy_cost(ct: ClassTemplate) -> int:
	if SynergyManager and SynergyManager.has_method("get_discounted_deploy_cost"):
		return SynergyManager.get_discounted_deploy_cost(ct.deploy_cost)
	return ct.deploy_cost


func _get_synergy_line(ct: ClassTemplate) -> String:
	var tags: Array[String] = []
	if ct.class_group != "":
		tags.append(_main_group_label(ct.class_group))
	for tag in ct.stat_tags:
		tags.append(str(tag))
	for tag in ct.alignment_tags:
		tags.append(_alignment_label(str(tag)))
	return " / ".join(tags)


func _main_group_label(class_group: String) -> String:
	match class_group:
		"fighter":
			return "战士"
		"ranger":
			return "游侠"
		"wizard":
			return "法师"
		"cleric":
			return "牧师"
		"rogue":
			return "游荡者"
	return class_group


func _alignment_label(tag: String) -> String:
	match tag:
		"LAWFUL":
			return "守序"
		"CHAOTIC":
			return "混沌"
		"GOOD":
			return "善良"
		"EVIL":
			return "邪恶"
		"NEUTRAL":
			return "中立"
	return tag


func _get_deploy_progress(deploy_cost: int) -> float:
	"""计算当前DP相对部署费用的进度"""
	if deploy_cost <= 0:
		return 1.0
	return clamp(float(ResourceManager.current_dp) / float(deploy_cost), 0.0, 1.0)


func _update_card_progress_visual(index: int, progress: float, can_afford: bool) -> void:
	"""更新单张手牌的暗色遮罩与文字状态"""
	if index < 0 or index >= card_shades.size():
		return
	if index >= card_labels.size() or index >= deployment_system.hand_cards.size():
		return

	var card_data = deployment_system.hand_cards[index]
	var ct := ClassDefinitions.get_template(card_data["class_id"])
	var shade := card_shades[index] as ColorRect
	var label := card_labels[index] as Label
	var shade_height := card_size.y * (1.0 - progress)

	shade.position = Vector2.ZERO
	shade.size = Vector2(card_size.x, shade_height)
	shade.visible = shade_height > 0.5
	shade.color = Color(0.05, 0.05, 0.06, 0.68) if not can_afford else Color(0.05, 0.05, 0.06, 0.0)

	label.size = card_size
	label.text = _get_card_text(ct, card_data)
	label.modulate = Color.WHITE if can_afford else Color(0.72, 0.72, 0.72, 1.0)


func _on_card_gui_input(event: InputEvent, index: int) -> void:
	"""处理单张卡牌上的鼠标输入"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_drag()
			_clear_pending_press()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin_card_press(index)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_card_press(index)
			accept_event()
	elif event is InputEventMouseMotion:
		_update_pending_drag(index)


func _begin_card_press(index: int) -> void:
	"""记录鼠标按下，暂不立即进入拖拽"""
	if not deployment_system or not deployment_system.can_deploy_now():
		return
	if index < 0 or index >= deployment_system.hand_cards.size():
		return

	press_card_index = index
	press_started_at_msec = Time.get_ticks_msec()
	press_start_mouse_pos = get_viewport().get_mouse_position()
	press_started_drag = false


func _finish_card_press(index: int) -> void:
	"""鼠标短按释放时选中卡牌；拖拽释放交给部署系统处理"""
	if press_card_index != index:
		_clear_pending_press()
		return
	if press_started_drag:
		_clear_pending_press()
		return

	_select_card(index)
	_clear_pending_press()


func _update_pending_drag(index: int) -> void:
	"""鼠标移动超过阈值时将短按判定切换为拖拽"""
	if press_card_index != index or press_started_drag:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_clear_pending_press()
		return

	var mouse_pos := get_viewport().get_mouse_position()
	if mouse_pos.distance_to(press_start_mouse_pos) >= drag_distance_threshold:
		_start_drag_from_press()


func _update_pending_hold() -> void:
	"""鼠标按住超过阈值时开始拖拽"""
	if press_card_index < 0 or press_started_drag:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_clear_pending_press()
		return

	var elapsed := float(Time.get_ticks_msec() - press_started_at_msec) / 1000.0
	if elapsed >= drag_hold_time:
		_start_drag_from_press()


func _start_drag_from_press() -> void:
	"""从待判定按压状态进入拖拽部署"""
	if not deployment_system:
		_clear_pending_press()
		return
	if press_card_index < 0 or press_card_index >= deployment_system.hand_cards.size():
		_clear_pending_press()
		return

	var class_id: String = deployment_system.hand_cards[press_card_index]["class_id"]
	if deployment_system.begin_drag(press_card_index):
		press_started_drag = true
		drag_highlight_index = -1
		_update_button_states()
		card_clicked.emit(press_card_index, class_id)


func _select_card(index: int) -> void:
	"""短按卡牌时高亮选中，并将卡牌向上提起"""
	if not deployment_system:
		return
	if index < 0 or index >= deployment_system.hand_cards.size():
		return

	var class_id: String = deployment_system.hand_cards[index]["class_id"]
	if deployment_system.select_card(index):
		drag_highlight_index = -1
		_update_button_states()
		card_clicked.emit(index, class_id)


func _clear_pending_press() -> void:
	"""清除鼠标按下待判定状态"""
	press_card_index = -1
	press_started_at_msec = 0
	press_start_mouse_pos = Vector2.ZERO
	press_started_drag = false


func _cancel_drag() -> void:
	"""取消当前拖拽或选中"""
	if deployment_system:
		deployment_system.cancel_drag()
		deployment_system.clear_selected_card()
	drag_highlight_index = -1
	_update_button_states()


func _on_hand_updated(_cards: Array) -> void:
	"""手牌变化时刷新"""
	_refresh_ui()


func _on_drag_ended() -> void:
	"""拖拽完成（成功或失败），清除高亮"""
	_clear_pending_press()
	drag_highlight_index = -1
	_update_button_states()


func _on_unit_selected(_unit: HeroUnit) -> void:
	_refresh_ui()


func _on_unit_deselected() -> void:
	_refresh_ui()


func _on_dp_changed(_current: int, _max_val: int) -> void:
	_update_button_states()


func _process(_delta: float) -> void:
	# 持续更新按钮状态（DP变化、状态变化）并检测长按拖拽
	_update_pending_hold()
	_update_button_states()
