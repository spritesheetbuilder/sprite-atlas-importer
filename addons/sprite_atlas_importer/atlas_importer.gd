@tool
extends RefCounted

## Parses the three atlas metadata shapes the sprite sheet tools emit and returns a
## SpriteFrames resource:
##   1. Phaser / TexturePacker JSON  — { "frames": { "name": { "frame": {x,y,w,h}, ... } }, "meta": {...} }
##   2. Unity .frames.json           — { "width": w, "height": h, "frames": [ {name,x,y,width,height} ] }
##   3. Sparrow XML                  — <TextureAtlas imagePath=".."><SubTexture name x y width height/></TextureAtlas>
##
## `build()` returns { ok, sprite_frames, animations, frame_count, animation_count } or { ok=false, error }.

const DEFAULT_FPS := 12.0
const LOOP_ANIMATION := true

func build(meta_path: String, image_path: String) -> Dictionary:
	if not FileAccess.file_exists(meta_path):
		return {"ok": false, "error": "Metadata file not found:\n%s" % meta_path}
	if not FileAccess.file_exists(image_path):
		return {"ok": false, "error": "Image file not found:\n%s" % image_path}

	var texture := _load_texture(image_path)
	if texture == null:
		return {"ok": false, "error": "Could not load the sheet image:\n%s" % image_path}

	var text := FileAccess.get_file_as_string(meta_path)
	if text.is_empty():
		return {"ok": false, "error": "Metadata file is empty:\n%s" % meta_path}

	var rects: Array = []
	var ext := meta_path.get_extension().to_lower()
	if ext == "xml":
		rects = _parse_sparrow_xml(text)
	else:
		rects = _parse_json(text)

	if rects.is_empty():
		return {"ok": false, "error": "No frames found in %s.\nExpected a Phaser/TexturePacker JSON, a Unity .frames.json or a Sparrow XML." % meta_path.get_file()}

	return _to_sprite_frames(rects, texture)

func _load_texture(image_path: String) -> Texture2D:
	# Load through the resource loader when the image is inside the project (imported),
	# otherwise read the bytes so sheets living outside res:// still work.
	# The editor's file dialog always hands back an absolute path, so localize it first.
	var local := ProjectSettings.localize_path(image_path)
	if local.begins_with("res://") and ResourceLoader.exists(local):
		var t := ResourceLoader.load(local)
		if t is Texture2D:
			return t
	var bytes := FileAccess.get_file_as_bytes(image_path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := FAILED
	var lower := image_path.to_lower()
	if lower.ends_with(".webp"):
		err = img.load_webp_from_buffer(bytes)
	else:
		err = img.load_png_from_buffer(bytes)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

func _parse_json(text: String) -> Array:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var out: Array = []
	var frames: Variant = data.get("frames", null)

	# Shape 1: Phaser / TexturePacker — dictionary keyed by frame name.
	if typeof(frames) == TYPE_DICTIONARY:
		for key in frames.keys():
			var entry: Variant = frames[key]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var rect: Variant = entry.get("frame", entry)
			if typeof(rect) != TYPE_DICTIONARY:
				continue
			var r := _rect_from(rect)
			if r.size.x > 0 and r.size.y > 0:
				out.append({"name": str(entry.get("filename", key)), "rect": r})
		return out

	# Shape 2: Unity helper — array of {name,x,y,width,height} (or w/h).
	if typeof(frames) == TYPE_ARRAY:
		for entry in frames:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var r := _rect_from(entry)
			if r.size.x > 0 and r.size.y > 0:
				out.append({"name": str(entry.get("name", "frame")), "rect": r})
		return out

	return out

# Accepts x/y/w/h (Phaser) and x/y/width/height (Unity) alike.
func _rect_from(d: Dictionary) -> Rect2:
	var x := float(d.get("x", 0))
	var y := float(d.get("y", 0))
	var w := float(d.get("w", d.get("width", 0)))
	var h := float(d.get("h", d.get("height", 0)))
	return Rect2(x, y, w, h)

func _parse_sparrow_xml(text: String) -> Array:
	var out: Array = []
	var parser := XMLParser.new()
	if parser.open_buffer(text.to_utf8_buffer()) != OK:
		return out
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if parser.get_node_name() != "SubTexture":
			continue
		var name := parser.get_named_attribute_value_safe("name")
		if name.is_empty():
			name = "frame%04d" % (out.size() + 1)
		var r := Rect2(
			float(parser.get_named_attribute_value_safe("x")),
			float(parser.get_named_attribute_value_safe("y")),
			float(parser.get_named_attribute_value_safe("width")),
			float(parser.get_named_attribute_value_safe("height"))
		)
		if r.size.x > 0 and r.size.y > 0:
			out.append({"name": name, "rect": r})
	return out

func _to_sprite_frames(rects: Array, texture: Texture2D) -> Dictionary:
	# Group frames into animations by the non-numeric prefix: idle0001 -> "idle".
	var strip := RegEx.new()
	strip.compile("[0-9]+$")

	var groups: Dictionary = {}          # animation name -> Array of {name, rect}
	var order: Array = []                # preserve first-seen order
	for entry in rects:
		var raw: String = entry["name"]
		var anim := strip.sub(raw, "", false)
		if anim.is_empty():
			anim = "default"
		if not groups.has(anim):
			groups[anim] = []
			order.append(anim)
		groups[anim].append(entry)

	# Sort inside each animation by the numeric suffix so atlas placement order cannot
	# shuffle the sequence (the classic bug when a sheet is auto-packed).
	for anim in groups.keys():
		groups[anim].sort_custom(func(a, b): return _suffix(a["name"]) < _suffix(b["name"]))

	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var total := 0
	for anim in order:
		sf.add_animation(anim)
		sf.set_animation_speed(anim, DEFAULT_FPS)
		sf.set_animation_loop(anim, LOOP_ANIMATION)
		for entry in groups[anim]:
			var at := AtlasTexture.new()
			at.atlas = texture
			at.region = entry["rect"]
			sf.add_frame(anim, at)
			total += 1

	return {
		"ok": true,
		"sprite_frames": sf,
		"animations": order,
		"frame_count": total,
		"animation_count": order.size(),
	}

func _suffix(name: String) -> int:
	var digits := ""
	for i in range(name.length() - 1, -1, -1):
		var c := name[i]
		if c >= "0" and c <= "9":
			digits = c + digits
		else:
			break
	return int(digits) if not digits.is_empty() else 0
