extends SceneTree

## Smoke test: instantiate the real main scene headless and simulate a reading session.
## Run: godot --headless --path . --testcfg --script res://scripts/smoke_main.gd
## --testcfg points the app at a scratch config so the real shelf is never touched.

func _init() -> void:
	print("--- Smoke: instantiate main scene ---")
	DirAccess.make_dir_recursive_absolute("user://test_config")
	if FileAccess.file_exists("My UI/smoke_panel.png"):
		DirAccess.remove_absolute("My UI/smoke_panel.png")
	var scene: PackedScene = load("res://scenes/main.tscn")
	assert(scene != null, "main.tscn failed to load")
	var main = scene.instantiate() # untyped: dynamic access to script members
	assert(main != null, "main scene failed to instantiate")
	root.add_child(main)
	await process_frame
	await process_frame

	# Load a document like a user would
	main.load_document("res://assets/sample_paper.txt", 0)
	await process_frame
	assert(main.slides.size() > 0, "no slides loaded from sample")
	print("Loaded %d slides, state=%s" % [main.slides.size(), main.current_state])

	# Layout regression guard: controls configured via presets must have real size
	# (the anchors_preset property assignment silently produced zero-sized controls)
	assert(main.bg_rect.size.x > 500 and main.bg_rect.size.y > 400, "bg_rect zero-sized (anchors bug)")
	assert(main.bg_rect.texture != null, "bg_rect.texture never assigned")
	assert(main.sprite_holder.size.x > 300 and main.sprite_holder.size.y > 100, "sprite_holder zero-sized (anchors bug)")
	assert(main.dialogue_box.size.x > 500, "dialogue_box zero-sized")
	assert(main.dialogue_box.offset_top <= -160.0, "textbox layout not applied")
	assert(main.sprite_names.size() == main.sprite_textures.size(), "sprite names out of sync")
	assert(main.menu_bg_rect.size.x > 500, "menu backdrop zero-sized")
	assert(main.bg_textures.size() > 40, "background pool suspiciously small: %d" % main.bg_textures.size())
	# Backgrounds: fit mode is now a decision (auto/fill/fit), not a fixed mode.
	# The darkened stretched copy behind stays fixed regardless of mode.
	main.manager.bg_fit_mode = 2
	main._apply_bg_fit(main.bg_rect, main.bg_rect.texture)
	assert(main.bg_rect.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "fit mode not applied")
	main.manager.bg_fit_mode = 1
	main._apply_bg_fit(main.bg_rect, main.bg_rect.texture)
	assert(main.bg_rect.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "fill mode not applied")
	main.manager.bg_fit_mode = 0
	var wide := ImageTexture.create_from_image(Image.create_empty(1920, 1080, false, Image.FORMAT_RGBA8))
	var tall := ImageTexture.create_from_image(Image.create_empty(600, 900, false, Image.FORMAT_RGBA8))
	main._apply_bg_fit(main.bg_rect, wide)
	assert(main.bg_rect.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "auto should fill a 16:9 image")
	main._apply_bg_fit(main.bg_rect, tall)
	assert(main.bg_rect.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "auto should frame a portrait image")
	main._apply_bg_fit(main.bg_rect, main.bg_rect.texture)
	assert(main.bg_back != null and main.bg_back.stretch_mode == TextureRect.STRETCH_SCALE, "bg backdrop missing")
	assert(not ("particles" in main), "floating particles should be gone entirely")
	print("Layout guard passed: bg=%s sprite=%s pool=%d" % [main.bg_rect.size, main.sprite_holder.size, main.bg_textures.size()])

	# Sprite band: the character is sandwiched between the top bar and the textbox
	var band_top: float = main.sprite_holder.global_position.y
	var band_bottom: float = band_top + main.sprite_holder.size.y
	var box_top: float = main.dialogue_box.global_position.y
	assert(band_top >= main.top_bar.size.y - 0.5, "sprite reaches into the top bar")
	assert(band_bottom <= box_top + 0.5, "sprite reaches behind the textbox")
	print("Sprite band guard passed: y %.0f..%.0f, textbox top %.0f" % [band_top, band_bottom, box_top])

	# Shrink-to-fit: Font Size is a ceiling; long slides draw smaller, never below the floor
	var orig_fs: int = main.manager.font_size
	main.manager.font_size = 30
	var long_slide := "The quick brown fox jumps over the lazy dog and keeps running through the wet field. ".repeat(6)
	var tight: int = main._fit_font_size(long_slide, 1100.0, 90.0)
	var roomy: int = main._fit_font_size("Short sentence.", 1100.0, 400.0)
	assert(tight < 30 and tight >= 18, "long slide did not shrink into range: %d" % tight)
	# A box this tall fits an in-between size; a broken measurement always lands on the floor
	var mid: int = main._fit_font_size(long_slide, 1100.0, 200.0)
	assert(mid > 18 and mid < 30, "fit should pick a measured size between floor and ceiling, got %d" % mid)
	assert(roomy == 30, "short slide should keep the full font size: %d" % roomy)
	main.manager.font_size = orig_fs
	print("Shrink-to-fit guard passed: 30 -> %d px on an over-long slide" % tight)

	# Typewriter skip path: advance input while typing must finish the line instantly
	assert(main.is_typing, "typewriter should be active after showing a slide")
	main._handle_advance_input()
	assert(not main.is_typing, "skip input did not finish the typewriter")

	# Advance through every slide (exercises bg/sprite rotation + progress save)
	for i in range(main.slides.size()):
		main._advance_slide()
	print("Advanced to slide %d / %d" % [main.current_slide_idx + 1, main.slides.size()])
	assert(main.current_slide_idx == main.slides.size() - 1, "did not reach last slide")

	# Backwards navigation
	main._previous_slide()
	assert(main.current_slide_idx == main.slides.size() - 2, "previous slide broken")

	# Overlays exist and can toggle without crashing
	main._toggle_auto()
	main._open_backlog()
	await process_frame
	main._show_state(main.State.MENU)
	await process_frame
	await process_frame

	# Book shelf: the menu must build real-sized shelf UI and at least one spine
	# (the sample doc was opened above, so the shelf has one resumable book)
	assert(main.shelf_panel.size.x > 400, "shelf panel zero-sized")
	assert(main.hover_strip.size.y >= 60, "hover strip too small")
	assert(main.spotlight_box.visible and main.spotlight_box.modulate.a == 1.0, "spotlight should show the active book poster")
	var spine_count := 0
	for c in main.shelf_row.get_children():
		if c is Button:
			spine_count += 1
	assert(spine_count > 0, "no book spines on the shelf")
	var one_spine: Button = main.shelf_row.get_children().filter(func(c): return c is Button)[0]
	assert(one_spine.size.x >= 30 and one_spine.size.y >= 130, "book spine not sized: %s" % [one_spine.size])
	assert(one_spine.clip_contents, "book spine must have clip_contents = true")
	var one_lbl: Label = null
	for c in one_spine.get_children():
		if c is Label:
			one_lbl = c
	assert(one_lbl != null, "book spine label missing")
	assert(one_lbl.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "spine label missing overrun ellipsis")
	print("Book shelf guard passed (%d spine(s))" % spine_count)

	# Menu fit: on the default 1280x720 window the whole menu must fit, or the bottom
	# action row clips off the edge (content min measured 773 vs 720 on 2026-10-09).
	var menu_min_y := 0.0
	for c in main.menu_overlay.get_children():
		if c is MarginContainer:
			menu_min_y = maxf(menu_min_y, (c as Control).get_combined_minimum_size().y)
	var declared_h: float = ProjectSettings.get_setting("display/window/size/viewport_height", 720)
	assert(menu_min_y <= declared_h, "menu is taller than the window: %.0f > %.0f" % [menu_min_y, declared_h])
	print("Menu fit guard passed (%.0f <= %.0f)" % [menu_min_y, declared_h])

	main._show_state(main.State.READING)
	await process_frame

	# Reactive expressions: mapper sanity + real override on the live sprite
	assert(MoodMapper.mood_for("What is this?") == "confused", "question should map to confused")
	assert(MoodMapper.mood_for("Stop that!!!") == "angry", "angry words should win")
	assert(MoodMapper.mood_for("Well... maybe.") == "thoughtfull", "ellipsis should map to thoughtfull")
	assert(MoodMapper.mood_for("A plain sentence.") == "", "no cue should return empty")
	var confused_tex: Texture2D = null
	for t in main.sprite_textures:
		if t.resource_path.contains("confused"):
			confused_tex = t
	assert(confused_tex != null, "Ginger confused expression missing")
	main._apply_reactive_mood("What is this?")
	assert(main.character_sprite.texture == confused_tex, "reactive mood did not apply")
	print("Mood mapper passed")

	# Audit guards
	assert(main._bbcode_safe("[12] note") == "[lb]12] note", "bbcode escaping broken")
	main.load_raw_text("Clipboard pasted text. Second sentence here.", "Test Paste")
	await process_frame
	for item in main.manager.get_recent_files():
		assert(not str(item["path"]).begins_with("clipboard://"), "clipboard doc leaked into recents")
	# Input double-fire: after clicking Auto, a Space press must not re-activate it
	main._show_state(main.State.READING)
	await process_frame
	var auto_before: bool = main.is_auto_reading
	main._toggle_auto() # simulates the click (button focus stays in headless too)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	main._input(key) # the reading keys are marked handled; direct call mirrors _input
	assert(main.is_auto_reading == (not auto_before), "space after Auto click re-toggled Auto (input double-fire)")
	print("Audit guards passed")

	# Book illustrations: markers stripped, images mapped, and the decode path works
	main.load_document("res://assets/sample_story.epub", 0)
	await process_frame
	assert(not main.slide_images.is_empty(), "sample epub images not mapped to slides")
	var img_slide: int = main.slide_images.keys()[0]
	var book_tex: Texture2D = main._book_image_for(img_slide)
	assert(book_tex != null, "book image failed to decode")
	print("Book image decode passed (%d image slide(s))" % main.slide_images.size())

	# Chapters: epub TOC becomes a jump list; opening the panel and jumping works
	assert(main.chapter_list.size() == 2, "epub chapters missing: %s" % [main.chapter_list])
	var target: int = int(main.chapter_list[1]["slide"])
	main._open_chapters()
	await process_frame
	assert(main.current_state == main.State.CHAPTERS, "chapters overlay did not open")
	assert(main.chapters_overlay.visible, "chapters overlay hidden in CHAPTERS state")
	main._jump_to_slide(target)
	await process_frame
	assert(main.current_state == main.State.READING, "jump did not return to reading")
	assert(main.current_slide_idx == target, "jump landed on the wrong slide")
	print("Chapters guard passed (%d chapter(s))" % main.chapter_list.size())

	# Settings tabs: the old screen was one ~20-row scroll; these replaced it.
	# Every tab must build real controls, and the two retired ones must be gone.
	main._show_state(main.State.SETTINGS)
	await process_frame
	assert(main.settings_tab_btns.size() == main.SETTINGS_TABS.size(), "settings tab count wrong")
	var tab_rows: Array = []
	var all_labels := ""
	for i in main.SETTINGS_TABS.size():
		main._select_settings_tab(i)
		await process_frame
		tab_rows.append(main.settings_grid.get_child_count())
		for c in main.settings_grid.get_children():
			if c is Button or c is CheckBox or c is Label:
				all_labels += " " + c.text
	for i in tab_rows.size():
		assert(tab_rows[i] > 0, "settings tab '%s' built no controls" % main.SETTINGS_TABS[i])
	assert(not all_labels.contains("Particles"), "particles setting is still present")
	assert(not all_labels.contains("Reset to Built-in"), "reset-art button is still present")
	print("Settings tabs guard passed: %s" % [tab_rows])

	# My Media: unticking an item must actually shrink the rotation pool
	main._show_state(main.State.MEDIA)
	await process_frame
	var tiles: int = main.media_grid.get_child_count()
	assert(tiles > 0, "My Media rendered no tiles")
	var pool_before: int = main.bg_textures.size()
	var entry: Dictionary = main._media["bg"][0]
	main._on_media_toggled(false, entry)
	await process_frame
	var pool_off: int = main.bg_textures.size()
	assert(pool_off == pool_before - 1, "untick did not remove the item: %d -> %d" % [pool_before, pool_off])
	assert(main.manager.off_backgrounds.has(entry["name"]), "untick not recorded")
	main._on_media_toggled(true, entry)
	await process_frame
	assert(main.bg_textures.size() == pool_before, "retick did not restore the pool")
	assert(not main.manager.off_backgrounds.has(entry["name"]), "retick not cleared")
	print("My Media guard passed (%d tiles, pool %d -> %d -> %d)" % [tiles, pool_before, pool_off, main.bg_textures.size()])

	# Settings return path: Menu -> Settings -> My Media -> ESC -> Settings -> ESC -> Menu.
	# ESC back out of My Media used to overwrite the saved origin, so Save & Close
	# (and ESC) bounced straight back into My Media forever.
	main._show_state(main.State.MENU)
	await process_frame
	main._show_state(main.State.SETTINGS)
	await process_frame
	main._show_state(main.State.MEDIA)
	await process_frame
	main._escape_back()
	await process_frame
	assert(main.current_state == main.State.SETTINGS, "ESC from My Media did not land in Settings")
	main._escape_back()
	await process_frame
	assert(main.current_state == main.State.MENU, "ESC from Settings did not land in Menu")
	print("Settings return-path guard passed (Settings -> My Media -> Settings -> Menu)")

	# A long book title must not widen the top bar: it is clipped with an ellipsis
	main.doc_title_label.text = "A Very Long Book Title That Would Otherwise Stretch The Whole Top Bar And Push The Menu Button Off The Right Edge Of The Screen"
	await process_frame
	var bar_min: float = main.top_bar.get_combined_minimum_size().x
	assert(bar_min <= main.size.x + 1.0, "long title widened the top bar: %.0f > %.0f" % [bar_min, main.size.x])
	assert(main.doc_title_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "title ellipsis not set")
	assert(main.doc_title_label.clip_text, "title clip_text not set")
	main.doc_title_label.text = "VN Reader"
	print("Top bar long-title guard passed (min width %.0f <= %.0f)" % [bar_min, main.size.x])

	# Motion: the perpetual idle-breathing scale loop is gone entirely
	assert(not main.has_method("_start_idle_breathing"), "idle breathing loop still exists")
	print("Motion guard passed (no idle breathing loop)")

	# Font: Atkinson Hyperlegible is bundled as the readable default; Kaph stays selectable
	var font_names: Array = []
	for e in main._media["font"]:
		font_names.append(e["name"])
	assert(font_names.has("Atkinson Hyperlegible"), "Atkinson missing from font list: %s" % [font_names])
	assert(font_names.has("Kaph"), "Kaph missing from font list: %s" % [font_names])
	if main.manager.custom_font_path.is_empty():
		assert(main._ui_font != null and main._ui_font.resource_path.contains("Atkinson"), "default font is not Atkinson: %s" % [main._ui_font])
	print("Font guard passed: %s" % [font_names])

	# Pinned menu background beats the rotation
	main.manager.menu_bg = main._bg_name(3)
	main._update_menu_background()
	assert(main.menu_bg_rect.texture == main._bg_texture(3), "pinned menu background not applied")
	main.manager.menu_bg = ""
	main._update_menu_background()
	print("Menu background guard passed (pinned then released)")

	# Hovering a spine previews that book in the spotlight; unhovering clears to nothing.
	# Crucially, hovering and unhovering must NEVER resize the shelf panel.
	main._show_state(main.State.MENU)
	await process_frame
	await process_frame
	var shelf: Array[Dictionary] = main.manager.get_recent_files()
	if not shelf.is_empty():
		assert(main.spotlight_box.modulate.a == 1.0, "spotlight should show active book on menu open")
		var shelf_size_before: Vector2 = main.shelf_panel.size
		main._show_spot(shelf[0])
		await process_frame
		assert(main.spot_title.text == shelf[0]["title"], "hover poster did not update the spotlight")
		assert(main.spotlight_box.modulate.a == 1.0, "spotlight not visible on hover")
		assert(main.shelf_panel.size == shelf_size_before, "shelf panel resized on hover: %s vs %s" % [main.shelf_panel.size, shelf_size_before])
		main._show_spot(main._spot_book)
		await process_frame
		assert(main.spotlight_box.modulate.a == 1.0, "spotlight remains visible for active book after hover")
		assert(main.shelf_panel.size == shelf_size_before, "shelf panel resized on exit: %s vs %s" % [main.shelf_panel.size, shelf_size_before])
		print("Hover poster guard passed (no resize, active book spotlight preserved)")

	# My Books folder exists and is scanned
	main._ensure_asset_folders()
	assert(DirAccess.dir_exists_absolute(main._asset_base_dir().path_join("My Books")), "My Books folder not created")
	assert(main._my_books() is Array, "My Books scan failed")
	print("My Books guard passed")

	# Delete flow: a book opened from outside My Books leaves the shelf but stays on
	# disk; a My Books book moves to the Recycle Bin. Exercised through the real
	# confirm-dialog signal, not a shortcut.
	var ext_path := "user://smoke_ext_book.txt"
	var ef := FileAccess.open(ext_path, FileAccess.WRITE)
	ef.store_string("External smoke book used by the delete guard.")
	ef.close()
	var ext_abs := ProjectSettings.globalize_path(ext_path)
	main.manager.save_progress(ext_abs, "Smoke External", 0, 5, 0)
	var ext_item: Dictionary = {}
	for r in main.manager.get_recent_files():
		if r["path"] == ext_abs:
			ext_item = r
	assert(not ext_item.is_empty(), "external smoke book not on the shelf")
	assert(main.hover_strip.mouse_filter == Control.MOUSE_FILTER_STOP, "hover strip must accept mouse for its Delete button")
	assert(not main.hover_delete_btn.visible, "Delete button visible on an empty card")
	main._set_hover_card(ext_item)
	assert(main.hover_delete_btn.visible, "Delete button hidden while a book is on the card")
	main._ask_delete()
	await process_frame
	assert(main._confirm_dialog.visible, "delete confirmation did not open")
	assert(main._confirm_dialog.size.x >= 500.0 and main._confirm_dialog.size.y >= 120.0, "confirm dialog sized wrong: %s" % [main._confirm_dialog.size])
	main._confirm_dialog.confirmed.emit()
	await process_frame
	main._confirm_dialog.hide()
	assert(FileAccess.file_exists(ext_path), "external delete must keep the file on disk")
	assert(main.manager.get_recent_files().filter(func(r): return r["path"] == ext_abs).is_empty(), "external book still on the shelf after delete")
	assert(not main.manager._load_config().has_section("doc_" + ext_abs.md5_text()), "external doc_ section not erased")
	DirAccess.remove_absolute(ext_abs)

	var mb_path: String = main._my_books_root().path_join("smoke_delete_me.txt")
	var mbf := FileAccess.open(mb_path, FileAccess.WRITE)
	mbf.store_string("Scratch book for the delete guard; it is moved to the Recycle Bin.")
	mbf.close()
	main.manager.save_progress(mb_path, "Smoke MyBooks", 0, 5, 0)
	var mb_item: Dictionary = {}
	for r in main.manager.get_recent_files():
		if r["path"] == mb_path:
			mb_item = r
	assert(not mb_item.is_empty(), "My Books smoke book not on the shelf")
	main._set_hover_card(mb_item)
	main._ask_delete()
	await process_frame
	main._confirm_dialog.confirmed.emit()
	await process_frame
	main._confirm_dialog.hide()
	main._set_hover_card({})
	assert(not main.hover_delete_btn.visible, "Delete button still visible on an empty card")
	assert(not FileAccess.file_exists(mb_path), "My Books delete did not move the file off disk")
	assert(main.manager.get_recent_files().filter(func(r): return r["path"] == mb_path).is_empty(), "My Books book still on the shelf after delete")
	print("Delete guards passed (external kept off-shelf, My Books trashed, dialog and button wired)")

	# The wooden skin must actually be applied by _apply_theme alone. This block
	# once lived inside the opacity fast path, so the whole app booted unskinned
	# and this test still printed "applied cleanly".
	main._apply_theme()
	await process_frame
	var bar_sb := main.top_bar.get_theme_stylebox("panel") as StyleBoxFlat
	assert(bar_sb != null and bar_sb.bg_color == Color("241c14e6"), "top bar not skinned: %s" % [bar_sb])
	var overlay_sb := main.settings_overlay.get_theme_stylebox("panel") as StyleBoxFlat
	assert(overlay_sb != null and overlay_sb.bg_color == Color("2a2018f2"), "overlay not skinned")
	assert(overlay_sb.content_margin_left == 60.0, "overlay margins missing")
	assert(main.media_overlay.get_theme_stylebox("panel") != null, "My Media has no panel")
	assert(main.hover_strip.get_theme_stylebox("panel") != null, "hover strip not skinned")
	var prim_sb := main.menu_primary_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert(prim_sb != null and prim_sb.bg_color == Color("9c3a2c"), "primary button not accent red")
	assert(main.shelf_panel.get_theme_stylebox("panel") is StyleBoxTexture, "shelf plank texture missing")
	assert(main.dialogue_box.get_theme_stylebox("panel") is StyleBoxTexture, "dialogue box texture missing")
	var box_tex := main.dialogue_box.get_theme_stylebox("panel") as StyleBoxTexture
	assert(box_tex.modulate_color.r < 0.9, "wood texture not darkened: cream text would be 1.96:1")
	assert(main.spot_cover.get_theme_stylebox("panel") != null, "spotlight cover panel unstyled")
	assert(not ("particles" in main), "floating particles should be gone entirely")
	print("Wooden skin guard passed: top bar, overlays, plank, hover strip, primary, textbox")

	# Look presets: switching must recolor real surfaces (whole app), and Cozy
	# Wood must round-trip exactly (it is the row every DESIGN.md claim is
	# measured against). The plank modulate assert also pins the audit fix: the
	# plank shipped untinted (raw light peach) because the modulate was never set.
	var slate: Dictionary = {}
	for l in main.LOOKS:
		if l["name"] == "Slate":
			slate = l
	assert(not slate.is_empty(), "Slate look missing from LOOKS")
	main.manager.ui_look = "Slate"
	main._look = main._current_look()
	main._apply_theme()
	await process_frame
	var slate_box := main.dialogue_box.get_theme_stylebox("panel") as StyleBoxTexture
	assert(slate_box.modulate_color == Color(slate["tint"], main.manager.textbox_opacity), "look did not retint the textbox: %s" % [slate_box.modulate_color])
	var slate_prim := main.menu_primary_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert(slate_prim.bg_color == slate["primary"], "look did not recolor the primary button")
	var slate_bar := main.top_bar.get_theme_stylebox("panel") as StyleBoxFlat
	assert(slate_bar.bg_color == slate["topbar"], "look did not recolor the top bar")
	var plank_sb := main.shelf_panel.get_theme_stylebox("panel") as StyleBoxTexture
	assert(plank_sb.modulate_color == Color(slate["tint"], 1.0), "plank not tinted by the look: %s" % [plank_sb.modulate_color])
	main.manager.ui_look = "Cozy Wood"
	main._look = main._current_look()
	main._apply_theme()
	await process_frame
	var cozy_prim := main.menu_primary_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert(cozy_prim.bg_color == Color("9c3a2c"), "cozy wood did not round-trip")
	var cozy_box := main.dialogue_box.get_theme_stylebox("panel") as StyleBoxTexture
	assert(cozy_box.modulate_color == Color(main.LOOKS[0]["tint"], main.manager.textbox_opacity), "cozy tint did not round-trip")
	print("Look guard passed (Slate applied and cleared, plank tinted)")

	# My UI: a bright custom panel dropped in the My UI folder is picked up,
	# dimmed by the readability safeguard, applied, and unticking restores the
	# built-in panel. The scratch file is removed afterwards.
	var myui_path: String = main._asset_base_dir().path_join("My UI").path_join("smoke_panel.png")
	var pim := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	pim.fill(Color(0.95, 0.9, 0.8))
	pim.save_png(myui_path)
	main._load_default_assets()
	var ui_entry: Dictionary = {}
	for e in main._media["ui"]:
		if e["name"] == "smoke_panel":
			ui_entry = e
	assert(not ui_entry.is_empty(), "smoke My UI file not scanned: %s" % [main._media["ui"]])
	main._media_kind = "ui"
	main._on_media_toggled(true, ui_entry)
	await process_frame
	assert(main._ui_tex_dim < 1.0, "bright custom panel was not dimmed: %f" % main._ui_tex_dim)
	var dim_used: float = main._ui_tex_dim
	var custom_box := main.dialogue_box.get_theme_stylebox("panel") as StyleBoxTexture
	assert(custom_box.texture != null and is_equal_approx(custom_box.modulate_color.r, main._ui_tex_dim), "custom panel dim not applied: %s" % [custom_box.modulate_color])
	assert(main._contrast(main.WOOD_INK, Color(0.95, 0.9, 0.8) * main._ui_tex_dim) >= 4.5, "dimmed custom panel still under 4.5:1")
	main._on_media_toggled(false, ui_entry)
	await process_frame
	var restored_box := main.dialogue_box.get_theme_stylebox("panel") as StyleBoxTexture
	assert(restored_box.modulate_color == Color(main.LOOKS[0]["tint"], main.manager.textbox_opacity), "built-in panel not restored after untick")
	DirAccess.remove_absolute(myui_path)
	main._load_default_assets()
	print("My UI guard passed (bright panel dimmed to %.2f, builtin restored)" % dim_used)

	# Textbox options: switching position (top/bottom) and style (wooden/flat/frameless)
	main._show_state(main.State.READING)
	await process_frame

	# 1. Top position layout
	main.manager.textbox_position = 1
	main._apply_textbox_layout()
	main._apply_sprite_layout()
	await process_frame
	assert(main.dialogue_box.anchor_top == 0.0, "dialogue_box anchor_top should be 0.0 in top mode")
	assert(main.dialogue_box.offset_top == main.TOP_BAR_H + 8.0, "dialogue_box offset_top mismatch in top mode")
	assert(main.sprite_holder.offset_bottom == -10.0, "sprite_holder should be grounded at bottom in top mode")

	# 2. Frameless style
	main.manager.textbox_style = 2
	main._apply_theme()
	await process_frame
	assert(main.dialogue_box.get_theme_stylebox("panel") is StyleBoxEmpty, "dialogue_box should use StyleBoxEmpty in frameless mode")
	assert(main.nameplate_panel.get_theme_stylebox("panel") is StyleBoxEmpty, "nameplate_panel should use StyleBoxEmpty in frameless mode")
	assert(main.dialogue_label.get_theme_constant("outline_size") == 4, "dialogue_label should have 4px outline in frameless mode")

	# 3. Round-trip back to classic bottom wooden box
	main.manager.textbox_position = 0
	main.manager.textbox_style = 0
	main._apply_textbox_layout()
	main._apply_sprite_layout()
	main._apply_theme()
	await process_frame
	assert(main.dialogue_box.anchor_top == 1.0, "dialogue_box anchor_top should be 1.0 in bottom mode")
	assert(main.dialogue_box.offset_top <= -160.0, "dialogue_box offset_top should be bottom-anchored")
	assert(main.dialogue_box.get_theme_stylebox("panel") is StyleBoxTexture, "dialogue_box should restore StyleBoxTexture")
	assert(main.dialogue_label.get_theme_constant("outline_size") == 0, "dialogue_label outline should reset in boxed mode")
	print("Textbox mode guard passed (top floating + frameless round-trip)")

	# 4. Sprite size modes (Full Height and Screen Takeover)
	main.manager.sprite_mode = 1
	main._apply_sprite_layout()
	assert(main.sprite_holder.offset_bottom == 0.0, "mode 1 sprite should reach bottom")
	main.manager.sprite_mode = 2
	main._apply_sprite_layout()
	assert(main.sprite_holder.offset_bottom == 260.0, "mode 2 sprite should extend for takeover")
	main.manager.sprite_mode = 0
	main._apply_sprite_layout()
	print("Sprite size modes guard passed (framed / full height / screen takeover)")

	# Free the scene before quitting so no resources are reported in use at exit
	root.remove_child(main)
	main.free()
	main = null
	scene = null
	await process_frame

	print("--- Smoke passed ---")
	quit(0)
