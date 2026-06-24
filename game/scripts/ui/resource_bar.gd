# resource_bar.gd — DP资源显示条 + 开始波次按钮
class_name ResourceBar
extends Control

const M = "ResourceBar"

@export var bar_width: float = 260.0
@export var bar_height: float = 24.0

var dp_label: Label
var dp_bar: ProgressBar
var gold_label: Label
var wave_label: Label
var wave_start_btn: Button
var info_panel: PanelContainer
var start_button_margin: MarginContainer


## 初始化节点状态并连接必要依赖。
func _ready() -> void:
	# 确保 Control 有足够尺寸捕获鼠标事件
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	info_panel = PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(300, 96)
	info_panel.anchor_left = 0.0
	info_panel.anchor_top = 0.0
	info_panel.anchor_right = 0.0
	info_panel.anchor_bottom = 0.0
	info_panel.offset_left = 10.0
	info_panel.offset_top = 10.0
	info_panel.offset_right = 310.0
	info_panel.offset_bottom = 106.0
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

	# 波次
	wave_label = Label.new()
	wave_label.name = "WaveLabel"
	wave_label.add_theme_font_size_override("font_size", 12)
	wave_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	info_stack.add_child(wave_label)

	start_button_margin = MarginContainer.new()
	start_button_margin.anchor_left = 1.0
	start_button_margin.anchor_top = 0.0
	start_button_margin.anchor_right = 1.0
	start_button_margin.anchor_bottom = 0.0
	start_button_margin.offset_left = -156.0
	start_button_margin.offset_top = 62.0
	start_button_margin.offset_right = -16.0
	start_button_margin.offset_bottom = 94.0
	start_button_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(start_button_margin)

	# 开始波次按钮
	wave_start_btn = Button.new()
	wave_start_btn.name = "WaveStartBtn"
	wave_start_btn.custom_minimum_size = Vector2(140, 32)
	wave_start_btn.add_theme_font_size_override("font_size", 13)
	wave_start_btn.pressed.connect(_on_wave_start_pressed)
	start_button_margin.add_child(wave_start_btn)

	ResourceManager.dp_changed.connect(_on_dp_changed)
	_on_dp_changed(ResourceManager.current_dp, ResourceManager.max_dp)


## 每帧更新运行状态。
func _process(_delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size != size:
		size = viewport_size

	# 更新金币和波次
	if gold_label:
		gold_label.text = "金币: %d" % GameManager.get_active_gold()

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
	_update_wave_button()


## 更新波次按钮。
func _update_wave_button() -> void:
	if not wave_start_btn:
		return

	match BattleManager.state:
		BattleManager.BattleState.PREPARING:
			wave_start_btn.visible = true
			wave_start_btn.text = "准备战斗"
			wave_start_btn.disabled = false
		_:
			wave_start_btn.visible = false


## 处理波次startpressed回调。
func _on_wave_start_pressed() -> void:
	if BattleManager.state == BattleManager.BattleState.PREPARING or \
	   BattleManager.state == BattleManager.BattleState.WAVE_BREAK:
		BattleManager.start_next_wave()


## 处理部署点变化回调。
func _on_dp_changed(current: int, max_val: int) -> void:
	dp_label.text = "DP: %d / %d" % [current, max_val]
	if dp_bar:
		dp_bar.max_value = max(max_val, 1)
		dp_bar.value = clampi(current, 0, max(max_val, 1))
