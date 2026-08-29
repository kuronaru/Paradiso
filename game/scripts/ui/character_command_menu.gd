# character_command_menu.gd — 英雄近身交互菜单
# 单击战场英雄后，在角色头顶附近显示出售与撤退两个方形按钮。
class_name CharacterCommandMenu
extends Control

const M = "CharacterMenu"

@export var button_size: Vector2 = Vector2(46, 46)
@export var button_gap: float = 6.0
@export var unit_head_gap: float = 6.0

var deployment_system: DeploymentSystem = null
var selected_unit: HeroUnit = null
var was_paused_before_open: bool = false

var menu_panel: Control = null
var sell_button: Button = null
var retreat_button: Button = null


## 初始化角色菜单并连接部署系统
func _ready() -> void:
	"""初始化角色菜单并连接部署系统"""
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 90
	_set_full_rect()
	_build_menu()
	visible = false

	var nodes := get_tree().get_nodes_in_group("deployment_system")
	if nodes.size() > 0:
		deployment_system = nodes[0]
		deployment_system.unit_selected.connect(_on_unit_selected)
		deployment_system.unit_deselected.connect(_on_unit_deselected)


## 让菜单覆盖整个窗口，用于接收菜单外点击
func _set_full_rect() -> void:
	"""让菜单覆盖整个窗口，用于接收菜单外点击"""
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP


## 创建角色头顶的两个紧凑方形按钮。
func _build_menu() -> void:
	"""创建角色头顶的两个紧凑方形按钮。"""
	menu_panel = Control.new()
	menu_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(menu_panel)

	sell_button = _create_corner_button("出售", _on_sell_pressed)
	retreat_button = _create_corner_button("撤退", _on_retreat_pressed)
	menu_panel.add_child(sell_button)
	menu_panel.add_child(retreat_button)

	_layout_menu()


## 创建菜单四角的方形按钮
func _create_corner_button(text: String, callback: Callable) -> Button:
	"""创建菜单四角的方形按钮"""
	var button := Button.new()
	button.text = text
	button.size = button_size
	button.custom_minimum_size = button_size
	button.add_theme_font_size_override("font_size", 13)
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.pressed.connect(callback)
	return button


## 根据英雄当前形象尺寸，把菜单紧贴在角色头顶上方。
func _layout_menu() -> void:
	"""根据英雄当前形象尺寸，把菜单紧贴在角色头顶上方。"""
	var panel_size := Vector2(button_size.x * 2.0 + button_gap, button_size.y)
	menu_panel.size = panel_size
	var center_pos := get_viewport_rect().size * 0.5
	var visual_radius := 24.0
	if selected_unit and is_instance_valid(selected_unit):
		center_pos = _get_unit_screen_position(selected_unit)
		visual_radius = selected_unit.unit_radius
	var viewport_size := get_viewport_rect().size
	var max_position := (viewport_size - panel_size).max(Vector2.ZERO)
	var desired_position := Vector2(
		center_pos.x - panel_size.x * 0.5,
		center_pos.y - visual_radius - unit_head_gap - panel_size.y
	)
	menu_panel.position = desired_position.clamp(Vector2.ZERO, max_position)

	sell_button.position = Vector2.ZERO
	retreat_button.position = Vector2(button_size.x + button_gap, 0.0)


## 获取角色在屏幕/UI坐标中的中心点，用于定位角色命令菜单
func _get_unit_screen_position(unit: Node2D) -> Vector2:
	"""获取角色在屏幕/UI坐标中的中心点，用于定位角色命令菜单"""
	if unit is UnitBase:
		return unit.get_global_transform_with_canvas() * (unit as UnitBase).billboard_screen_offset
	return unit.get_global_transform_with_canvas().origin


## 选中角色后暂停游戏并显示菜单
func _on_unit_selected(unit: HeroUnit) -> void:
	"""选中角色后暂停游戏并显示菜单"""
	Log.d(M, "收到选中的角色信号: unit=%s valid=%s" % [unit, is_instance_valid(unit)])
	if not unit or not is_instance_valid(unit):
		return

	selected_unit = unit
	was_paused_before_open = get_tree().paused
	_layout_menu()
	Log.d(M, "准备弹出角色命令菜单: unit=%s world_pos=%s screen_pos=%s menu_rect=%s paused_before=%s" % [
		selected_unit.unit_name,
		selected_unit.global_position,
		_get_unit_screen_position(selected_unit),
		menu_panel.get_global_rect(),
		was_paused_before_open
	])
	if not _is_online_session():
		get_tree().paused = true
	visible = true
	_update_unit_display()


## 部署系统取消选择时隐藏菜单
func _on_unit_deselected() -> void:
	"""部署系统取消选择时隐藏菜单"""
	_hide_menu(true)


## 刷新角色菜单按钮文字和可用状态
func _update_unit_display() -> void:
	"""刷新角色菜单按钮文字和可用状态"""
	if not selected_unit or not is_instance_valid(selected_unit):
		return

	sell_button.disabled = not _can_sell_selected_unit()


## 检查当前选中英雄是否可以被出售。
func _can_sell_selected_unit() -> bool:
	if not selected_unit or not is_instance_valid(selected_unit):
		return false
	return GameManager.is_roguelike_run and BattleManager.state == BattleManager.BattleState.PREPARING


## 隐藏角色菜单，并按需恢复打开前的暂停状态
func _hide_menu(restore_pause: bool) -> void:
	"""隐藏角色菜单，并按需恢复打开前的暂停状态"""
	visible = false
	selected_unit = null
	if restore_pause and not _is_online_session():
		get_tree().paused = was_paused_before_open


func _is_online_session() -> bool:
	var coordinator := get_tree().root.get_node_or_null("MultiplayerRunManager")
	return coordinator and coordinator.has_method("is_session_active") and coordinator.is_session_active()


## 取消角色选中并关闭菜单
func _clear_selection_and_hide() -> void:
	"""取消角色选中并关闭菜单"""
	if deployment_system and deployment_system.selected_unit:
		deployment_system.select_unit_at(Vector2i(-1, -1))
	else:
		_hide_menu(true)


## 出售：从战场移除角色并获得固定 1 金币。
func _on_sell_pressed() -> void:
	"""出售：从战场移除角色并获得固定 1 金币。"""
	if deployment_system and deployment_system.sell_selected_unit():
		_hide_menu(true)
	else:
		_update_unit_display()


## 撤退：从战场移除角色并收回手牌
func _on_retreat_pressed() -> void:
	"""撤退：从战场移除角色并收回手牌"""
	if deployment_system:
		deployment_system.retreat_selected()
	_hide_menu(true)


## 点击角色菜单区域外时取消角色选中
func _gui_input(event: InputEvent) -> void:
	"""点击角色菜单区域外时取消角色选中"""
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos := get_viewport().get_mouse_position()
		if not menu_panel.get_global_rect().has_point(mouse_pos):
			_clear_selection_and_hide()
			accept_event()


## 每帧更新运行状态。
func _process(_delta: float) -> void:
	if visible:
		if selected_unit and is_instance_valid(selected_unit):
			_update_unit_display()
		else:
			_hide_menu(true)
