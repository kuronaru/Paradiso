# unit_visual_config.gd - Editor-configurable visual setup for combat units.
class_name UnitVisualConfig
extends Resource

@export var texture: Texture2D = null
@export var sprite_frames: SpriteFrames = null
@export var sprite_scale: Vector2 = Vector2.ONE
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var idle_animation: String = "idle"
@export var walk_animation: String = "walk"
@export var attack_animation: String = "attack"
@export var dead_animation: String = "dead"
@export var flip_when_moving_left: bool = true
