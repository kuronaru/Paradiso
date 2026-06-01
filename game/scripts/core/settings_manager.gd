# settings_manager.gd — 全局游戏设置管理
# 负责加载、保存和应用跨存档共享的玩家配置。
extends Node

const CONFIG_DIR_PATH := "res://userdata"
const CONFIG_FILE_PATH := "res://userdata/settings.cfg"

signal settings_changed

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var muted: bool = false
var fullscreen: bool = false
var vsync_enabled: bool = true
var show_floating_numbers: bool = true


func _enter_tree() -> void:
	"""启动游戏时加载并应用全局设置"""
	load_settings()


func load_settings() -> void:
	"""从全局配置文件读取玩家设置"""
	_ensure_config_directory()
	var config := ConfigFile.new()
	var path := _get_config_file_absolute_path()
	var error := config.load(path)
	if error == OK:
		master_volume = clampf(float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
		music_volume = clampf(float(config.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
		muted = bool(config.get_value("audio", "muted", muted))
		fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))
		vsync_enabled = bool(config.get_value("display", "vsync_enabled", vsync_enabled))
		show_floating_numbers = bool(config.get_value("gameplay", "show_floating_numbers", show_floating_numbers))
	else:
		save_settings()

	apply_settings()
	settings_changed.emit()


func save_settings() -> bool:
	"""保存玩家设置到全局配置文件"""
	_ensure_config_directory()
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "muted", muted)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "vsync_enabled", vsync_enabled)
	config.set_value("gameplay", "show_floating_numbers", show_floating_numbers)

	var error := config.save(_get_config_file_absolute_path())
	if error != OK:
		push_warning("保存游戏设置失败: error=%d" % error)
		return false
	return true


func apply_settings() -> void:
	"""把当前设置应用到引擎运行状态"""
	_apply_bus_volume("Master", master_volume)
	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)

	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, muted)

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		DisplayServer.window_set_mode(mode)


func set_master_volume(value: float) -> void:
	"""设置主音量"""
	master_volume = clampf(value, 0.0, 1.0)
	_commit_settings()


func set_music_volume(value: float) -> void:
	"""设置音乐音量"""
	music_volume = clampf(value, 0.0, 1.0)
	_commit_settings()


func set_sfx_volume(value: float) -> void:
	"""设置音效音量"""
	sfx_volume = clampf(value, 0.0, 1.0)
	_commit_settings()


func set_muted(value: bool) -> void:
	"""设置是否静音"""
	muted = value
	_commit_settings()


func set_fullscreen(value: bool) -> void:
	"""设置是否全屏"""
	fullscreen = value
	_commit_settings()


func set_vsync_enabled(value: bool) -> void:
	"""设置是否启用垂直同步"""
	vsync_enabled = value
	_commit_settings()


func set_show_floating_numbers(value: bool) -> void:
	"""设置是否显示伤害和治疗飘字"""
	show_floating_numbers = value
	_commit_settings()


func _commit_settings() -> void:
	"""应用并保存一次设置变更"""
	apply_settings()
	save_settings()
	settings_changed.emit()


func _apply_bus_volume(bus_name: String, value: float) -> void:
	"""按总线名称应用线性音量"""
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var linear := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear) if linear > 0.0 else -80.0)


func _ensure_config_directory() -> void:
	"""确保全局配置目录存在"""
	var dir_path := _get_config_dir_absolute_path()
	if DirAccess.dir_exists_absolute(dir_path):
		return
	var error := DirAccess.make_dir_recursive_absolute(dir_path)
	if error != OK:
		push_warning("创建设置目录失败: %s error=%d" % [dir_path, error])


func _get_config_dir_absolute_path() -> String:
	"""获取全局配置目录的绝对路径"""
	return ProjectSettings.globalize_path(CONFIG_DIR_PATH)


func _get_config_file_absolute_path() -> String:
	"""获取全局配置文件的绝对路径"""
	return ProjectSettings.globalize_path(CONFIG_FILE_PATH)
