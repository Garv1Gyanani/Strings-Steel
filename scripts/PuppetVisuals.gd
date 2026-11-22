class_name PuppetVisuals
extends RefCounted

## Shared visual constants & ink-silhouette ShaderMaterial for all puppet sprites and weapons.

const REAR_LIMB_TINT := Color(0.79, 0.77, 0.84, 1.0)
const SCABBARD_TINT := Color(0.78, 0.75, 0.80, 1.0)

static var _ink_material: ShaderMaterial = null


static func get_ink_material() -> ShaderMaterial:
	if _ink_material != null:
		return _ink_material
	if ResourceLoader.exists("res://scripts/PuppetInk.gdshader"):
		var sh := load("res://scripts/PuppetInk.gdshader") as Shader
		if sh != null:
			var mat := ShaderMaterial.new()
			mat.shader = sh
			_ink_material = mat
	return _ink_material


static func apply_ink_material(sp: CanvasItem) -> void:
	if sp == null:
		return
	var mat := get_ink_material()
	if mat != null:
		sp.material = mat


static func set_base_tint(sp: CanvasItem, col: Color) -> void:
	if sp == null:
		return
	sp.modulate = col
	sp.set_meta("base_tint", col)
