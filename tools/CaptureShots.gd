extends SceneTree

## Renders the game (non-headless) and saves screenshots of the key screens.
## Usage:
##   godot --path . --script res://tools/CaptureShots.gd -- --out=C:/some/folder

var out_dir := "user://shots"
var arena: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	var ps := load("res://scenes/Arena.tscn") as PackedScene
	arena = ps.instantiate()
	arena.settings_path = "user://capture_settings.cfg"
	root.add_child(arena)
	await wait(0.6)
	await shot("1_title")

	arena._on_start_requested({"p1": 2, "p2": 3, "mode": "duel"})
	await wait(0.3)
	await shot("2_round_intro")
	await wait(1.6)
	# Let the AI fight a little, then force some gore for the screenshot.
	await wait(1.5)
	arena.p2.position.x = arena.p1.position.x + 190.0
	arena.p2.apply_blade_damage("arm_l", 30.0, arena.p2.position + Vector2(-20, -150), Vector2(1, -0.2), true, true, 1.0)
	await wait(0.5)
	arena.p1.apply_blade_damage("thigh_l", 30.0, arena.p1.position + Vector2(0, -60), Vector2(-1, -0.2), true, true, 1.0)
	await wait(1.2)
	await shot("3_fight_gore")

	arena._toggle_pause()
	await shot("4_pause")
	arena._toggle_pause()

	arena.p2.kill_fighter()
	await wait(0.8)
	await shot("5_ko")
	await wait(3.5)
	arena.p2.kill_fighter()
	await wait(3.5)
	await shot("6_result")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_settings.cfg"))
	get_root().get_tree().paused = false
	Engine.time_scale = 1.0
	quit(0)
