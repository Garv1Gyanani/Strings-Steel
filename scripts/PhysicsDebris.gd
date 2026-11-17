extends Node2D
class_name PhysicsDebris

## Physical severed limb / head / upper-torso debris.
## - Ballistic mode: tumbles, bounces across the stage timber, and stains floorboards.
## - Dangling Marionette mode: hangs cleanly from its overhead control string with
##   natural upright pendulum stability (so decapitated heads hang face-forward & bleed down!).

signal floor_bounced(world_pos: Vector2, speed: float)
signal blood_drip(world_pos: Vector2, vel: Vector2)

var vel: Vector2 = Vector2.ZERO
var ang_vel: float = 0.0
var floor_y: float = 562.0
var bounce_coeff: float = 0.44
var gravity_accel: float = 1120.0
var grounded: bool = false
var bleed_timer: float = 0.0
var bleed_life: float = 3.2
var gore_enabled: bool = true

# Dangling Marionette String Mode
var dangling: bool = false
var string_anchor: Vector2 = Vector2.ZERO
var rope_length: float = 240.0
var hang_offset_local: Vector2 = Vector2.ZERO
var upright_bias: float = 0.0 # >0 keeps dangling heads skull-up / neck-down
var rest_dangle_angle: float = 0.0

# Exposed Bone Stump visual on severed edge
var show_stump: bool = true
var stump_local: Vector2 = Vector2.ZERO
var stump_radius: float = 10.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if dangling:
		_step_pendulum(delta)
	else:
		_step_ballistic(delta)

	if gore_enabled and bleed_life > 0.0 and (not grounded or dangling):
		bleed_life -= delta
		bleed_timer -= delta
		if bleed_timer <= 0.0:
			bleed_timer = randf_range(0.025, 0.065) if dangling else randf_range(0.04, 0.09)
			var emit_pt := to_global(stump_local)
			var spray_vel := vel * 0.3 + Vector2(randf_range(-48, 48), randf_range(20, 120))
			blood_drip.emit(emit_pt, spray_vel)

	queue_redraw()


func _step_ballistic(delta: float) -> void:
	if grounded:
		vel.x *= maxf(0.0, 1.0 - 7.5 * delta)
		ang_vel *= maxf(0.0, 1.0 - 9.0 * delta)
		if absf(vel.x) < 4.0 and absf(ang_vel) < 0.05:
			return
	else:
		vel.y += gravity_accel * delta

	position += vel * delta
	rotation += ang_vel * delta

	if position.y >= floor_y - 8.0:
		position.y = floor_y - 8.0
		if absf(vel.y) > 90.0:
			floor_bounced.emit(global_position, absf(vel.y))
			vel.y = -absf(vel.y) * bounce_coeff
			vel.x *= 0.72
			ang_vel = vel.x * 0.015
		else:
			vel.y = 0.0
			grounded = true


func _step_pendulum(delta: float) -> void:
	vel.y += gravity_accel * 0.88 * delta
	vel *= maxf(0.0, 1.0 - 0.75 * delta)
	position += vel * delta

	var attach_world := to_global(hang_offset_local)
	var diff := attach_world - string_anchor
	var dist := diff.length()
	if dist > rope_length and dist > 1.0:
		var dir := diff / dist
		var excess := dist - rope_length
		position -= dir * excess
		var radial_v := vel.dot(dir)
		if radial_v > 0.0:
			vel -= dir * radial_v * 1.12

		if upright_bias > 0.0:
			# Pull toward gentle tilted skull-up rest angle based on horizontal swing
			var swing_tilt := clampf(-vel.x * 0.0014 + rest_dangle_angle, -0.45, 0.45)
			var err := wrapf(swing_tilt - rotation, -PI, PI)
			ang_vel += err * upright_bias * delta
			ang_vel *= maxf(0.0, 1.0 - 4.2 * delta)
		else:
			var target_ang := atan2(-dir.x, dir.y) * 0.7
			var err := wrapf(target_ang - rotation, -PI, PI)
			ang_vel += err * 12.0 * delta
			ang_vel *= maxf(0.0, 1.0 - 2.6 * delta)
	elif upright_bias > 0.0:
		var err := wrapf(rest_dangle_angle - rotation, -PI, PI)
		ang_vel += err * (upright_bias * 0.6) * delta
		ang_vel *= maxf(0.0, 1.0 - 3.0 * delta)

	rotation += ang_vel * delta

	if position.y >= floor_y - 16.0:
		position.y = floor_y - 16.0
		if vel.y > 0.0:
			vel.y *= -0.35


func get_string_segment() -> Array:
	if not dangling:
		return []
	return [string_anchor, to_global(hang_offset_local)]


func cut_string(impulse: Vector2 = Vector2.ZERO) -> void:
	if not dangling:
		return
	dangling = false
	vel += impulse + Vector2(randf_range(-50, 50), 30.0)
	ang_vel = randf_range(-8.0, 8.0)


func _draw() -> void:
	if dangling:
		var anchor_local := to_local(string_anchor)
		draw_line(anchor_local, hang_offset_local, Color(0.88, 0.80, 0.64, 0.62), 1.6, true)

	if gore_enabled and show_stump:
		draw_circle(stump_local, stump_radius * 1.15, Color(0.40, 0.02, 0.04, 0.94))
		draw_circle(stump_local, stump_radius * 0.72, Color(0.86, 0.08, 0.14, 0.98))
		draw_circle(stump_local, maxf(2.2, stump_radius * 0.28), Color(0.95, 0.90, 0.80, 1.0))
