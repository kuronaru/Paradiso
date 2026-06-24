# touch_scroll_container.gd — 触屏式滚动容器
# 封装鼠标/触屏拖拽滚动，以及滚动时显示、停止后隐藏滚动条的行为。
class_name TouchScrollContainer
extends ScrollContainer

@export var enable_horizontal_drag: bool = true
@export var enable_vertical_drag: bool = true
@export var drag_threshold: float = 8.0
@export var scroll_bar_hide_delay: float = 0.65

var is_pressing: bool = false
var is_dragging: bool = false
var press_position: Vector2 = Vector2.ZERO
var start_h_value: float = 0.0
var start_v_value: float = 0.0
var hide_timer: Timer = null


## 初始化触屏式滚动容器
func _ready() -> void:
	"""初始化触屏式滚动容器"""
	gui_input.connect(_on_touch_scroll_gui_input)

	hide_timer = Timer.new()
	hide_timer.one_shot = true
	hide_timer.wait_time = scroll_bar_hide_delay
	hide_timer.timeout.connect(_hide_scroll_bars)
	add_child(hide_timer)

	get_h_scroll_bar().value_changed.connect(_on_scroll_value_changed)
	get_v_scroll_bar().value_changed.connect(_on_scroll_value_changed)
	_hide_scroll_bars()


## 供子控件转发输入；返回松开时是否应继续执行点击行为
func handle_child_gui_input(event: InputEvent) -> bool:
	"""供子控件转发输入；返回松开时是否应继续执行点击行为"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin_touch_scroll()
			return false
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			return _finish_touch_scroll()
		if _is_wheel_event(event):
			_show_scroll_bars_temporarily()
			return false
	elif event is InputEventMouseMotion:
		_update_touch_scroll()
		return false
	return false


## 处理滚动容器自身空白区域的输入
func _on_touch_scroll_gui_input(event: InputEvent) -> void:
	"""处理滚动容器自身空白区域的输入"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin_touch_scroll()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_touch_scroll()
			accept_event()
		elif _is_wheel_event(event):
			_show_scroll_bars_temporarily()
	elif event is InputEventMouseMotion:
		if _update_touch_scroll():
			accept_event()


## 记录拖拽滚动起点
func _begin_touch_scroll() -> void:
	"""记录拖拽滚动起点"""
	is_pressing = true
	is_dragging = false
	press_position = get_viewport().get_mouse_position()
	start_h_value = get_h_scroll_bar().value
	start_v_value = get_v_scroll_bar().value


## 根据鼠标拖拽距离更新滚动值
func _update_touch_scroll() -> bool:
	"""根据鼠标拖拽距离更新滚动值"""
	if not is_pressing:
		return false
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_touch_scroll()
		return false

	var drag_delta := get_viewport().get_mouse_position() - press_position
	var active_delta := Vector2(
		drag_delta.x if enable_horizontal_drag else 0.0,
		drag_delta.y if enable_vertical_drag else 0.0
	)
	if not is_dragging and active_delta.length() < drag_threshold:
		return false

	is_dragging = true
	if enable_horizontal_drag:
		var h_bar := get_h_scroll_bar()
		h_bar.value = clamp(start_h_value - drag_delta.x, h_bar.min_value, h_bar.max_value)
	if enable_vertical_drag:
		var v_bar := get_v_scroll_bar()
		v_bar.value = clamp(start_v_value - drag_delta.y, v_bar.min_value, v_bar.max_value)
	_show_scroll_bars_temporarily()
	return true


## 结束拖拽；返回是否应当按普通点击处理
func _finish_touch_scroll() -> bool:
	"""结束拖拽；返回是否应当按普通点击处理"""
	var should_click := is_pressing and not is_dragging
	is_pressing = false
	is_dragging = false
	return should_click


## 滚动值变化时临时显示滚动条
func _on_scroll_value_changed(_value: float) -> void:
	"""滚动值变化时临时显示滚动条"""
	_show_scroll_bars_temporarily()


## 显示启用方向的滚动条，并在停止滚动后自动隐藏
func _show_scroll_bars_temporarily() -> void:
	"""显示启用方向的滚动条，并在停止滚动后自动隐藏"""
	if enable_horizontal_drag:
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	if enable_vertical_drag:
		vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	if hide_timer:
		hide_timer.start()


## 隐藏滚动条，但保留滚动能力
func _hide_scroll_bars() -> void:
	"""隐藏滚动条，但保留滚动能力"""
	if enable_horizontal_drag:
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	if enable_vertical_drag:
		vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	if not enable_horizontal_drag:
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if not enable_vertical_drag:
		vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


## 判断是否为鼠标滚轮输入
func _is_wheel_event(event: InputEventMouseButton) -> bool:
	"""判断是否为鼠标滚轮输入"""
	return event.button_index in [
		MOUSE_BUTTON_WHEEL_UP,
		MOUSE_BUTTON_WHEEL_DOWN,
		MOUSE_BUTTON_WHEEL_LEFT,
		MOUSE_BUTTON_WHEEL_RIGHT,
	]
