@tool
extends EditorScript

## Editor Tool Script: Open this script in Godot and click File -> Run (Ctrl+Shift+X)
## to procedurally regenerate all reusable fighter .tscn rigs from data/rig_metadata.json.

func _run() -> void:
	var built := CharacterRigBuilder.build_all_fighters()
	print("BuildRigsEditor: Regenerated ", built.size(), " fighter scene(s): ", built)
