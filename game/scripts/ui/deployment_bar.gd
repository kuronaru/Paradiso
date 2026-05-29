# deployment_bar.gd — 底部部署卡牌栏
# 显示手牌，支持点击进入拖拽部署模式
class_name DeploymentBar
extends Control

signal card_clicked(card_index: int, class_id: String)

@export var card_size: Vector2 = Vector2(80, 100)
@export var spacing: float = 8.0
@export var bar_height: float = 120.0

var cards: Array = []           # 卡牌按钮节点
var deployment_system: DeploymentSystem = null

## 拖拽状态视觉提示
var drag_highlight_index: int = -1


func _ready() -> void:
	# 确保 Control 占据底部区域
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
		btn.position = Vector2(start_x + i * (card_size.x + spacing), btn_y)
		btn.text = "%s\nDP:%d\nLv.%d" % [ct.job_name, ct.deploy_cost, card_data["level"]]
		btn.add_theme_font_size_override("font_size", 11)
		btn.flat = false

		var idx := i
		btn.pressed.connect(func(): _on_card_pressed(idx))
		# 右键取消拖拽
		btn.gui_input.connect(func(event: InputEvent): _on_card_gui_input(event, idx))

		add_child(btn)
		cards.append(btn)

	_update_button_states()


func _update_button_states() -> void:
	"""根据 DP 和战斗状态更新按钮可用性"""
	if not deployment_system:
		return

	# 允许在准备阶段、战斗中、波次间隙部署
	var can_deploy_now := BattleManager.state in [
		BattleManager.BattleState.PREPARING,
		BattleManager.BattleState.IN_PROGRESS,
		BattleManager.BattleState.WAVE_BREAK,
	]

	for i in range(min(cards.size(), deployment_system.hand_cards.size())):
		var card_data = deployment_system.hand_cards[i]
		var ct := ClassDefinitions.get_template(card_data["class_id"])
		cards[i].disabled = not (can_deploy_now and ResourceManager.can_afford(ct.deploy_cost))

		# 高亮当前拖拽选中的卡
		if i == drag_highlight_index:
			cards[i].modulate = Color(1.3, 1.3, 0.6, 1.0)
		else:
			cards[i].modulate = Color.WHITE


func _on_card_pressed(index: int) -> void:
	if not deployment_system:
		return
	var hand := deployment_system.hand_cards
	if index < 0 or index >= hand.size():
		return

	# 进入拖拽模式 / 或切换拖拽
	if deployment_system.is_dragging and deployment_system.drag_card_index == index:
		# 再次点击同一张卡：取消拖拽
		_cancel_drag()
	else:
		deployment_system.is_dragging = true
		deployment_system.drag_card_index = index
		drag_highlight_index = index
		_update_button_states()
		card_clicked.emit(index, hand[index]["class_id"])


func _on_card_gui_input(event: InputEvent, _index: int) -> void:
	"""右键取消拖拽"""
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag()


func _cancel_drag() -> void:
	if deployment_system:
		deployment_system.is_dragging = false
		deployment_system.drag_card_index = -1
	drag_highlight_index = -1
	_update_button_states()


func _on_hand_updated(_cards: Array) -> void:
	"""手牌变化时刷新"""
	_cancel_drag()
	_refresh_ui()


func _on_unit_selected(_unit: HeroUnit) -> void:
	_refresh_ui()


func _on_unit_deselected() -> void:
	_refresh_ui()


func _on_dp_changed(_current: int, _max_val: int) -> void:
	_update_button_states()


func _process(_delta: float) -> void:
	# 持续更新按钮状态（DP变化、状态变化）
	_update_button_states()

	# 拖拽状态未激活时重置高亮
	if deployment_system and not deployment_system.is_dragging and drag_highlight_index >= 0:
		drag_highlight_index = -1
		_update_button_states()
