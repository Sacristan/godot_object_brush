@tool
extends EditorPlugin


# Constants
## Brush node class.
const Brush = preload("brush.gd")


# Enums
enum ButtonStatus {
	RELEASED,
	PRESSED,
}


# Variables
var brush: Brush
var editor_camera: Camera3D
var mouse_overlay_pos: Vector2
var last_drawn_mouse_overlay_pos: Vector2

var mouse_hit_point: Vector3
var mouse_hit_normal: Vector3

var draw_status = ButtonStatus.RELEASED
var erase_status = ButtonStatus.RELEASED

var draw_cursor: bool = false
var drawn_ever: bool = false

var _prev_mouse_hit_point := Vector3.ZERO
var _is_draw_dirty := true
var _is_erase_dirty := true

var prev_mouse_hit_point: Vector3:
	get:
		return _prev_mouse_hit_point
	set(value):
		_is_draw_dirty = false
		_is_erase_dirty = false
		_prev_mouse_hit_point = value


func _handles(object):
#	print("_handles")

	if object is Brush:
		brush = object as Brush
		return object.is_visible_in_tree()

	return false


func _enter_tree():
	#print("editor _enter_tree")
	add_custom_type("Brush", "Node3D", Brush, null)
	set_process(true)


func _exit_tree():
	#print("editor_exit_tree")
	remove_custom_type("Brush")
	set_process(false)


func _process(delta):
	if last_drawn_mouse_overlay_pos.distance_to(mouse_overlay_pos) > 0.0001:
		last_drawn_mouse_overlay_pos = mouse_overlay_pos
		draw_cursor = test_cursor_surface()

	if draw_cursor:
		draw_hit()
		draw_brush()


func _forward_3d_draw_over_viewport(overlay: Control):
#	print("_forward_3d_draw_over_viewport "+ str(overlay.get_local_mouse_position()))
	mouse_overlay_pos = overlay.get_local_mouse_position()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent):
#	print("_forward_3d_gui_input")
	if not editor_camera:
		editor_camera = camera

	var prev_draw_status = draw_status
	var prev_erase_status = erase_status

	if event is InputEventMouseButton:
		var button_event = event as InputEventMouseButton

		if button_event.pressed:
			if button_event.button_index == MOUSE_BUTTON_LEFT:
				draw_status = ButtonStatus.PRESSED
			elif button_event.button_index == MOUSE_BUTTON_RIGHT:
				erase_status = ButtonStatus.PRESSED
		else:
			if button_event.button_index == MOUSE_BUTTON_LEFT:
				draw_status = ButtonStatus.RELEASED
			elif button_event.button_index == MOUSE_BUTTON_RIGHT:
				erase_status = ButtonStatus.RELEASED

		if prev_draw_status == ButtonStatus.PRESSED and draw_status == ButtonStatus.RELEASED:
			_is_draw_dirty = true

		if prev_erase_status == ButtonStatus.PRESSED and erase_status == ButtonStatus.RELEASED:
			_is_erase_dirty = true

		process_mouse()

		if draw_status == ButtonStatus.PRESSED or erase_status == ButtonStatus.PRESSED:
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	elif event is InputEventMouseMotion:
		update_overlays()

		if draw_status == ButtonStatus.PRESSED or erase_status == ButtonStatus.PRESSED:
			process_mouse()

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func process_mouse():
	if draw_status == ButtonStatus.PRESSED:
		draw_req()
	if erase_status == ButtonStatus.PRESSED:
		erase_req()


func draw_req():
#	print("drawReq")
	if _is_draw_dirty or mouse_hit_point.distance_to(prev_mouse_hit_point) > brush.brush_size:
		prev_mouse_hit_point = mouse_hit_point
		draw()


func erase_req():
#	print("eraseReq")
	if _is_erase_dirty or mouse_hit_point.distance_to(prev_mouse_hit_point) > brush.brush_size:
		prev_mouse_hit_point = mouse_hit_point
		erase()


func erase():
	for child in brush.get_children():

		var dist: float = mouse_hit_point.distance_to(child.position)

		if dist < brush.brush_size:
			child.queue_free()


func draw():
#	print("draw")
	var local_density: int = brush.brush_density

	for i in local_density:
		var dir: Vector3 = Quaternion(Vector3.UP, randf_range(0, 360)) * Vector3.RIGHT
		var spawnPos: Vector3 = (dir * brush.brush_size * randf_range(0.05, 1)) + mouse_hit_point
		spawn_object(spawnPos)


func spawn_object(pos: Vector3):
	var result: Dictionary = raycast_test_pos(pos, mouse_hit_normal)
	var can_place: bool = result.was_hit
	#print(result)

	if can_place:
		var final_pos: Vector3 = result.hit_result.position
		var normal: Vector3 = result.hit_result.normal
		var rotated_normal: Vector3 = Quaternion.from_euler(Vector3.ZERO) * normal

		brush.draw_debug_ray(final_pos, final_pos + normal * 3, Color.BLUE)
		brush.draw_debug_ray(final_pos, final_pos + rotated_normal * 3, Color.CYAN)

		var obj := brush.get_random_paintable()

		if obj == null:
			return

		var rotation_offset: Vector3 = brush.get_random_rotation()
		brush.add_child(obj)
		obj.owner = get_tree().get_edited_scene_root()
		obj.position = final_pos
		obj.rotate_x(rotation_offset.x)
		obj.rotate_y(rotation_offset.y)
		obj.rotate_z(rotation_offset.z)

		obj.global_transform.basis = align_up(obj.global_transform.basis, rotated_normal)

		obj.scale = Vector3.ONE * brush.get_random_size()
		obj.name = obj.name + "_" + get_unix_timestamp()


# used to test whether to spawn an object over cursor
func raycast_test_pos(pos: Vector3, normal: Vector3) -> Dictionary:
	var dir := Vector3.UP

	if brush.use_surface_normal:
		dir = normal

	var params := PhysicsRayQueryParameters3D.new()
	params.from = pos + dir * 3
	params.to = pos

	brush.draw_debug_ray(params.from, params.to, Color.YELLOW)

	var result := brush.get_world_3d().direct_space_state.intersect_ray(params)

	if result:
		return { "was_hit": true, "hit_result": result }

	return { "was_hit": false, "hit_result": result }


# used to test whether to display cursor over a surface
func test_cursor_surface() -> bool:
	if editor_camera == null:
		return false

	var from = editor_camera.global_position
	var dir = editor_camera.project_ray_normal(mouse_overlay_pos)
	var to = from + dir * 1000

	var params = PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = to

	var result := brush.get_world_3d().direct_space_state.intersect_ray(params)

	if result and result.collider:
		#print("Collided with: ", result.collider.name)
		if brush.limit_to_bodies.size() > 0:
			var found: bool = false

			for body in brush.limit_to_bodies:
				#print(body, result.collider)
				if body == result.collider:
					found = true
					break

			if not found:
				return false

		mouse_hit_point = result.position
		mouse_hit_normal = result.normal

		return true

	return false


func draw_hit():
	draw_cursor_indicator(0.1, brush.cursor_inner_color)


func draw_brush():
	draw_cursor_indicator(brush.brush_size, brush.cursor_outer_color)


func draw_cursor_indicator(radius: float, color: Color):
	brush.draw_sphere(mouse_hit_point, radius, color)


func get_unix_timestamp() -> String:
	return str(Time.get_unix_time_from_system())


# ref: https://github.com/Yog-Shoggoth/Intersection_Test/blob/master/Intersect.gd
func align_up(node_basis: Basis, normal: Vector3):
	node_basis.y = normal
	var potential_z = -node_basis.x.cross(normal)
	var potential_x = -node_basis.z.cross(normal)

	if potential_z.length() > potential_x.length():
		node_basis.x = potential_z
	else:
		node_basis.x = potential_x

	node_basis.z = node_basis.x.cross(node_basis.y)
	node_basis = node_basis.orthonormalized()

	return node_basis
