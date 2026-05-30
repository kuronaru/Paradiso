# resource_bar.gd — DP资源显示条 + 开始波次按钮
class_name ResourceBar
extends Control

@export var bar_width: float = 200.0
@export var bar_height: float = 24.0

var dp_label: Label
var dp_bar_bg: ColorRect
var dp_bar_fill: ColorRect
var wave_start_btn: Button


func _ready() -> void:
	# 背景条
	dp_bar_bg = ColorRect.new()
	dp_bar_bg.size = Vector2(bar_width, bar_height)
	dp_bar_bg.color = Color(0.15, 0.15, 0.15, 0.8)
	dp_bar_bg.position = Vector2(10, 10)
	add_child(dp_bar_bg)

	# 填充条
	dp_bar_fill = ColorRect.new()
	dp_bar_fill.size = Vector2(bar_width, bar_height)
	dp_bar_fill.color = Color(0.2, 0.6, 1.0, 0.9)
	dp_bar_fill.position = Vector2(10, 10)
	add_child(dp_bar_fill)

	# DP条
	dp_label = Label.new()
	dp_label.position = Vector2(14, 12)
	dp_label.add_theme_font_size_override("font_size", 14)
	dp_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(dp_label)

	# 金币显示
	var gold_label := Label.new()
	gold_label.name = "GoldLabel"
	gold_label.position = Vector2(14, 42)
	gold_label.add_theme_font_size_override("font_size", 12)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	add_child(gold_label)

	# 波次
	var wave_label := Label.new()
	wave_label.name = "WaveLabel"
	wave_label.position = Vector2(14, 66)
	wave_label.add_theme_font_size_override("font_size", 12)
	wave_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	add_child(wave_label)

	# 开始波次按钮
	wave_start_btn = Button.new()
	wave_start_btn.name = "WaveStartBtn"
	wave_start_btn.position = Vector2(14, 92)
	wave_start_btn.size = Vector2(140, 32)
	wave_start_btn.add_theme_font_size_override("font_size", 13)
	wave_start_btn.pressed.connect(_on_wave_start_pressed)
	add_child(wave_start_btn)

	ResourceManager.dp_changed.connect(_on_dp_changed)
	_on_dp_changed(ResourceManager.current_dp, ResourceManager.max_dp)


func _process(_delta: float) -> void:
	# 更新金币和波次
	var gold_label = get_node_or_null("GoldLabel")
	if gold_label:
		gold_label.text = "金币: %d" % GameManager.gold

	var wave_label = get_node_or_null("WaveLabel")
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
		wave_label.text = "波次: %d/%d | %s" % [BattleManager.current_wave, BattleManager.total_waves, state_text]

	# 更新波次按钮
	_update_wave_button()


func _update_wave_button() -> void:
	if not wave_start_btn:
		return

	match BattleManager.state:
		BattleManager.BattleState.PREPARING:
			wave_start_btn.visible = true
			wave_start_btn.text = "▶ 开始战斗"
			wave_start_btn.disabled = false
		_:
			wave_start_btn.visible = false


func _on_wave_start_pressed() -> void:
	if BattleManager.state == BattleManager.BattleState.PREPARING or \
	   BattleManager.state == BattleManager.BattleState.WAVE_BREAK:
		BattleManager.start_next_wave()


func _on_dp_changed(current: int, max_val: int) -> void:
	dp_label.text = "DP: %d / %d" % [current, max_val]
	var ratio: float = float(current) / max(max_val, 1)
	dp_bar_fill.size.x = bar_width * ratio
