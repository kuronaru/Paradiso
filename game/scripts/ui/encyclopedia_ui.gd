# encyclopedia_ui.gd — 角色/敌人图鉴界面
# 从 ClassDefinitions 与 EnemyUnit 模板读取数据，展示可点击列表和详情文本。
class_name EncyclopediaUI
extends Control

const START_MENU_PATH := "res://scenes/start_menu.tscn"

var hero_button_box: VBoxContainer = null
var enemy_button_box: VBoxContainer = null
var hero_detail: TextEdit = null
var enemy_detail: TextEdit = null
var selected_hero_button: Button = null
var selected_enemy_button: Button = null

var normal_button_style: StyleBoxFlat = null
var selected_button_style: StyleBoxFlat = null
var return_callback: Callable = Callable()


func _ready() -> void:
	"""创建图鉴界面"""
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_button_styles()
	_set_full_rect()
	_build_background()
	_build_layout()
	_populate_heroes()
	_populate_enemies()


func _set_full_rect() -> void:
	"""让图鉴界面铺满窗口"""
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build_background() -> void:
	"""创建深色背景"""
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.06, 0.075, 1.0)
	bg.anchor_left = 0.0
	bg.anchor_top = 0.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_layout() -> void:
	"""创建图鉴主布局"""
	var margin := MarginContainer.new()
	margin.anchor_left = 0.0
	margin.anchor_top = 0.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(1, 48)
	root.add_child(top_bar)

	var title := Label.new()
	title.text = "图鉴"
	title.add_theme_font_size_override("font_size", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title)

	var back_button := Button.new()
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(120, 40)
	back_button.pressed.connect(_on_back_pressed)
	top_bar.add_child(back_button)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var hero_tab := _create_tab_page("角色图鉴")
	tabs.add_child(hero_tab)
	hero_button_box = hero_tab.get_node("Columns/ListPanel/ListScroll/ButtonBox")
	hero_detail = hero_tab.get_node("Columns/DetailText")

	var enemy_tab := _create_tab_page("敌人图鉴")
	tabs.add_child(enemy_tab)
	enemy_button_box = enemy_tab.get_node("Columns/ListPanel/ListScroll/ButtonBox")
	enemy_detail = enemy_tab.get_node("Columns/DetailText")


func _create_tab_page(tab_name: String) -> Control:
	"""创建带左右两栏的标签页"""
	var page := Control.new()
	page.name = tab_name

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.anchor_left = 0.0
	columns.anchor_top = 0.0
	columns.anchor_right = 1.0
	columns.anchor_bottom = 1.0
	columns.offset_left = 0.0
	columns.offset_top = 12.0
	columns.offset_right = 0.0
	columns.offset_bottom = 0.0
	columns.add_theme_constant_override("separation", 16)
	page.add_child(columns)

	var list_panel := PanelContainer.new()
	list_panel.name = "ListPanel"
	list_panel.custom_minimum_size = Vector2(260, 1)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(list_panel)

	var list_scroll := ScrollContainer.new()
	list_scroll.name = "ListScroll"
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_child(list_scroll)

	var button_box := VBoxContainer.new()
	button_box.name = "ButtonBox"
	button_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_box.add_theme_constant_override("separation", 8)
	list_scroll.add_child(button_box)

	var detail := TextEdit.new()
	detail.name = "DetailText"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.editable = false
	detail.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	detail.add_theme_font_size_override("font_size", 16)
	columns.add_child(detail)

	return page


func _build_button_styles() -> void:
	"""创建普通与选中状态的列表按钮样式"""
	normal_button_style = StyleBoxFlat.new()
	normal_button_style.bg_color = Color(0.12, 0.13, 0.16, 0.95)
	normal_button_style.corner_radius_top_left = 4
	normal_button_style.corner_radius_top_right = 4
	normal_button_style.corner_radius_bottom_left = 4
	normal_button_style.corner_radius_bottom_right = 4
	normal_button_style.content_margin_left = 10
	normal_button_style.content_margin_right = 10

	selected_button_style = normal_button_style.duplicate()
	selected_button_style.bg_color = Color(0.18, 0.19, 0.22, 1.0)
	selected_button_style.border_width_left = 2
	selected_button_style.border_width_top = 2
	selected_button_style.border_width_right = 2
	selected_button_style.border_width_bottom = 2
	selected_button_style.border_color = Color(0.95, 0.85, 0.45, 1.0)


func _populate_heroes() -> void:
	"""填充角色图鉴列表"""
	var first_button: Button = null
	for class_id in ClassDefinitions.get_all_class_ids():
		var ct := ClassDefinitions.get_template(class_id)
		var button := _create_list_button(ct.job_name)
		button.pressed.connect(func(): _select_hero(button, ct))
		hero_button_box.add_child(button)
		if not first_button:
			first_button = button

	if first_button:
		var first_ct := ClassDefinitions.get_template(ClassDefinitions.get_all_class_ids()[0])
		_select_hero(first_button, first_ct)


func _populate_enemies() -> void:
	"""填充敌人图鉴列表"""
	var first_button: Button = null
	var enemy_pool := EnemyUnit.get_enemy_pool()
	for enemy_template in enemy_pool:
		var enemy_name: String = enemy_template.get("name", "Unknown")
		var button := _create_list_button(enemy_name)
		button.pressed.connect(func(): _select_enemy(button, enemy_template))
		enemy_button_box.add_child(button)
		if not first_button:
			first_button = button

	if first_button and not enemy_pool.is_empty():
		_select_enemy(first_button, enemy_pool[0])


func _create_list_button(text: String) -> Button:
	"""创建左侧列表按钮"""
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 16)
	_apply_button_selected(button, false)
	return button


func _select_hero(button: Button, ct: ClassTemplate) -> void:
	"""选中一个角色并显示详情"""
	if selected_hero_button:
		_apply_button_selected(selected_hero_button, false)
	selected_hero_button = button
	_apply_button_selected(button, true)
	hero_detail.text = _format_hero_detail(ct)


func _select_enemy(button: Button, enemy_template: Dictionary) -> void:
	"""选中一个敌人并显示详情"""
	if selected_enemy_button:
		_apply_button_selected(selected_enemy_button, false)
	selected_enemy_button = button
	_apply_button_selected(button, true)
	enemy_detail.text = _format_enemy_detail(enemy_template)


func _apply_button_selected(button: Button, selected: bool) -> void:
	"""更新列表按钮的选中内轮廓"""
	var style: StyleBox
	var focus_style: StyleBox
	if selected:
		style = selected_button_style
		focus_style = selected_button_style
	else:
		style = normal_button_style
		focus_style = StyleBoxEmpty.new()
	
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", focus_style)


func _format_hero_detail(ct: ClassTemplate) -> String:
	"""格式化角色职业数据"""
	return "\n".join([
		"名称：%s" % ct.job_name,
		"职业ID：%s" % ct.class_id,
		"部署费用：%d DP" % ct.deploy_cost,
		"",
		"基础属性",
		"生命值：%d" % ct.base_hp,
		"攻击力：%d" % ct.base_atk,
		"防御力：%d" % ct.base_def,
		"攻击速度：%.2f 次/秒" % ct.attack_speed,
		"移动速度：%.2f 格/秒" % ct.move_speed,
		"",
		"战斗参数",
		"攻击模式：%s" % _attack_mode_name(ct.attack_mode),
		"目标类型：%s" % _target_type_name(ct.target_type),
		"范围形状：%s" % _range_shape_name(ct.range_shape),
		"攻击范围：%.1f 格" % ct.attack_range,
		"索敌范围：%.1f 格" % ct.search_range,
		"索敌优先级：%s" % _target_priority_name(ct.target_priority),
		"",
		"姿态修正",
		"驻守防御倍率：%.2f" % ct.stance_defense_bonus,
		"驻守范围倍率：%.2f" % ct.stance_range_bonus,
		"驻守可移动：%s" % _bool_text(ct.stance_can_move),
		"驻守定身：%s" % _bool_text(ct.stance_is_rooted),
		"行进移速倍率：%.2f" % ct.march_move_speed_bonus,
		"行进攻击倍率：%.2f" % ct.march_attack_penalty,
		"",
		"技能ID：%s" % _array_text(ct.skill_ids),
	])


func _format_enemy_detail(enemy_template: Dictionary) -> String:
	"""格式化敌人模板数据"""
	return "\n".join([
		"名称：%s" % enemy_template.get("name", "Unknown"),
		"类型：%s" % _enemy_type_name(enemy_template.get("type", EnemyUnit.EnemyType.MELEE)),
		"",
		"基础属性",
		"生命值：%d" % enemy_template.get("hp", 80),
		"攻击力：%d" % enemy_template.get("atk", 10),
		"防御力：%d" % enemy_template.get("def", 3),
		"攻击速度：%.2f 次/秒" % enemy_template.get("attack_speed", 1.0),
		"移动速度：%.2f 格/秒" % enemy_template.get("move_speed", 1.5),
		"",
		"战斗参数",
		"攻击范围：%.1f 格" % enemy_template.get("attack_range", 1.5),
		"索敌范围：%.1f 格" % enemy_template.get("search_range", 5.0),
	])


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


func _enemy_type_name(value: int) -> String:
	match value:
		EnemyUnit.EnemyType.MELEE:
			return "近战"
		EnemyUnit.EnemyType.RANGED:
			return "远程"
		EnemyUnit.EnemyType.BRUTE:
			return "重装"
		EnemyUnit.EnemyType.BOSS:
			return "Boss"
		_:
			return "未知"


func _bool_text(value: bool) -> String:
	return "是" if value else "否"


func _array_text(values: Array) -> String:
	return "无" if values.is_empty() else ", ".join(values)


func set_return_callback(callback: Callable) -> void:
	"""设置返回按钮回调；用于游戏内覆盖层关闭后回到原游戏状态"""
	return_callback = callback


func _on_back_pressed() -> void:
	"""返回开始菜单"""
	if return_callback.is_valid():
		return_callback.call()
	else:
		get_tree().change_scene_to_file(START_MENU_PATH)
