extends SceneTree

## Headless / CLI Builder for Strings and Steel.
## Usage:
##   godot --headless --path "c:/Users/dell/asda/stringsandsteel/string-and-steel" --script res://tools/BuildAllRigs.gd

func _init() -> void:
	var builder_script := load("res://tools/CharacterRigBuilder.gd")
	var built: Array[String] = builder_script.build_all_fighters()
	print("BuildAllRigs: Built %d fighter scenes." % built.size())
	_build_arena_scene()
	quit()


func _build_arena_scene() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes"))

	var arena := Node2D.new()
	arena.name = "Arena"
	arena.set_script(load("res://scripts/ArenaController.gd"))

	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.position = Vector2(640, 360)
	arena.add_child(cam)
	cam.owner = arena

	# Dark Puppet Theater Backdrop
	var bg := ColorRect.new()
	bg.name = "StageBackdrop"
	bg.color = Color(0.08, 0.06, 0.07, 1.0)
	bg.position = Vector2(0, 0)
	bg.size = Vector2(1280, 720)
	bg.z_index = -50
	arena.add_child(bg)
	bg.owner = arena

	var floor_rect := ColorRect.new()
	floor_rect.name = "StageFloor"
	floor_rect.color = Color(0.18, 0.13, 0.10, 1.0)
	floor_rect.position = Vector2(0, 560)
	floor_rect.size = Vector2(1280, 160)
	floor_rect.z_index = -40
	arena.add_child(floor_rect)
	floor_rect.owner = arena

	# Instantiate both procedurally rigged fighters
	var p1_scene := ResourceLoader.load("res://scenes/fighters/Landsknecht.tscn") as PackedScene
	if p1_scene != null:
		var p1 := p1_scene.instantiate() as Node2D
		p1.name = "Landsknecht"
		p1.position = Vector2(440, 445)
		arena.add_child(p1)
		p1.owner = arena

	var p2_scene := ResourceLoader.load("res://scenes/fighters/Fechtmeister.tscn") as PackedScene
	if p2_scene != null:
		var p2 := p2_scene.instantiate() as Node2D
		p2.name = "Fechtmeister"
		p2.position = Vector2(840, 445)
		arena.add_child(p2)
		p2.owner = arena

	var packed := PackedScene.new()
	var err := packed.pack(arena)
	if err == OK:
		ResourceSaver.save(packed, "res://scenes/Arena.tscn")
		print("Built playable stage scene: res://scenes/Arena.tscn")
	else:
		push_error("BuildAllRigs: Failed to pack Arena.tscn (err=%d)" % err)
	arena.free()
