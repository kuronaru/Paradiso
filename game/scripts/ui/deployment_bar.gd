# deployment_bar.gd — 底部部署卡牌栏
# 显示手牌，支持按住左键拖拽部署
class_name DeploymentBar
extends Control

const M = "DeployBar"

signal card_clicked(card_index: int, class_id: String)

@export var card_size: Vector2 = Vector2(80, 100)
@export var spacing: float = 8.0
@export var bar_height: float = 120.0

var cards: Array = []           # 卡牌按钮节点
var card_shades: Array = []     # DP不足时覆盖在卡牌上方的暗色遮罩
var card_labels: Array = []     # 卡牌文字节点，用于刷新DP进度
var deployment_system: DeploymentSystem = null

## 拖拽状态视觉提示
var drag_highlight_index: int = -1


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

		var btn := Button.new()
		btn.size = card_size
		btn.clip_contents = true
		btn.position = Vector2(start_x + i * (card_size.x + spacing), btn_y)
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
		# 按下左键即开始拖拽；真正部署在 DeploymentSystem 中处理
		btn.button_down.connect(func(): _on_card_drag_started(idx))
		# 右键取消拖拽
		btn.gui_input.connect(func(event: InputEvent): _on_card_gui_input(event))

		add_child(btn)
		cards.append(btn)
		card_shades.append(shade)
		card_labels.append(label)

	_update_button_states()


func _update_button_states() -> void:
	"""根据 DP 和战斗状态更新按钮可用性"""
	if not deployment_system:
		return

	var can_deploy_now := deployment_system.can_deploy_now()

	for i in range(min(cards.size(), deployment_system.hand_cards.size())):
		var card_data = deployment_system.hand_cards[i]
		var ct := ClassDefinitions.get_template(card_data["class_id"])
		var progress := _get_deploy_progress(ct.deploy_cost) if can_deploy_now else 0.0
		var can_afford := ResourceManager.can_afford(ct.deploy_cost)

		# 战斗阶段不可部署时禁用按钮；DP不足时仍允许点击反馈，但不会开始拖拽
		cards[i].disabled = not can_deploy_now
		_update_card_progress_visual(i, progress, can_afford and can_deploy_now)

		# 高亮当前拖拽选中的卡
		if i == drag_highlight_index:
			cards[i].modulate = Color(1.3, 1.3, 0.6, 1.0)
		else:
			cards[i].modulate = Color.WHITE


func _get_card_text(ct: ClassTemplate, card_data: Dictionary) -> String:
	"""生成卡牌文字，包含部署DP进度"""
	var current_dp: int = min(ResourceManager.current_dp, ct.deploy_cost)
	return "%s\nDP:%d/%d\nLv.%d" % [ct.job_name, current_dp, ct.deploy_cost, card_data["level"]]


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


func _on_card_drag_started(index: int) -> void:
	"""左键按下卡牌时开始拖拽部署"""
	if not deployment_system:
		return
	var hand := deployment_system.hand_cards
	if index < 0 or index >= hand.size():
		return

	var class_id: String = hand[index]["class_id"]
	if deployment_system.begin_drag(index):
		drag_highlight_index = -1
		_update_button_states()
		card_clicked.emit(index, class_id)


func _on_card_gui_input(event: InputEvent) -> void:
	"""右键取消拖拽"""
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag()


func _cancel_drag() -> void:
	"""取消当前拖拽"""
	if deployment_system:
		deployment_system.cancel_drag()
	drag_highlight_index = -1
	_update_button_states()


func _on_hand_updated(_cards: Array) -> void:
	"""手牌变化时刷新"""
	_refresh_ui()


func _on_drag_ended() -> void:
	"""拖拽完成（成功或失败），清除高亮"""
	drag_highlight_index = -1
	_update_button_states()


func _on_unit_selected(_unit: HeroUnit) -> void:
	_refresh_ui()


func _on_unit_deselected() -> void:
	_refresh_ui()


func _on_dp_changed(_current: int, _max_val: int) -> void:
	_update_button_states()


func _process(_delta: float) -> void:
	# 持续更新按钮状态（DP变化、状态变化）
	_update_button_states()
