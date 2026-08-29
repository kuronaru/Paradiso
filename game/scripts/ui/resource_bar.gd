# resource_bar.gd — DP资源显示条 + 开始波次按钮
class_name ResourceBar
extends Control

const M = "ResourceBar"
const BATTLE_BUTTON_SIZE := Vector2(88.0, 32.0)
const BATTLE_BUTTON_VERTICAL_GAP := 8.0
const BATTLE_BUTTON_SIDE_GAP := 12.0
const BATTLE_BUTTON_RECRUIT_GAP := 10.0

@export var bar_width: float = 260.0
@export var bar_height: float = 24.0

var dp_label: Label
var dp_bar: ProgressBar
var gold_label: Label
var life_label: Label
var wave_label: Label
var wave_start_btn: Button
var enemy_preview_btn: Button
var info_panel: PanelContainer
var start_button_margin: MarginContainer
var preview_button_margin: MarginContainer


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	# 确保 Control 有足够尺寸捕获鼠标事件
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	info_panel = PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(300, 116)
	info_panel.anchor_left = 0.0
	info_panel.anchor_top = 0.0
	info_panel.anchor_right = 0.0
	info_panel.anchor_bottom = 0.0
	info_panel.offset_left = 10.0
	info_panel.offset_top = 10.0
	info_panel.offset_right = 310.0
	info_panel.offset_bottom = 126.0
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.035, 0.04, 0.055, 0.82)
	info_style.corner_radius_top_left = 4
	info_style.corner_radius_top_right = 4
	info_style.corner_radius_bottom_left = 4
	info_style.corner_radius_bottom_right = 4
	info_panel.add_theme_stylebox_override("panel", info_style)
	add_child(info_panel)

	var info_margin := MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 10)
	info_margin.add_theme_constant_override("margin_top", 8)
	info_margin.add_theme_constant_override("margin_right", 10)
	info_margin.add_theme_constant_override("margin_bottom", 8)
	info_panel.add_child(info_margin)

	var info_stack := VBoxContainer.new()
	info_stack.add_theme_constant_override("separation", 4)
	info_margin.add_child(info_stack)

	# DP条
	dp_label = Label.new()
	dp_label.add_theme_font_size_override("font_size", 14)
	dp_label.add_theme_color_override("font_color", Color.WHITE)
	info_stack.add_child(dp_label)

	dp_bar = ProgressBar.new()
	dp_bar.custom_minimum_size = Vector2(bar_width, bar_height)
	dp_bar.max_value = max(ResourceManager.max_dp, 1)
	dp_bar.show_percentage = false
	info_stack.add_child(dp_bar)

	# 金币显示
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.add_theme_font_size_override("font_size", 12)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	info_stack.add_child(gold_label)

	# 单局玩家生命
	life_label = Label.new()
	life_label.name = "LifeLabel"
	life_label.add_theme_font_size_override("font_size", 12)
	life_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))
	info_stack.add_child(life_label)

	# 波次
	wave_label = Label.new()
	wave_label.name = "WaveLabel"
	wave_label.add_theme_font_size_override("font_size", 12)
	wave_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	info_stack.add_child(wave_label)

	start_button_margin = MarginContainer.new()
	start_button_margin.anchor_left = 0.0
	start_button_margin.anchor_top = 0.0
	start_button_margin.anchor_right = 0.0
	start_button_margin.anchor_bottom = 0.0
	start_button_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(start_button_margin)

	# 开始波次按钮
	wave_start_btn = Button.new()
	wave_start_btn.name = "WaveStartBtn"
	wave_start_btn.custom_minimum_size = BATTLE_BUTTON_SIZE
	wave_start_btn.add_theme_font_size_override("font_size", 13)
	wave_start_btn.pressed.connect(_on_wave_start_pressed)
	start_button_margin.add_child(wave_start_btn)

	preview_button_margin = MarginContainer.new()
	preview_button_margin.anchor_left = 0.0
	preview_button_margin.anchor_top = 0.0
	preview_button_margin.anchor_right = 0.0
	preview_button_margin.anchor_bottom = 0.0
	preview_button_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_button_margin)

	enemy_preview_btn = Button.new()
	enemy_preview_btn.name = "EnemyPreviewBtn"
	enemy_preview_btn.custom_minimum_size = BATTLE_BUTTON_SIZE
	enemy_preview_btn.add_theme_font_size_override("font_size", 13)
	enemy_preview_btn.pressed.connect(_on_enemy_preview_pressed)
	preview_button_margin.add_child(enemy_preview_btn)

	ResourceManager.dp_changed.connect(_on_dp_changed)
	_on_dp_changed(ResourceManager.current_dp, ResourceManager.max_dp)
	_layout_battle_buttons()


## 每帧更新运行状态。
func _process(_delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size != size:
		size = viewport_size

	# 更新金币和波次
	if gold_label:
		gold_label.text = "金币: %d" % GameManager.get_active_gold()
	if life_label:
		life_label.visible = GameManager.is_roguelike_run
		life_label.text = "生命: %d / %d" % [GameManager.run_life, GameManager.run_max_life]

	if wave_label:
		var state_text := ""
		match BattleManager.state:
			BattleManager.BattleState.PREPARING:
				state_text = "准备阶段"
			BattleManager.BattleState.IN_PROGRESS:
				state_text = "战斗中"
			BattleManager.BattleState.WAVE_BREAK:
				state_text = "波次间隙"
			BattleManager.BattleState.VICTORY:
				state_text = "胜利!"
			BattleManager.BattleState.DEFEAT:
				state_text = "失败!"
		if GameManager.is_roguelike_run:
			wave_label.text = "回合: %d/%d | 波次: %d/%d | %s" % [
				GameManager.current_run_round,
				GameManager.max_run_rounds,
				BattleManager.current_wave,
				BattleManager.total_waves,
				state_text
			]
		else:
			wave_label.text = "波次: %d/%d | %s" % [BattleManager.current_wave, BattleManager.total_waves, state_text]

	# 更新波次按钮
	_layout_battle_buttons()
	_update_wave_button()


## 将两个战斗按钮放在备战区右侧空白处，并贴近招募栏上方纵向排列。
func _layout_battle_buttons() -> void:
	if not start_button_margin or not preview_button_margin:
		return
	var viewport_size := get_viewport_rect().size
	var recruit_top := viewport_size.y - RecruitUI.PANEL_HEIGHT - 8.0
	var available_left := viewport_size.x - RecruitUI.PANEL_MARGIN - BATTLE_BUTTON_SIZE.x
	var grid := BattleManager.grid as GridSystem
	if grid:
		recruit_top = grid.get_recruit_panel_top_y()
		var reserve_polygon := grid.get_reserve_polygon()
		var grid_to_screen := grid.get_global_transform_with_canvas()
		var reserve_right := -INF
		for point in reserve_polygon:
			reserve_right = maxf(reserve_right, (grid_to_screen * point).x)
		available_left = reserve_right + BATTLE_BUTTON_SIDE_GAP

	var available_right := viewport_size.x - RecruitUI.PANEL_MARGIN
	var available_width := maxf(available_right - available_left, 0.0)
	var button_x := available_left + maxf((available_width - BATTLE_BUTTON_SIZE.x) * 0.5, 0.0)
	button_x = minf(button_x, available_right - BATTLE_BUTTON_SIZE.x)
	var stack_height := BATTLE_BUTTON_SIZE.y * 2.0 + BATTLE_BUTTON_VERTICAL_GAP
	var preview_y := recruit_top - BATTLE_BUTTON_RECRUIT_GAP - stack_height
	_set_button_container_rect(preview_button_margin, Vector2(button_x, preview_y))
	_set_button_container_rect(start_button_margin, Vector2(
		button_x,
		preview_y + BATTLE_BUTTON_SIZE.y + BATTLE_BUTTON_VERTICAL_GAP
	))


func _set_button_container_rect(container: MarginContainer, top_left: Vector2) -> void:
	container.offset_left = top_left.x
	container.offset_top = top_left.y
	container.offset_right = top_left.x + BATTLE_BUTTON_SIZE.x
	container.offset_bottom = top_left.y + BATTLE_BUTTON_SIZE.y


## 更新波次按钮。
func _update_wave_button() -> void:
	if not wave_start_btn:
		return

	match BattleManager.state:
		BattleManager.BattleState.PREPARING:
			wave_start_btn.visible = true
			wave_start_btn.text = "准备战斗"
			wave_start_btn.disabled = false
			if enemy_preview_btn:
				enemy_preview_btn.visible = true
				var grid := BattleManager.grid as GridSystem
				enemy_preview_btn.text = "返回战场" if grid and grid.enemy_preview_view_enabled else "敌人预览"
		_:
			wave_start_btn.visible = false
			if enemy_preview_btn:
				enemy_preview_btn.visible = false


## 处理波次startpressed回调。
func _on_wave_start_pressed() -> void:
	if BattleManager.state == BattleManager.BattleState.PREPARING or \
	   BattleManager.state == BattleManager.BattleState.WAVE_BREAK:
		var grid := BattleManager.grid as GridSystem
		if grid:
			grid.set_enemy_preview_view(false, false)
		BattleManager.start_next_wave()


func _on_enemy_preview_pressed() -> void:
	var grid := BattleManager.grid as GridSystem
	if grid and BattleManager.state == BattleManager.BattleState.PREPARING:
		grid.toggle_enemy_preview_view()


## 处理部署点变化回调。
func _on_dp_changed(current: int, max_val: int) -> void:
	dp_label.text = "DP: %d / %d" % [current, max_val]
	if dp_bar:
		dp_bar.max_value = max(max_val, 1)
		dp_bar.value = clampi(current, 0, max(max_val, 1))
