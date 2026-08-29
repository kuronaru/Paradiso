# ui_flow_rules_test.gd - Multiplayer entry/exit and run-result UI regression checks.
extends Node

const TestAssertions = preload("res://scripts/testing/test_assertions.gd")

var t := TestAssertions.new("UIFlowRules")
var coordinator: Node = null


class RecruitPurchaseSpy:
	extends RoguelikeManager

	var purchase_calls: Array[int] = []

	func purchase_recruit(option_index: int) -> bool:
		purchase_calls.append(option_index)
		if not recruit_system or option_index < 0 or option_index >= recruit_system.current_options.size():
			return false
		recruit_system.remove_option(option_index)
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	coordinator = get_tree().root.get_node_or_null("MultiplayerRunManager")
	t.assert_true(coordinator != null, "multiplayer coordinator autoload exists")
	if not coordinator:
		t.finish(get_tree())
		return

	await _test_relic_selection_tracks_online_session()
	await _test_life_display()
	await _test_deployment_hand_frame()
	await _test_recruit_option_info_panel()
	await _test_run_result_overlay()
	coordinator._reset_runtime_state()
	t.finish(get_tree())


func _test_relic_selection_tracks_online_session() -> void:
	coordinator._session_active = true
	coordinator._run_active = true
	var relic_select := RoguelikeRelicSelectUI.new()
	add_child(relic_select)
	await get_tree().process_frame

	t.assert_true(relic_select.online_selection, "relic selection remembers multiplayer origin")
	t.assert_true(
		coordinator.session_ended.is_connected(relic_select._on_multiplayer_session_ended),
		"relic selection listens for host/session disconnect"
	)
	t.assert_true(
		relic_select._is_online_session(coordinator),
		"relic selection recognizes an active multiplayer session"
	)

	remove_child(relic_select)
	relic_select.queue_free()
	coordinator._reset_runtime_state()
	await get_tree().process_frame


func _test_life_display() -> void:
	GameManager.is_roguelike_run = true
	GameManager.run_max_life = 20
	GameManager.run_life = 7
	var resource_bar := ResourceBar.new()
	add_child(resource_bar)
	await get_tree().process_frame
	resource_bar._process(0.0)

	var life_label := resource_bar.find_child("LifeLabel", true, false) as Label
	t.assert_true(life_label != null, "resource bar exposes a player-life label")
	if life_label:
		t.assert_true(life_label.visible, "life label is visible during a roguelike run")
		t.assert_eq(life_label.text, "生命: 7 / 20", "life label displays current and maximum life")

	remove_child(resource_bar)
	resource_bar.queue_free()
	await get_tree().process_frame


func _test_deployment_hand_frame() -> void:
	GameManager.is_roguelike_run = true
	BattleManager.state = BattleManager.BattleState.PREPARING
	var grid := GridSystem.new()
	add_child(grid)
	await get_tree().process_frame
	var deployment := DeploymentSystem.new()
	add_child(deployment)
	deployment.hand_cards = [{"class_id": "fighter_champion", "level": 1, "star_level": 1}]
	var player_unit_count_before_preview := BattleManager.player_units.size()
	var deployment_bar := DeploymentBar.new()
	add_child(deployment_bar)
	await get_tree().process_frame

	t.assert_true(deployment_bar.get_node_or_null("PreparationAreaFrame") == null, "reserve area has no text-label frame")
	t.assert_eq(deployment_bar.hand_row.name, "ReserveHeroSlots", "reserve area exposes battle-visual hero slots")
	t.assert_eq(deployment_bar.cards.size(), 1, "one reserve hero control is built for one hand hero")
	if not deployment_bar.cards.is_empty():
		var reserve_button := deployment_bar.cards[0] as Button
		t.assert_true(reserve_button.get_theme_stylebox("normal") is StyleBoxEmpty, "reserve hero has no card frame")
		var reserve_visual := deployment_bar.cards[0].find_child("BattleHeroVisual", true, false) as UnitBase
		t.assert_true(reserve_visual != null, "reserve hero exposes a battle-art visual node")
		if reserve_visual:
			t.assert_true(reserve_visual.is_reserve_preview, "reserve hero uses the explicit UnitBase reserve state")
			t.assert_true(reserve_visual.info_hitbox != null, "UnitBase exposes an image interaction hitbox")
			t.assert_false(reserve_visual.ai_enabled, "reserve hero does not call character AI")
			t.assert_false(reserve_visual.is_processing(), "reserve hero does not run combat process updates")
			t.assert_true(reserve_visual.ai_controller != null, "reserve hero remains a complete UnitBase instance")
			t.assert_eq(reserve_visual.ground_collision_area.collision_layer, 0, "reserve hero has no combat collision layer")
			t.assert_near(
				float(reserve_visual.get_meta("combat_visual_multiplier", 0.0)),
				grid.cell_size * 0.4 / 24.0,
				0.001,
				"reserve hero uses the same visual multiplier as a deployed hero"
			)
			t.assert_false(reserve_visual in grid.all_units, "reserve hero is not inserted into battlefield cells")
			var expected_anchor := grid.get_global_transform_with_canvas() * grid.reserve_slot_visual_anchor(0, grid.reserve_slot_count)
			t.assert_near(reserve_visual.get_billboard_screen_center().x, expected_anchor.x, 0.001, "reserve hero anchor matches the battlefield X baseline")
			t.assert_near(reserve_visual.get_billboard_screen_center().y, expected_anchor.y, 0.001, "reserve hero anchor sits one fifth below the slot screen top")
			await _test_unit_info_panel(reserve_visual, grid)
	t.assert_eq(BattleManager.player_units.size(), player_unit_count_before_preview, "building reserve visuals does not register combat units")
	t.assert_eq(deployment_bar.position, Vector2.ZERO, "reserve hero UI shares the battlefield canvas origin")
	var reserve_center := grid.reserve_slot_to_world(0, grid.reserve_slot_count)
	var reserve_screen_center := grid.get_global_transform_with_canvas() * reserve_center
	t.assert_true(deployment_bar.is_point_over_reserve_area(reserve_screen_center), "projected reserve slot is inside the interactive preparation area")
	BattleManager.state = BattleManager.BattleState.IN_PROGRESS
	deployment_bar._apply_stage_layout(false)
	t.assert_eq(deployment_bar.position, Vector2.ZERO, "battle reserve remains an extension of the battlefield")
	t.assert_true(deployment_bar.find_child("PreparationAreaTitle", true, false) == null, "reserve area has no text label")

	remove_child(deployment_bar)
	deployment_bar.queue_free()
	remove_child(deployment)
	deployment.queue_free()
	remove_child(grid)
	grid.queue_free()
	BattleManager.grid = null
	BattleManager.state = BattleManager.BattleState.PREPARING
	await get_tree().process_frame


func _test_unit_info_panel(unit: UnitBase, grid: GridSystem) -> void:
	var overlay := get_tree().root.get_node_or_null("UnitInfoOverlay") as UnitInfoPanel
	t.assert_true(overlay != null, "unit information overlay autoload exists")
	if not overlay:
		return

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	unit.set_meta("equipment_ids", ["dragon_scale", "polymorph"])
	unit._on_info_gui_input(click)
	await get_tree().process_frame
	t.assert_true(overlay.is_showing_unit(unit), "clicking a unit image opens its information panel")
	t.assert_eq(overlay.panel.size, Vector2(280.0, 480.0), "unit information panel uses the requested approximate size")
	t.assert_true(overlay.panel.find_child("OverviewSection", true, false) != null, "unit information panel has the portrait and stats section")
	var synergy_column := overlay.panel.find_child("SynergyColumn", true, false) as PanelContainer
	t.assert_true(synergy_column != null, "unit information overview exposes a third synergy column")
	if synergy_column:
		t.assert_true(synergy_column.get_theme_stylebox("panel") is StyleBoxEmpty, "synergy column has no outer frame")
	t.assert_true(overlay.synergy_items.get_child_count() > 0, "unit information panel renders owned synergy icons")
	var traits_section := overlay.panel.find_child("TraitsSection", true, false) as Control
	t.assert_true(traits_section != null, "unit information panel has the autochess trait section")
	if traits_section:
		t.assert_near(traits_section.size.y, 94.0, 0.001, "autochess trait section has the requested fixed height")
	var skills_section := overlay.panel.find_child("SkillsSection", true, false) as Control
	t.assert_true(skills_section != null, "unit information panel has the skill section")
	var equipment_section := overlay.panel.find_child("EquipmentSection", true, false) as Control
	t.assert_true(equipment_section != null, "equipment is rendered as an independent bordered section")
	t.assert_true(overlay.panel.find_child("EquipmentTitle", true, false) != null, "independent equipment section has an equipment title")
	if skills_section:
		t.assert_true(skills_section.find_child("EquipmentRow1", true, false) == null, "equipment rows are outside the skill section")
	t.assert_true(overlay.panel.find_child("EquipmentRow1", true, false) != null, "equipment section reserves the first equipment row")
	t.assert_true(overlay.panel.find_child("EquipmentRow2", true, false) != null, "equipment section reserves the second equipment row")
	t.assert_true("龙焰鳞片" in overlay.equipment_description_labels[0].text, "equipment row displays equipment name and description")
	var expected_y := grid.get_recruit_panel_top_y() - UnitInfoPanel.PANEL_SIZE.y - UnitInfoPanel.PANEL_MARGIN
	t.assert_near(overlay.panel.position.y, expected_y, 0.001, "unit information panel has a fixed Y above the recruit panel")
	t.assert_near(overlay.panel.position.y + overlay.panel.size.y, grid.get_recruit_panel_top_y() - UnitInfoPanel.PANEL_MARGIN, 0.001, "unit information panel bottom stays above the recruit panel")
	var unit_screen := unit.get_global_transform_with_canvas() * unit.billboard_screen_offset
	t.assert_true(overlay.panel.position.x > unit_screen.x, "a left-side unit opens its information panel on the right")
	var original_global_position := unit.global_position
	var original_billboard_offset := unit.billboard_screen_offset
	unit.global_position = Vector2(get_viewport().get_visible_rect().size.x - 40.0, unit.global_position.y)
	unit.set_billboard_screen_offset(Vector2.ZERO)
	overlay.show_for_unit(unit)
	t.assert_true(overlay.panel.position.x < unit.global_position.x, "a right-side unit opens its information panel on the left")
	unit.global_position = original_global_position
	unit.set_billboard_screen_offset(original_billboard_offset)
	t.assert_true(overlay.traits_text.text != "", "unit information panel renders autochess trait descriptions")
	t.assert_true(overlay.skills_text.text != "", "unit information panel renders skill descriptions")

	unit._on_info_mouse_exited()
	t.assert_false(overlay.panel.visible, "leaving the unit image hides its information panel")
	unit._on_info_mouse_entered()
	await get_tree().create_timer(UnitBase.INFO_HOVER_DELAY + 0.05).timeout
	t.assert_true(overlay.is_showing_unit(unit), "hovering a unit image for 0.5 seconds opens its information panel")
	unit._on_info_mouse_exited()


func _test_recruit_option_info_panel() -> void:
	GameManager.is_roguelike_run = true
	BattleManager.state = BattleManager.BattleState.PREPARING
	var manager := RecruitPurchaseSpy.new()
	add_child(manager)
	await get_tree().process_frame
	manager.recruit_system.current_options = [
		RecruitSystem.RecruitOption.new("fighter_champion", 1, 2, 1, "测试招募被动"),
		RecruitSystem.RecruitOption.new("ranger_hunter", 1, 3, 1, "测试游侠被动")
	]
	var recruit_ui := RecruitUI.new()
	add_child(recruit_ui)
	await get_tree().process_frame
	recruit_ui._show()
	await get_tree().process_frame

	var overlay := get_tree().root.get_node_or_null("UnitInfoOverlay") as UnitInfoPanel
	var option_button := recruit_ui.option_buttons[0] as Button
	recruit_ui._show_option_info(0)
	await get_tree().process_frame
	t.assert_true(overlay.is_showing_recruit_option(option_button), "recruit option opens the shared unit information panel")
	var option_center_x := option_button.get_global_rect().get_center().x
	t.assert_near(overlay.panel.position.x + overlay.panel.size.x * 0.5, option_center_x, 0.001, "recruit information panel center aligns with the option center")
	t.assert_near(overlay.panel.position.y + overlay.panel.size.y, get_viewport().get_visible_rect().size.y - RecruitUI.PANEL_HEIGHT - 16.0, 0.001, "recruit information panel stays above the recruit bar")
	t.assert_true(overlay.synergy_items.get_child_count() > 0, "recruit preview includes the option hero synergies")
	recruit_ui._on_option_info_mouse_exited(0)
	t.assert_false(overlay.panel.visible, "leaving a recruit option hides its information panel")
	recruit_ui._on_option_info_mouse_entered(0)
	await get_tree().create_timer(UnitBase.INFO_HOVER_DELAY + 0.05).timeout
	t.assert_true(overlay.is_showing_recruit_option(option_button), "hovering a recruit option for 0.5 seconds opens its information panel")
	recruit_ui._on_option_info_mouse_exited(0)

	recruit_ui._on_purchase(0)
	t.assert_eq(manager.purchase_calls.size(), 0, "first recruit option click only selects and does not purchase")
	t.assert_eq(recruit_ui.selected_option_index, 0, "first recruit option click records the selected option")
	var selected_style := option_button.get_theme_stylebox("normal") as StyleBoxFlat
	t.assert_eq(selected_style.border_width_left, RecruitUI.OPTION_SELECTED_BORDER_WIDTH, "selected recruit option uses a thicker highlight border")
	t.assert_eq(selected_style.border_color, RecruitUI.OPTION_SELECTED_BORDER_COLOR, "selected recruit option uses the gold highlight color")
	var selection_click := InputEventMouseButton.new()
	selection_click.button_index = MOUSE_BUTTON_LEFT
	selection_click.pressed = true
	selection_click.position = option_button.get_global_rect().get_center()
	recruit_ui._input(selection_click)
	t.assert_eq(recruit_ui.selected_option_index, 0, "clicking inside the selected recruit option keeps it selected for purchase confirmation")
	selection_click.position = Vector2.ZERO
	recruit_ui._input(selection_click)
	t.assert_eq(recruit_ui.selected_option_index, -1, "clicking anywhere outside the selected recruit option clears its selection")
	recruit_ui._on_purchase(0)
	t.assert_eq(recruit_ui.selected_option_index, 0, "an option can be selected again after an outside click clears it")

	recruit_ui._on_purchase(1)
	t.assert_eq(manager.purchase_calls.size(), 0, "clicking another recruit option switches selection without purchasing")
	t.assert_eq(recruit_ui.selected_option_index, 1, "only the latest recruit option remains selected")
	var previous_style := option_button.get_theme_stylebox("normal") as StyleBoxFlat
	t.assert_eq(previous_style.border_width_left, 2, "switching options removes the previous selection highlight")

	recruit_ui._on_purchase(1)
	t.assert_eq(manager.purchase_calls, [1], "clicking the selected recruit option again executes its purchase")
	t.assert_eq(recruit_ui.selected_option_index, -1, "successful purchase clears the recruit selection")
	t.assert_eq(manager.recruit_system.current_options.size(), 1, "successful second click removes the purchased option")

	remove_child(recruit_ui)
	recruit_ui.queue_free()
	remove_child(manager)
	manager.queue_free()
	await get_tree().process_frame


func _test_run_result_overlay() -> void:
	var roguelike_manager := RoguelikeManager.new()
	add_child(roguelike_manager)
	var game_menu := GameMenuUI.new()
	add_child(game_menu)
	await get_tree().process_frame

	t.assert_true(
		roguelike_manager.run_ended.is_connected(game_menu._on_run_ended),
		"game menu listens for roguelike completion"
	)
	roguelike_manager.run_ended.emit(false)
	t.assert_true(game_menu.run_end_overlay.visible, "defeat opens the result overlay")
	t.assert_eq(game_menu.run_end_title.text, "冒险失败", "defeat overlay has a clear title")
	t.assert_false(game_menu.run_end_stay_button.visible, "offline defeat does not show multiplayer wait action")
	t.assert_eq(game_menu.run_end_return_button.text, "返回 AFK 大厅", "offline defeat offers a return path")

	game_menu._on_run_ended(true)
	t.assert_eq(game_menu.run_end_title.text, "冒险完成", "victory overlay has a clear title")

	remove_child(game_menu)
	game_menu.queue_free()
	remove_child(roguelike_manager)
	roguelike_manager.queue_free()
	GameManager.is_roguelike_run = false
	await get_tree().process_frame
