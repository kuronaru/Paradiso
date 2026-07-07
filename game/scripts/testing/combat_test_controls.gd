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
@onready var synergy_option: OptionButton = $SynergyPanel/Margin/Layout/EditorRow/SynergyOption
@onready var synergy_count_spin: SpinBox = $SynergyPanel/Margin/Layout/EditorRow/CountSpin
@onready var synergy_layer_spin: SpinBox = $SynergyPanel/Margin/Layout/EditorRow/LayerSpin
@onready var update_synergy_button: Button = $SynergyPanel/Margin/Layout/EditorRow/UpdateSynergyButton
@onready var apply_synergy_button: Button = $SynergyPanel/Margin/Layout/EditorRow/ApplySynergyButton
@onready var clear_synergy_button: Button = $SynergyPanel/Margin/Layout/EditorRow/ClearSynergyButton
@onready var synergy_list: ItemList = $SynergyPanel/Margin/Layout/SynergyList
@onready var synergy_hint: Label = $SynergyPanel/Margin/Layout/SynergyHint


## 初始化开发者控制面板。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not runner:
		_set_status("未找到 CombatTestRunner")
		return

	debug_toggle.button_pressed = runner.is_debug_visuals_enabled()
	_populate_synergy_options()
	_refresh_synergy_list()
	_connect_signals()
	_set_status("测试场景已暂停")


## 连接按钮和输入框信号。
func _connect_signals() -> void:
	start_button.pressed.connect(_on_start_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	add_hero_button.pressed.connect(_on_add_hero_pressed)
	hero_input.text_submitted.connect(_on_hero_text_submitted)
	debug_toggle.toggled.connect(_on_debug_toggled)
	synergy_option.item_selected.connect(_on_synergy_selected)
	update_synergy_button.pressed.connect(_on_update_synergy_pressed)
	apply_synergy_button.pressed.connect(_on_apply_synergy_pressed)
	clear_synergy_button.pressed.connect(_on_clear_synergy_pressed)


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


## 选中羁绊时同步已有测试配置或默认值。
func _on_synergy_selected(_index: int) -> void:
	_load_selected_synergy_values()


## 添加或更新测试羁绊配置。
func _on_update_synergy_pressed() -> void:
	if not runner:
		return
	var synergy_id := _get_selected_synergy_id()
	if synergy_id == "":
		_set_status("请选择测试羁绊")
		return
	var count := int(round(synergy_count_spin.value))
	var layer := int(round(synergy_layer_spin.value))
	runner.set_test_synergy_spec(synergy_id, count, layer)
	_refresh_synergy_list()
	_set_status("测试羁绊已配置，点击“羁绊机制生效”应用")


## 让测试羁绊配置生效。
func _on_apply_synergy_pressed() -> void:
	if not runner:
		return
	var summaries := runner.apply_test_synergies()
	_refresh_synergy_list()
	_set_status("测试羁绊已生效：%d项" % summaries.size())


## 清空测试羁绊配置。
func _on_clear_synergy_pressed() -> void:
	if not runner:
		return
	runner.clear_test_synergies()
	_refresh_synergy_list()
	_load_selected_synergy_values()
	_set_status("已清空测试羁绊，恢复场上阵容自动计算")


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
		_set_status("添加失败: 没有可用位置或已达8人上限")
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


## 初始化测试羁绊下拉列表。
func _populate_synergy_options() -> void:
	synergy_option.clear()
	if not runner:
		return
	var options := runner.get_test_synergy_options()
	for option in options:
		var option_data: Dictionary = option
		var text := "%s · %s" % [
			str(option_data.get("type_name", "")),
			str(option_data.get("display_name", "")),
		]
		synergy_option.add_item(text)
		synergy_option.set_item_metadata(synergy_option.item_count - 1, option_data)
	if synergy_option.item_count > 0:
		synergy_option.select(0)
		_load_selected_synergy_values()


## 根据当前选中项装载人数与层数。
func _load_selected_synergy_values() -> void:
	var option := _get_selected_synergy_option()
	if option.is_empty():
		return

	var synergy_id := str(option.get("id", ""))
	for spec in runner.get_test_synergy_specs():
		if str(spec.get("id", "")) == synergy_id:
			synergy_count_spin.value = int(spec.get("count", 0))
			synergy_layer_spin.value = int(spec.get("layer", 0))
			return

	var default_count := maxi(1, int(option.get("activation_count", 1)))
	synergy_count_spin.value = default_count
	synergy_layer_spin.max_value = maxf(1.0, float(option.get("max_layer", synergy_layer_spin.max_value)))
	synergy_layer_spin.value = int(option.get("default_layer", default_count * 20))


## 刷新测试羁绊列表。
func _refresh_synergy_list() -> void:
	synergy_list.clear()
	if not runner:
		return
	var specs := runner.get_test_synergy_specs()
	for spec in specs:
		var synergy_id := str(spec.get("id", ""))
		var option := _get_synergy_option_by_id(synergy_id)
		var label := synergy_id
		if not option.is_empty():
			label = "%s · %s" % [
				str(option.get("type_name", "")),
				str(option.get("display_name", "")),
			]
		synergy_list.add_item("%s  %d人  %d层" % [
			label,
			int(spec.get("count", 0)),
			int(spec.get("layer", 0)),
		])
	var state := "覆盖中" if runner.is_test_synergies_enabled() else "待生效"
	synergy_hint.text = "测试羁绊：%s · %d项配置" % [state, specs.size()]


## 获取当前选中的羁绊ID。
func _get_selected_synergy_id() -> String:
	return str(_get_selected_synergy_option().get("id", ""))


## 获取当前选中的羁绊选项。
func _get_selected_synergy_option() -> Dictionary:
	if synergy_option.item_count <= 0 or synergy_option.selected < 0:
		return {}
	var metadata = synergy_option.get_item_metadata(synergy_option.selected)
	return metadata.duplicate(true) if metadata is Dictionary else {}


## 根据ID获取羁绊选项。
func _get_synergy_option_by_id(synergy_id: String) -> Dictionary:
	for index in range(synergy_option.item_count):
		var metadata = synergy_option.get_item_metadata(index)
		if metadata is Dictionary and str(metadata.get("id", "")) == synergy_id:
			return metadata.duplicate(true)
	return {}


## 设置状态栏文本。
func _set_status(message: String) -> void:
	if status_label:
		status_label.text = message
