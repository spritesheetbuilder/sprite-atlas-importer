@tool
extends EditorPlugin

## Sprite Atlas Importer — Godot 4 editor plugin
## Imports a sprite sheet + its metadata (Phaser/TexturePacker JSON, Unity .frames.json or
## Sparrow XML) and builds a SpriteFrames resource, one animation per action prefix.
##
## Metadata is produced by the free browser tools at https://spritesheetbuilder.com/

const Importer := preload("res://addons/sprite_atlas_importer/atlas_importer.gd")

var _meta_dialog: EditorFileDialog
var _png_dialog: EditorFileDialog
var _pending_meta_path := ""

func _enter_tree() -> void:
	add_tool_menu_item("Import Sprite Atlas (JSON/XML)…", _on_import_pressed)

func _exit_tree() -> void:
	remove_tool_menu_item("Import Sprite Atlas (JSON/XML)…")
	if _meta_dialog:
		_meta_dialog.queue_free()
	if _png_dialog:
		_png_dialog.queue_free()

func _on_import_pressed() -> void:
	if _meta_dialog == null:
		_meta_dialog = EditorFileDialog.new()
		_meta_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_meta_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_meta_dialog.add_filter("*.json,*.xml", "Atlas metadata")
		_meta_dialog.title = "Select the atlas metadata (JSON or XML)"
		_meta_dialog.file_selected.connect(_on_meta_selected)
		EditorInterface.get_base_control().add_child(_meta_dialog)
	_meta_dialog.popup_centered_ratio(0.6)

func _on_meta_selected(path: String) -> void:
	_pending_meta_path = path
	var sibling := _find_sibling_image(path)
	if sibling != "":
		# The common case: sheet.png next to sheet.json — no second prompt.
		_build_atlas(path, sibling)
		return
	if _png_dialog == null:
		_png_dialog = EditorFileDialog.new()
		_png_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_png_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_png_dialog.add_filter("*.png,*.webp", "Sprite sheet image")
		_png_dialog.title = "Select the sprite sheet image for %s" % path.get_file()
		_png_dialog.file_selected.connect(_on_png_selected)
		EditorInterface.get_base_control().add_child(_png_dialog)
	_png_dialog.popup_centered_ratio(0.6)

func _on_png_selected(path: String) -> void:
	_build_atlas(_pending_meta_path, path)

# sheet.json -> sheet.png. `sheet.frames.json` is the name the Unity shape is normally
# exported under, so the `.frames` part belongs to the metadata, not to the sheet:
# try `sheet.frames.png` first (literal basename) and then `sheet.png`.
func _find_sibling_image(meta_path: String) -> String:
	var base := meta_path.get_basename()
	var stems := [base]
	if base.ends_with(".frames"):
		stems.append(base.trim_suffix(".frames"))
	for stem in stems:
		for ext in [".png", ".webp"]:
			if FileAccess.file_exists(stem + ext):
				return stem + ext
	return ""

# NB: must not be called `_build` — EditorPlugin already declares `_build() -> bool`
# (the editor build-system hook), and shadowing it is a parse error that stops the
# whole plugin from loading.
func _build_atlas(meta_path: String, image_path: String) -> void:
	var importer := Importer.new()
	var result: Dictionary = importer.build(meta_path, image_path)
	if not result.get("ok", false):
		_alert("Sprite Atlas Importer", str(result.get("error", "Unknown error")))
		return

	var sheet_name: String = image_path.get_file().get_basename()
	var out_path := image_path.get_basename() + "_frames.tres"
	var err := ResourceSaver.save(result["sprite_frames"], out_path)
	if err != OK:
		_alert("Sprite Atlas Importer", "Could not write %s (error %d)." % [out_path, err])
		return

	var lines := PackedStringArray()
	lines.append("Imported %d frames into %d animation(s)." % [result["frame_count"], result["animation_count"]])
	lines.append("")
	lines.append("Saved as:")
	lines.append(out_path)
	lines.append("")
	lines.append("Asset names:")
	for n in result["animations"]:
		lines.append("  • %s" % n)
	lines.append("")
	lines.append("Note: files outside res:// must be moved into the project before they can be used.")
	_alert("Sprite Atlas Importer — %s" % sheet_name, "\n".join(lines))

func _alert(title: String, text: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.dialog_text = text
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()
