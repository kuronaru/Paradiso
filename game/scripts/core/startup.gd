# startup.gd — 游戏启动引导
# 挂载在主场景的Startup节点上，负责初始流程和调试控制
extends Node

const M = "Startup"

var roguelike_manager: RoguelikeManager = null


func _ready() -> void:
	# 等待Autoload都初始化完毕
	await get_tree().process_frame

	# 直接进入主场景时，确保有可用的玩家存档
	if not GameManager.has_active_save:
		if GameManager.has_any_save_slot():
			GameManager.load_save(GameManager.get_continue_save_id())
		else:
			GameManager.create_new_save(GameManager.current_save_id)

	# 找到RoguelikeManager
	var rms := get_tree().get_nodes_in_group("roguelike_manager")
	if rms.size() > 0:
		roguelike_manager = rms[0]
		# 启动肉鸽模式
		roguelike_manager.start_run()
		Log.i(M, "肉鸽模式已启动!")

	# 设置部署系统为手动触发
	ResourceManager.set_regen_enabled(true)
	ResourceManager.reset_dp(30, 100)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_F:
				# 手动推进波次
				if BattleManager.state == BattleManager.BattleState.PREPARING or \
				   BattleManager.state == BattleManager.BattleState.WAVE_BREAK:
					BattleManager.start_next_wave()
					Log.d(M, "手动开始下一波")
			KEY_ESCAPE:
				# 取消选中
				var dp_systems := get_tree().get_nodes_in_group("deployment_system")
				if dp_systems.size() > 0:
					var dps = dp_systems[0]
					if dps.selected_unit:
						dps.select_unit_at(Vector2i(-1, -1))
