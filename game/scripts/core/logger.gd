# logger.gd — 通用日志系统
# 提供等级过滤、时间戳、模块标记的日志输出
# Autoload 名称: Log
class_name GameLogger
extends Node

enum Level {
	DEBUG = 0,  ## 调试细节
	INFO  = 1,  ## 常规信息
	WARN  = 2,  ## 警告
	ERROR = 3,  ## 错误
	OFF   = 4,  ## 关闭所有输出
}

const LEVEL_NAMES: Array[String] = ["DEBUG", "INFO", "WARN", "ERROR"]

## 最低输出等级（低于此等级的日志被忽略）
@export var min_level: Level = Level.DEBUG
## 是否显示时间戳
@export var show_timestamp: bool = true
## 是否显示等级标签
@export var show_level: bool = true
## 是否显示模块名
@export var show_module: bool = true


func debug(module: String, msg: String) -> void:
	_log(Level.DEBUG, module, msg)


func info(module: String, msg: String) -> void:
	_log(Level.INFO, module, msg)


func warn(module: String, msg: String) -> void:
	_log(Level.WARN, module, msg)


func error(module: String, msg: String) -> void:
	_log(Level.ERROR, module, msg)


func _log(level: Level, module: String, msg: String) -> void:
	if level < min_level:
		return

	var parts: PackedStringArray = []

	if show_timestamp:
		parts.append("[%s]" % Time.get_time_string_from_system())

	if show_level:
		var name := LEVEL_NAMES[level] if level < LEVEL_NAMES.size() else "???"
		parts.append("[%s]" % name)

	if show_module and not module.is_empty():
		parts.append("[%s]" % module)

	parts.append(msg)
	print(" ".join(parts))


## 便捷：设置全局日志等级
func set_level(level: Level) -> void:
	min_level = level
	info("Log", "日志等级切换为: %s" % LEVEL_NAMES[level])


## 便捷：临时关闭日志
func silence() -> void:
	min_level = Level.OFF


## 便捷：恢复默认日志等级
func verbose() -> void:
	min_level = Level.DEBUG


## 简写别名（配合 const M 使用: Log.d(M, "msg")）
func d(module: String, msg: String) -> void: debug(module, msg)
func i(module: String, msg: String) -> void: info(module, msg)
func w(module: String, msg: String) -> void: warn(module, msg)
func e(module: String, msg: String) -> void: error(module, msg)
