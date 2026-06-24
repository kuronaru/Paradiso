# character_storage_ui.gd — 冒险小队界面
# 以卡牌形式展示玩家持有角色，并提供金币升级入口。
class_name CharacterStorageUI
extends Control

const M = "CharacterStorage"
const CARD_SIZE := Vector2(156, 236)
const CARD_IMAGE_SIZE := Vector2(124, 154)
const CARD_SPACING := 12.0
const LIST_PADDING := 16.0
const CARD_IMAGE_HEIGHT_RATIO := 0.66

var return_callback: Callable = Callable()
var selected_index: int = -1
var selected_card_button: Button = null
var selected_skill_button: Button = null
var target_level: int = 1
var drag_start_mouse_x: float = 0.0
var drag_start_level: int = 1
var is_dragging_level: bool = false

var gold_label: Label = null
var card_scroll: TouchScrollContainer = null
var card_grid: GridContainer = null
var detail_panel: PanelContainer = null
var detail_scroll_box: VBoxContainer = null
var info_list: RichTextLabel = null
var skill_tab_box: HBoxContainer = null
var skill_detail: TextEdit = null
var target_level_label: Label = null
var upgrade_button: Button = null

var normal_card_style: StyleBoxFlat = null
var selected_card_style: StyleBoxFlat = null
var skill_normal_style: StyleBoxFlat = null
var skill_selected_style: StyleBoxFlat = null


## 初始化冒险小队界面
func _ready() -> void:
	"""初始化冒险小队界面"""
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_styles()
	_set_full_rect()
	_build_background()
	_build_layout()
	_refresh_cards()
	_connect_game_manager_signals()


## 窗口或容器尺寸变化时同步刷新角色列表内容尺寸
func _notification(what: int) -> void:
	"""窗口或容器尺寸变化时同步刷新角色列表内容尺寸"""
	if what == NOTIFICATION_RESIZED:
		_update_card_grid_size()


## 让仓库界面铺满窗口并拦截鼠标输入
func _set_full_rect() -> void:
	"""让仓库界面铺满窗口并拦截鼠标输入"""
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP


## 创建仓库背景
func _build_background() -> void:
	"""创建仓库背景"""
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.05, 0.06, 0.98)
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


## 创建冒险小队主布局
func _build_layout() -> void:
	"""创建冒险小队主布局"""
	var margin := MarginContainer.new()
	margin.anchor_left = 0.0
	margin.anchor_top = 0.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(1, 46)
	root.add_child(top_bar)

	var title := Label.new()
	title.text = "冒险小队"
	title.add_theme_font_size_override("font_size", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title)

	gold_label = Label.new()
	gold_label.custom_minimum_size = Vector2(180, 40)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 18)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.28))
	top_bar.add_child(gold_label)

	var back_button := Button.new()
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(112, 40)
	back_button.pressed.connect(_on_back_pressed)
	top_bar.add_child(back_button)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	var list_panel := PanelContainer.new()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 1.0
	body.add_child(list_panel)

	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left", int(LIST_PADDING))
	list_margin.add_theme_constant_override("margin_top", int(LIST_PADDING))
	list_margin.add_theme_constant_override("margin_right", int(LIST_PADDING))
	list_margin.add_theme_constant_override("margin_bottom", int(LIST_PADDING))
	list_panel.add_child(list_margin)

	card_scroll = TouchScrollContainer.new()
	card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.enable_horizontal_drag = true
	card_scroll.enable_vertical_drag = false
	list_margin.add_child(card_scroll)

	card_grid = GridContainer.new()
	card_grid.columns = 1
	card_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_grid.custom_minimum_size = _get_card_grid_size(1)
	card_grid.add_theme_constant_override("h_separation", int(CARD_SPACING))
	card_grid.add_theme_constant_override("v_separation", int(CARD_SPACING))
	card_scroll.add_child(card_grid)

	detail_panel = PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(320, 1)
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_stretch_ratio = 1.0
	detail_panel.visible = false
	body.add_child(detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 14)
	detail_margin.add_theme_constant_override("margin_top", 14)
	detail_margin.add_theme_constant_override("margin_right", 14)
	detail_margin.add_theme_constant_override("margin_bottom", 14)
	detail_panel.add_child(detail_margin)

	var detail_scroll := TouchScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.enable_horizontal_drag = false
	detail_scroll.enable_vertical_drag = true
	detail_margin.add_child(detail_scroll)

	detail_scroll_box = VBoxContainer.new()
	detail_scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll_box.add_theme_constant_override("separation", 18)
	detail_scroll.add_child(detail_scroll_box)

	_build_detail_content()
	_update_gold_label()


## 创建右侧详情滚动页面内容
func _build_detail_content() -> void:
	"""创建右侧详情滚动页面内容"""
	var first_row := HBoxContainer.new()
	first_row.add_theme_constant_override("separation", 12)
	detail_scroll_box.add_child(first_row)

	var image_frame := PanelContainer.new()
	image_frame.custom_minimum_size = Vector2(116, 150)
	first_row.add_child(image_frame)

	var image_rect := ColorRect.new()
	image_rect.name = "ImagePlaceholder"
	image_rect.custom_minimum_size = Vector2(116, 150)
	image_rect.color = Color(0.22, 0.33, 0.48)
	image_frame.add_child(image_rect)

	info_list = RichTextLabel.new()
	info_list.custom_minimum_size = Vector2(1, 190)
	info_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_list.fit_content = true
	info_list.bbcode_enabled = true
	first_row.add_child(info_list)

	var skill_section := VBoxContainer.new()
	skill_section.add_theme_constant_override("separation", 8)
	detail_scroll_box.add_child(skill_section)

	var skill_title := Label.new()
	skill_title.text = "技能"
	skill_title.add_theme_font_size_override("font_size", 20)
	skill_section.add_child(skill_title)

	skill_tab_box = HBoxContainer.new()
	skill_tab_box.add_theme_constant_override("separation", 8)
	skill_section.add_child(skill_tab_box)

	skill_detail = TextEdit.new()
	skill_detail.custom_minimum_size = Vector2(1, 116)
	skill_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_detail.editable = false
	skill_detail.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	skill_section.add_child(skill_detail)

	var upgrade_section := VBoxContainer.new()
	upgrade_section.add_theme_constant_override("separation", 10)
	detail_scroll_box.add_child(upgrade_section)

	var upgrade_title := Label.new()
	upgrade_title.text = "等级养成"
	upgrade_title.add_theme_font_size_override("font_size", 20)
	upgrade_section.add_child(upgrade_title)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	upgrade_section.add_child(controls)

	var level_spin := HBoxContainer.new()
	level_spin.custom_minimum_size = Vector2(210, 46)
	level_spin.add_theme_constant_override("separation", 0)
	controls.add_child(level_spin)

	var decrease_button := Button.new()
	decrease_button.text = "<"
	decrease_button.custom_minimum_size = Vector2(42, 46)
	decrease_button.pressed.connect(func(): _change_target_level(-1))
	level_spin.add_child(decrease_button)

	var wheel := PanelContainer.new()
	wheel.custom_minimum_size = Vector2(126, 46)
	wheel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wheel.gui_input.connect(_on_level_wheel_gui_input)
	level_spin.add_child(wheel)

	target_level_label = Label.new()
	target_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	target_level_label.add_theme_font_size_override("font_size", 20)
	wheel.add_child(target_level_label)

	var increase_button := Button.new()
	increase_button.text = ">"
	increase_button.custom_minimum_size = Vector2(42, 46)
	increase_button.pressed.connect(func(): _change_target_level(1))
	level_spin.add_child(increase_button)

	upgrade_button = Button.new()
	upgrade_button.custom_minimum_size = Vector2(150, 46)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	controls.add_child(upgrade_button)


## 创建卡牌和技能标签的选中样式
func _build_styles() -> void:
	"""创建卡牌和技能标签的选中样式"""
	normal_card_style = StyleBoxFlat.new()
	normal_card_style.bg_color = Color(0.12, 0.13, 0.16, 1.0)
	normal_card_style.border_color = Color(0.28, 0.3, 0.34, 1.0)
	normal_card_style.border_width_left = 1
	normal_card_style.border_width_top = 1
	normal_card_style.border_width_right = 1
	normal_card_style.border_width_bottom = 1
	normal_card_style.corner_radius_top_left = 5
	normal_card_style.corner_radius_top_right = 5
	normal_card_style.corner_radius_bottom_left = 5
	normal_card_style.corner_radius_bottom_right = 5

	selected_card_style = normal_card_style.duplicate()
	selected_card_style.bg_color = Color(0.18, 0.19, 0.22, 1.0)
	selected_card_style.border_color = Color(1.0, 0.84, 0.34, 1.0)
	selected_card_style.border_width_left = 3
	selected_card_style.border_width_top = 3
	selected_card_style.border_width_right = 3
	selected_card_style.border_width_bottom = 3

	skill_normal_style = StyleBoxFlat.new()
	skill_normal_style.bg_color = Color(0.26, 0.36, 0.52, 1.0)
	skill_normal_style.corner_radius_top_left = 4
	skill_normal_style.corner_radius_top_right = 4
	skill_normal_style.corner_radius_bottom_left = 4
	skill_normal_style.corner_radius_bottom_right = 4

	skill_selected_style = skill_normal_style.duplicate()
	skill_selected_style.border_color = Color(1.0, 0.84, 0.34, 1.0)
	skill_selected_style.border_width_left = 2
	skill_selected_style.border_width_top = 2
	skill_selected_style.border_width_right = 2
	skill_selected_style.border_width_bottom = 2


## 连接全局金币和角色数据变化信号
func _connect_game_manager_signals() -> void:
	"""连接全局金币和角色数据变化信号"""
	if not GameManager.gold_changed.is_connected(_on_gold_changed):
		GameManager.gold_changed.connect(_on_gold_changed)
	if not GameManager.owned_characters_changed.is_connected(_on_owned_characters_changed):
		GameManager.owned_characters_changed.connect(_on_owned_characters_changed)


## 处理卡牌上的点击和拖拽滚动输入
func _on_card_button_gui_input(event: InputEvent, index: int, button: Button) -> void:
	"""处理卡牌上的点击和拖拽滚动输入"""
	if not card_scroll:
		return
	var should_select := card_scroll.handle_child_gui_input(event)
	if should_select:
		_select_card(index, button)
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		accept_event()


## 计算两排横向卡牌列表内容尺寸，超出宽度交给滚动容器处理
func _get_card_grid_size(columns: int) -> Vector2:
	"""计算两排横向卡牌列表内容尺寸，超出宽度交给滚动容器处理"""
	var safe_columns: int = max(1, columns)
	var visible_height := 1.0
	if card_scroll and is_instance_valid(card_scroll):
		visible_height = max(1.0, card_scroll.size.y)
	var card_size: Vector2 = _get_card_size_for_grid_height(visible_height)
	return Vector2(
		safe_columns * card_size.x + max(0, safe_columns - 1) * CARD_SPACING,
		max(visible_height, CARD_SIZE.y * 2.0 + CARD_SPACING)
	)


## 根据列表内容格高度计算单张卡牌尺寸
func _get_card_size_for_grid_height(grid_height: float) -> Vector2:
	"""根据列表内容格高度计算单张卡牌尺寸"""
	var available_height: float = max(CARD_SIZE.y * 2.0 + CARD_SPACING, grid_height)
	var card_height: float = (available_height - CARD_SPACING) * 0.5
	var card_width: float = card_height * CARD_SIZE.x / CARD_SIZE.y
	return Vector2(card_width, card_height)


## 获取当前角色列表中应使用的单张卡牌尺寸
func _get_current_card_size() -> Vector2:
	"""获取当前角色列表中应使用的单张卡牌尺寸"""
	var grid_height := CARD_SIZE.y * 2.0 + CARD_SPACING
	if card_grid and is_instance_valid(card_grid) and card_grid.size.y > 1.0:
		grid_height = card_grid.size.y
	elif card_scroll and is_instance_valid(card_scroll) and card_scroll.size.y > 1.0:
		grid_height = card_scroll.size.y
	return _get_card_size_for_grid_height(grid_height)


## 根据卡牌尺寸计算图片框尺寸
func _get_card_image_size(card_size: Vector2) -> Vector2:
	"""根据卡牌尺寸计算图片框尺寸"""
	var image_height: float = card_size.y * CARD_IMAGE_HEIGHT_RATIO
	var image_width: float = min(card_size.x - 32.0, image_height * CARD_IMAGE_SIZE.x / CARD_IMAGE_SIZE.y)
	return Vector2(max(1.0, image_width), max(1.0, image_height))


## 刷新角色列表内容格尺寸，使其垂直撑满滚动区域
func _update_card_grid_size() -> void:
	"""刷新角色列表内容格尺寸，使其垂直撑满滚动区域"""
	if not card_grid:
		return
	var card_count := GameManager.owned_characters.size()
	var columns: int = max(1, ceili(float(card_count) / 2.0))
	card_grid.columns = columns
	card_grid.custom_minimum_size = _get_card_grid_size(columns)
	_update_all_card_layouts()


## 根据当前列表高度刷新所有卡牌按钮尺寸
func _update_all_card_layouts() -> void:
	"""根据当前列表高度刷新所有卡牌按钮尺寸"""
	if not card_grid:
		return
	for child in card_grid.get_children():
		if child is Button:
			_update_card_button_layout(child)


## 根据当前card_grid高度设置单张卡牌按钮和图片框尺寸
func _update_card_button_layout(button: Button) -> void:
	"""根据当前card_grid高度设置单张卡牌按钮和图片框尺寸"""
	var card_size: Vector2 = _get_current_card_size()
	var image_size: Vector2 = _get_card_image_size(card_size)
	button.custom_minimum_size = card_size
	button.size = card_size

	var image_block := button.get_node_or_null("ImageBlock") as ColorRect
	if image_block:
		image_block.size = image_size
		image_block.position = Vector2((card_size.x - image_size.x) * 0.5, 14.0)

	var label := button.get_node_or_null("CardLabel") as Label
	if label:
		var label_top := image_size.y + 22.0
		label.size = Vector2(card_size.x, max(1.0, card_size.y - label_top))
		label.position = Vector2(0.0, label_top)


## 刷新玩家持有角色卡牌列表
func _refresh_cards() -> void:
	"""刷新玩家持有角色卡牌列表"""
	for child in card_grid.get_children():
		child.queue_free()
	selected_card_button = null

	var card_count := GameManager.owned_characters.size()
	_update_card_grid_size()

	for i in range(card_count):
		var card_data: Dictionary = GameManager.owned_characters[i]
		var ct := ClassDefinitions.get_template(card_data.get("class_id", "warrior"))
		var button := _create_character_card(i, ct, int(card_data.get("level", 1)))
		card_grid.add_child(button)
		if i == selected_index:
			selected_card_button = button
			_apply_card_selected(button, true)

	if selected_index >= card_count:
		selected_index = -1
		detail_panel.visible = false
	if selected_index >= 0:
		_refresh_detail()
	call_deferred("_update_card_grid_size")


## 创建单张冒险小队卡牌
func _create_character_card(index: int, ct: ClassTemplate, level: int) -> Button:
	"""创建单张冒险小队卡牌"""
	var button := Button.new()
	button.clip_contents = true
	button.text = ""
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 15)
	_apply_card_selected(button, false)
	button.gui_input.connect(func(event: InputEvent): _on_card_button_gui_input(event, index, button))

	var color_block := ColorRect.new()
	color_block.name = "ImageBlock"
	color_block.color = _class_color(ct.class_id)
	color_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_block.z_index = 1
	button.add_child(color_block)

	var label := Label.new()
	label.name = "CardLabel"
	label.text = "%s\nLv.%d" % [ct.job_name, level]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 2
	button.add_child(label)
	_update_card_button_layout(button)
	return button


## 选中仓库中的一张角色卡牌并打开右侧详情
func _select_card(index: int, button: Button) -> void:
	"""选中仓库中的一张角色卡牌并打开右侧详情"""
	if selected_card_button:
		_apply_card_selected(selected_card_button, false)
	selected_index = index
	if selected_index >= 0 and selected_index < GameManager.owned_characters.size():
		target_level = int(GameManager.owned_characters[selected_index].get("level", 1))
	selected_card_button = button
	_apply_card_selected(button, true)
	detail_panel.visible = true
	_refresh_detail()


## 刷新右侧角色详情和升级目标
func _refresh_detail() -> void:
	"""刷新右侧角色详情和升级目标"""
	if selected_index < 0 or selected_index >= GameManager.owned_characters.size():
		return

	var card_data: Dictionary = GameManager.owned_characters[selected_index]
	var ct := ClassDefinitions.get_template(card_data.get("class_id", "warrior"))
	var current_level := int(card_data.get("level", 1))
	target_level = clampi(max(target_level, current_level), current_level, GameManager.MAX_CHARACTER_LEVEL)
	info_list.text = _format_class_info(ct, current_level)
	_refresh_skill_tabs(ct)
	_update_upgrade_controls()


## 刷新技能色块标签和默认技能说明
func _refresh_skill_tabs(ct: ClassTemplate) -> void:
	"""刷新技能色块标签和默认技能说明"""
	for child in skill_tab_box.get_children():
		child.queue_free()
	selected_skill_button = null
	skill_detail.text = ""

	for i in range(ct.skill_ids.size()):
		var skill_id: String = ct.skill_ids[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(52, 42)
		button.tooltip_text = skill_id
		button.text = ""
		button.add_theme_stylebox_override("normal", _skill_style_for_index(i, false))
		button.add_theme_stylebox_override("hover", _skill_style_for_index(i, false))
		button.add_theme_stylebox_override("pressed", _skill_style_for_index(i, true))
		button.pressed.connect(func(): _select_skill(skill_id, button, i))
		skill_tab_box.add_child(button)
		if i == 0:
			_select_skill(skill_id, button, i)


## 选中一个技能标签并展示技能文本
func _select_skill(skill_id: String, button: Button, index: int) -> void:
	"""选中一个技能标签并展示技能文本"""
	if selected_skill_button:
		var old_index := int(selected_skill_button.get_meta("skill_index", 0))
		selected_skill_button.add_theme_stylebox_override("normal", _skill_style_for_index(old_index, false))
		selected_skill_button.add_theme_stylebox_override("hover", _skill_style_for_index(old_index, false))
	selected_skill_button = button
	button.set_meta("skill_index", index)
	button.add_theme_stylebox_override("normal", _skill_style_for_index(index, true))
	button.add_theme_stylebox_override("hover", _skill_style_for_index(index, true))

	var sd := SkillData.get_skill(skill_id)
	if sd:
		skill_detail.text = "\n".join([
			"技能名称: %s" % sd.skill_name,
			"技能ID: %s" % sd.skill_id,
			"效果: %s" % sd.description,
			"冷却: %.1f 秒" % sd.cooldown,
			"消耗: %d DP" % sd.dp_cost,
			"伤害倍率: %.2f" % sd.damage_multiplier,
			"范围半径: %.1f" % sd.aoe_radius,
			"治疗倍率: %.2f" % sd.heal_amount,
			"防御增益: %.2f" % sd.buff_defense,
			"持续时间: %.1f 秒" % sd.duration,
		])
	else:
		skill_detail.text = "技能名称: 待定\n效果: 文字占位"


## 通过左右三角按钮调整目标升级等级
func _change_target_level(delta: int) -> void:
	"""通过左右三角按钮调整目标升级等级"""
	if selected_index < 0 or selected_index >= GameManager.owned_characters.size():
		return
	var current_level := int(GameManager.owned_characters[selected_index].get("level", 1))
	target_level = clampi(target_level + delta, current_level, GameManager.MAX_CHARACTER_LEVEL)
	_update_upgrade_controls()


## 处理目标等级滑动轮盘的鼠标拖动
func _on_level_wheel_gui_input(event: InputEvent) -> void:
	"""处理目标等级滑动轮盘的鼠标拖动"""
	if selected_index < 0 or selected_index >= GameManager.owned_characters.size():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			is_dragging_level = true
			drag_start_mouse_x = get_viewport().get_mouse_position().x
			drag_start_level = target_level
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			is_dragging_level = false
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_change_target_level(1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_change_target_level(-1)
			accept_event()
	elif event is InputEventMouseMotion and is_dragging_level:
		var current_level := int(GameManager.owned_characters[selected_index].get("level", 1))
		var delta := int(round((get_viewport().get_mouse_position().x - drag_start_mouse_x) / 8.0))
		target_level = clampi(drag_start_level + delta, current_level, GameManager.MAX_CHARACTER_LEVEL)
		_update_upgrade_controls()
		accept_event()


## 刷新目标等级文本和升级按钮状态
func _update_upgrade_controls() -> void:
	"""刷新目标等级文本和升级按钮状态"""
	if selected_index < 0 or selected_index >= GameManager.owned_characters.size():
		return
	var current_level := int(GameManager.owned_characters[selected_index].get("level", 1))
	target_level = clampi(target_level, current_level, GameManager.MAX_CHARACTER_LEVEL)
	var cost := GameManager.calculate_upgrade_cost(current_level, target_level)
	target_level_label.text = "Lv.%d" % target_level
	upgrade_button.text = "升级 %d 金币" % cost
	upgrade_button.disabled = cost <= 0 or GameManager.gold < cost


## 点击升级按钮后将角色升到目标等级
func _on_upgrade_pressed() -> void:
	"""点击升级按钮后将角色升到目标等级"""
	if selected_index < 0:
		return
	if GameManager.upgrade_owned_character(selected_index, target_level):
		_refresh_cards()
		_refresh_detail()


## 金币变化时刷新仓库显示
func _on_gold_changed(_gold: int) -> void:
	"""金币变化时刷新仓库显示"""
	_update_gold_label()
	_update_upgrade_controls()


## 持有角色变化时刷新仓库卡牌
func _on_owned_characters_changed(_characters: Array) -> void:
	"""持有角色变化时刷新仓库卡牌"""
	_refresh_cards()


## 刷新金币文本
func _update_gold_label() -> void:
	"""刷新金币文本"""
	if gold_label:
		gold_label.text = "金币: %d" % GameManager.gold


## 更新角色卡牌选中状态
func _apply_card_selected(button: Button, selected: bool) -> void:
	"""更新角色卡牌选中状态"""
	var style := selected_card_style if selected else normal_card_style
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style if selected else StyleBoxEmpty.new())


## 格式化角色职业定义和当前等级信息
func _format_class_info(ct: ClassTemplate, level: int) -> String:
	"""格式化角色职业定义和当前等级信息"""
	var _scale := 1.0 + float(level - 1) * 0.05
	return "\n".join([
		"[b]等级[/b]: %d / %d" % [level, GameManager.MAX_CHARACTER_LEVEL],
		"[b]名称[/b]: %s" % ct.job_name,
		"[b]职业ID[/b]: %s" % ct.class_id,
		"[b]部署费用[/b]: %d DP" % ct.deploy_cost,
		"",
		"[b]当前属性[/b]",
		"生命值: %d" % int(round(ct.base_hp * _scale)),
		"攻击力: %d" % int(round(ct.base_atk * _scale)),
		"防御力: %d" % int(round(ct.base_def * _scale)),
		"攻击速度: %.2f 次/秒" % ct.attack_speed,
		"移动速度: %.2f 格/秒" % ct.move_speed,
		"",
		"[b]职业定义[/b]",
		"攻击模式: %s" % _attack_mode_name(ct.attack_mode),
		"目标类型: %s" % _target_type_name(ct.target_type),
		"范围形状: %s" % _range_shape_name(ct.range_shape),
		"攻击范围: %.1f 格" % ct.attack_range,
		"索敌范围: %.1f 格" % ct.search_range,
		"索敌优先级: %s" % _target_priority_name(ct.target_priority),
		"驻扎防御倍率: %.2f" % ct.stance_defense_bonus,
		"驻扎范围倍率: %.2f" % ct.stance_range_bonus,
		"驻扎可移动: %s" % _bool_text(ct.stance_can_move),
		"驻扎定身: %s" % _bool_text(ct.stance_is_rooted),
		"行进移速倍率: %.2f" % ct.march_move_speed_bonus,
		"行进攻击倍率: %.2f" % ct.march_attack_penalty,
		"技能ID: %s" % _array_text(ct.skill_ids),
	])


## 按技能序号生成色块标签样式
func _skill_style_for_index(index: int, selected: bool) -> StyleBoxFlat:
	"""按技能序号生成色块标签样式"""
	var colors := [
		Color(0.28, 0.46, 0.75),
		Color(0.55, 0.36, 0.72),
		Color(0.64, 0.42, 0.26),
		Color(0.31, 0.58, 0.43),
	]
	var style := (skill_selected_style if selected else skill_normal_style).duplicate()
	style.bg_color = colors[index % colors.size()]
	return style


## 处理职业color逻辑。
func _class_color(class_id: String) -> Color:
	return ClassDefinitions.get_template_color(class_id)


## 处理攻击modename逻辑。
func _attack_mode_name(value: int) -> String:
	match value:
		ClassTemplate.AttackMode.MELEE_SINGLE:
			return "近战单体"
		ClassTemplate.AttackMode.RANGED_SINGLE:
			return "远程单体"
		ClassTemplate.AttackMode.MAGIC_AOE:
			return "魔法范围"
		ClassTemplate.AttackMode.HEAL:
			return "治疗"
		ClassTemplate.AttackMode.PIERCING_LINE:
			return "穿透直线"
		_:
			return "未知"


## 处理目标typename逻辑。
func _target_type_name(value: int) -> String:
	match value:
		ClassTemplate.TargetType.GROUND:
			return "地面"
		ClassTemplate.TargetType.AIR:
			return "空中"
		ClassTemplate.TargetType.BOTH:
			return "地面/空中"
		_:
			return "未知"


## 处理范围形状name逻辑。
func _range_shape_name(value: int) -> String:
	match value:
		ClassTemplate.RangeShape.CIRCLE:
			return "圆形"
		ClassTemplate.RangeShape.FAN:
			return "扇形"
		ClassTemplate.RangeShape.LINE:
			return "直线"
		ClassTemplate.RangeShape.GLOBAL:
			return "全图"
		ClassTemplate.RangeShape.AREA:
			return "矩形区域"
		_:
			return "未知"


## 处理目标priorityname逻辑。
func _target_priority_name(value: int) -> String:
	match value:
		ClassTemplate.TargetPriority.NEAREST:
			return "最近"
		ClassTemplate.TargetPriority.LOWEST_HP:
			return "最低生命"
		ClassTemplate.TargetPriority.HIGHEST_ATK:
			return "最高攻击"
		ClassTemplate.TargetPriority.FARTHEST:
			return "最远"
		ClassTemplate.TargetPriority.RANDOM:
			return "随机"
		_:
			return "未知"


## 处理bool文本逻辑。
func _bool_text(value: bool) -> String:
	return "是" if value else "否"


## 处理array文本逻辑。
func _array_text(values: Array) -> String:
	return "无" if values.is_empty() else ", ".join(values)


## 设置返回按钮回调，用于关闭游戏内仓库覆盖层
func set_return_callback(callback: Callable) -> void:
	"""设置返回按钮回调，用于关闭游戏内仓库覆盖层"""
	return_callback = callback


## 关闭冒险小队界面
func _on_back_pressed() -> void:
	"""关闭冒险小队界面"""
	if return_callback.is_valid():
		return_callback.call()
	else:
		queue_free()
