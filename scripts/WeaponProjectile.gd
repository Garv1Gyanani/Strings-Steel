class_name WeaponProjectile
extends Node2D

## Hurled or disarmed weapon in flight and on the stage floorboards.
## - While `flying`: spins through the air, can be deflected by a parry/clash or
##   strike an opponent for heavy piercing damage.
## - Once deflected / embedded / dropped (`flying = false`): bounces onto the stage
##   timber and rests with a subtle glint so ANY unarmed fighter can pick it up!

signal floor_clattered(world_pos: Vector2)

var weapon_part_id: String = "p1_sword_long"
var thrower: Node2D = null
var vel: Vector2 = Vector2.ZERO
var ang_vel: float = 18.0
var flying: bool = true
var grounded: bool = false
var floor_y: float = 556.0
var pickup_cooldown: float = 0.30
var blade_half_len: float = 85.0

var _sprite: Sprite2D
var _trail_pts: Array[Vector2] = []


func setup_visual(tex: Texture2D, spr_scale: Vector2, spr_offset: Vector2, half_len: float = 85.0) -> void:
	blade_half_len = half_len
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.centered = false
	_sprite.scale = spr_scale
	_sprite.offset = spr_offset
	PuppetVisuals.apply_ink_material(_sprite)
	add_child(_sprite)


func get_segment() -> Array:
	var dir := Vector2(cos(rotation), sin(rotation))
	return [global_position - dir * (blade_half_len * 0.35), global_position + dir * blade_half_len]


func drop_from_impact(bounce_vel: Vector2) -> void:
	flying = false
	vel = bounce_vel
	ang_vel = clampf(bounce_vel.x * 0.04, -14.0, 14.0)
	if absf(ang_vel) < 3.0:
		ang_vel = 6.5 if bounce_vel.x >= 0.0 else -6.5
	pickup_cooldown = 0.22
	_trail_pts.clear()


func can_be_picked_up() -> bool:
	return not flying and pickup_cooldown <= 0.0


func _process(delta: float) -> void:
	pickup_cooldown = maxf(0.0, pickup_cooldown - delta)
	if flying:
		vel.y += 380.0 * delta
		position += vel * delta
		rotation += ang_vel * delta
		_trail_pts.append(global_position)
		if _trail_pts.size() > 6:
			_trail_pts.pop_front()
		if position.x <= 95.0 or position.x >= 1185.0:
			position.x = clampf(position.x, 95.0, 1185.0)
			drop_from_impact(Vector2(-vel.x * 0.32, -80.0))
			floor_clattered.emit(global_position)
		elif position.y >= floor_y:
			position.y = floor_y
			drop_from_impact(Vector2(vel.x * 0.45, -absf(vel.y) * 0.35))
			floor_clattered.emit(global_position)
	else:
		if not grounded:
			vel.y += 1120.0 * delta
			position += vel * delta
			rotation += ang_vel * delta
			position.x = clampf(position.x, 105.0, 1175.0)
			if position.y >= floor_y:
				position.y = floor_y
				if absf(vel.y) > 95.0:
					floor_clattered.emit(global_position)
					vel.y = -absf(vel.y) * 0.36
					vel.x *= 0.62
					ang_vel *= 0.55
				else:
					vel = Vector2.ZERO
					ang_vel = 0.0
					grounded = true
					# Settle nearly flat along the floorboards.
					rotation = 0.06 if cos(rotation) >= 0.0 else PI - 0.06
	queue_redraw()


func _draw() -> void:
	if flying and _trail_pts.size() >= 2:
		for i in range(_trail_pts.size() - 1):
			var frac := float(i + 1) / float(_trail_pts.size())
			draw_line(to_local(_trail_pts[i]), to_local(_trail_pts[i + 1]), Color(1.0, 0.94, 0.72, 0.45 * frac), 3.0 * frac, true)
	elif grounded and pickup_cooldown <= 0.0:
		var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.007)
		draw_arc(Vector2(28.0, 0.0), 22.0, 0.0, TAU, 20, Color(1.0, 0.86, 0.40, 0.38 * pulse), 1.6, true)
