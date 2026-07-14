class_name Projectile
extends Node2D

var source: Node = null
var target: Node = null
var on_hit: Callable = Callable()
var speed: float = 640.0
var visual_scene: PackedScene = null
var visual_texture: Texture2D = null
var visual_color: Color = Color(1.0, 0.0, 0.0, 1.0)
var visual_radius: float = 6.0
var target_offset: Vector2 = Vector2.ZERO

var _start_position: Vector2 = Vector2.ZERO
var _sprite: Sprite2D = null
var _custom_visual: Node = null


func setup(config: Dictionary) -> void:
	source = config.get("source", null) as Node
	target = config.get("target", null)
	on_hit = config.get("on_hit", Callable())
	speed = maxf(1.0, float(config.get("speed", 640.0)))
	_start_position = config.get("start_position", global_position)
	target_offset = config.get("target_offset", Vector2.ZERO)
	visual_scene = config.get("visual_scene", null)
	visual_texture = config.get("visual_texture", null)
	visual_color = config.get("visual_color", visual_color)
	visual_radius = maxf(1.0, float(config.get("visual_radius", visual_radius)))
	global_position = _start_position
	z_index = int(config.get("z_index", 90))
	_rebuild_visual()


func _process(delta: float) -> void:
	if not _is_valid_target():
		queue_free()
		return

	var destination := _target_position()
	var travel := speed * delta
	if global_position.distance_to(destination) <= travel:
		global_position = destination
		_hit_target()
	else:
		global_position = global_position.move_toward(destination, travel)


func _draw() -> void:
	if visual_texture or _custom_visual:
		return
	draw_circle(Vector2.ZERO, visual_radius, visual_color)


func _hit_target() -> void:
	if _is_valid_target() and on_hit.is_valid():
		on_hit.call()
	queue_free()


func _is_valid_target() -> bool:
	if not target or not is_instance_valid(target):
		return false
	var alive_value = target.get("is_alive")
	if alive_value is bool:
		return bool(alive_value)
	return true


func _target_position() -> Vector2:
	if target is Node2D:
		return (target as Node2D).global_position + target_offset
	return global_position


func _rebuild_visual() -> void:
	if visual_scene:
		_custom_visual = visual_scene.instantiate()
		if _custom_visual:
			add_child(_custom_visual)
			queue_redraw()
			return

	if visual_texture:
		_sprite = Sprite2D.new()
		_sprite.texture = visual_texture
		_sprite.centered = true
		add_child(_sprite)
	queue_redraw()
