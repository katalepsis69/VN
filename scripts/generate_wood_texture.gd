extends SceneTree

## One-off generator for the bundled panel texture (assets/ui/container_wood.png).
## Run: godot --headless --path . --script res://scripts/generate_wood_texture.gd
##
## Why: the retired Cozy UI Pack panel was 1511x384 at ~12KB, i.e. nearly flat
## colour, so the nine-patch centre read as a washed-out peach smear across a
## ~1100px textbox. This renders a real wood panel instead: y-dominant grain
## streaks (they survive the nine-patch stretch and stay seam-safe), a darker
## frame with a bevel, and rounded corners. The centre region keeps the pack's
## average tone #dd9a79 so every measured contrast claim in DESIGN.md (tint x
## base -> cream >= 5:1) still holds; test_verification.gd asserts the average.
##
## Deliberate: same dimensions as the pack file, so both nine-patch call sites
## (dialogue box 30/22 margins, shelf plank 26/12) keep their proportions.

const OUT_PATH := "res://assets/ui/container_wood.png"
const W := 1511
const H := 384
const MARGIN_X := 30
const MARGIN_Y := 22
const CORNER_RADIUS := 16
const BASE := Color("dd9a79") # pack panel average; the tint math is anchored to it

func _init() -> void:
	_report_original()
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)

	# Grain: broad tone bands + thin streak lines, varying along y only so the
	# nine-patch edge strips blend into the stretched centre; a whisper of 2D
	# mottling keeps it from looking like scanlines.
	var broad := FastNoiseLite.new()
	broad.seed = 7
	broad.frequency = 0.9
	var fine := FastNoiseLite.new()
	fine.seed = 23
	fine.frequency = 6.0
	var mottle := FastNoiseLite.new()
	mottle.seed = 41
	mottle.frequency = 0.02

	# factor[y][x] is a brightness multiplier; normalised so the centre's mean
	# is exactly 1.0, which pins the centre average to BASE.
	var factors: Array = []
	factors.resize(H)
	var y := 0
	while y < H:
		var row: PackedFloat32Array = PackedFloat32Array()
		row.resize(W)
		var b := 0.055 * broad.get_noise_2d(11.7, float(y) * 0.22)
		var f := 0.022 * fine.get_noise_2d(3.3, float(y) * 1.7)
		var grad := 0.012 * (1.0 - float(y) / float(H))
		var x := 0
		while x < W:
			row[x] = 1.0 + b + f + grad + 0.02 * mottle.get_noise_2d(float(x), float(y))
			x += 1
		factors[y] = row
		y += 1

	# normalise the centre region (frame excluded: text never sits on the frame)
	var sum := 0.0
	var n := 0
	y = MARGIN_Y
	while y < H - MARGIN_Y:
		var row2: PackedFloat32Array = factors[y]
		var x2 := MARGIN_X
		while x2 < W - MARGIN_X:
			sum += row2[x2]
			n += 1
			x2 += 1
		y += 1
	var mean := sum / float(n)
	var corr := 1.0 / mean

	y = 0
	while y < H:
		var r: PackedFloat32Array = factors[y]
		var x3 := 0
		while x3 < W:
			var in_frame := x3 < MARGIN_X or x3 >= W - MARGIN_X or y < MARGIN_Y or y >= H - MARGIN_Y
			var factor: float
			if in_frame:
				if x3 < 2 or x3 >= W - 2 or y < 2 or y >= H - 2:
					factor = 0.45 # outer edge line
				elif (x3 >= MARGIN_X - 2 and x3 < MARGIN_X) \
						or (x3 >= W - MARGIN_X and x3 < W - MARGIN_X + 2) \
						or (y >= MARGIN_Y - 2 and y < MARGIN_Y) \
						or (y >= H - MARGIN_Y and y < H - MARGIN_Y + 2):
					factor = 1.12 # inner bevel highlight
				else:
					factor = 0.62 # frame band
			else:
				factor = r[x3] * corr
			img.set_pixel(x3, y, Color(BASE.r * factor, BASE.g * factor, BASE.b * factor, 1.0))
			x3 += 1
		y += 1

	_round_corners(img)

	var err := img.save_png(OUT_PATH)
	if err != OK:
		printerr("GENERATE FAILED: ", err)
		quit(1)
		return
	_report_saved()
	print("--- Wood texture generated: %s ---" % OUT_PATH)
	quit(0)

## Rounded corners via alpha, matching the flat textbox style's radius language.
func _round_corners(img: Image) -> void:
	var r := float(CORNER_RADIUS)
	for cy in CORNER_RADIUS:
		for cx in CORNER_RADIUS:
			var d := Vector2(float(cx) + 0.5 - r, float(cy) + 0.5 - r).length()
			if d > r:
				img.set_pixel(cx, cy, Color(0, 0, 0, 0))
				img.set_pixel(W - 1 - cx, cy, Color(0, 0, 0, 0))
				img.set_pixel(cx, H - 1 - cy, Color(0, 0, 0, 0))
				img.set_pixel(W - 1 - cx, H - 1 - cy, Color(0, 0, 0, 0))

## Print the stats the design claims rest on, so a regeneration can be checked.
func _report_saved() -> void:
	var check := Image.load_from_file(OUT_PATH)
	if check == null:
		printerr("saved file unreadable")
		return
	var avg := Color(0, 0, 0)
	var n := 0
	var y := MARGIN_Y
	while y < H - MARGIN_Y:
		var x := MARGIN_X
		while x < W - MARGIN_X:
			avg += check.get_pixel(x, y)
			n += 1
			x += 4
		y += 4
	avg /= float(n)
	print("GENERATED %dx%d centre avg #%s (target #dd9a79) corner a=%.2f" % [
		check.get_width(), check.get_height(), avg.to_html(false), check.get_pixel(2, 2).a])

func _report_original() -> void:
	if not FileAccess.file_exists(OUT_PATH):
		print("No existing panel texture (fresh generation)")
		return
	var im := Image.load_from_file(OUT_PATH)
	if im == null:
		print("Existing panel texture unreadable (import cache); regenerating anyway")
		return
	print("REPLACING %dx%d corner a=%.2f" % [im.get_width(), im.get_height(), im.get_pixel(2, 2).a])
