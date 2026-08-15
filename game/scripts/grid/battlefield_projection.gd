# battlefield_projection.gd — 固定俯角下带轻微透视的 3D/2D 坐标换算。
class_name BattlefieldProjection
extends RefCounted

const MIN_PITCH_DEGREES := 45.0
const MAX_PITCH_DEGREES := 60.0


## 将三维战场点投影到二维画布。Z 越大，X/Y 相对透视中心的缩放越小。
static func world_to_screen(
	world_position: Vector3,
	screen_origin: Vector2,
	pitch_degrees: float,
	horizontal_center: float = 0.0,
	reference_depth: float = 1.0,
	perspective_strength: float = 0.0
) -> Vector2:
	var pitch := deg_to_rad(clampf(pitch_degrees, MIN_PITCH_DEGREES, MAX_PITCH_DEGREES))
	var depth := maxf(reference_depth, 1.0)
	var scale_value := perspective_scale(world_position.z, reference_depth, perspective_strength)
	return screen_origin + Vector2(
		horizontal_center + (world_position.x - horizontal_center) * scale_value,
		((depth - world_position.z) * sin(pitch) - world_position.y * cos(pitch)) * scale_value
	)


## 将二维画布点反算到指定高度的三维平面。
static func screen_to_world(
	screen_position: Vector2,
	world_height: float,
	screen_origin: Vector2,
	pitch_degrees: float,
	horizontal_center: float = 0.0,
	reference_depth: float = 1.0,
	perspective_strength: float = 0.0
) -> Vector3:
	var pitch := deg_to_rad(clampf(pitch_degrees, MIN_PITCH_DEGREES, MAX_PITCH_DEGREES))
	var local := screen_position - screen_origin
	var depth := maxf(reference_depth, 1.0)
	var strength := maxf(perspective_strength, 0.0)
	var depth_factor := strength / depth
	var denominator := maxf(sin(pitch) + local.y * depth_factor, 0.0001)
	var world_z := (depth * sin(pitch) - world_height * cos(pitch) - local.y) / denominator
	var scale_value := perspective_scale(world_z, depth, strength)
	return Vector3(
		horizontal_center + (local.x - horizontal_center) / maxf(scale_value, 0.0001),
		world_height,
		world_z
	)


## 指定纵深处的透视缩放。reference_depth 处缩放为 1 / (1 + strength)。
static func perspective_scale(world_z: float, reference_depth: float, perspective_strength: float) -> float:
	var depth := maxf(reference_depth, 1.0)
	return 1.0 / maxf(1.0 + maxf(perspective_strength, 0.0) * world_z / depth, 0.05)


## 地面纵深在屏幕竖轴上的压缩比例。
static func depth_scale(pitch_degrees: float, perspective_strength: float = 0.0) -> float:
	return sin(deg_to_rad(clampf(pitch_degrees, MIN_PITCH_DEGREES, MAX_PITCH_DEGREES)))


## 世界高度在屏幕竖轴上的投影比例。
static func height_scale(pitch_degrees: float) -> float:
	return cos(deg_to_rad(clampf(pitch_degrees, MIN_PITCH_DEGREES, MAX_PITCH_DEGREES)))
