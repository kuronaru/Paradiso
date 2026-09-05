# enemy_showcase.gd - Interactive acceptance scene for the three enemy chapters.
extends Node

var grid: GridSystem
var demo_heroes: Array[UnitBase] = []
var panel: PanelContainer
var status_label: Label
var current_selection := {"chapter": 1, "type": "battle", "occurrence": 1}


func _ready() -> void:
	grid = GridSystem.new()
	grid.debug_collision_prediction = false
	grid.debug_collision_prediction_logs = false
	grid.debug_attack_entry_push_logs = false
	grid.debug_diagonal_detour_logs = false
	grid.debug_ui_hits = false
	add_child(grid)
	_build_controls()
	if not BattleManager.battle_won.is_connected(_on_battle_won):
		BattleManager.battle_won.connect(_on_battle_won)
	if not BattleManager.battle_lost.is_connected(_on_battle_lost):
		BattleManager.battle_lost.connect(_on_battle_lost)
	call_deferred("_start_encounter", 1, "battle", 1)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_R:
			_start_encounter(
				int(current_selection.get("chapter", 1)),
				str(current_selection.get("type", "battle")),
				int(current_selection.get("occurrence", 1))
			)
		KEY_H:
			panel.visible = not panel.visible


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	panel = PanelContainer.new()
	panel.position = Vector2(1000, 20)
	panel.custom_minimum_size = Vector2(260, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var title := Label.new()
	title.text = "异世界敌人验收"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var help := Label.new()
	help.text = "选择遭遇｜R 重开｜H 隐藏面板"
	help.add_theme_font_size_override("font_size", 13)
	box.add_child(help)

	var chapter_names := {1: "腐化边境", 2: "亡者之城", 3: "深渊王庭"}
	for chapter in [1, 2, 3]:
		var header := Label.new()
		header.text = "%d. %s" % [chapter, chapter_names[chapter]]
		header.add_theme_color_override("font_color", Color(0.96, 0.76, 0.34))
		box.add_child(header)
		var row := HBoxContainer.new()
		box.add_child(row)
		_add_encounter_button(row, "普通", chapter, "battle", 1)
		_add_encounter_button(row, "精英", chapter, "elite", 2 if chapter == 3 else 1)
		_add_encounter_button(row, "Boss", chapter, "boss", 1)

	status_label = Label.new()
	status_label.text = "准备加载……"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(230, 54)
	box.add_child(status_label)


func _add_encounter_button(parent: HBoxContainer, text: String, chapter: int, encounter_type: String, occurrence: int) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_start_encounter.bind(chapter, encounter_type, occurrence))
	parent.add_child(button)


func _start_encounter(chapter: int, encounter_type: String, occurrence: int) -> void:
	current_selection = {"chapter": chapter, "type": encounter_type, "occurrence": occurrence}
	_clear_demo_heroes()
	var generator := MapGenerator.new()
	var node := generator.build_encounter_node(chapter, encounter_type, occurrence)
	BattleManager.setup_battle(
		[],
		node.get("enemy_pool", []),
		int(node.get("waves", 1)),
		false,
		node.get("scripted_waves", [])
	)
	BattleManager.enemy_spawn_points = []
	GameManager.reset_run_life(20)
	_spawn_demo_party()
	status_label.text = "%s｜%s｜%d 波\n正在战斗……" % [
		_chapter_name(chapter),
		_encounter_name(encounter_type),
		BattleManager.total_waves,
	]
	BattleManager.start_next_wave()


func _spawn_demo_party() -> void:
	_spawn_demo_hero("铁壁护卫", Vector2i(3, 1), 520, 15, 10, 1.0, 1.0, Color(0.28, 0.56, 0.95))
	_spawn_demo_hero("破甲战士", Vector2i(3, 2), 400, 23, 6, 1.15, 1.2, Color(0.25, 0.72, 0.78))
	_spawn_demo_hero("长弓手", Vector2i(1, 0), 260, 27, 3, 1.25, 5.0, Color(0.34, 0.82, 0.46))
	_spawn_demo_hero("奥术师", Vector2i(1, 3), 240, 31, 2, 0.95, 4.5, Color(0.52, 0.42, 0.96))


func _spawn_demo_hero(
	display_name: String,
	cell: Vector2i,
	hp: int,
	atk: int,
	def_value: int,
	attack_speed_value: float,
	attack_range_value: float,
	visual_color: Color
) -> void:
	var hero := UnitBase.new()
	hero.team = "player"
	hero.unit_name = display_name
	hero.color = visual_color
	hero.max_hp = hp
	hero.current_hp = hp
	hero.attack = atk
	hero.defense = def_value
	hero.attack_speed = attack_speed_value
	hero.move_speed = 1.8
	hero.attack_range = attack_range_value
	hero.search_range = 9.0
	hero.set_base_stats_from_current()
	hero.grid_position = cell
	hero.global_position = grid.grid_to_world(cell)
	hero.finish_grid_move(cell)
	grid.all_units.append(hero)
	grid.occupy_cell(cell, hero)
	grid.add_child(hero)
	BattleManager.register_player_unit(hero)
	demo_heroes.append(hero)


func _clear_demo_heroes() -> void:
	for hero in demo_heroes.duplicate():
		if not is_instance_valid(hero):
			continue
		grid.remove_unit(hero)
		hero.queue_free()
	demo_heroes.clear()
	BattleManager.player_units.clear()


func _on_battle_won() -> void:
	status_label.text += "\n通过：敌人已全部清除。按 R 可重开。"


func _on_battle_lost() -> void:
	status_label.text += "\n失败：据点生命归零。可调整观察重点后按 R。"


func _chapter_name(chapter: int) -> String:
	return ["", "腐化边境", "亡者之城", "深渊王庭"][clampi(chapter, 1, 3)]


func _encounter_name(encounter_type: String) -> String:
	match encounter_type:
		"elite":
			return "精英遭遇"
		"boss":
			return "Boss 战"
		_:
			return "普通遭遇"

