class_name BloodCanvas
extends Node2D

## Persistent blood layers (velvet backdrop + stage floor), painted on the GPU.
##
## The old implementation blended every splat pixel-by-pixel into a CPU Image from
## GDScript and re-uploaded the whole texture, which hitched during heavy gore.
## Here each layer is a SubViewport that never clears: splats are queued as draw
## ops, rendered once into the viewport (UPDATE_ONCE), and accumulate for free.
##
## A coarse per-column "wetness" array replaces Image.get_pixel() lookups for
## bloody-bootprint detection.

const WALL_SIZE := Vector2i(1280, 560)
const FLOOR_SIZE := Vector2i(1280, 160)
const FLOOR_Y := 560.0
const WET_COLUMN_PX := 8

var _wall_vp: SubViewport
var _floor_vp: SubViewport
var _wall_painter: Node2D
var _floor_painter: Node2D
var _wall_ops: Array = []
var _floor_ops: Array = []
var _wet := PackedFloat32Array()


func _ready() -> void:
	_wall_vp = _make_layer(WALL_SIZE, Vector2.ZERO, -25)
	_floor_vp = _make_layer(FLOOR_SIZE, Vector2(0, FLOOR_Y), -15)
	_wall_painter = Node2D.new()
	_wall_painter.draw.connect(_draw_ops.bind(true))
	_wall_vp.add_child(_wall_painter)
	_floor_painter = Node2D.new()
	_floor_painter.draw.connect(_draw_ops.bind(false))
	_floor_vp.add_child(_floor_painter)
	_wet.resize(int(ceil(float(FLOOR_SIZE.x) / float(WET_COLUMN_PX))))
	clear()


func _make_layer(sz: Vector2i, pos: Vector2, z: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = sz
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var sp := Sprite2D.new()
	sp.texture = vp.get_texture()
	sp.centered = false
	sp.position = pos
	sp.z_index = z
	# Mix-blending onto a transparent target stores premultiplied colour.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	sp.material = mat
	add_child(sp)
	return vp


func _process(delta: float) -> void:
	# Blood slowly soaks into the timber, so boots stop picking it up.
	for i in range(_wet.size()):
		if _wet[i] > 0.0:
			_wet[i] = maxf(0.0, _wet[i] - 0.012 * delta)


func clear() -> void:
	_wall_ops.clear()
	_floor_ops.clear()
	_wet.fill(0.0)
	for vp in [_wall_vp, _floor_vp]:
		if vp != null:
			vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _wall_painter != null:
		_wall_painter.queue_redraw()
	if _floor_painter != null:
		_floor_painter.queue_redraw()


## Blood wetness (0..~1) of the floor under world x.
func floor_wetness_at(wx: float) -> float:
	var idx := clampi(int(wx) / WET_COLUMN_PX, 0, _wet.size() - 1)
	return _wet[idx]


func paint_floor_splat(wx: float, rad: float) -> void:
	var cx := clampf(wx, 4.0, 1275.0)
	var cy := randf_range(6.0, 38.0)
	var rx := clampf(rad * randf_range(1.4, 2.4), 4.0, 32.0)
	var ry := clampf(rad * 0.42, 2.0, 11.0)
	var col := Color(0.28, 0.012, 0.025, 0.62) if randf() < 0.5 else Color(0.46, 0.024, 0.045, 0.56)
	_floor_ops.append({"t": "ellipse", "c": Vector2(cx, cy), "r": Vector2(rx, ry), "col": col})
	if rx >= 12.0 and randf() < 0.45:
		var sx := cx + randf_range(-rx / 3.0, rx / 3.0)
		_floor_ops.append({"t": "dot", "c": Vector2(sx, cy), "r": 1.2, "col": Color(0.88, 0.34, 0.38, 0.4)})
	# Wetness for bootprints
	var c0 := clampi(int(cx - rx) / WET_COLUMN_PX, 0, _wet.size() - 1)
	var c1 := clampi(int(cx + rx) / WET_COLUMN_PX, 0, _wet.size() - 1)
	for i in range(c0, c1 + 1):
		_wet[i] = minf(1.0, _wet[i] + col.a * 0.6)
	_request(false)


func paint_bootprint(wx: float, alpha: float) -> void:
	var c := Vector2(clampf(wx, 4.0, 1274.0), randf_range(12.0, 26.0))
	_floor_ops.append({"t": "ellipse", "c": c, "r": Vector2(4.5, 1.6), "col": Color(0.36, 0.015, 0.03, alpha)})
	_request(false)


func paint_wall_splat(wx: float, wy: float, rad: float) -> void:
	var cx := clampf(wx, 8.0, 1270.0)
	var cy := clampf(wy, 8.0, 540.0)
	var r := clampf(rad, 5.0, 26.0)
	_wall_ops.append({"t": "dot", "c": Vector2(cx, cy), "r": r, "col": Color(0.32, 0.015, 0.03, 0.30)})
	_wall_ops.append({"t": "dot", "c": Vector2(cx, cy), "r": r * 0.6, "col": Color(0.32, 0.015, 0.03, 0.32)})
	# Fine mist satellites around the impact
	for _s in range(14):
		var sp := Vector2(cx + randf_range(-r * 2.0, r * 2.0), cy + randf_range(-r * 2.0, r * 2.0))
		_wall_ops.append({"t": "dot", "c": sp, "r": randf_range(0.8, 1.8), "col": Color(0.45, 0.02, 0.04, 0.45)})
	# Tapered gravity runs down the velvet
	for _run in range(randi_range(2, 4)):
		var rx := cx + randf_range(-r / 2.0, r / 2.0)
		var run_len := randf_range(45.0, 130.0)
		var end_y := minf(cy + run_len, float(WALL_SIZE.y) - 1.0)
		_wall_ops.append({"t": "run", "a": Vector2(rx, cy), "b": Vector2(rx, end_y), "col": Color(0.30, 0.012, 0.025, 0.42)})
	_request(true)


func _request(wall: bool) -> void:
	if wall:
		_wall_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_wall_painter.queue_redraw()
	else:
		_floor_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_floor_painter.queue_redraw()


func _draw_ops(wall: bool) -> void:
	var painter := _wall_painter if wall else _floor_painter
	var ops: Array = _wall_ops if wall else _floor_ops
	for op in ops:
		match String(op["t"]):
			"dot":
				painter.draw_circle(op["c"], float(op["r"]), op["col"])
			"ellipse":
				_draw_ellipse(painter, op["c"], op["r"], op["col"])
			"run":
				var a: Vector2 = op["a"]
				var b: Vector2 = op["b"]
				var col: Color = op["col"]
				var steps := 4
				for k in range(steps):
					var t0 := float(k) / float(steps)
					var t1 := float(k + 1) / float(steps)
					var seg_col := Color(col.r, col.g, col.b, col.a * (1.0 - t0))
					painter.draw_line(a.lerp(b, t0), a.lerp(b, t1), seg_col, lerpf(1.8, 0.8, t0))
	# Ops are baked into the never-clearing viewport on this render; drop them so
	# they are never drawn twice.
	ops.clear()


func _draw_ellipse(painter: Node2D, c: Vector2, r: Vector2, col: Color) -> void:
	# Soft edge: faint outer ellipse + denser core.
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var n := 18
	for i in range(n):
		var ang := TAU * float(i) / float(n)
		var v := Vector2(cos(ang), sin(ang))
		outer.append(c + v * r)
		inner.append(c + v * r * 0.62)
	painter.draw_colored_polygon(outer, Color(col.r, col.g, col.b, col.a * 0.45))
	painter.draw_colored_polygon(inner, Color(col.r, col.g, col.b, col.a * 0.7))
