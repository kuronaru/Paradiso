# deployment_bar.gd — 战场延伸备战区
# 在透视备战槽位显示英雄战斗形象，使用按住拖动部署与右键出售交互
class_name DeploymentBar
extends Control

const TraitTextFormatterScript = preload("res://scripts/ui/auto_trait_text_formatter.gd")

const M = "DeployBar"
const SHOP_PANEL_HEIGHT := 136.0
const SHOP_BOTTOM_MARGIN := 8.0
const HAND_GAP_ABOVE_SHOP := 8.0
const LAYOUT_TWEEN_TIME := 0.22

signal card_clicked(card_index: int, class_id: String)

@export var card_size: Vector2 = Vector2(68, 74)
@export var spacing: float = 8.0
@export var bar_height: float = 96.0
@export var selected_raise_ratio: float = 0.25
@export var drag_gesture_time: float = 0.3
@export var drag_distance_threshold: float = 4.0

var cards: Array = []                # 卡牌按钮节点
var card_base_positions: Array = []  # 卡牌未选中时的位置
var card_slots: Array = []           # HBox中的卡牌槽位
var card_visuals: Array = []         # 处于备战状态的 UnitBase 展示实例
var deployment_system: DeploymentSystem = null
var hand_center: CenterContainer = null
var hand_row: Control = null

## 拖拽状态视觉提示
var drag_highlight_index: int = -1

## 鼠标按压手势状态：识别窗口内必须发生位移才进入拖拽。
var press_card_index: int = -1
var press_started_at_msec: int = 0
var press_start_mouse_pos: Vector2 = Vector2.ZERO
var press_started_drag: bool = false
var layout_tween: Tween = null
var last_prepare_layout: bool = true
var cached_viewport_size: Vector2 = Vector2.ZERO


## 初始化节点状态并连接必要依赖。
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


## 设置阶段感知的手牌栏布局
func _setup_layout() -> void:
	"""设置阶段感知的手牌栏布局"""
	cached_viewport_size = get_viewport_rect().size
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80

	hand_row = Control.new()
	hand_row.name = "ReserveHeroSlots"
	hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(hand_row)
	add_child(hand_row)

## 重建卡牌按钮
func _refresh_ui() -> void:
	"""重建卡牌按钮"""
	if hand_row:
		for child in hand_row.get_children():
			child.queue_free()
	cards.clear()
	card_base_positions.clear()
	card_slots.clear()
	card_visuals.clear()
	drag_highlight_index = -1

	if not deployment_system or not hand_row:
		return

	var hand := deployment_system.hand_cards
	for i in range(hand.size()):
		var card_data = hand[i]
		var ct := ClassDefinitions.get_template(card_data["class_id"])

		var slot := Control.new()
		slot.name = "ReserveSlot%d" % i
		slot.size = card_size
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hand_row.add_child(slot)

		var btn := Button.new()
		btn.size = card_size
		btn.clip_contents = false
		btn.position = Vector2.ZERO
		btn.flat = false
		_apply_reserve_hero_style(btn, bool(card_data.get("is_golden", false)))
		var trait_description: String = TraitTextFormatterScript.format_trait_list(
			ct.auto_trait_ids,
			ct.class_id,
			int(card_data.get("star_level", 1)),
			false,
			ct.autochess_synergy_ids
		)
		btn.tooltip_text = "%s\n按住左键拖拽部署；备战阶段右键出售（%d金币）" % [
			"特质：%s" % trait_description,
			1,
		]

		_add_battle_hero_visual(btn, ct, card_data)

		var idx := i
		# 按住左键立即进入拖拽，不再保留点击选卡部署。
		btn.gui_input.connect(func(event: InputEvent): _on_card_gui_input(event, idx))

		slot.add_child(btn)
		cards.append(btn)
		card_base_positions.append(Vector2.ZERO)
		card_slots.append(slot)

	_layout_reserve_slots()
	_update_button_states()


## 根据 DP、战斗状态和选中状态更新按钮表现
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
		var ignores_dp := BattleManager.state == BattleManager.BattleState.PREPARING
		var progress := 1.0 if ignores_dp else (_get_deploy_progress(deploy_cost) if can_deploy_now else 0.0)
		var can_afford := true if ignores_dp else ResourceManager.can_afford(deploy_cost)

		# 战斗阶段不可部署时禁用按钮；DP不足时仍允许拖拽，落点时再失败并退回。
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


## 更新选中卡牌的上提位置
func _update_card_selection_visual(index: int, is_selected: bool) -> void:
	"""更新选中卡牌的上提位置"""
	if index < 0 or index >= cards.size() or index >= card_base_positions.size():
		return

	var btn := cards[index] as Button
	var base_position: Vector2 = card_base_positions[index]
	btn.position = base_position
	btn.z_index = 20 if is_selected else 0


## 使用 UnitBase 的完整战斗外观，但进入备战状态，不运行 AI、碰撞或战斗逻辑。
func _add_battle_hero_visual(parent: Control, ct: ClassTemplate, card_data: Dictionary) -> void:
	var preview := UnitBase.new()
	preview.name = "BattleHeroVisual"
	preview.position = card_size * 0.5
	preview.team = "player"
	preview.unit_name = ""
	preview.visual_id = ct.visual_id
	preview.color = _get_class_icon_color(ct.class_id)
	preview.show_body_debug_ring = false
	preview.show_collision_debug_ring = false
	preview.show_attack_range_debug_ring = false
	parent.add_child(preview)
	preview.setup(ct, int(card_data.get("level", 1)))
	preview.set_meta("class_id", ct.class_id)
	preview.set_meta("star_level", int(card_data.get("star_level", 1)))
	preview.set_meta("equipment_ids", (card_data.get("equipment_ids", []) as Array).duplicate())
	preview.enter_reserve_preview_state(_reserve_grid_cell_size())
	card_visuals.append(preview)


## 与 HeroUnit.sync_geometry_to_grid 保持同一个 0.4 格本体半径和参考倍率。
func _sync_battle_hero_visual_scale(preview: UnitBase, grid: GridSystem) -> void:
	if not preview or not grid:
		return
	preview.sync_reserve_preview_geometry(grid.cell_size)


func _reserve_grid_cell_size() -> float:
	var grid := BattleManager.grid as GridSystem
	return grid.cell_size if grid else 64.0


func _apply_reserve_hero_style(btn: Button, _is_golden: bool) -> void:
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())


## 应用卡牌样式。
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


## 生成卡牌样式。
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


## 获取职业图标color。
func _get_class_icon_color(class_id: String) -> Color:
	return ClassDefinitions.get_template_color(class_id)


## 生成简化手牌文字。
func _get_card_text(ct: ClassTemplate, card_data: Dictionary) -> String:
	"""生成简化手牌文字。"""
	var star_level := int(card_data.get("star_level", 1))
	return "%s\n%d星 T%d\n%s" % [
		ct.job_name,
		star_level,
		ct.trait_tier,
		_get_synergy_short_line(ct),
	]


## 获取deploy消耗。
func _get_deploy_cost(ct: ClassTemplate) -> int:
	if SynergyManager and SynergyManager.has_method("get_discounted_deploy_cost"):
		return SynergyManager.get_discounted_deploy_cost(ct.deploy_cost)
	return ct.deploy_cost


## 获取羁绊文本行。
func _get_synergy_line(ct: ClassTemplate) -> String:
	var tags: Array[String] = []
	if not ct.autochess_synergy_ids.is_empty():
		for synergy_id in ct.autochess_synergy_ids:
			var synergy_data := DataRegistry.get_synergy(synergy_id)
			tags.append(str(synergy_data.get("display_name", synergy_id)))
		return " / ".join(tags)
	if ct.class_group != "":
		tags.append(_main_group_label(ct.class_group))
	for tag in ct.stat_tags:
		tags.append(str(tag))
	for tag in ct.alignment_tags:
		tags.append(_alignment_label(str(tag)))
	return " / ".join(tags)


func _get_synergy_short_line(ct: ClassTemplate) -> String:
	var tags: Array[String] = []
	for synergy_id in ct.autochess_synergy_ids:
		var synergy_data := DataRegistry.get_synergy(synergy_id)
		tags.append(str(synergy_data.get("short_name", synergy_data.get("display_name", synergy_id))))
	return " / ".join(tags)


## 处理main分组标签逻辑。
func _main_group_label(class_group: String) -> String:
	return ClassDefinitions.get_class_group_label(class_group)


## 处理阵营标签逻辑。
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


## 计算当前DP相对部署费用的进度
func _get_deploy_progress(deploy_cost: int) -> float:
	"""计算当前DP相对部署费用的进度"""
	if deploy_cost <= 0:
		return 1.0
	return clamp(float(ResourceManager.current_dp) / float(deploy_cost), 0.0, 1.0)


## 更新单张手牌的暗色遮罩与文字状态
func _update_card_progress_visual(index: int, progress: float, can_afford: bool) -> void:
	"""更新单张手牌的暗色遮罩与文字状态"""
	if index < 0 or index >= card_visuals.size():
		return
	var preview := card_visuals[index] as UnitBase
	if preview:
		var brightness := 1.0 if can_afford else lerpf(0.45, 0.72, progress)
		preview.modulate = Color(brightness, brightness, brightness, 1.0)


## 处理单张卡牌上的鼠标输入
func _on_card_gui_input(event: InputEvent, index: int) -> void:
	"""处理单张卡牌上的鼠标输入"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_drag()
			_clear_pending_press()
			if deployment_system and deployment_system.sell_hand_card(index):
				_refresh_ui()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin_card_press(index)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_card_press(index)
			accept_event()
	elif event is InputEventMouseMotion:
		_update_pending_drag(get_viewport().get_mouse_position(), Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))


## 按下备战英雄后开启 0.3 秒“位移即拖拽”识别窗口。
func _begin_card_press(index: int) -> void:
	"""按下备战英雄后开启拖拽手势识别窗口。"""
	if not deployment_system or not deployment_system.can_deploy_now():
		return
	if index < 0 or index >= deployment_system.hand_cards.size():
		return

	press_card_index = index
	press_started_at_msec = Time.get_ticks_msec()
	press_start_mouse_pos = get_viewport().get_mouse_position()
	press_started_drag = false


## 拖拽释放由 DeploymentSystem 的全局输入处理。
func _finish_card_press(index: int) -> void:
	"""拖拽释放由 DeploymentSystem 的全局输入处理。"""
	if press_card_index != index:
		_clear_pending_press()
		return
	if not press_started_drag and index >= 0 and index < card_visuals.size():
		var preview := card_visuals[index] as UnitBase
		if preview:
			preview._show_unit_info()
	_clear_pending_press()


## 0.3 秒识别窗口内必须发生明确位移；静止长按仍按单击处理。
func _update_pending_drag(mouse_position: Vector2, left_button_pressed: bool = true) -> void:
	if press_card_index < 0 or press_started_drag:
		return
	if not left_button_pressed:
		return
	var elapsed := float(Time.get_ticks_msec() - press_started_at_msec) / 1000.0
	if elapsed > drag_gesture_time:
		return
	if mouse_position.distance_to(press_start_mouse_pos) < drag_distance_threshold:
		return
	_start_drag_from_press()


## 从待判定按压状态进入拖拽部署
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


## 清除鼠标按下待判定状态
func _clear_pending_press() -> void:
	"""清除鼠标按下待判定状态"""
	press_card_index = -1
	press_started_at_msec = 0
	press_start_mouse_pos = Vector2.ZERO
	press_started_drag = false


## 取消当前拖拽或选中
func _cancel_drag() -> void:
	"""取消当前拖拽或选中"""
	if deployment_system:
		deployment_system.cancel_drag()
		deployment_system.clear_selected_card()
	drag_highlight_index = -1
	_update_button_states()


## 手牌变化时刷新
func _on_hand_updated(_cards: Array) -> void:
	"""手牌变化时刷新"""
	_refresh_ui()


## 拖拽完成（成功或失败），清除高亮
func _on_drag_ended() -> void:
	"""拖拽完成（成功或失败），清除高亮"""
	_clear_pending_press()
	drag_highlight_index = -1
	_update_button_states()


## 处理单位选中回调。
func _on_unit_selected(_unit: HeroUnit) -> void:
	_refresh_ui()


## 处理单位取消选中回调。
func _on_unit_deselected() -> void:
	_refresh_ui()


## 处理部署点变化回调。
func _on_dp_changed(_current: int, _max_val: int) -> void:
	_update_button_states()


## 每帧更新运行状态。
func _process(_delta: float) -> void:
	# 持续更新按钮状态和阶段布局；拖拽由实际鼠标位移事件触发。
	_update_stage_layout()
	_update_button_states()


## 更新阶段布局。
func _update_stage_layout() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size != cached_viewport_size:
		cached_viewport_size = viewport_size
		_refresh_ui()
		_apply_stage_layout(false)

	var wants_prepare := _is_prepare_layout()
	if wants_prepare != last_prepare_layout:
		last_prepare_layout = wants_prepare
		_apply_stage_layout(true)
	_layout_reserve_slots()


## 判断布局状态。
func _is_prepare_layout() -> bool:
	return GameManager.is_roguelike_run and BattleManager.state == BattleManager.BattleState.PREPARING


## 应用阶段布局。
func _apply_stage_layout(animated: bool) -> void:
	if layout_tween and layout_tween.is_valid():
		layout_tween.kill()
	position = Vector2.ZERO
	_layout_reserve_slots()


## 将每个英雄 UI 对齐到 GridSystem 的透视备战槽位。
func _layout_reserve_slots() -> void:
	var grid := BattleManager.grid as GridSystem
	if not grid or not hand_row:
		return
	var slot_count := maxi(grid.reserve_slot_count, maxi(card_slots.size(), GameManager.get_roguelike_max_hand_cards()))
	if grid.reserve_slot_count != slot_count:
		grid.set_reserve_slot_count(slot_count, false)
	for index in range(card_slots.size()):
		var slot := card_slots[index] as Control
		if not slot:
			continue
		var local_center := grid.reserve_slot_to_world(index, slot_count)
		var screen_center := grid.get_global_transform_with_canvas() * local_center
		slot.position = screen_center - card_size * 0.5
		if index < card_visuals.size():
			var preview := card_visuals[index] as UnitBase
			_sync_battle_hero_visual_scale(preview, grid)
			var local_anchor := grid.reserve_slot_visual_anchor(index, slot_count)
			var screen_anchor := grid.get_global_transform_with_canvas() * local_anchor
			preview.set_billboard_screen_offset(screen_anchor - screen_center)


## 拖拽预览用：检测鼠标是否位于透视备战延伸区。
func is_point_over_reserve_area(screen_point: Vector2) -> bool:
	var grid := BattleManager.grid as GridSystem
	if not grid:
		return false
	var local_point := grid.get_global_transform_with_canvas().affine_inverse() * screen_point
	return grid.is_world_point_inside_reserve(local_point)


## 准备Y 坐标。
func _prepare_y() -> float:
	return 0.0


## 处理战斗Y 坐标逻辑。
func _battle_y() -> float:
	return 0.0


## 处理fill父节点逻辑。
func _fill_parent(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
