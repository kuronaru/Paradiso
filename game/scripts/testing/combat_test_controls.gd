# combat_test_controls.gd — 战斗测试场景开发者控制面板
extends CanvasLayer

const M = "CombatTestUI"

@onready var runner: CombatTestRunner = get_node_or_null("../CombatTestRunner") as CombatTestRunner
@onready var start_button: Button = $BottomPanel/Margin/Controls/StartButton
@onready var pause_button: Button = $BottomPanel/Margin/Controls/PauseButton
@onready var restart_button: Button = $BottomPanel/Margin/Controls/RestartButton
@onready var hero_input: LineEdit = $BottomPanel/Margin/Controls/HeroInput
@onready var add_hero_button: Button = $BottomPanel/Margin/Controls/AddHeroButton
@onready var debug_toggle: CheckButton = $BottomPanel/Margin/Controls/DebugToggle
@onready var status_label: Label = $BottomPanel/Margin/Controls/StatusLabel


## 初始化开发者控制面板。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not runner:
		_set_status("未找到 CombatTestRunner")
		return

	debug_toggle.button_pressed = runner.is_debug_visuals_enabled()
	_connect_signals()
	_set_status("测试面板已就绪")


## 连接按钮和输入框信号。
func _connect_signals() -> void:
	start_button.pressed.connect(_on_start_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	add_hero_button.pressed.connect(_on_add_hero_pressed)
	hero_input.text_submitted.connect(_on_hero_text_submitted)
	debug_toggle.toggled.connect(_on_debug_toggled)


## 开始或继续测试。
func _on_start_pressed() -> void:
	if not runner:
		return
	runner.start_test()
	_set_status("测试运行中")


## 暂停测试。
func _on_pause_pressed() -> void:
	if not runner:
		return
	runner.pause_test()
	_set_status("测试已暂停")


## 重新生成当前测试配置。
func _on_restart_pressed() -> void:
	if not runner:
		return
	runner.restart_test()
	_set_status("测试已重新开始")


## 添加输入框中的角色。
func _on_add_hero_pressed() -> void:
	_add_hero_from_input(hero_input.text)


## 回车添加输入框中的角色。
func _on_hero_text_submitted(text: String) -> void:
	_add_hero_from_input(text)


## 切换调试可视化。
func _on_debug_toggled(enabled: bool) -> void:
	if not runner:
		return
	runner.set_debug_visuals(enabled)
	_set_status("Debug可视化: %s" % ("开" if enabled else "关"))


## 从输入文本添加角色，支持 class_id 或 class_id:level。
func _add_hero_from_input(raw_text: String) -> void:
	if not runner:
		return

	var parsed := _parse_hero_input(raw_text)
	if parsed.is_empty():
		_set_status("请输入角色ID")
		return

	var class_id := str(parsed.get("class_id", ""))
	var level := int(parsed.get("level", 1))
	if not runner.is_valid_hero_class_id(class_id):
		_set_status("未知角色ID: %s" % class_id)
		return

	var hero := runner.add_hero(class_id, level)
	if not hero:
		_set_status("添加失败: 没有可用位置")
		return

	hero_input.clear()
	_set_status("已添加 %s Lv.%d" % [hero.unit_name, hero.level])


## 解析角色输入。
func _parse_hero_input(raw_text: String) -> Dictionary:
	var text := raw_text.strip_edges()
	if text == "":
		return {}

	var normalized := text.replace(":", " ").replace(",", " ").replace("，", " ")
	var parts := normalized.split(" ", false)
	if parts.is_empty():
		return {}

	var level := 1
	if parts.size() >= 2:
		var level_text := str(parts[1]).strip_edges()
		if level_text.is_valid_int():
			level = clampi(int(level_text), 1, GameManager.get_max_character_level())

	return {
		"class_id": str(parts[0]).strip_edges(),
		"level": level,
	}


## 设置状态栏文本。
func _set_status(message: String) -> void:
	if status_label:
		status_label.text = message
