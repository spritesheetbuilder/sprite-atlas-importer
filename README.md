# Sprite Atlas Importer (Godot 4)

Import a sprite sheet plus its atlas metadata and get a ready-to-use **`SpriteFrames`** resource:
one animation per action prefix, frames sorted, `AtlasTexture` regions set from the metadata.

Primary use case: you exported a sheet for Phaser or Unity (or you have a Flixel/FNF Sparrow atlas) and
you want the same sheet in Godot without re-cutting it by hand.

## Supported metadata

| Format | Shape |
|---|---|
| Phaser / TexturePacker JSON | `{ "frames": { "<name>": { "frame": { "x","y","w","h" }, ... } }, "meta": {...} }` |
| Unity `.frames.json` | `{ "width": w, "height": h, "frames": [ { "name","x","y","width","height" } ] }` |
| Sparrow XML | `<TextureAtlas imagePath="sheet.png"><SubTexture name="idle0001" x y width height/></TextureAtlas>` |

Free browser tools that emit all three, plus a Godot `.tres` directly:
<https://spritesheetbuilder.com/> — engine notes at <https://spritesheetbuilder.com/engines>.

## Install

1. Copy the `addons/sprite_atlas_importer/` folder into your project's `addons/` directory.
2. **Project → Project Settings → Plugins** → enable **Sprite Atlas Importer**.
3. **Project → Tools → Import Sprite Atlas (JSON/XML)…**
4. Pick the metadata file. If a `.png`/`.webp` with the same basename sits next to it, the image is picked
   up automatically — including the `sheet.frames.json` + `sheet.png` pair; otherwise you are asked for it.
5. The result is written next to the image as `<sheet>_frames.tres`.

## Behaviour

- Frames are grouped into animations by stripping the trailing digits from the frame name:
  `idle0001`, `idle0002` → the `idle` animation. A name that is *only* digits (`0007`) has no prefix left to
  group under and lands in `default`; a name with no digits at all (`explosion`) keeps its own name as the
  animation.
- Inside an animation, frames are sorted by that numeric suffix, **not** by their order in the file. Atlas
  order is the packer's placement order and is not animation order — sorting here is what prevents the
  "right poses, wrong sequence" bug.
- Default animation speed is 12 FPS and animations loop. Change both on the resource afterwards.
- Sheets inside `res://` are loaded through the project's own import, so the `.tres` references the imported
  PNG and re-exporting the sheet updates the animation. Sheets outside `res://` are read from disk and
  wrapped in an `ImageTexture`, which gets embedded in the `.tres`: the resource is self-contained, but it
  carries a copy of the image (a 1200×630 sheet produces a ~9 MB `.tres`), so keep sheets in the project
  when you can.

## Limitations

- Trimmed and rotated frames are not reconstructed. Frame rects are used as-is; the tools linked above
  do not emit rotated frames, which is why this is acceptable here.
- No animation preview or per-animation FPS editing in the dock — that is what the `SpriteFrames` editor
  is for.

## Status: executed and passing (Godot 4.7.2)

Run headlessly on **Godot 4.7.2-stable (official, win64)** in a throwaway project: the plugin was enabled in
Project Settings and then driven through its real code path (Tools menu handler → file dialog →
`file_selected` → import → `ResourceSaver.save`), and each resulting `.tres` was reloaded from disk and
asserted on. **91 assertions, 0 failures.**

Verified:

- The plugin enables with no script errors and registers **Tools → Import Sprite Atlas (JSON/XML)…** (found
  in the editor's Tools menu at runtime).
- Phaser/TexturePacker JSON, Unity `.frames.json` and Sparrow XML all import, each writing
  `<sheet>_frames.tres` next to the image.
- One animation per action prefix, and frames sorted by numeric suffix rather than file order — fixtures put
  `idle0002`/`idle0010` before `idle0001` in the file and assert the exported order is 1, 2, 10.
- `AtlasTexture` regions equal the metadata rects and are never zero-sized; every animation starts at 12 FPS
  and loops.
- The `default` bucket (digits-only names), unnamed Sparrow `SubTexture` fallback names, and skipping of
  zero-sized entries.
- Sheet auto-pick next to the metadata — including the `sheet.frames.json` + `sheet.png` pair — the second
  prompt when no sibling sheet exists, and the error dialog when the metadata contains no frames.
- In-project sheets produce a `.tres` that references the imported PNG (~1.5 KB); sheets outside the project
  embed the image instead.

Three bugs came out of that pass:

- The import helper was named `_build`, which shadows `EditorPlugin._build() -> bool`. That is a GDScript
  parse error, so the plugin never loaded at all: no Tools menu entry, nothing importable. Reproduced on a
  copy of the pre-fix source, then renamed to `_build_atlas`.
- `_on_meta_selected()` looked for the sheet as `path.get_basename() + ".png"`, so the normal Unity pair
  `sheet.frames.json` + `sheet.png` was searched for as `sheet.frames.png` and the auto-pick never fired. It
  now also tries the name without the `.frames` suffix, and accepts a sibling `.webp`.
- `_load_texture()` only took the project-import branch when it was handed a `res://` path, which the file
  dialog never returns — so in-project sheets were wrapped in an `ImageTexture` (and embedded in the `.tres`)
  instead of using the project's own import. It localizes the path first; an in-project sheet now gives a
  ~1.5 KB `.tres` pointing at the imported PNG.


## Licence

MIT. See `LICENSE`.
