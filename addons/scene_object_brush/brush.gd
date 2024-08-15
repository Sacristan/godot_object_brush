@tool
@icon("res://addons/scene_object_brush/icon.svg")
extends Node3D
class_name Brush


# Constants
## Brush indicator shader.
const IndicatorShader: Shader = preload("indicator.gdshader")


# Variables
## Brush size in meters.
@export var brush_size: float = 1.0
## Spawned objects in brush area.
@export var brush_density: int = 10

@export_category("Paintable Settings")
## Scenes (assets) to paint. If multiple are selected, they will be randomly picked.
@export var paintable_objects: Array[PackedScene]
## Minimum random size of painted object.
@export var min_size: float = 1.0
## Maximum random size of painted object.
@export var max_size: float = 1.0

## Use surface normal or Vector.UP for projection.
@export var use_surface_normal := true

@export_group("Paintable Random Rotation")
## Minimum random rotation of painted object.
@export var random_rot_min := Vector3.ZERO
## Maximum random rotation of painted object.
@export var random_rot_max := Vector3.ZERO

@export_group("Cursor Indicator")
## Cursor indicator inner color.
@export var cursor_inner_color := Color.RED
## Cursor indicator outer color.
@export var cursor_outer_color := Color.DARK_BLUE

@export_category("Brush Settings (Optional)")
## Limit brush to certain static bodies. Leave empty for any static body.
@export var limit_to_bodies: Array[StaticBody3D]
## Draw debug rays on editor.
@export var draw_debug_rays := false


## Get random size of painted object.
func get_random_size() -> float:
	return randf_range(min_size, max_size)


## Get random paintable object.
func get_random_paintable() -> Node3D:
	clean_paintable_objects()

	if paintable_objects == null or paintable_objects.size() == 0:
		return null

	var index := randi_range(0, paintable_objects.size() - 1)
	var obj := paintable_objects[index]

	if obj == null:
		return null

	return obj.instantiate()


## Clean paintable objects.
func clean_paintable_objects() -> void:
	if paintable_objects != null:
		if paintable_objects.any(func(obj): return obj == null):
			paintable_objects = paintable_objects.filter(func(obj): return obj != null)


## Get random rotation of painted object.
func get_random_rotation() -> Vector3:
	var x = randf_range(deg_to_rad(random_rot_min.x), deg_to_rad(random_rot_max.x))
	var y = randf_range(deg_to_rad(random_rot_min.y), deg_to_rad(random_rot_max.y))
	var z = randf_range(deg_to_rad(random_rot_min.z), deg_to_rad(random_rot_max.z))

	return Vector3(x, y, z)


## Draw debug ray on editor.
func draw_debug_ray(pos1: Vector3, pos2: Vector3, color: Color) -> void:
	if draw_debug_rays:
		draw_line(pos1, pos2, color, 3 * 60)


# TODO: optimise
## Draw debug line on editor.
func draw_line(pos1: Vector3, pos2: Vector3, color = Color.WHITE_SMOKE, persist_frames: int = 1):
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	var material := ORMMaterial3D.new()

	mesh_instance.mesh = immediate_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate_mesh.surface_add_vertex(pos1)
	immediate_mesh.surface_add_vertex(pos2)
	immediate_mesh.surface_end()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color

	return await queue_free_draw(mesh_instance, persist_frames)


# TODO: optimise
# ref: https://github.com/Ryan-Mirch/Line-and-Sphere-Drawing
## Draw sphere on editor.
func draw_sphere(pos: Vector3, radius = 0.05, color = Color.WHITE, persist_frames: int = 1):
	var mesh_instance := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.rings = 8
	sphere_mesh.radial_segments = 16

	var material := ShaderMaterial.new()
	material.shader	= IndicatorShader

	mesh_instance.mesh = sphere_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = pos

	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2
	sphere_mesh.material = material

	material.set_shader_parameter("albedo", Color(0,0,0,0))
	material.set_shader_parameter("wire_color", color)

	material.set_shader_parameter("wire_width", 0.4)
	material.set_shader_parameter("wire_smoothness", 0)

	return await queue_free_draw(mesh_instance, persist_frames)


## Queue free draw.
func queue_free_draw(mesh_instance: MeshInstance3D, persist_frames: int):
	add_child(mesh_instance)

	for i in range(persist_frames):
		await get_tree().process_frame

	if is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
