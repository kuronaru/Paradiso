# deployment_bar.gd — 底部部署卡牌栏
# 显示手牌，支持点击选中部署与按住/拖动部署
class_name DeploymentBar
extends Control

const M = "DeployBar"
const SHOP_PANEL_HEIGHT := 112.0
const SHOP_BOTTOM_MARGIN := 8.0
const HAND_GAP_ABOVE_SHOP := 8.0
const LAYOUT_TWEEN_TIME := 0.22

signal card_clicked(card_index: int, class_id: String)

@export var card_size: Vector2 = Vector2(78, 88)
@export var spacing: float = 8.0
@export var bar_height: float = 100.0
@export var selected_raise_ratio: float = 0.25
@export var drag_hold_time: float = 0.18
@export var drag_distance_threshold: float = 16.0

var cards: Array = []                # 卡牌按钮节点
var card_base_positions: Array = []  # 卡牌未选中时的位置
var card_shades: Array = []          # DP不足时覆盖在卡牌上方的暗色遮罩
var card_labels: Array = []          # 卡牌文字节点，用于刷新DP进度
var card_slots: Array = []           # HBox中的卡牌槽位
var deployment_system: DeploymentSystem = null
var hand_center: CenterContainer = null
var hand_row: HBoxContainer = null

## 拖拽状态视觉提示
var drag_highlight_index: int = -1

## 鼠标按下后的待判定状态：短按为选中，长按/拖动为拖拽
var press_card_index: int = -1
var press_started_at_msec: int = 0
var press_start_mouse_pos: Vector2 = Vector2.ZERO
var press_started_drag: bool = false
var layout_tween: Tween = null
var last_prepare_layout: bool = true
var cached_viewport_size: Vector2 = Vector2.ZERO


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
	"""设置阶段感知的手牌栏布局"""
	cached_viewport_size = get_viewport_rect().size
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_right = cached_viewport_size.x
	offset_top = 0.0
	offset_bottom = 0.0
	size = Vector2(cached_viewport_size.x, bar_height)
	position = Vector2(0.0, _prepare_y())
	z_index = 80

	hand_center = CenterContainer.new()
	hand_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(hand_center)
	add_child(hand_center)

	hand_row = HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", int(spacing))
	hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_center.add_child(hand_row)


func _refresh_ui() -> void:
	"""重建卡牌按钮"""
	if hand_row:
		for child in hand_row.get_children():
			child.queue_free()
	cards.clear()
	card_base_positions.clear()
	card_shades.clear()
	card_labels.clear()
	card_slots.clear()
	drag_highlight_index = -1

	if not deployment_system or not hand_row:
		return

	var hand := deployment_system.hand_cards
	var raise_height := card_size.y * selected_raise_ratio

	for i in range(hand.size()):
		var card_data = hand[i]
		var ct := ClassDefinitions.get_template(card_data["class_id"])

		var slot := Control.new()
		slot.custom_minimum_size = Vector2(card_size.x, card_size.y + raise_height)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hand_row.add_child(slot)

		var btn := Button.new()
		btn.size = card_size
		btn.clip_contents = true
		btn.position = Vector2(0.0, raise_height)
		btn.flat = false
		_apply_card_style(btn, bool(card_data.get("is_golden", false)))

		var card_margin := MarginContainer.new()
		card_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fill_parent(card_margin)
		card_margin.add_theme_constant_override("margin_left", 6)
		card_margin.add_theme_constant_override("margin_top", 6)
		card_margin.add_theme_constant_override("margin_right", 6)
		card_margin.add_theme_constant_override("margin_bottom", 6)
		btn.add_child(card_margin)

		var card_stack := VBoxContainer.new()
		card_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_stack.add_theme_constant_override("separation", 4)
		card_margin.add_child(card_stack)

		var icon_center := CenterContainer.new()
		icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_stack.add_child(icon_center)

		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(44, 38)
		icon.color = _get_class_icon_color(card_data["class_id"])
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_center.add_child(icon)

		var label := Label.new()
		label.custom_minimum_size = Vector2(0, 32)
		label.text = _get_card_text(ct, card_data)
		label.add_theme_font_size_override("font_size", 11)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_stack.add_child(label)

		# 遮罩从顶部向下覆盖卡牌；DP增加时高度变小，露出底部正常颜色
		var shade := ColorRect.new()
		shade.size = card_size
		shade.position = Vector2.ZERO
		shade.color = Color(0.05, 0.05, 0.06, 0.68)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.z_index = 4
		btn.add_child(shade)

		var idx := i
		# 左键短按为选中；按住一定时间或拖动一定距离后才开始拖拽
		btn.gui_input.connect(func(event: InputEvent): _on_card_gui_input(event, idx))

		slot.add_child(btn)
		cards.append(btn)
		card_base_positions.append(Vector2(0.0, raise_height))
		card_shades.append(shade)
		card_labels.append(label)
		card_slots.append(slot)

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


func _apply_card_style(btn: Button, is_golden: bool) -> void:
	var base_color := Color(0.11, 0.12, 0.16, 0.96)
	var border_color := Color(0.28, 0.32, 0.42, 1.0)
	if is_golden:
		base_color = Color(0.72, 0.52, 0.12, 0.98)
		border_color = Color(1.0, 0.83, 0.28, 1.0)

	var normal := _make_card_style(base_color, border_color)
	var hover := _make_card_style(base_color.lightened(0.08), border_color.lightened(0.08))
	var pressed := _make_card_style(base_color.darkened(0.08), border_color)
	var disabled := _make_card_style(base_color.darkened(0.25), border_color.darkened(0.25))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)


func _make_card_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


func _get_class_icon_color(class_id: String) -> Color:
	match class_id:
		"warrior":
			return Color(0.78, 0.24, 0.20, 1.0)
		"ranger":
			return Color(0.22, 0.58, 0.28, 1.0)
		"mage":
			return Color(0.35, 0.34, 0.86, 1.0)
		"priest":
			return Color(0.88, 0.82, 0.42, 1.0)
		"rogue":
			return Color(0.48, 0.30, 0.62, 1.0)
	return Color(0.48, 0.52, 0.58, 1.0)


func _get_card_text(ct: ClassTemplate, card_data: Dictionary) -> String:
	"""生成简化手牌文字。"""
	var shop_level := int(card_data.get("shop_level", card_data.get("star_level", 1)))
	return "%s\n等阶 %d" % [
		ct.job_name,
		shop_level
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
	_update_stage_layout()
	_update_pending_hold()
	_update_button_states()


func _update_stage_layout() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size != cached_viewport_size:
		cached_viewport_size = viewport_size
		size = Vector2(viewport_size.x, bar_height)
		offset_right = viewport_size.x
		_refresh_ui()
		_apply_stage_layout(false)

	var wants_prepare := _is_prepare_layout()
	if wants_prepare != last_prepare_layout:
		last_prepare_layout = wants_prepare
		_apply_stage_layout(true)


func _is_prepare_layout() -> bool:
	return GameManager.is_roguelike_run and BattleManager.state == BattleManager.BattleState.PREPARING


func _apply_stage_layout(animated: bool) -> void:
	var target_y := _prepare_y() if _is_prepare_layout() else _battle_y()
	if layout_tween and layout_tween.is_valid():
		layout_tween.kill()
	if animated and is_inside_tree():
		layout_tween = create_tween()
		layout_tween.tween_property(self, "position:y", target_y, LAYOUT_TWEEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		position.y = target_y


func _prepare_y() -> float:
	return get_viewport_rect().size.y - SHOP_PANEL_HEIGHT - SHOP_BOTTOM_MARGIN - bar_height - HAND_GAP_ABOVE_SHOP


func _battle_y() -> float:
	return get_viewport_rect().size.y - SHOP_PANEL_HEIGHT - SHOP_BOTTOM_MARGIN + (SHOP_PANEL_HEIGHT - bar_height) * 0.5


func _fill_parent(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
