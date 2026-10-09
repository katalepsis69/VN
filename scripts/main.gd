extends Control

## Master Controller for ADHD VN Reader
## Provides visual novel presentation for text documents, visual stimulation,
## customizable themes, audio feedback, and progress bookmarks.

enum State { MENU, READING, SETTINGS, RECENT, BACKLOG, CHAPTERS, MEDIA }

var current_state: State = State.MENU

# Core data
var manager: ReaderManager = ReaderManager.new()
var slides: Array[String] = []
var current_slide_idx: int = 0
var current_doc_path: String = ""
var current_doc_title: String = ""

# Asset pools
var bg_textures: Array = [] # String res:// paths (lazy) or Texture2D (custom folders)
var _bg_tex_cache := {}
var _asset_signature := ""
var _state_initialized := false
var _bg_tween: Tween
var _bounce_tween: Tween
var _last_blip_ms := -1000
var sprite_textures: Array[Texture2D] = []
var sprite_names: Array = [] # filenames, kept for reactive expression matching
var slide_images := {} # slide index -> Array[PackedByteArray] (book illustrations)
var _slide_img_cache := {}
var _img_showing := false
var _img_hold := 0
var chapter_list: Array = [] # {slide: int, title: String}, from the parser
var book_start_slide: int = -1 # first slide after Gutenberg boilerplate
var current_bg_idx: int = 0
var current_sprite_idx: int = 0
var slides_since_bg: int = 0
var slides_since_sprite: int = 0

# Typewriter state
var is_typing: bool = false
var typewriter_progress: float = 0.0
var typewriter_char_count: int = 0

# Auto-advance state
var is_auto_reading: bool = false
var auto_timer: float = 0.0

# UI Node References
var bg_rect: TextureRect
var bg_back: TextureRect
var bg_fade_rect: TextureRect
var bg_dim: ColorRect

var sprite_holder: Control
var character_sprite: TextureRect

var top_bar: PanelContainer
var doc_title_label: Label
var progress_label: Label
var progress_bar: ProgressBar
var btn_auto: Button

var dialogue_box: PanelContainer
var nameplate_panel: PanelContainer
var nameplate_label: Label
var dialogue_label: RichTextLabel
var next_arrow: TextureRect
var _last_parsed_cap: Dictionary = {}
var _raw_clipboard_text: String = ""

var menu_overlay: Control
var settings_overlay: PanelContainer
var recent_overlay: PanelContainer
var backlog_overlay: PanelContainer
var chapters_overlay: PanelContainer

var audio_player: AudioStreamPlayer
var file_dialog: FileDialog
var updater: Node
var update_banner: PanelContainer
var update_label: Label
var update_progress_bar: ProgressBar
var update_now_btn: Button
var update_dismiss_btn: Button
var settings_update_status: Label

# Wooden skin palette + pack SFX (see DESIGN.md for asset credits)
const WOOD_INK := Color("f5ead6")      # light text on wooden surfaces
const WOOD_INK_DIM := Color("d9c9a8")  # secondary text on wood
const WOOD_BTN_INK := Color("3a2a18")  # dark text on the cream LineEdit field
const TOP_BAR_H := 54.0                # reading top bar height (sprite band starts below it)
const TEXTBOX_GAP := 12.0              # breathing room between the sprite band and the textbox
const ASSET_SUBDIRS := ["My Backgrounds", "My Sprites", "My Sounds", "My Fonts", "My Books", "My UI"]

## Whole-app preset looks. Owner override 2026-10-09: the one-skin rule is
## retired (recorded in DESIGN.md like the particles override). "Cozy Wood" is
## the exact pre-looks skin, so every measured contrast claim in DESIGN.md is
## that row. Any look must clear the per-look vetting in test_verification.gd:
## cream ink on every surface at 4.5:1+, edge and accent at 3:1+ on the dark
## faces. The panel texture base (#dd9a79) x tint = the tone cream ink sits on.
const LOOKS := [
	{
		"name": "Cozy Wood", "accent": Color("e8a04c"),
		"tint": Color(0.62, 0.58, 0.52), "edge": Color("8a6a44"),
		"face": Color("3a2e22"), "shade": Color("2e241a"),
		"topbar": Color("241c14e6"), "overlay": Color("2a2018f2"),
		"flat": Color(0.16, 0.12, 0.09), "namebg": Color("7a5230"),
		"primary": Color("9c3a2c"),
	},
	{
		"name": "Ember", "accent": Color("eda45c"),
		"tint": Color(0.62, 0.50, 0.42), "edge": Color("96604a"),
		"face": Color("3a2a20"), "shade": Color("2e241c"),
		"topbar": Color("241a14e6"), "overlay": Color("2a1e16f2"),
		"flat": Color(0.17, 0.11, 0.08), "namebg": Color("7a4630"),
		"primary": Color("a04428"),
	},
	{
		"name": "Forest", "accent": Color("a8c060"),
		"tint": Color(0.48, 0.58, 0.44), "edge": Color("6a8a54"),
		"face": Color("2c3624"), "shade": Color("242e1e"),
		"topbar": Color("1c2416e6"), "overlay": Color("202a1af2"),
		"flat": Color(0.10, 0.14, 0.08), "namebg": Color("4a5c30"),
		"primary": Color("3e6a34"),
	},
	{
		"name": "Slate", "accent": Color("8fb8d8"),
		"tint": Color(0.48, 0.52, 0.64), "edge": Color("74829c"),
		"face": Color("323640"), "shade": Color("2a2f38"),
		"topbar": Color("20242ee6"), "overlay": Color("262b34f2"),
		"flat": Color(0.10, 0.12, 0.16), "namebg": Color("46526e"),
		"primary": Color("3a5a7c"),
	},
	{
		"name": "Dusk", "accent": Color("c9a0d8"),
		"tint": Color(0.52, 0.46, 0.56), "edge": Color("84689c"),
		"face": Color("33283a"), "shade": Color("2a2130"),
		"topbar": Color("211a28e6"), "overlay": Color("271f2ef2"),
		"flat": Color(0.13, 0.10, 0.16), "namebg": Color("5c4468"),
		"primary": Color("7c3a5c"),
	},
]
## Active look. Never mutate entries; reassign from LOOKS only (Dictionary is a
## reference type, so a mutated LOOKS row would corrupt the const table).
var _look: Dictionary = LOOKS[0]
const BUILTIN_PANEL_TEX := "res://assets/ui/container_wood.png"
var _ui_tex_dim := 1.0   # dimming applied to a custom textbox texture (1.0 = none)
var _ui_tex_cache := {}  # path|mtime -> {"tex": Texture2D, "dim": float}

## WCAG relative luminance / contrast ratio, shared by the dim safeguard and the
## per-look vetting in the tests. Static so the test suites can call them
## without instantiating the main scene.
static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)

static func _wcag_lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)

static func _contrast(a: Color, b: Color) -> float:
	var la := _wcag_lum(a) + 0.05
	var lb := _wcag_lum(b) + 0.05
	return maxf(la, lb) / minf(la, lb)

## The lightest uniform dimming under which cream ink keeps 4.5:1 against an
## average tone. 1.0 = already dark enough. 0.4 is the floor of acceptability.
static func _dim_for(avg: Color) -> float:
	var k := 1.0
	while k > 0.4 and _contrast(WOOD_INK, Color(avg.r * k, avg.g * k, avg.b * k)) < 4.5:
		k -= 0.05
	return k

var sfx_blip: AudioStream
var sfx_click: AudioStream
var sfx_back: AudioStream
var sfx_open: AudioStream
var sfx_save: AudioStream
var boot_done := false

var menu_bg_rect: TextureRect
var menu_bg_back: TextureRect
var current_menu_bg_idx: int = 0

var menu_primary_btn: Button     # CONTINUE — the menu's one accent-filled button
var settings_save_btn: Button    # SAVE & CLOSE — the settings screen's primary

# Settings tabs + My Media picker
const SETTINGS_TABS := ["Reading & Sound", "Appearance & Character", "Custom Art & Files"]
const MEDIA_KINDS := [["bg", "Backgrounds"], ["sprite", "Sprites"], ["sound", "Sounds"], ["font", "Fonts"], ["ui", "UI textures"]]
var settings_grid: GridContainer
var settings_tab_btns: Array[Button] = []
var _settings_tab := 0
var _settings_return_to := 1 # State.READING: safe default before Settings is ever opened
var media_overlay: PanelContainer
var media_kind_btns: Array[Button] = []
var media_src_btns: Array[Button] = []
var media_src_box: HBoxContainer
var media_grid: HFlowContainer
var media_note: Label
var _media_kind := "bg"
var _media_builtin := true
var _thumb_cache := {}
var _sprite_tex_cache := {}

# Book shelf (menu) — spotlight + spines + hover card
var spotlight_box: HBoxContainer
var spot_cover: PanelContainer
var spot_title: Label
var spot_meta: Label
var spot_preview: Label
var shelf_search: LineEdit
var shelf_tabs: Array[Button] = []
var shelf_panel: PanelContainer
var shelf_row: HBoxContainer
var hover_strip: PanelContainer
var hover_title: Label
var hover_preview: Label
var hover_meta: Label
var shelf_filter: int = 0   # 0 All, 1 Reading, 2 Finished
var shelf_query := ""
var _shelf_tweens: Array[Tween] = []
var _hover_item: Dictionary = {}    # the book currently on the hover card ({} = none)
var _hover_grace: Timer             # delays clearing the card so its Delete button is reachable
var hover_delete_btn: Button
var _confirm_dialog: ConfirmationDialog
var _pending_delete: Dictionary = {} # the book awaiting the delete confirmation

var _asset_dialog: FileDialog
var _asset_dialog_setter: Callable
var _active_textbox_stylebox: StyleBox # opacity slider adjusts only this, not the whole theme
var _panel_style_dark: StyleBoxFlat    # shared by the spotlight cover panel
var _media_tile_style: StyleBoxFlat    # shared by every My Media tile
var _ui_font: Font                     # resolved font, so pre-tree labels measure right
const BOOK_IMG_CACHE_CAP := 16 # decoded illustration textures kept at once (bytes stay in slide_images)

func _ready() -> void:
	# Smoke test hook: a scratch config keeps test runs off the real shelf
	if "--testcfg" in OS.get_cmdline_args():
		manager.config_path = "user://test_config/reader_config.cfg"
	manager.load_settings()
	_look = _current_look()
	if manager.recovery_note != "":
		# a crash mid-save was repaired from the backup; tell the reader once
		var note := manager.recovery_note
	# deferred so it lands after the first frame draws; Callable form is
	# rejected by call_deferred's StringName signature in 4.7
		OS.alert.call_deferred(note, "Settings Repaired")
	_init_sounds()
	_load_default_assets()
	_build_ui()
	_apply_theme()
	_apply_settings_to_ui()
	_apply_sprite_layout()
	_apply_textbox_layout()
	_show_state(State.MENU)

	# Handle window file drag & drop
	get_tree().root.files_dropped.connect(_on_files_dropped)
	# Reflow the text when the window is resized (deferred: the new layout
	# must settle before measuring)
	get_viewport().size_changed.connect(_on_window_resized)
	boot_done = true
	# Initialize updater (silent background check, skipped in test runs)
	var UpdaterScript = load("res://scripts/updater.gd")
	if UpdaterScript != null:
		updater = UpdaterScript.new()
		add_child(updater)
		updater.check_completed.connect(_on_update_checked)
		updater.download_progress.connect(_on_update_download_progress)
		updater.download_finished.connect(_on_update_download_finished)
		if not "--testcfg" in OS.get_cmdline_args() and not "--headless" in OS.get_cmdline_args():
			updater.check_for_updates()
	# Test hook: --bgtest opens the sample doc, saves a render to user://, quits
	if "--bgtest" in OS.get_cmdline_args():
		call_deferred("_bgtest_run")
	if "--pdftest" in OS.get_cmdline_args():
		call_deferred("_pdftest_run")

func _process(delta: float) -> void:
	if current_state != State.READING:
		return
		
	# Typewriter effect
	if is_typing:
		var speed: float = manager.typewriter_speed
		if speed >= 120.0: # Instant mode
			dialogue_label.visible_characters = -1
			is_typing = false
			next_arrow.visible = true
		else:
			typewriter_progress += speed * delta
			var new_chars: int = int(typewriter_progress)
			if new_chars != dialogue_label.visible_characters:
				dialogue_label.visible_characters = new_chars
				# Play subtle blip sound every 2-3 characters
				if manager.sound_enabled and new_chars > 0 and new_chars % 3 == 0:
					_play_blip()
					
			if dialogue_label.visible_characters >= typewriter_char_count:
				dialogue_label.visible_characters = -1
				is_typing = false
				next_arrow.visible = true
	else:
		# Auto-advance timer
		if is_auto_reading:
			auto_timer += delta
			if auto_timer >= manager.auto_delay:
				auto_timer = 0.0
				_advance_slide()

func _input(event: InputEvent) -> void:
	if current_state != State.READING:
		if event.is_action_pressed("ui_cancel"):
			_escape_back()
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			# A focused top-bar button owns Enter/Space; advancing here would activate
			# it and advance in the same press
			if get_viewport().gui_get_focus_owner() is BaseButton:
				return
			_handle_advance_input()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BACKSPACE or event.keycode == KEY_LEFT or event.keycode == KEY_A:
			_previous_slide()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			# was Tab, which left the top bar unreachable by keyboard entirely
			_toggle_auto()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_B:
			_open_backlog()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_escape_back()
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Clicks aimed at top-bar buttons belong to the GUI, not the reader
			var hovered := get_viewport().gui_get_hovered_control()
			if hovered is BaseButton:
				return
			_handle_advance_input()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_previous_slide()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_handle_advance_input() # finish the line first, same as a click
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_previous_slide()

func _escape_back() -> void:
	# Escape belongs to an open file dialog; without this the overlay underneath
	# closes too and the dialog is left floating over the wrong screen
	if (_asset_dialog != null and _asset_dialog.visible) or (file_dialog != null and file_dialog.visible):
		return
	# Same for the delete confirmation: ESC cancels the dialog, it does not leave the screen
	if _confirm_dialog != null and _confirm_dialog.visible:
		_confirm_dialog.hide()
		return
	# Contextual back: leave the overlay you are in, don't dump to menu blindly
	match current_state:
		State.SETTINGS:
			manager.save_settings()
			_show_state(_settings_return_to)
		State.BACKLOG, State.CHAPTERS:
			_show_state(State.READING)
		State.MEDIA:
			_show_state(State.SETTINGS)
		State.RECENT:
			_show_state(State.MENU)
		State.READING:
			_show_state(State.MENU)

func _on_window_resized() -> void:
	# Reflow text when the window resizes; deferred so the new layout settles first
	if current_state == State.READING:
		_refit_current_slide.call_deferred()
	# a fill/fit decision made for the old window size can be stale now
	_apply_bg_fit(bg_rect, bg_rect.texture)
	_apply_bg_fit(bg_fade_rect, bg_fade_rect.texture)
	_apply_bg_fit(menu_bg_rect, menu_bg_rect.texture)

func _bbcode_safe(text: String) -> String:
	# document text may contain [b], [i], [12]... escape so RichTextLabel shows them literally
	return text.replace("[", "[lb]")

func _handle_advance_input() -> void:
	if is_typing:
		# Skip typewriter to end of slide
		dialogue_label.visible_characters = -1
		is_typing = false
		next_arrow.visible = true
		auto_timer = 0.0
	else:
		_advance_slide()

# ==============================================================================
# READING & NAVIGATION
# ==============================================================================

func _pdftest_run() -> void:
	print("PDFTEST exists: ", FileAccess.file_exists("res://assets/sample_paper.pdf"))
	print("PDFTEST txt exists: ", FileAccess.file_exists("res://assets/sample_paper.txt"))
	var df := FileAccess.open("res://assets/sample_paper.pdf", FileAccess.READ)
	print("PDFTEST open ok: ", df != null, " len: ", df.get_length() if df else -1)
	if df:
		df.close()
	var d := DirAccess.open("res://assets")
	if d:
		var listing: PackedStringArray = []
		var fn := d.get_next()
		while not fn.is_empty():
			listing.append(fn)
			fn = d.get_next()
		print("PDFTEST assets dir: ", listing)
	var parsed := TextParser.parse_file("res://assets/sample_paper.pdf", 2)
	if parsed.is_empty():
		print("PDFTEST FAIL: no slides extracted")
		get_tree().quit(1)
		return
	print("PDFTEST OK: ", parsed.size(), " slides, first: ", parsed[0])
	var epub_res := TextParser.parse_file_with_images("res://assets/sample_story.epub", 2)
	var epub: Array[String] = epub_res["slides"]
	var epub_imgs: Dictionary = epub_res["images"]
	if epub.is_empty() or epub_imgs.is_empty() or "\n".join(epub).contains("\uE000"):
		print("EPUBTEST FAIL: ", epub.size(), " slides, ", epub_imgs.size(), " image slides")
		get_tree().quit(1)
		return
	print("EPUBTEST OK: ", epub.size(), " slides, ", epub_imgs.size(), " image slide(s), first: ", epub[0])
	get_tree().quit()

func _bgtest_run() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png("user://bgtest_menu.png")
	print("BGTEST_SAVED menu")
	load_document("res://assets/sample_paper.txt", 0)
	await get_tree().create_timer(1.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://bgtest_render.png")
	print("BGTEST_SAVED reading ", img.get_width(), "x", img.get_height())
	get_tree().quit()

func _continue_reading() -> void:
	# The spotlight can be showing a My Books file that is not in the recents list
	# yet, so its button has to try that book first or it opens a different one.
	var candidates: Array = []
	if not _spot_book.is_empty():
		candidates.append(_spot_book)
	for item in manager.get_recent_files():
		if not candidates.has(item):
			candidates.append(item)
	for item in candidates:
		var p: String = item["path"]
		if not FileAccess.file_exists(p):
			continue
		var total: int = int(item.get("total_slides", 0))
		var start: int = int(item.get("slide_index", 0))
		# a finished book starts over at the first real page, past any front matter
		if total > 0 and start >= total - 1:
			var bs: int = int(item.get("book_start", -1))
			start = bs if bs > 0 else 0
		load_document(p, start, total if start < total - 1 else -1)
		return
	if candidates.is_empty() and FileAccess.file_exists("res://assets/sample_paper.txt"):
		load_document("res://assets/sample_paper.txt", 0)
		return
	OS.alert("The last document could not be found. It may have been moved, renamed, or deleted.\n\nOpen a document from the menu to start reading.", "File Not Found")

func _height_capacity_desc(h: int) -> String:
	var s := TextParser.sentences_for_height(h)
	return "%d sentence%s" % [s, "" if s == 1 else "s"]

func load_document(path: String, start_slide: int = 0, saved_total: int = -1) -> void:
	var cap := manager.get_slide_capacity()
	var parsed := TextParser.parse_file_with_images(path, cap["sentences"], cap["max_chars"])
	var parsed_slides: Array[String] = parsed["slides"]
	if parsed_slides.is_empty():
		OS.alert("No readable text was found in:\n" + path + "\n\nThe file may be empty, locked, or in an unsupported format.", "Could Not Read Document")
		return
		
	slides = parsed_slides
	slide_images = parsed["images"]
	chapter_list = parsed["chapters"]
	book_start_slide = parsed["book_start"]
	_slide_img_cache.clear()
	_last_parsed_cap = cap
	_img_showing = false
	_img_hold = 0
	current_doc_path = path
	current_doc_title = path.get_file().get_basename()
	doc_title_label.text = current_doc_title
	doc_title_label.tooltip_text = current_doc_title
	_save_book_meta()

	# Scale start_slide if saved_total differs from current parsed slide count
	if saved_total > 0 and saved_total != parsed_slides.size() and start_slide > 0:
		var ratio := float(start_slide) / float(saved_total)
		start_slide = clampi(int(round(ratio * float(parsed_slides.size()))), 0, parsed_slides.size() - 1)
	
	current_slide_idx = clampi(start_slide, 0, slides.size() - 1)
	slides_since_bg = 0
	slides_since_sprite = 0
	
	_show_state(State.READING)
	_display_current_slide()
	_update_background(true)
	_update_sprite(true)

func _sync_book_to_textbox_height() -> void:
	if current_doc_path.is_empty() or slides.is_empty():
		return
	var cap := manager.get_slide_capacity()
	if _last_parsed_cap.get("sentences", -1) == cap["sentences"] and _last_parsed_cap.get("max_chars", -1) == cap["max_chars"]:
		return

	var anchor := ""
	if current_slide_idx >= 0 and current_slide_idx < slides.size():
		var raw_s: String = slides[current_slide_idx].strip_edges()
		anchor = raw_s.substr(0, mini(40, raw_s.length()))

	var new_slides: Array[String] = []
	var new_images: Dictionary = {}
	var new_chapters: Array = []
	var new_book_start: int = -1

	if current_doc_path.begins_with("clipboard://"):
		if not _raw_clipboard_text.is_empty():
			var heur: Array = []
			new_slides = TextParser.parse_string(_raw_clipboard_text, cap["sentences"], heur, cap["max_chars"])
			new_chapters = heur
			new_book_start = TextParser.find_book_start(new_slides)
	else:
		var parsed := TextParser.parse_file_with_images(current_doc_path, cap["sentences"], cap["max_chars"])
		new_slides = parsed["slides"]
		new_images = parsed["images"]
		new_chapters = parsed["chapters"]
		new_book_start = parsed["book_start"]

	if new_slides.is_empty():
		return

	var new_idx := -1
	if not anchor.is_empty():
		for i in new_slides.size():
			if new_slides[i].contains(anchor):
				new_idx = i
				break
	if new_idx == -1:
		var ratio := float(current_slide_idx) / float(maxi(1, slides.size() - 1))
		new_idx = clampi(int(round(ratio * float(new_slides.size() - 1))), 0, new_slides.size() - 1)

	slides = new_slides
	slide_images = new_images
	chapter_list = new_chapters
	book_start_slide = new_book_start
	_slide_img_cache.clear()
	_last_parsed_cap = cap
	current_slide_idx = new_idx
	_display_current_slide()

func _save_book_meta() -> void:
	# Once per document open: stash the first real sentence (after Gutenberg
	# boilerplate) and the book's first illustration as the shelf cover.
	if current_doc_path.is_empty() or current_doc_path.begins_with("clipboard://"):
		return
	var idx := book_start_slide if book_start_slide > 0 and book_start_slide < slides.size() else 0
	var preview := slides[idx].strip_edges().replace("\n", " ")
	if preview.length() > 150:
		preview = preview.substr(0, 149) + "…"
	var cover_path := ""
	if not slide_images.is_empty():
		var first: int = slide_images.keys().min()
		var tex := _book_image_for(first)
		if tex:
			cover_path = _save_cover_png(tex)
	manager.save_book_meta(current_doc_path, preview, cover_path)

func _save_cover_png(tex: Texture2D) -> String:
	var dir := DirAccess.open("user://")
	if dir == null:
		return ""
	dir.make_dir_recursive("covers")
	var path := "user://covers/" + current_doc_path.md5_text() + ".png"
	var img := tex.get_image()
	if img == null:
		return ""
	img.decompress()
	if img.get_height() > 300:
		var nw := int(float(img.get_width()) * 300.0 / float(img.get_height()))
		img.resize(nw, 300, Image.INTERPOLATE_LANCZOS)
	var _err := img.save_png(path)
	return path

func load_raw_text(text: String, title: String = "Pasted Text") -> void:
	_raw_clipboard_text = text
	var cap := manager.get_slide_capacity()
	var heur: Array = []
	var parsed_slides := TextParser.parse_string(text, cap["sentences"], heur, cap["max_chars"])
	if parsed_slides.is_empty():
		return

	slides = parsed_slides
	slide_images = {}
	chapter_list = heur
	book_start_slide = TextParser.find_book_start(parsed_slides)
	_slide_img_cache.clear()
	_last_parsed_cap = cap
	_img_showing = false
	_img_hold = 0
	current_doc_path = "clipboard://" + title
	current_doc_title = title
	doc_title_label.text = current_doc_title
	doc_title_label.tooltip_text = current_doc_title
	current_slide_idx = 0
	slides_since_bg = 0
	slides_since_sprite = 0
	
	_show_state(State.READING)
	_display_current_slide()
	_update_background(true)
	_update_sprite(true)

func _display_current_slide() -> void:
	if slides.is_empty() or current_slide_idx < 0 or current_slide_idx >= slides.size():
		return
		
	var text: String = slides[current_slide_idx]
	_fit_dialogue_text(text)
	dialogue_label.text = _bbcode_safe(text)
	dialogue_label.visible_characters = 0
	typewriter_progress = 0.0
	typewriter_char_count = text.length()
	is_typing = true
	next_arrow.visible = false
	auto_timer = 0.0
	
	# Progress Bar & Counter
	progress_bar.max_value = slides.size()
	progress_bar.value = current_slide_idx + 1
	var pct: int = int((float(current_slide_idx + 1) / float(slides.size())) * 100.0)
	progress_label.text = "Slide %d / %d (%d%%)" % [current_slide_idx + 1, slides.size(), pct]
	
	# Character bounce animation when speaking
	if manager.character_bounce:
		_animate_speaker_bounce()

	# Reactive expressions: match Ginger's face to the sentence
	if manager.reactive_expressions:
		_apply_reactive_mood(text)

	# Book illustrations: the image tied to this part of the story appears behind
	# the dialogue; once the reader moves past it, the landscape rotation returns.
	if slide_images.has(current_slide_idx):
		var book_tex := _book_image_for(current_slide_idx)
		if book_tex:
			_crossfade_bg(book_tex)
			_img_showing = true
			_img_hold = 2
			slides_since_bg = 0
	elif _img_showing:
		if _img_hold > 0:
			_img_hold -= 1
		else:
			_img_showing = false
			_update_background(false)
		
	# Progress is written every 10 slides, not on every advance: each write parses
	# the whole config and does a temp write + backup copy + rename, which is tens
	# of thousands of file operations across a long serial. The exact position is
	# flushed whenever reading is left.
	if current_slide_idx == 0 or current_slide_idx % 10 == 0:
		_write_progress()

func _write_progress() -> void:
	# clipboard pastes cannot be resumed, so they are never recorded
	if current_doc_path.is_empty() or current_doc_path.begins_with("clipboard://"):
		return
	manager.save_progress(current_doc_path, current_doc_title, current_slide_idx, slides.size(), book_start_slide)

## Font Size is the ceiling: a slide too tall for the box is drawn smaller until
## it fits, so the reader never has to scroll to finish a line.
func _fit_dialogue_text(text: String) -> void:
	dialogue_label.add_theme_font_size_override("normal_font_size", _fit_font_size(text, dialogue_label.size.x, dialogue_label.size.y))

func _refit_current_slide() -> void:
	if current_slide_idx >= 0 and current_slide_idx < slides.size():
		_fit_dialogue_text(slides[current_slide_idx])

func _fit_font_size(text: String, width: float, height: float) -> int:
	var max_size: int = manager.font_size
	var font: Font = dialogue_label.get_theme_font("normal_font")
	if text.is_empty() or font == null or width < 40.0 or height < 24.0:
		return max_size
	var floor_size: int = maxi(14, int(max_size * 0.6))
	for s in range(max_size, floor_size, -1):
		if _text_block_height(font, text, width, s) <= height:
			return s
	return floor_size

func _text_block_height(font: Font, text: String, width: float, size: int) -> float:
	var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size).y
	return h * 1.12 # room for the label's line gap

func _advance_slide() -> void:
	if current_slide_idx < slides.size() - 1:
		current_slide_idx += 1
		slides_since_bg += 1
		slides_since_sprite += 1
		
		# Check stimulation change conditions (paused while a book illustration is up)
		if slides_since_bg >= manager.bg_change_freq and not _img_showing and not slide_images.has(current_slide_idx):
			slides_since_bg = 0
			_update_background(false)
			
		if slides_since_sprite >= manager.sprite_change_freq:
			slides_since_sprite = 0
			_update_sprite(false)
			
		_play_click()
		_display_current_slide()
	else:
		# End of document
		is_auto_reading = false
		btn_auto.text = "Auto"

func _previous_slide() -> void:
	if current_slide_idx > 0:
		current_slide_idx -= 1
		_release_book_image()
		_play_sfx(sfx_back, 0.7)
		_display_current_slide()

## An illustration held over from the slide you came from would otherwise stay up
## over earlier or unrelated text: the hold only counts down while advancing.
func _release_book_image() -> void:
	if _img_showing and not slide_images.has(current_slide_idx):
		_img_showing = false
		_img_hold = 0
		_update_background(false)

func _toggle_auto() -> void:
	is_auto_reading = not is_auto_reading
	auto_timer = 0.0
	btn_auto.text = "Auto: ON" if is_auto_reading else "Auto"

# ==============================================================================
# VISUAL STIMULATION & DYNAMICS
# ==============================================================================

func _bg_texture(idx: int) -> Texture2D:
	if idx < 0 or idx >= bg_textures.size():
		return null
	var entry: Variant = bg_textures[idx]
	if entry is Texture2D:
		return entry
	var path: String = entry
	if not _bg_tex_cache.has(path):
		if path.begins_with("res://"):
			_bg_tex_cache[path] = load(path)
		else:
			var im := Image.load_from_file(path)
			_bg_tex_cache[path] = ImageTexture.create_from_image(im) if im else null
	return _bg_tex_cache[path]

## Display key for a pool entry, used by the My Media picker and the pinned-menu
## setting. Built-ins and folder files are both addressed by bare filename.
func _bg_name(idx: int) -> String:
	if idx < 0 or idx >= bg_textures.size():
		return ""
	var entry: Variant = bg_textures[idx]
	var path := ""
	if entry is Texture2D:
		path = (entry as Texture2D).resource_path
	else:
		path = String(entry)
	return path.get_file().get_basename()

func _update_menu_background() -> void:
	if bg_textures.is_empty() or menu_bg_rect == null:
		menu_bg_rect.texture = null
		menu_bg_back.texture = null
		return
	# A pinned menu background beats the rotation; "" means keep it random.
	var pinned := -1
	if manager.menu_bg != "":
		for i in bg_textures.size():
			if _bg_name(i) == manager.menu_bg:
				pinned = i
				break
	if pinned >= 0:
		current_menu_bg_idx = pinned
	else:
		var next_idx := randi() % bg_textures.size()
		if bg_textures.size() > 1 and current_menu_bg_idx == next_idx:
			next_idx = (next_idx + 1) % bg_textures.size()
		current_menu_bg_idx = next_idx
	menu_bg_rect.texture = _bg_texture(current_menu_bg_idx)
	_apply_bg_fit(menu_bg_rect, menu_bg_rect.texture)
	menu_bg_back.texture = menu_bg_rect.texture

func _apply_sprite_layout() -> void:
	# Position: left / center / right.
	# Mode: 0 = above textbox (framed), 1 = full height (behind textbox), 2 = screen takeover (giant VN style).
	var pos := clampi(manager.sprite_position, 0, 2)
	var mode := clampi(manager.sprite_mode, 0, 2)
	var holder_w: float
	match mode:
		1:
			holder_w = 680.0
		2:
			holder_w = 760.0
		_:
			holder_w = 520.0

	match pos:
		0:
			sprite_holder.anchor_left = 0.0
			sprite_holder.anchor_right = 0.0
			sprite_holder.offset_left = 20.0 if mode > 0 else 40.0
			sprite_holder.offset_right = sprite_holder.offset_left + holder_w
		1:
			sprite_holder.anchor_left = 0.5
			sprite_holder.anchor_right = 0.5
			sprite_holder.offset_left = -holder_w / 2.0
			sprite_holder.offset_right = holder_w / 2.0
		2:
			sprite_holder.anchor_left = 1.0
			sprite_holder.anchor_right = 1.0
			sprite_holder.offset_right = -20.0 if mode > 0 else -40.0
			sprite_holder.offset_left = sprite_holder.offset_right - holder_w

	sprite_holder.anchor_top = 0.0
	sprite_holder.anchor_bottom = 1.0

	if mode == 1:
		# Full Height: grounded at the bottom of the screen, extending behind the textbox
		sprite_holder.offset_top = TOP_BAR_H + 4.0
		sprite_holder.offset_bottom = 0.0
	elif mode == 2:
		# Screen Takeover: character dominates the scene, lower body extends behind textbox
		sprite_holder.offset_top = TOP_BAR_H
		sprite_holder.offset_bottom = 260.0
	else:
		# Framed above textbox (default)
		if manager.textbox_position == 1:
			var top_gap: float = float(mini(manager.textbox_height, 180)) if manager.textbox_style == 2 else float(manager.textbox_height)
			sprite_holder.offset_top = TOP_BAR_H + 8.0 + top_gap + TEXTBOX_GAP
			sprite_holder.offset_bottom = -10.0
		else:
			sprite_holder.offset_top = TOP_BAR_H + 8.0
			sprite_holder.offset_bottom = -(float(manager.textbox_height) + TEXTBOX_GAP)

func _apply_reactive_mood(text: String) -> void:
	var mood := MoodMapper.mood_for(text)
	if mood.is_empty():
		return
	var candidates := [mood]
	# accept common spellings so user-named sprite files match (angry.png, thoughtful.png, ...)
	if mood == "thoughtfull":
		candidates.append("thoughtful")
	elif mood == "embarrassing":
		candidates.append("embarrassed")
	# iterate from the END: user sprites are appended after built-ins, so a
	# custom "angry.png" beats the built-in ginger_angry for the same mood
	for i in range(sprite_textures.size() - 1, -1, -1):
		if i >= sprite_names.size():
			continue
		var nm: String = str(sprite_names[i]).to_lower()
		for c in candidates:
			if nm.contains(c):
				current_sprite_idx = i
				character_sprite.texture = sprite_textures[i]
				return

## The saved look by name; unknown or missing names fall back to Cozy Wood so an
## old config (or a renamed look) can never boot into a half-defined skin.
func _current_look() -> Dictionary:
	for l in LOOKS:
		if l["name"] == manager.ui_look:
			return l
	return LOOKS[0]

## How a background fills the screen. Auto: a landscape image with pixels to
## spare covers the screen (a sliver of edge is cropped); portrait or small
## images sit framed on the darkened backdrop. Fill / fit modes override it.
func _apply_bg_fit(rect: TextureRect, tex: Texture2D) -> void:
	if tex == null:
		return
	if manager.bg_fit_mode == 1:
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		return
	if manager.bg_fit_mode == 2:
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return
	var vp := get_viewport().get_visible_rect().size
	if DisplayServer.get_name() == "headless" or vp.x < 8.0 or vp.y < 8.0:
		vp = Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width", 1280),
			ProjectSettings.get_setting("display/window/size/viewport_height", 720)
		)
	if tex.get_width() < 1 or tex.get_height() < 1:
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return
	var tex_aspect := float(tex.get_width()) / float(tex.get_height())
	var vp_aspect := vp.x / vp.y
	var aspect_close := absf(tex_aspect - vp_aspect) / vp_aspect < 0.15
	var pixels_enough := float(tex.get_width() * tex.get_height()) >= float(vp.x * vp.y) * 0.5
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED \
			if aspect_close and pixels_enough else TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _update_background(instant: bool) -> void:
	if bg_textures.is_empty():
		# everything unticked, or a folder picker aimed at an empty directory:
		# show the flat fallback rather than freezing on the last image
		bg_back.texture = null
		bg_rect.texture = null
		bg_fade_rect.texture = null
		bg_fade_rect.modulate.a = 0.0
		return
		
	var next_idx := current_bg_idx
	if bg_textures.size() > 1:
		if manager.bg_change_random:
			while next_idx == current_bg_idx:
				next_idx = randi() % bg_textures.size()
		else:
			next_idx = (current_bg_idx + 1) % bg_textures.size()
	current_bg_idx = next_idx
	
	var new_tex: Texture2D = _bg_texture(current_bg_idx)
	if new_tex == null:
		return
	if instant:
		bg_back.texture = new_tex
		if _bg_tween:
			_bg_tween.kill()
		bg_rect.texture = new_tex
		_apply_bg_fit(bg_rect, new_tex)
		bg_fade_rect.modulate.a = 0.0
	else:
		_crossfade_bg(new_tex)

func _crossfade_bg(new_tex: Texture2D) -> void:
	# kill any in-flight fade so a fast advance can't stack them
	if _bg_tween:
		_bg_tween.kill()
	bg_fade_rect.texture = new_tex
	_apply_bg_fit(bg_fade_rect, new_tex)
	bg_fade_rect.modulate.a = 0.0
	_bg_tween = create_tween()
	_bg_tween.tween_property(bg_fade_rect, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_bg_tween.tween_callback(func():
		bg_rect.texture = new_tex
		_apply_bg_fit(bg_rect, new_tex)
		bg_back.texture = new_tex # moves with the image, not a half-second before it
		bg_fade_rect.modulate.a = 0.0
	)

func _book_image_for(slide_idx: int) -> Texture2D:
	if not slide_images.has(slide_idx):
		return null
	if _slide_img_cache.has(slide_idx):
		return _slide_img_cache[slide_idx]
	# ponytail: LRU cap on decoded textures; raw bytes stay in slide_images
	# (window them too if comic-sized epubs ever matter)
	while _slide_img_cache.size() >= BOOK_IMG_CACHE_CAP:
		_slide_img_cache.erase(_slide_img_cache.keys()[0])
	var refs: Array = slide_images[slide_idx]
	if refs.is_empty():
		return null
	var bytes: PackedByteArray = refs[0]
	var img := _decode_image_bytes(bytes)
	var tex: Texture2D = ImageTexture.create_from_image(img) if img else null
	_slide_img_cache[slide_idx] = tex
	# re-insert at the end so the most recently used is always last
	_slide_img_cache.erase(slide_idx)
	_slide_img_cache[slide_idx] = tex
	return tex

func _decode_image_bytes(bytes: PackedByteArray) -> Image:
	# Godot 4.7: the load_*_from_buffer helpers are instance methods (return Error)
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var ok := false
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		ok = img.load_png_from_buffer(bytes) == OK
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		ok = img.load_jpg_from_buffer(bytes) == OK
	elif bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[8] == 0x57: # RIFF..WEBP
		ok = img.load_webp_from_buffer(bytes) == OK
	elif bytes[0] == 0x42 and bytes[1] == 0x4D:
		ok = img.load_bmp_from_buffer(bytes) == OK
	return img if ok else null

func _update_sprite(instant: bool) -> void:
	if sprite_textures.is_empty():
		character_sprite.texture = null
		return
		
	var next_idx := current_sprite_idx
	if sprite_textures.size() > 1:
		if manager.sprite_change_random:
			while next_idx == current_sprite_idx:
				next_idx = randi() % sprite_textures.size()
		else:
			next_idx = (current_sprite_idx + 1) % sprite_textures.size()
	current_sprite_idx = next_idx
	
	var new_tex := sprite_textures[current_sprite_idx]
	character_sprite.texture = new_tex

func _animate_speaker_bounce() -> void:
	# kill the previous bounce: fast advancing otherwise stacks tweens fighting over
	# the same property and the sprite snaps instead of bouncing
	if _bounce_tween != null:
		_bounce_tween.kill()
	_bounce_tween = create_tween()
	# TRANS_BOUNCE on the return overshoots several times, which at 0.16s reads as
	# a jitter, not a landing. One hop up, one smooth settle back.
	_bounce_tween.tween_property(character_sprite, "position:y", -10.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bounce_tween.tween_property(character_sprite, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ==============================================================================
# AUDIO & SOUND GENERATOR
# ==============================================================================

func _init_sounds() -> void:
	if audio_player == null:
		audio_player = AudioStreamPlayer.new()
		add_child(audio_player)
	sfx_blip = load("res://assets/sfx/menu_hover.ogg")
	sfx_click = load("res://assets/sfx/menu_confirm.ogg")
	sfx_back = load("res://assets/sfx/menu_back.ogg")
	sfx_open = load("res://assets/sfx/menu_open.ogg")
	sfx_save = load("res://assets/sfx/menu_save.ogg")
	# ponytail: procedural fallback if the pack files go missing
	if sfx_blip == null:
		sfx_blip = SoundGenerator.create_typewriter_blip(640.0)
	if sfx_click == null:
		sfx_click = SoundGenerator.create_advance_click()
	# My Sounds folder: drop-in overrides, matched by filename keywords
	var my_sounds := _asset_base_dir().path_join("My Sounds")
	if DirAccess.dir_exists_absolute(my_sounds):
		var sdir := DirAccess.open(my_sounds)
		if sdir:
			sdir.list_dir_begin()
			var sname2 := sdir.get_next()
			while not sname2.is_empty():
				var low := sname2.to_lower()
				if low.get_extension() in ["ogg", "wav"] and not manager.off_sounds.has(sname2.get_basename()):
					var lp := my_sounds.path_join(sname2)
					var stream: AudioStream = null
					if low.ends_with(".ogg"):
						stream = AudioStreamOggVorbis.load_from_file(lp)
					elif low.ends_with(".wav"):
						stream = AudioStreamWAV.load_from_file(lp)
					if stream:
						if low.contains("type") or low.contains("blip") or low.contains("key"):
							sfx_blip = stream
						elif low.contains("confirm") or low.contains("click") or low.contains("advance"):
							sfx_click = stream
						elif low.contains("back") or low.contains("return"):
							sfx_back = stream
						elif low.contains("open"):
							sfx_open = stream
						elif low.contains("save"):
							sfx_save = stream
				sname2 = sdir.get_next()

func _play_sfx(stream: AudioStream, vol_factor: float) -> void:
	if not manager.sound_enabled or stream == null:
		return
	audio_player.stream = stream
	audio_player.volume_db = linear_to_db(manager.sound_volume * vol_factor)
	audio_player.play()

func _play_blip() -> void:
	# One shared player: at 45 chars/sec a blip fires every 67 ms, which restarts
	# the sample before its 216 ms has played and reads as buzzing. 110 ms apart
	# keeps the typewriter rhythm without the overlap.
	var now := Time.get_ticks_msec()
	if now - _last_blip_ms < 110:
		return
	_last_blip_ms = now
	_play_sfx(sfx_blip, 0.35)

func _play_click() -> void:
	_play_sfx(sfx_click, 0.7)

# ==============================================================================
# ASSET LOADING & DEFAULTS
# ==============================================================================

func _asset_base_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	return OS.get_executable_path().get_base_dir()

func _ensure_asset_folders() -> void:
	var base := _asset_base_dir()
	for sub in ASSET_SUBDIRS:
		var dp := base.path_join(sub)
		if not DirAccess.dir_exists_absolute(dp):
			DirAccess.make_dir_recursive_absolute(dp)
		var gi := dp.path_join(".gdignore")
		if not FileAccess.file_exists(gi):
			var gf := FileAccess.open(gi, FileAccess.WRITE)
			if gf:
				gf.close()

## Root of the drop-in library. Forward slashes: every stored recent path went
## through _normalize_path, and a backslashed base from get_executable_path()
## would make each book list twice.
func _my_books_root() -> String:
	return _asset_base_dir().path_join("My Books").replace("\\", "/")

## Every readable file in My Books, normalized the same way recents are stored so
## one book can never show up as two spines.
func _my_books() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir_path := _my_books_root()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and not fname.begins_with("."):
			if fname.get_extension().to_lower() in TextParser.SUPPORTED_EXTENSIONS:
				var full_path := dir_path.path_join(fname)
				var cover := ""
				var cpath := "user://covers/" + full_path.md5_text() + ".png"
				if FileAccess.file_exists(cpath):
					cover = cpath
				elif fname.get_extension().to_lower() == "epub":
					cover = _extract_and_cache_epub_cover(full_path)
				out.append({
					"path": full_path, "title": fname.get_basename(),
					"slide_index": 0, "total_slides": 0, "timestamp": 0,
					"preview": "", "cover": cover,
				})
		fname = dir.get_next()
	return out

func _extract_and_cache_epub_cover(path: String) -> String:
	var out_path := "user://covers/" + path.md5_text() + ".png"
	if FileAccess.file_exists(out_path):
		return out_path
	var img := TextParser.probe_epub_cover_image(path)
	if img == null:
		return ""
	var dir := DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("covers")
	img.decompress()
	if img.get_height() > 300:
		var nw := int(float(img.get_width()) * 300.0 / float(img.get_height()))
		img.resize(nw, 300, Image.INTERPOLATE_LANCZOS)
	var err := img.save_png(out_path)
	if err == OK:
		return out_path
	return ""

## My Books mirrors the folder: a book deleted from disk leaves the shelf, and
## with it goes its stored progress and generated cover.
func _prune_missing_my_books() -> void:
	# trailing slash so a sibling named "My Books Old" cannot match, and forward
	# slashes to agree with the normalized keys the config stores
	var base := _my_books_root() + "/"
	# If the folder itself is unreachable (an external drive unplugged) every
	# book inside it looks deleted. Pruning then would erase real progress.
	if not DirAccess.dir_exists_absolute(base):
		return
	for r in manager.get_recent_files():
		if r.path.begins_with(base) and not FileAccess.file_exists(r.path):
			manager.remove_recent(r.path)

func _asset_folders_signature() -> String:
	# Cheap change-detector for the My * folders: file count + newest mtime each
	var sig := ""
	var base := _asset_base_dir()
	for sub in ["My Backgrounds", "My Sprites", "My Sounds", "My Fonts", "My UI"]:
		var dp := base.path_join(sub)
		if not DirAccess.dir_exists_absolute(dp):
			continue
		var d := DirAccess.open(dp)
		if d == null:
			continue
		var count := 0
		var newest := 0
		d.list_dir_begin()
		var fname := d.get_next()
		while not fname.is_empty():
			if not d.current_is_dir() and not fname.begins_with("."):
				count += 1
				newest = maxi(newest, FileAccess.get_modified_time(dp.path_join(fname)))
			fname = d.get_next()
		sig += "%s:%d:%d|" % [sub, count, newest]
	return sig

func _check_asset_folders_changed() -> void:
	if _asset_folders_signature() == _asset_signature:
		return
	_load_default_assets()
	_init_sounds()
	_apply_theme()
	_apply_sprite_layout()
	_apply_textbox_layout()
	_update_sprite(true)
	_update_background(true)
	_update_menu_background()

func _apply_textbox_layout() -> void:
	if manager.textbox_position == 1:
		dialogue_box.anchor_top = 0.0
		dialogue_box.anchor_bottom = 0.0
		dialogue_box.offset_top = TOP_BAR_H + 8.0
		var box_h: float = float(mini(manager.textbox_height, 180)) if manager.textbox_style == 2 else float(manager.textbox_height)
		dialogue_box.offset_bottom = TOP_BAR_H + 8.0 + box_h
	else:
		dialogue_box.anchor_top = 1.0
		dialogue_box.anchor_bottom = 1.0
		dialogue_box.offset_top = -float(manager.textbox_height)
		dialogue_box.offset_bottom = -20.0

## Everything the My Media screen lists, built once per asset refresh so the
## rotation pool and the picker can never disagree about what exists.
## bg / sprite / sound / font -> Array of {name, path, builtin}
var _media := {}

## Image filenames in a folder, as {name, path, builtin}. Skips dotfiles and the
## .gdignore markers the My * folders carry.
func _scan_images(dir_path: String, builtin: bool) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and not fname.begins_with("."):
			var base := fname.trim_suffix(".import")
			if base.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp", "svg"]:
				var stem := base.get_basename()
				if not out.any(func(e): return e["name"] == stem):
					out.append({"name": stem, "builtin": builtin, "path": dir_path.path_join(base)})
		fname = dir.get_next()
	return out

func _scan_files(dir_path: String, exts: Array, builtin: bool) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and not fname.begins_with("."):
			var base := fname.trim_suffix(".import")
			if base.get_extension().to_lower() in exts:
				var stem := base.get_basename()
				# click.ogg plus click.wav would otherwise produce two tiles sharing
				# one off-list name, so ticking one would untick both
				if not out.any(func(e): return e["name"] == stem):
					out.append({"name": stem, "builtin": builtin, "path": dir_path.path_join(base)})
		fname = dir.get_next()
	return out

func _off_list(kind: String) -> PackedStringArray:
	match kind:
		"sprite": return manager.off_sprites
		"sound": return manager.off_sounds
		"font": return manager.off_fonts
		"ui": return manager.off_ui
	return manager.off_backgrounds

## PackedStringArray is value type: mutating the list returned above would edit
## a copy, so changes have to be written back through here.
func _set_off_list(kind: String, value: PackedStringArray) -> void:
	match kind:
		"sprite": manager.off_sprites = value
		"sound": manager.off_sounds = value
		"font": manager.off_fonts = value
		"ui": manager.off_ui = value
		_: manager.off_backgrounds = value

func _media_kind_label() -> String:
	for pair in MEDIA_KINDS:
		if pair[0] == _media_kind:
			return pair[1]
	return "items"

func _media_folder_label() -> String:
	if _media_kind == "ui":
		return "My UI"
	return "My " + _media_kind_label()

func _load_default_assets() -> void:
	_ensure_asset_folders()
	bg_textures.clear()
	sprite_textures.clear()
	sprite_names.clear()
	current_bg_idx = 0
	current_sprite_idx = 0

	var asset_base := _asset_base_dir()
	_media = {"bg": [], "sprite": [], "sound": [], "font": [], "ui": []}

	# Built-ins are scanned from the project; the My * folders supply the rest.
	# Dropping a fully-opaque image in either folder adds it to the rotation.
	_media["bg"] = _scan_images("res://assets/backgrounds", true)
	_media["bg"] += _scan_images(asset_base.path_join("My Backgrounds"), false)
	_media["sprite"] = _scan_images("res://assets/sprites", true)
	_media["sprite"] += _scan_images(asset_base.path_join("My Sprites"), false)
	_media["sound"] = _scan_files(asset_base.path_join("My Sounds"), ["ogg", "wav"], false)
	_media["font"] = _scan_files(asset_base.path_join("My Fonts"), ["ttf", "otf"], false)
	# Textbox textures: My UI files first, custom UI dir, the bundled panel last
	_media["ui"] = _scan_images(asset_base.path_join("My UI"), false)
	if not manager.custom_ui_dir.is_empty():
		_media["ui"] += _scan_images(manager.custom_ui_dir, false)
	_media["ui"].append({"name": "Cozy wood (built-in)", "builtin": true, "path": BUILTIN_PANEL_TEX})
	if ResourceLoader.exists("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"):
		_media["font"].append({"name": "Atkinson Hyperlegible", "builtin": true, "path": "res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"})
	if ResourceLoader.exists("res://assets/fonts/Kaph-Regular.ttf"):
		_media["font"].append({"name": "Kaph", "builtin": true, "path": "res://assets/fonts/Kaph-Regular.ttf"})

	# Settings folder pickers override the matching kind entirely.
	if not manager.custom_bgs_dir.is_empty():
		_media["bg"] = _scan_images(manager.custom_bgs_dir, false)
	if not manager.custom_sprites_dir.is_empty():
		_media["sprite"] = _scan_images(manager.custom_sprites_dir, false)

	for e in _media["bg"]:
		if not manager.off_backgrounds.has(e["name"]):
			bg_textures.append(e["path"])

	for e in _media["sprite"]:
		if manager.off_sprites.has(e["name"]):
			continue
		var stex: Texture2D = _sprite_texture(e["path"])
		if stex:
			sprite_textures.append(stex)
			sprite_names.append(e["name"])
		else:
			push_warning("Sprite failed to load: " + e["name"])

	_asset_signature = _asset_folders_signature()

# ==============================================================================
# UI CONSTRUCTION (Programmatic Godot 4.7)
# ==============================================================================

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	
	# Background: whole image visible (nothing cropped). A darkened, stretched
	# copy behind fills the letterbox so the edges read as a soft backdrop.
	# ponytail: flat dark backdrop, not a real blur. A blur shader is the
	# upgrade if the bars ever look too hard-edged.
	bg_back = TextureRect.new()
	bg_back.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_back.stretch_mode = TextureRect.STRETCH_SCALE
	bg_back.modulate = Color(0.42, 0.38, 0.33, 1.0)
	add_child(bg_back)

	bg_rect = TextureRect.new()
	bg_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(bg_rect)
	
	bg_fade_rect = TextureRect.new()
	bg_fade_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg_fade_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_fade_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg_fade_rect.modulate.a = 0.0
	add_child(bg_fade_rect)
	
	# Dimmer overlay so text is crisp and readable
	bg_dim = ColorRect.new()
	bg_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg_dim.color = Color(0, 0, 0, 0.25)
	add_child(bg_dim)
	
	# Character Sprite Holder
	sprite_holder = Control.new()
	sprite_holder.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	sprite_holder.offset_left = -260
	sprite_holder.offset_right = 260
	sprite_holder.offset_top = -680
	sprite_holder.offset_bottom = 0
	add_child(sprite_holder)
	
	character_sprite = TextureRect.new()
	character_sprite.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	character_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite_holder.add_child(character_sprite)
	
	# Top Bar
	_build_top_bar()
	
	# Dialogue Box
	_build_dialogue_box()
	
	# Overlays
	_build_main_menu()
	_build_settings_dialog()
	_build_recent_dialog()
	_build_backlog_dialog()
	_build_chapters_dialog()
	_build_media_dialog()
	
	# Native File Dialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray([
		"*.txt, *.md, *.docx, *.pdf, *.epub ; Documents",
		"*.txt ; Plain Text (*.txt)",
		"*.docx ; Word Document (*.docx)",
		"*.md ; Markdown Document (*.md)",
		"*.pdf ; PDF Document (*.pdf)",
		"*.epub ; EPUB Book (*.epub)",
		"*.* ; All Files"
	])
	file_dialog.file_selected.connect(func(path: String):
		load_document(path, 0)
	)
	add_child(file_dialog)

func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_top = 0.0
	top_bar.offset_bottom = TOP_BAR_H
	add_child(top_bar)
	
	var bar_style := StyleBoxFlat.new()
	bar_style.content_margin_left = 16.0
	bar_style.content_margin_right = 16.0
	bar_style.content_margin_top = 8.0
	bar_style.content_margin_bottom = 8.0
	top_bar.add_theme_stylebox_override("panel", bar_style) # colors set in _apply_theme
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	top_bar.add_child(hbox)
	
	doc_title_label = Label.new()
	doc_title_label.text = "VN Reader"
	doc_title_label.size_flags_horizontal = SIZE_EXPAND_FILL
	# clip_text drops the text from this label's minimum width: a long book title
	# otherwise widened the whole row and pushed the Menu button off the right edge
	doc_title_label.clip_text = true
	doc_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	doc_title_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(doc_title_label)
	
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(220, 18)
	progress_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	progress_bar.show_percentage = false
	hbox.add_child(progress_bar)
	
	progress_label = Label.new()
	progress_label.text = "Slide 0 / 0"
	progress_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(progress_label)
	
	btn_auto = Button.new()
	btn_auto.text = "Auto"
	btn_auto.pressed.connect(_toggle_auto)
	hbox.add_child(btn_auto)

	var btn_chapters := Button.new()
	btn_chapters.text = "Chapters"
	btn_chapters.pressed.connect(_open_chapters)
	hbox.add_child(btn_chapters)

	var btn_log := Button.new()
	btn_log.text = "History"
	btn_log.pressed.connect(_open_backlog)
	hbox.add_child(btn_log)
	
	var btn_settings := Button.new()
	btn_settings.text = "Settings"
	btn_settings.pressed.connect(func(): _show_state(State.SETTINGS))
	hbox.add_child(btn_settings)
	
	var btn_menu := Button.new()
	btn_menu.text = "Menu"
	btn_menu.pressed.connect(func(): _show_state(State.MENU))
	hbox.add_child(btn_menu)

func _build_dialogue_box() -> void:
	dialogue_box = PanelContainer.new()
	dialogue_box.anchor_left = 0.05
	dialogue_box.anchor_right = 0.95
	dialogue_box.anchor_top = 1.0
	dialogue_box.anchor_bottom = 1.0
	dialogue_box.offset_top = -260.0
	dialogue_box.offset_bottom = -20.0
	add_child(dialogue_box)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	dialogue_box.add_child(vbox)
	
	# Nameplate container
	nameplate_panel = PanelContainer.new()
	nameplate_panel.size_flags_horizontal = SIZE_SHRINK_BEGIN
	vbox.add_child(nameplate_panel)
	
	nameplate_label = Label.new()
	nameplate_label.text = manager.speaker_name
	nameplate_label.add_theme_font_size_override("font_size", 18)
	nameplate_panel.add_child(nameplate_label)
	
	# Dialogue text
	dialogue_label = RichTextLabel.new()
	dialogue_label.size_flags_vertical = SIZE_EXPAND_FILL
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.bbcode_enabled = true
	dialogue_label.selection_enabled = false
	dialogue_label.scroll_active = false # zero scrolling guarantee: auto-fitting ensures text always fits
	dialogue_label.add_theme_font_size_override("normal_font_size", manager.font_size)
	vbox.add_child(dialogue_label)
	
	# Bouncing Next Arrow
	next_arrow = TextureRect.new()
	next_arrow.texture = _scaled_icon("res://assets/ui/arrow_brown.png", 26)
	next_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	next_arrow.custom_minimum_size = Vector2(34, 26)
	next_arrow.size_flags_horizontal = SIZE_SHRINK_END
	vbox.add_child(next_arrow)
	
	var arrow_tween := create_tween().set_loops()
	arrow_tween.tween_property(next_arrow, "modulate:a", 0.3, 0.4)
	arrow_tween.tween_property(next_arrow, "modulate:a", 1.0, 0.4)

# ==============================================================================
# MENU & DIALOGS
# ==============================================================================

func _build_main_menu() -> void:
	menu_overlay = Control.new()
	menu_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(menu_overlay)

	# Full-window wooden backdrop — the menu owns the whole screen
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color("241c14")
	menu_overlay.add_child(bg)

	# Menu background: whole image visible, darkened stretched copy behind the bars
	menu_bg_back = TextureRect.new()
	menu_bg_back.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	menu_bg_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_bg_back.stretch_mode = TextureRect.STRETCH_SCALE
	menu_bg_back.modulate = Color(0.42, 0.38, 0.33, 1.0)
	menu_overlay.add_child(menu_bg_back)

	menu_bg_rect = TextureRect.new()
	menu_bg_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	menu_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	menu_overlay.add_child(menu_bg_rect)

	var menu_dim := ColorRect.new()
	menu_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	menu_dim.color = Color(0.08, 0.05, 0.03, 0.7)
	menu_overlay.add_child(menu_dim)

	var content := MarginContainer.new()
	content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 140)
	content.add_theme_constant_override("margin_right", 140)
	# 26/44 clipped the action row off the bottom of a 720-tall window (content min
	# was 773). Everything here is sized to keep the whole menu at ~677.
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_bottom", 20)
	menu_overlay.add_child(content)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	content.add_child(vbox)

	var title := Label.new()
	title.text = "VN Reader"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Your book shelf: pick up where you left off"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	vbox.add_child(subtitle)

	update_banner = PanelContainer.new()
	update_banner.visible = false
	update_banner.custom_minimum_size = Vector2(0, 36)
	var banner_hbox := HBoxContainer.new()
	banner_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_hbox.add_theme_constant_override("separation", 12)
	update_banner.add_child(banner_hbox)

	update_label = Label.new()
	update_label.text = "A new version is available!"
	update_label.add_theme_font_size_override("font_size", 13)
	banner_hbox.add_child(update_label)

	update_progress_bar = ProgressBar.new()
	update_progress_bar.custom_minimum_size = Vector2(160, 20)
	update_progress_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	update_progress_bar.visible = false
	update_progress_bar.show_percentage = true
	banner_hbox.add_child(update_progress_bar)

	update_now_btn = Button.new()
	update_now_btn.text = "Update Now"
	update_now_btn.custom_minimum_size = Vector2(100, 26)
	update_now_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	update_now_btn.add_theme_font_size_override("font_size", 12)
	update_now_btn.pressed.connect(_on_update_now_pressed)
	banner_hbox.add_child(update_now_btn)

	update_dismiss_btn = Button.new()
	update_dismiss_btn.text = "Later"
	update_dismiss_btn.custom_minimum_size = Vector2(50, 26)
	update_dismiss_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	update_dismiss_btn.add_theme_font_size_override("font_size", 12)
	update_dismiss_btn.pressed.connect(func(): update_banner.visible = false)
	banner_hbox.add_child(update_dismiss_btn)

	vbox.add_child(update_banner)

	# --- "Now Reading" spotlight: cover of the current book + Continue button ---
	spotlight_box = HBoxContainer.new()
	spotlight_box.custom_minimum_size = Vector2(0, 132)
	spotlight_box.size_flags_horizontal = SIZE_EXPAND_FILL
	spotlight_box.modulate.a = 0.0
	spotlight_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spotlight_box.add_theme_constant_override("separation", 18)
	vbox.add_child(spotlight_box)

	spot_cover = PanelContainer.new()
	spot_cover.custom_minimum_size = Vector2(100, 132)
	spot_cover.clip_contents = true
	spotlight_box.add_child(spot_cover)

	var spot_info := VBoxContainer.new()
	spot_info.size_flags_horizontal = SIZE_EXPAND_FILL
	spot_info.alignment = BoxContainer.ALIGNMENT_CENTER
	spot_info.add_theme_constant_override("separation", 4)
	spotlight_box.add_child(spot_info)

	spot_title = Label.new()
	spot_title.add_theme_font_size_override("font_size", 20)
	spot_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	spot_title.custom_minimum_size = Vector2(0, 0)
	spot_info.add_child(spot_title)

	spot_meta = Label.new()
	spot_meta.add_theme_font_size_override("font_size", 13)
	spot_meta.add_theme_color_override("font_color", WOOD_INK_DIM)
	spot_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	spot_meta.custom_minimum_size = Vector2(0, 0)
	spot_info.add_child(spot_meta)

	spot_preview = Label.new()
	spot_preview.add_theme_font_size_override("font_size", 13)
	spot_preview.add_theme_color_override("font_color", WOOD_INK_DIM)
	spot_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spot_preview.max_lines_visible = 2
	spot_preview.custom_minimum_size = Vector2(0, 0)
	spot_info.add_child(spot_preview)

	menu_primary_btn = Button.new()
	menu_primary_btn.text = "Continue Reading"
	menu_primary_btn.custom_minimum_size = Vector2(210, 52)
	menu_primary_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	menu_primary_btn.add_theme_font_size_override("font_size", 19)
	menu_primary_btn.pressed.connect(_continue_reading)
	spotlight_box.add_child(menu_primary_btn)

	# --- Search box + Reading/Finished filter tabs ---
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	vbox.add_child(controls)

	shelf_search = LineEdit.new()
	shelf_search.placeholder_text = "Search your shelf..."
	shelf_search.size_flags_horizontal = SIZE_EXPAND_FILL
	shelf_search.custom_minimum_size = Vector2(0, 34)
	shelf_search.text_changed.connect(func(q: String):
		shelf_query = q.to_lower()
		_populate_book_shelf(false)
	)
	controls.add_child(shelf_search)

	for i in 3:
		var tab := Button.new()
		tab.text = ["All", "Reading", "Finished"][i]
		tab.custom_minimum_size = Vector2(110, 34)
		tab.pressed.connect(func():
			shelf_filter = i
			_populate_book_shelf(false)
		)
		shelf_tabs.append(tab)
		controls.add_child(tab)

	# --- Hover card strip: shows the book under the mouse + its Delete button ---
	_hover_grace = Timer.new()
	_hover_grace.one_shot = true
	_hover_grace.wait_time = 0.30
	_hover_grace.timeout.connect(_on_hover_grace_timeout)
	add_child(_hover_grace)

	hover_strip = PanelContainer.new()
	hover_strip.custom_minimum_size = Vector2(0, 64)
	# STOP, not IGNORE: the strip hosts the Delete button, and its enter/exit drive
	# the grace timer that keeps the card alive while the mouse travels onto it.
	hover_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	hover_strip.mouse_entered.connect(func(): _hover_grace.stop())
	hover_strip.mouse_exited.connect(func(): _hover_grace.start())
	vbox.add_child(hover_strip)

	var strip_h := HBoxContainer.new()
	strip_h.add_theme_constant_override("separation", 12)
	strip_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_strip.add_child(strip_h)

	var strip_v := VBoxContainer.new()
	strip_v.add_theme_constant_override("separation", 2)
	strip_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_v.size_flags_horizontal = SIZE_EXPAND_FILL
	strip_h.add_child(strip_v)

	hover_delete_btn = Button.new()
	hover_delete_btn.text = "Delete"
	hover_delete_btn.add_theme_font_size_override("font_size", 12)
	hover_delete_btn.custom_minimum_size = Vector2(76, 34)
	hover_delete_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	hover_delete_btn.visible = false
	hover_delete_btn.pressed.connect(_ask_delete)
	strip_h.add_child(hover_delete_btn)

	hover_title = Label.new()
	hover_title.add_theme_font_size_override("font_size", 15)
	hover_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hover_title.custom_minimum_size = Vector2(0, 0)
	hover_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_v.add_child(hover_title)

	hover_preview = Label.new()
	hover_preview.add_theme_font_size_override("font_size", 12)
	hover_preview.add_theme_color_override("font_color", WOOD_INK_DIM)
	hover_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_preview.max_lines_visible = 2
	hover_preview.custom_minimum_size = Vector2(0, 0)
	hover_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_v.add_child(hover_preview)

	hover_meta = Label.new()
	hover_meta.add_theme_font_size_override("font_size", 12)
	hover_meta.add_theme_color_override("font_color", WOOD_INK_DIM)
	hover_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hover_meta.custom_minimum_size = Vector2(0, 0)
	hover_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_v.add_child(hover_meta)

	# --- The shelf: wooden plank with the book spines standing on it ---
	shelf_panel = PanelContainer.new()
	vbox.add_child(shelf_panel)

	var shelf_margin := MarginContainer.new()
	shelf_margin.add_theme_constant_override("margin_left", 32)
	shelf_margin.add_theme_constant_override("margin_right", 32)
	shelf_margin.add_theme_constant_override("margin_top", 14)
	shelf_margin.add_theme_constant_override("margin_bottom", 12)
	shelf_panel.add_child(shelf_margin)

	var shelf_scroll := ScrollContainer.new()
	shelf_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	# 216 = tallest spine (179) + 22px top margin + the 12px hover lift + bottom breathing room,
	# ensuring a hovered book never paints over the plank edge or gets clipped.
	shelf_scroll.custom_minimum_size = Vector2(0, 216)
	shelf_scroll.clip_contents = true
	shelf_margin.add_child(shelf_scroll)

	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 8)
	row_margin.add_theme_constant_override("margin_right", 8)
	row_margin.add_theme_constant_override("margin_top", 18)
	row_margin.add_theme_constant_override("margin_bottom", 6)
	row_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	row_margin.size_flags_vertical = SIZE_EXPAND_FILL
	shelf_scroll.add_child(row_margin)

	shelf_row = HBoxContainer.new()
	shelf_row.size_flags_vertical = SIZE_SHRINK_END
	shelf_row.add_theme_constant_override("separation", 8)
	row_margin.add_child(shelf_row)

	# --- Compact action row (used to be the big button stack) ---
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	vbox.add_child(actions)

	_add_menu_button(actions, "Open Document", 13, func():
		file_dialog.popup_centered(Vector2i(850, 550))
	)
	_add_menu_button(actions, "Paste Text", 13, func():
		var clip := DisplayServer.clipboard_get()
		if not clip.strip_edges().is_empty():
			load_raw_text(clip, "Pasted Document")
		else:
			OS.alert("Clipboard is empty. Copy some text first, then choose Paste Text.", "Clipboard Empty")
	)
	_add_menu_button(actions, "Sample Paper", 13, func():
		load_document("res://assets/sample_paper.txt", 0)
	)
	_add_menu_button(actions, "Bookmarks & Recent", 13, func():
		_populate_recent_list()
		_show_state(State.RECENT)
	)
	_add_menu_button(actions, "Settings", 13, func(): _show_state(State.SETTINGS))
	_add_menu_button(actions, "Quit", 13, func(): get_tree().quit())

	# Delete confirmation, created once and reused; only its text changes.
	# autowrap wraps the message; min_size pins the width (autowrap alone collapses
	# the dialog to its longest word, no autowrap stretches it to the full sentence).
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Delete book"
	_confirm_dialog.dialog_autowrap = true
	_confirm_dialog.min_size = Vector2i(560, 0)
	_confirm_dialog.ok_button_text = "Delete"
	_confirm_dialog.get_cancel_button().text = "Cancel"
	_confirm_dialog.exclusive = true
	_confirm_dialog.confirmed.connect(_do_delete)
	var dlg_style := StyleBoxFlat.new()
	dlg_style.bg_color = Color("2a2018")
	dlg_style.border_color = _look["edge"]
	dlg_style.set_border_width_all(2)
	dlg_style.set_corner_radius_all(10)
	dlg_style.set_content_margin_all(18)
	_confirm_dialog.add_theme_stylebox_override("panel", dlg_style)
	_confirm_dialog.get_label().add_theme_color_override("font_color", WOOD_INK)
	add_child(_confirm_dialog)

func _add_menu_button(parent: Container, label: String, font_size: int, action: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 46 if font_size >= 17 else 36)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	btn.pressed.connect(action)
	parent.add_child(btn)

# ==============================================================================
# BOOK SHELF (menu)
# ==============================================================================

func _populate_book_shelf(animate_drop: bool) -> void:
	for t in _shelf_tweens:
		t.kill()
	_shelf_tweens.clear()
	for child in shelf_row.get_children():
		shelf_row.remove_child(child)
		child.queue_free()
	_set_hover_card({})
	_hover_grace.stop()

	# Highlight the active filter tab
	for i in shelf_tabs.size():
		_paint_tab(shelf_tabs[i], i == shelf_filter)

	_prune_missing_my_books()
	var items := manager.get_recent_files()
	# My Books is scanned fresh each time the menu opens, so dropping a file in
	# the folder shows it up without a restart. Already-opened books win (they
	# carry progress), so a book is never listed twice.
	var on_shelf := {}
	for item in items:
		on_shelf[item.path] = true
	for b in _my_books():
		if not on_shelf.has(b["path"]):
			items.append(b)
	_update_spotlight(items)

	var shown: Array[Dictionary] = []
	for item in items:
		var finished: bool = item.total_slides > 0 and item.slide_index >= item.total_slides - 1
		if shelf_filter == 1 and finished:
			continue
		if shelf_filter == 2 and not finished:
			continue
		if not shelf_query.is_empty() and not item.title.to_lower().contains(shelf_query):
			continue
		shown.append(item)

	if shown.is_empty():
		var empty := Label.new()
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", WOOD_INK_DIM)
		empty.custom_minimum_size = Vector2(0, 150)
		empty.size_flags_horizontal = SIZE_EXPAND_FILL
		empty.text = "Your shelf is empty: open a document to add your first book." if items.is_empty() else "No books match. Clear the search or pick another tab."
		shelf_row.add_child(empty)
		return

	for i in shown.size():
		shelf_row.add_child(_make_book_spine(shown[i], i, animate_drop))

func _make_book_spine(item: Dictionary, idx: int, animate_drop: bool) -> Button:
	var path: String = item["path"]
	var h := absi(path.md5_text().hash())
	var w: int = 44 + h % 16
	var hh: int = 156 + (h >> 4) % 24
	var finished: bool = item.total_slides > 0 and item.slide_index >= item.total_slides - 1
	var target_alpha := 1.0 if FileAccess.file_exists(path) else 0.62

	var spine := Button.new()
	spine.custom_minimum_size = Vector2(w, hh)
	spine.size_flags_vertical = SIZE_SHRINK_END
	spine.clip_contents = true

	var base := _spine_color(path, target_alpha < 1.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.border_color = _look["accent"] if finished else base.darkened(0.35)
	sb.set_border_width_all(3 if finished else 1)
	sb.set_corner_radius_all(2)
	spine.add_theme_stylebox_override("normal", sb)
	var sb_hover: StyleBoxFlat = sb.duplicate()
	sb_hover.bg_color = base.lightened(0.12)
	spine.add_theme_stylebox_override("hover", sb_hover)
	var sb_press: StyleBoxFlat = sb.duplicate()
	sb_press.bg_color = base.darkened(0.12)
	spine.add_theme_stylebox_override("pressed", sb_press)
	spine.add_theme_color_override("font_color", Color.TRANSPARENT) # the rotated label below draws the title

	# Reading progress fills the spine from the bottom up. Added before the title
	# so the wash sits under the letters, not across them.
	if item.total_slides > 0:
		var frac := clampf(float(item.slide_index + 1) / float(item.total_slides), 0.0, 1.0)
		var fill := ColorRect.new()
		fill.color = Color(_look["accent"].r, _look["accent"].g, _look["accent"].b, 0.30)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.anchor_left = 0.0
		fill.anchor_right = 1.0
		fill.anchor_top = 1.0 - frac
		fill.anchor_bottom = 1.0
		spine.add_child(fill)

	# Vertical title, rotated like a real book spine.
	# max_len gives 10px margin at top and bottom so titles never escape the spine edges.
	var lbl := Label.new()
	lbl.text = str(item.title).strip_edges()
	lbl.add_theme_font_size_override("font_size", 12)
	if _ui_font != null:
		lbl.add_theme_font_override("font", _ui_font)
	lbl.add_theme_color_override("font_color", WOOD_INK)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var max_len: float = hh - 20.0
	lbl.custom_minimum_size = Vector2(0, 0)
	lbl.size = Vector2(max_len, float(w))
	lbl.pivot_offset = Vector2(max_len / 2.0, float(w) / 2.0)
	lbl.position = Vector2(float(w) - max_len, float(hh) - float(w)) / 2.0
	lbl.rotation_degrees = 90.0
	spine.add_child(lbl)

	spine.mouse_entered.connect(func():
		_play_blip()
		_hover_grace.stop()
		_set_hover_card(item)
		_show_spot(item)
		var tw := create_tween()
		tw.tween_property(spine, "scale", Vector2(1.07, 1.07), 0.09).set_trans(Tween.TRANS_BACK)
		tw.tween_property(spine, "rotation_degrees", -3.0, 0.08).set_trans(Tween.TRANS_SINE)
		tw.tween_property(spine, "rotation_degrees", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
		_shelf_tweens.append(tw)
	)
	spine.mouse_exited.connect(func():
		# not cleared at once: the mouse may be on its way to the card's Delete button.
		# The timer's timeout re-checks where the pointer actually landed.
		_hover_grace.start()
		var tw := create_tween()
		tw.tween_property(spine, "rotation_degrees", 0.0, 0.08).set_trans(Tween.TRANS_SINE)
		tw.tween_property(spine, "scale", Vector2.ONE, 0.09).set_trans(Tween.TRANS_SINE)
		_shelf_tweens.append(tw)
	)
	spine.pressed.connect(func():
		if FileAccess.file_exists(path):
			load_document(path, item.slide_index, item.total_slides)
		else:
			OS.alert("File not found:\n" + path + "\n\nIt may have been moved or deleted. You can remove it from Bookmarks & Recent.", "File Not Found")
	)

	# Pivot on the plank so hover scaling lifts the book upward instead of
	# pushing its top out through the shelf edge.
	spine.pivot_offset = Vector2(w / 2.0, hh)
	if animate_drop:
		# Book drops onto the shelf: grows up from the plank, bounces, thuds
		spine.scale = Vector2(1.0, 0.01)
		spine.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(minf(0.05 * idx, 0.85))
		tw.tween_property(spine, "modulate:a", target_alpha, 0.07)
		tw.tween_property(spine, "scale:y", 1.0, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if idx < 10:
			tw.tween_callback(func(): _play_sfx(sfx_back, 0.4))
		_shelf_tweens.append(tw)
	else:
		spine.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(spine, "modulate:a", target_alpha, 0.1)
		_shelf_tweens.append(tw)
	return spine

func _set_hover_card(item: Dictionary) -> void:
	_hover_item = item
	hover_delete_btn.visible = not item.is_empty()
	if item.is_empty():
		hover_title.text = ""
		hover_preview.text = ""
		hover_meta.text = "Hover a book to peek at it; click one to jump back in."
		return
	var pct := 0
	if item.total_slides > 0:
		pct = int(float(item.slide_index + 1) / float(item.total_slides) * 100.0)
	hover_title.text = item.title
	hover_preview.text = str(item.get("preview", ""))
	hover_meta.text = "Slide %d of %d (%d%%)  •  Last read %s  •  Click to resume" % [
		item.slide_index + 1, item.total_slides, pct, _time_ago(int(item.timestamp))
	]

## The card clears 0.3s after the pointer leaves a spine, but only if it left for
## real: landing on the card (reaching for Delete) or on another spine keeps it.
func _on_hover_grace_timeout() -> void:
	var mp := hover_strip.get_global_mouse_position()
	if hover_strip.get_global_rect().has_point(mp):
		return
	for child in shelf_row.get_children():
		if child is Control and (child as Control).get_global_rect().has_point(mp):
			return
	_set_hover_card({})
	_show_spot(_spot_book)

## Deleting asks first, and the wording says exactly what will happen to the file.
func _ask_delete() -> void:
	if _hover_item.is_empty():
		return
	_pending_delete = _hover_item
	var title := str(_pending_delete.get("title", "this book"))
	var path := str(_pending_delete.get("path", ""))
	var msg: String
	if not FileAccess.file_exists(path):
		msg = "\"%s\" is already gone from disk.\n\nRemove it from your shelf and erase its reading progress?" % title
	elif path.begins_with(_my_books_root() + "/"):
		msg = "Move \"%s\" to the Recycle Bin?\n\nIt leaves your shelf and its reading progress is erased. The file goes to the Windows Recycle Bin, so you can restore it there if you change your mind." % title
	else:
		msg = "Take \"%s\" off your shelf?\n\nThe file stays where it is on your PC. Only the shelf entry and its reading progress are erased." % title
	_confirm_dialog.dialog_text = msg
	_confirm_dialog.popup_centered(Vector2i(560, 0))

func _do_delete() -> void:
	var item := _pending_delete
	_pending_delete = {}
	var path := str(item.get("path", ""))
	if path.is_empty():
		return
	if path.begins_with(_my_books_root() + "/") and FileAccess.file_exists(path):
		if OS.move_to_trash(path) != OK:
			OS.alert("Could not move this file to the Recycle Bin:\n" + path + "\n\nIt may be open in another program. Nothing was deleted.", "Delete Failed")
			return
	manager.remove_recent(path)
	_play_sfx(sfx_back, 0.6)
	_populate_book_shelf(false)

## The book the spotlight shows when nothing is hovered. Hovering a spine
## previews that book in the spotlight; leaving restores it.
var _spot_book: Dictionary = {}
var _spot_shown_path := ""
var _cover_cache := {}

func _update_spotlight(items: Array[Dictionary]) -> void:
	_spot_book = {}
	for item in items:
		if FileAccess.file_exists(item.path):
			_spot_book = item
			break
	_show_spot(_spot_book)

func _show_spot(spot: Dictionary) -> void:
	if spot.is_empty():
		spotlight_box.modulate.a = 0.0
		spotlight_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spot_shown_path = ""
		spot_title.text = ""
		return
	spotlight_box.modulate.a = 1.0
	spotlight_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var path := str(spot.get("path", ""))
	if path == _spot_shown_path and spot_title.text == str(spot.title):
		return # mouse-exited back to the same book: do not re-upload its cover
	_spot_shown_path = path
	spot_title.text = spot.title
	if spot.total_slides <= 0:
		# a My Books file that has never been opened: inventing "1 of 0, 100% read"
		# made an unread book look finished
		spot_meta.text = "Not started yet  •  Added %s" % _time_ago(int(spot.timestamp))
		menu_primary_btn.text = "Start Reading"
	else:
		var pct := int(float(spot.slide_index + 1) / float(spot.total_slides) * 100.0)
		spot_meta.text = "Slide %d of %d  •  %d%% read  •  Last read %s" % [
			spot.slide_index + 1, spot.total_slides, pct, _time_ago(int(spot.timestamp))
		]
		if pct >= 100:
			menu_primary_btn.text = "Read Again"
		elif pct <= 0:
			menu_primary_btn.text = "Start Reading"
		else:
			menu_primary_btn.text = "Continue: %d%%" % pct
	var preview := str(spot.get("preview", ""))
	spot_preview.text = preview if preview != "" else "Open it to see the first line."

	for c in spot_cover.get_children():
		spot_cover.remove_child(c)
		c.queue_free()
	var cover_path := str(spot.get("cover", ""))
	if cover_path == "" and path.get_extension().to_lower() == "epub":
		cover_path = _extract_and_cache_epub_cover(path)
	var cover_tex: Texture2D = null
	if cover_path != "":
		# keyed by path; bounded by the shelf cap. Cached as a texture so hovering
		# back and forth does not re-upload to the GPU every time.
		if not _cover_cache.has(cover_path):
			var im := Image.load_from_file(cover_path) if FileAccess.file_exists(cover_path) else null
			_cover_cache[cover_path] = ImageTexture.create_from_image(im) if im else null
		cover_tex = _cover_cache[cover_path]
	if cover_tex:
		var tr := TextureRect.new()
		tr.texture = cover_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		spot_cover.add_child(tr)
	else:
		# Generated cover: title initial on the book's spine color
		var gen := PanelContainer.new()
		var col := _spine_color(spot.path)
		var sbg := StyleBoxFlat.new()
		sbg.bg_color = col
		sbg.border_color = col.darkened(0.3)
		sbg.set_border_width_all(1)
		sbg.set_corner_radius_all(4)
		sbg.content_margin_left = 8.0
		sbg.content_margin_right = 8.0
		sbg.content_margin_top = 10.0
		sbg.content_margin_bottom = 10.0
		gen.add_theme_stylebox_override("panel", sbg)
		gen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		spot_cover.add_child(gen)
		var gv := VBoxContainer.new()
		gv.alignment = BoxContainer.ALIGNMENT_CENTER
		gv.size_flags_vertical = SIZE_EXPAND_FILL
		gv.add_theme_constant_override("separation", 6)
		gen.add_child(gv)
		var letter := Label.new()
		letter.text = str(spot.title).substr(0, 1).to_upper()
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", 42)
		letter.add_theme_color_override("font_color", WOOD_INK)
		gv.add_child(letter)
		var name_lbl := Label.new()
		name_lbl.text = spot.title
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", WOOD_INK_DIM)
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.max_lines_visible = 3
		gv.add_child(name_lbl)

func _spine_color(path: String, missing := false) -> Color:
	# Stable per book: hue from the path hash. Value 0.44 keeps cream spine titles
	# above 4.5:1 on the lightest hue; the old 0.58 measured 2.69:1.
	var h := absi(path.md5_text().hash())
	if missing:
		return Color.from_hsv(float(h % 1000) / 1000.0, 0.10, 0.28)
	return Color.from_hsv(float(h % 1000) / 1000.0, 0.42, 0.44)

func _time_ago(unix: int) -> String:
	if unix <= 0:
		return "never"
	var diff := int(Time.get_unix_time_from_system()) - unix
	if diff < 120:
		return "just now"
	if diff < 7200:
		return "%d minutes ago" % (diff / 60)
	if diff < 86400:
		return "%d hours ago" % (diff / 3600)
	if diff < 604800:
		return "%d days ago" % (diff / 86400)
	return Time.get_datetime_string_from_unix_time(unix).split("T")[0]

func _build_settings_dialog() -> void:
	_build_asset_dialog()
	settings_overlay = PanelContainer.new()
	settings_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(settings_overlay)

	var panel_style := StyleBoxFlat.new()
	panel_style.content_margin_left = 60.0
	panel_style.content_margin_right = 60.0
	panel_style.content_margin_top = 40.0
	panel_style.content_margin_bottom = 40.0
	settings_overlay.add_theme_stylebox_override("panel", panel_style) # colors set in _apply_theme
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	settings_overlay.add_child(vbox)
	
	# Header
	var header := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Settings"
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(lbl)
	
	settings_save_btn = Button.new()
	settings_save_btn.text = "Save & Close"
	settings_save_btn.custom_minimum_size = Vector2(140, 36)
	settings_save_btn.pressed.connect(func():
		_play_sfx(sfx_save, 0.8)
		manager.save_settings()
		_apply_theme()
		_show_state(_settings_return_to)
	)
	header.add_child(settings_save_btn)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	# One tab at a time: the old screen was a single ~20-row scroll.
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 8)
	vbox.add_child(tabs_row)
	for i in SETTINGS_TABS.size():
		var tab_btn := Button.new()
		tab_btn.text = SETTINGS_TABS[i]
		tab_btn.custom_minimum_size = Vector2(126, 34)
		tab_btn.pressed.connect(func():
			_play_blip()
			_select_settings_tab(i)
		)
		settings_tab_btns.append(tab_btn)
		tabs_row.add_child(tab_btn)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	settings_grid = GridContainer.new()
	settings_grid.columns = 2
	settings_grid.add_theme_constant_override("h_separation", 30)
	settings_grid.add_theme_constant_override("v_separation", 18)
	settings_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(settings_grid)

	_select_settings_tab(0)

func _select_settings_tab(idx: int) -> void:
	_settings_tab = idx
	for i in settings_tab_btns.size():
		_paint_tab(settings_tab_btns[i], i == idx)
	# remove_child now, queue_free later: freeing alone leaves the old rows
	# painted under the new tab for a frame
	for child in settings_grid.get_children():
		settings_grid.remove_child(child)
		child.queue_free()
	match idx:
		0: _tab_reading_and_sound()
		1: _tab_appearance_and_character()
		2: _tab_custom_art()

func _tab_reading_and_sound() -> void:
	var g := settings_grid
	_add_slider_setting(g, "Typewriter Speed (chars/sec, 120 = instant):", 15, 120, manager.typewriter_speed, func(val: float):
		manager.typewriter_speed = val
	)
	_add_slider_setting(g, "Max Sentences per Slide:", 1, 5, float(manager.sentences_per_slide), func(val: float):
		manager.set_sentences_per_slide(int(val))
		_apply_textbox_layout()
		_apply_sprite_layout()
		_refit_current_slide()
	, 1.0, func(v: float) -> String:
		var iv := int(v)
		var def_str := " (Default)" if iv == 2 else ""
		return "%d (%d px box)%s" % [iv, TextParser.height_for_sentences(iv), def_str]
	)
	var s_blank := Control.new()
	g.add_child(s_blank)
	var s_hint := Label.new()
	s_hint.text = "Up to this many sentences per slide (dialogue and paragraph breaks end early). Original default: 2."
	s_hint.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60))
	s_hint.add_theme_font_size_override("font_size", 12)
	g.add_child(s_hint)
	_add_slider_setting(g, "Auto-Advance Delay (seconds):", 1.0, 10.0, manager.auto_delay, func(val: float):
		manager.auto_delay = val
	, 0.5)
	_add_slider_setting(g, "Font Size (px):", 18, 36, float(manager.font_size), func(val: float):
		manager.font_size = int(val)
		_refit_current_slide()
	)
	_add_toggle_setting(g, "Interface Sounds (buttons and text):", manager.sound_enabled, func(toggled: bool):
		manager.sound_enabled = toggled
	)
	_add_slider_setting(g, "Sound Volume:", 0.0, 1.0, manager.sound_volume, func(val: float):
		manager.sound_volume = val
	, 0.05)

	# App Version & Update check
	var cur_ver: String = updater.CURRENT_VERSION if updater != null else "1.0"
	var ver_lbl := Label.new()
	ver_lbl.text = "App Version: v%s" % cur_ver
	g.add_child(ver_lbl)

	var check_box := HBoxContainer.new()
	check_box.add_theme_constant_override("separation", 10)
	var check_btn := Button.new()
	check_btn.text = "Check for Updates"
	check_btn.pressed.connect(func():
		_play_click()
		if settings_update_status != null:
			settings_update_status.text = "Checking GitHub..."
			settings_update_status.add_theme_color_override("font_color", WOOD_INK_DIM)
		if updater != null:
			updater.check_for_updates()
	)
	check_box.add_child(check_btn)
	settings_update_status = Label.new()
	settings_update_status.text = ""
	check_box.add_child(settings_update_status)
	g.add_child(check_box)

func _tab_appearance_and_character() -> void:
	var g := settings_grid

	# App look preset
	var look_lbl := Label.new()
	look_lbl.text = "App Look (color theme):"
	g.add_child(look_lbl)
	var look_opt := OptionButton.new()
	for l in LOOKS:
		look_opt.add_item(String(l["name"]))
	look_opt.selected = 0
	for i in LOOKS.size():
		if String(LOOKS[i]["name"]) == manager.ui_look:
			look_opt.selected = i
	look_opt.item_selected.connect(func(id: int):
		manager.ui_look = String(LOOKS[id]["name"])
		manager.save_settings()
		_look = _current_look()
		_apply_theme()
		_select_settings_tab(_settings_tab)
		_populate_book_shelf(false)
		_update_menu_background()
	)
	g.add_child(look_opt)

	# Reading presentation style (unified textbox style + custom textures)
	var style_lbl := Label.new()
	style_lbl.text = "Reading Style (textbox):"
	g.add_child(style_lbl)
	var style_opt := OptionButton.new()
	style_opt.add_item("Classic Wood Box (Bottom)")
	style_opt.add_item("Clean Flat Box (Bottom)")
	style_opt.add_item("Higurashi / Floating Text (Top)")

	# Collect custom UI textures from My UI
	var custom_ui_items: Array = []
	for e in _media.get("ui", []):
		if not e.get("builtin", false):
			custom_ui_items.append(e)
			style_opt.add_item("Custom: " + String(e["name"]))

	# Resolve current selection
	var initial_style_idx := 0
	if not manager.custom_ui_name.is_empty():
		for ci in custom_ui_items.size():
			if custom_ui_items[ci]["name"] == manager.custom_ui_name:
				initial_style_idx = 3 + ci
				break
	elif manager.textbox_style == 2 or manager.textbox_position == 1:
		initial_style_idx = 2
	elif manager.textbox_style == 1 or manager.textbox_flat_style:
		initial_style_idx = 1
	else:
		initial_style_idx = 0
	style_opt.selected = initial_style_idx

	style_opt.item_selected.connect(func(id: int):
		if id == 0:
			manager.textbox_style = 0
			manager.textbox_flat_style = false
			manager.textbox_position = 0
			manager.custom_ui_name = ""
		elif id == 1:
			manager.textbox_style = 1
			manager.textbox_flat_style = true
			manager.textbox_position = 0
			manager.custom_ui_name = ""
		elif id == 2:
			manager.textbox_style = 2
			manager.textbox_flat_style = false
			manager.textbox_position = 1
			manager.custom_ui_name = ""
		else:
			var custom_idx := id - 3
			if custom_idx >= 0 and custom_idx < custom_ui_items.size():
				var picked_name: String = custom_ui_items[custom_idx]["name"]
				manager.textbox_style = 0
				manager.textbox_flat_style = false
				manager.textbox_position = 0
				manager.custom_ui_name = picked_name
		manager.save_settings()
		_apply_theme()
		_apply_textbox_layout()
		_apply_sprite_layout()
		_refit_current_slide()
		_select_settings_tab(_settings_tab)
	)
	g.add_child(style_opt)

	# Textbox opacity: disabled / greyed note if in frameless mode
	var op_label_text := "Textbox Opacity (%):"
	if manager.textbox_style == 2:
		op_label_text = "Textbox Opacity (not used in floating mode):"
	_add_slider_setting(g, op_label_text, 40, 100, manager.textbox_opacity * 100.0, func(val: float):
		manager.textbox_opacity = val / 100.0
		_apply_textbox_opacity()
	)

	_add_slider_setting(g, "Textbox Height (px):", 160, 400, float(manager.textbox_height), func(val: float):
		manager.set_textbox_height(int(val))
		_apply_textbox_layout()
		_apply_sprite_layout()
		_refit_current_slide()
	, 10.0, func(v: float) -> String:
		var iv := int(v)
		var def_str := " (Default)" if iv == 260 else ""
		return "%d px (up to %s)%s" % [iv, _height_capacity_desc(iv), def_str]
	)
	var h_blank := Control.new()
	g.add_child(h_blank)
	var h_hint := Label.new()
	h_hint.text = "Taller box fits more sentences (up to max, respects paragraph breaks). Original default: 260 px (2 sentences)."
	h_hint.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60))
	h_hint.add_theme_font_size_override("font_size", 12)
	g.add_child(h_hint)

	# Character settings
	var name_lbl := Label.new()
	name_lbl.text = "Character Nameplate:"
	g.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.text = manager.speaker_name
	name_edit.text_changed.connect(func(new_text: String):
		manager.speaker_name = new_text
		nameplate_label.text = new_text
		nameplate_panel.visible = not new_text.strip_edges().is_empty()
	)
	g.add_child(name_edit)

	var char_pos_lbl := Label.new()
	char_pos_lbl.text = "Character Position:"
	g.add_child(char_pos_lbl)
	var char_pos_opt := OptionButton.new()
	char_pos_opt.add_item("Left")
	char_pos_opt.add_item("Center")
	char_pos_opt.add_item("Right")
	char_pos_opt.selected = clampi(manager.sprite_position, 0, 2)
	char_pos_opt.item_selected.connect(func(id: int):
		manager.sprite_position = id
		manager.save_settings()
		_apply_sprite_layout()
	)
	g.add_child(char_pos_opt)

	var char_size_lbl := Label.new()
	char_size_lbl.text = "Character Size:"
	g.add_child(char_size_lbl)
	var char_size_opt := OptionButton.new()
	char_size_opt.add_item("Above Textbox (framed)")
	char_size_opt.add_item("Full Height (behind textbox)")
	char_size_opt.add_item("Screen Takeover (giant VN style)")
	char_size_opt.selected = clampi(manager.sprite_mode, 0, 2)
	char_size_opt.item_selected.connect(func(id: int):
		manager.sprite_mode = id
		manager.save_settings()
		_apply_sprite_layout()
	)
	g.add_child(char_size_opt)

	var cs_blank := Control.new()
	g.add_child(cs_blank)
	var cs_hint := Label.new()
	cs_hint.text = "Screen Takeover lets the character dominate the scene, extending behind the textbox."
	cs_hint.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60))
	cs_hint.add_theme_font_size_override("font_size", 12)
	g.add_child(cs_hint)

	_add_toggle_setting(g, "Speaker Bounce on Speech:", manager.character_bounce, func(toggled: bool):
		manager.character_bounce = toggled
	)
	_add_toggle_setting(g, "Reactive Expressions (match text):", manager.reactive_expressions, func(toggled: bool):
		manager.reactive_expressions = toggled
	)
	_add_slider_setting(g, "Sprite Change (Every N slides):", 1, 10, manager.sprite_change_freq, func(val: float):
		manager.sprite_change_freq = int(val)
	)
	_add_toggle_setting(g, "Random Sprite Selection:", manager.sprite_change_random, func(toggled: bool):
		manager.sprite_change_random = toggled
	)

	# Background settings
	var fit_lbl := Label.new()
	fit_lbl.text = "Background Fit:"
	g.add_child(fit_lbl)
	var fit_opt := OptionButton.new()
	fit_opt.add_item("Auto (wide images fill, rest stay framed)")
	fit_opt.add_item("Always fill the screen")
	fit_opt.add_item("Always fit with border")
	fit_opt.selected = clampi(manager.bg_fit_mode, 0, 2)
	fit_opt.item_selected.connect(func(id: int):
		manager.bg_fit_mode = id
		manager.save_settings()
		_apply_bg_fit(bg_rect, bg_rect.texture)
		_apply_bg_fit(bg_fade_rect, bg_fade_rect.texture)
		_apply_bg_fit(menu_bg_rect, menu_bg_rect.texture)
	)
	g.add_child(fit_opt)

	_add_slider_setting(g, "Background Change (Every N slides):", 1, 15, manager.bg_change_freq, func(val: float):
		manager.bg_change_freq = int(val)
	)
	_add_toggle_setting(g, "Random Background Selection:", manager.bg_change_random, func(toggled: bool):
		manager.bg_change_random = toggled
	)

func _tab_custom_art() -> void:
	var g := settings_grid

	var menu_lbl := Label.new()
	menu_lbl.text = "Menu Background:"
	g.add_child(menu_lbl)
	var menu_opt := OptionButton.new()
	menu_opt.add_item("Random (rotates each visit)")
	for e in _media.get("bg", []):
		if not manager.off_backgrounds.has(e["name"]):
			menu_opt.add_item(e["name"])
	menu_opt.selected = 0
	if manager.menu_bg != "":
		for i in menu_opt.item_count:
			if menu_opt.get_item_text(i) == manager.menu_bg:
				menu_opt.selected = i
	menu_opt.item_selected.connect(func(id: int):
		manager.menu_bg = "" if id == 0 else menu_opt.get_item_text(id)
		manager.save_settings()
		_update_menu_background()
	)
	g.add_child(menu_opt)

	var media_btn := Button.new()
	media_btn.text = "Choose Which Art To Use"
	media_btn.pressed.connect(func(): _show_state(State.MEDIA))
	g.add_child(media_btn)

	var open_assets := Button.new()
	open_assets.text = "Open Asset Folders"
	open_assets.pressed.connect(func():
		_ensure_asset_folders()
		OS.shell_open(_asset_base_dir())
	)
	g.add_child(open_assets)

	_add_path_picker(g, "Backgrounds Folder:", true, manager.custom_bgs_dir, func(p: String):
		manager.custom_bgs_dir = p
		manager.save_settings()
		_load_default_assets()
		_update_background(true)
	)
	_add_path_picker(g, "Character Sprites Folder:", true, manager.custom_sprites_dir, func(p: String):
		manager.custom_sprites_dir = p
		manager.save_settings()
		_load_default_assets()
		_update_sprite(true)
	)
	_add_path_picker(g, "Custom Textbox UI Folder:", true, manager.custom_ui_dir, func(p: String):
		manager.custom_ui_dir = p
		manager.save_settings()
		_load_default_assets()
		_apply_theme()
	)
	_add_path_picker(g, "Custom Font (.ttf/.otf):", false, manager.custom_font_path, func(p: String):
		manager.custom_font_path = p
		manager.save_settings()
		_apply_theme()
	)

# ==============================================================================
# MY MEDIA (tick which art actually joins the rotation)
# ==============================================================================

func _build_media_dialog() -> void:
	media_overlay = PanelContainer.new()
	media_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(media_overlay)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	media_overlay.add_child(vbox)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "My Media"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Done"
	close_btn.custom_minimum_size = Vector2(110, 36)
	close_btn.pressed.connect(func():
		_play_sfx(sfx_save, 0.8)
		manager.save_settings()
		_show_state(State.SETTINGS)
	)
	header.add_child(close_btn)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 8)
	for i in MEDIA_KINDS.size():
		var kbtn := Button.new()
		kbtn.text = MEDIA_KINDS[i][1]
		kbtn.custom_minimum_size = Vector2(126, 32)
		kbtn.pressed.connect(_on_media_kind_pressed.bind(i))
		kinds.add_child(kbtn)
		media_kind_btns.append(kbtn)
	vbox.add_child(kinds)

	var srcs := HBoxContainer.new()
	srcs.add_theme_constant_override("separation", 8)
	media_src_box = srcs
	for i in 2:
		var sbtn := Button.new()
		sbtn.text = ["Built-in", "My Own"][i]
		sbtn.custom_minimum_size = Vector2(126, 32)
		sbtn.pressed.connect(_on_media_src_pressed.bind(i))
		srcs.add_child(sbtn)
		media_src_btns.append(sbtn)
	vbox.add_child(srcs)

	media_note = Label.new()
	media_note.add_theme_color_override("font_color", WOOD_INK_DIM)
	media_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(media_note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	media_grid = HFlowContainer.new()
	media_grid.add_theme_constant_override("h_separation", 14)
	media_grid.add_theme_constant_override("v_separation", 14)
	media_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(media_grid)

func _on_media_kind_pressed(i: int) -> void:
	_play_blip()
	_media_kind = MEDIA_KINDS[i][0]
	_populate_media()

func _on_media_src_pressed(i: int) -> void:
	_play_blip()
	_media_builtin = i == 0
	_populate_media()

func _media_hint() -> String:
	var entries: Array = _media.get(_media_kind, [])
	var off := _off_list(_media_kind)
	var in_tab := 0
	var ticked := 0
	for e in entries:
		if e["builtin"] == _media_builtin:
			in_tab += 1
			if not off.has(e["name"]):
				ticked += 1
	var where := "the art that ships with the app" if _media_builtin else "files in your %s folder" % _media_folder_label()
	var base := "%d of the %d shown here are ticked on (%d in %s). Unticked items never appear while you read. New files start ticked on." % [ticked, in_tab, entries.size(), where]
	if _media_kind == "font":
		base += " Only one font can be active, so ticking one unticks the rest."
	if _media_kind == "ui":
		base += " Only one texture can be active, so ticking one unticks the rest. It skins the reading textbox only, and bright textures are dimmed automatically so text stays readable."
	return base

func _populate_media() -> void:
	for i in MEDIA_KINDS.size():
		_paint_tab(media_kind_btns[i], MEDIA_KINDS[i][0] == _media_kind)
	for i in 2:
		_paint_tab(media_src_btns[i], (_media_builtin == (i == 0)))

	for child in media_grid.get_children():
		media_grid.remove_child(child)
		child.queue_free()

	var entries: Array = _media.get(_media_kind, [])
	var shown: Array = []
	for e in entries:
		if e["builtin"] == _media_builtin:
			shown.append(e)
	media_note.text = _media_hint()
	# Sounds only ever come from the reader's own folder, so a Built-in tab for
	# them would be a permanently empty screen claiming nothing was installed
	if media_src_box != null:
		# My Sounds is the only source for interface sounds, so a Built-in tab there
		# would be a permanently empty screen claiming nothing was installed
		media_src_box.visible = _media_kind != "sound"

	if shown.is_empty():
		var empty := Label.new()
		empty.custom_minimum_size = Vector2(0, 120)
		empty.add_theme_color_override("font_color", WOOD_INK_DIM)
		empty.text = "Nothing here yet. Drop files into the %s folder and come back to this screen." % _media_folder_label() \
			if not _media_builtin else "The app ships no built-in %s of this kind. Use the My Own tab instead." % _media_kind_label().to_lower()
		media_grid.add_child(empty)
		return
	for e in shown:
		media_grid.add_child(_media_tile(e))

func _paint_tab(btn: Button, active: bool) -> void:
	var c: Color = _look["accent"] if active else WOOD_INK
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_hover_color", c)
	btn.add_theme_color_override("font_pressed_color", c)
	# Selected state used to be font colour only (a 1.84:1 shift). A filled face and
	# a 2px amber edge carry the same signal without relying on hue.
	var face := StyleBoxFlat.new()
	face.set_corner_radius_all(8)
	face.set_border_width_all(2 if active else 1)
	face.border_color = _look["accent"] if active else _look["edge"]
	face.bg_color = _look["face"].lightened(0.06) if active else _look["face"]
	face.content_margin_left = 12.0
	face.content_margin_right = 12.0
	face.content_margin_top = 6.0
	face.content_margin_bottom = 6.0
	var hovered: StyleBoxFlat = face.duplicate()
	hovered.bg_color = _look["face"].lightened(0.12)
	var pressed: StyleBoxFlat = face.duplicate()
	pressed.bg_color = _look["face"].darkened(0.08)
	btn.add_theme_stylebox_override("normal", face)
	btn.add_theme_stylebox_override("hover", hovered)
	btn.add_theme_stylebox_override("pressed", pressed)

func _media_thumb(e: Dictionary) -> Texture2D:
	if _media_kind != "bg" and _media_kind != "sprite" and _media_kind != "ui":
		return null
	var p := String(e["path"])
	# keyed by mtime as well as path, so a replaced file loses its stale thumbnail
	# without every checkbox click having to invalidate the whole cache
	var stamp := "%s|%d" % [p, FileAccess.get_modified_time(p)]
	if _thumb_cache.has(stamp):
		return _thumb_cache[stamp]
	var tex: Texture2D = null
	if p.begins_with("res://"):
		tex = load(p)
	else:
		var im := Image.load_from_file(p)
		if im:
			var s := minf(140.0 / im.get_width(), 96.0 / im.get_height())
			im.resize(maxi(1, int(im.get_width() * s)), maxi(1, int(im.get_height() * s)), Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(im)
	_thumb_cache[p] = tex
	return tex

func _media_tile(e: Dictionary) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(156, 146)
	if _media_tile_style != null:
		tile.add_theme_stylebox_override("panel", _media_tile_style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	tile.add_child(v)

	var frame := TextureRect.new()
	frame.custom_minimum_size = Vector2(140, 96)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex := _media_thumb(e)
	if tex:
		frame.texture = tex
		v.add_child(frame)
	else:
		# No preview for audio/font files: show the extension, not a fake icon.
		var tag := Label.new()
		tag.text = String(e["path"]).get_extension().to_upper()
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.custom_minimum_size = Vector2(140, 96)
		tag.add_theme_color_override("font_color", WOOD_INK_DIM)
		v.add_child(tag)

	var check := CheckBox.new()
	check.text = e["name"]
	check.clip_text = true
	check.add_theme_font_size_override("font_size", 12)
	check.button_pressed = not _off_list(_media_kind).has(e["name"])
	check.tooltip_text = String(e["path"])
	check.toggled.connect(_on_media_toggled.bind(e))
	v.add_child(check)
	return tile

func _on_media_toggled(on: bool, e: Dictionary) -> void:
	var off := _off_list(_media_kind)
	if on:
		off.erase(e["name"])
		# only one active item for single-select kinds: a new pick supersedes the rest
		if _media_kind == "font" or _media_kind == "ui":
			for other in _media.get(_media_kind, []):
				if other["name"] != e["name"] and not off.has(other["name"]):
					off.append(other["name"])
		if _media_kind == "ui":
			manager.custom_ui_name = e["name"]
			manager.textbox_style = 0
	elif not off.has(e["name"]):
		off.append(e["name"])
		if _media_kind == "ui" and manager.custom_ui_name == e["name"]:
			manager.custom_ui_name = ""
	_set_off_list(_media_kind, off)
	manager.save_settings()
	# Re-derive the pools from the inventory already in memory. A full
	# _load_default_assets() here would re-decode every sprite and re-scan every
	# folder on each click.
	_rebuild_pools()
	# only these kinds feed something other than the rotation pools
	if _media_kind == "sound":
		_init_sounds()
	if _media_kind == "font" or _media_kind == "ui":
		_apply_theme()
	_update_background(true)
	_update_sprite(true)
	_update_menu_background()
	_populate_media()

## Rebuild the rotation pools from _media minus the unticked names.
func _rebuild_pools() -> void:
	bg_textures.clear()
	sprite_textures.clear()
	sprite_names.clear()
	current_bg_idx = 0
	current_sprite_idx = 0
	for e in _media.get("bg", []):
		if not manager.off_backgrounds.has(e["name"]):
			bg_textures.append(e["path"])
	for e in _media.get("sprite", []):
		if manager.off_sprites.has(e["name"]):
			continue
		var stex: Texture2D = _sprite_texture(e["path"])
		if stex != null:
			sprite_textures.append(stex)
			sprite_names.append(e["name"])

## Sprites are held as decoded textures, so cache them across pool rebuilds: a
## tick should not re-decode eight 500x1280 images.
func _sprite_texture(path: String) -> Texture2D:
	if _sprite_tex_cache.has(path):
		return _sprite_tex_cache[path]
	var tex: Texture2D = load(path) if path.begins_with("res://") else null
	if tex == null:
		var im := Image.load_from_file(path)
		tex = ImageTexture.create_from_image(im) if im else null
	_sprite_tex_cache[path] = tex
	return tex

func _add_path_picker(grid: GridContainer, label_text: String, is_dir: bool, current_path: String, on_picked: Callable) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	grid.add_child(lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(row)

	var value := Label.new()
	value.text = current_path.get_file() if not current_path.is_empty() else "(built-in)"
	value.add_theme_color_override("font_color", WOOD_INK_DIM)
	value.size_flags_horizontal = SIZE_EXPAND_FILL
	value.custom_minimum_size = Vector2(110, 0)
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(value)

	# Each picker needs its own undo: picking a folder replaces the built-ins for
	# that kind, and the global reset button is gone.
	var clear_btn := Button.new()
	clear_btn.text = "Use Built-in"
	clear_btn.disabled = current_path.is_empty()
	clear_btn.pressed.connect(func():
		on_picked.call("")
		value.text = "(built-in)"
		clear_btn.disabled = true
	)

	var btn := Button.new()
	btn.text = "Choose..."
	btn.pressed.connect(func():
		_asset_dialog_setter = func(p: String):
			# the picker is not modal: switching Settings tabs while it is open frees
			# these controls, and writing to a freed node spams script errors
			if not is_instance_valid(value) or not is_instance_valid(clear_btn):
				return
			on_picked.call(p)
			value.text = p.get_file() if not p.is_empty() else "(built-in)"
			clear_btn.disabled = p.is_empty()
		_asset_dialog.title = label_text
		_asset_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR if is_dir else FileDialog.FILE_MODE_OPEN_FILE
		_asset_dialog.popup_centered(Vector2i(850, 550))
	)
	row.add_child(btn)
	row.add_child(clear_btn)

func _build_asset_dialog() -> void:
	_asset_dialog = FileDialog.new()
	_asset_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_asset_dialog.filters = PackedStringArray([
		"*.ttf, *.otf ; Font Files",
		"*.* ; All Files"
	])
	_asset_dialog.dir_selected.connect(func(p: String): _asset_dialog_setter.call(p))
	_asset_dialog.file_selected.connect(func(p: String): _asset_dialog_setter.call(p))
	add_child(_asset_dialog)

func _add_slider_setting(grid: GridContainer, label_text: String, min_val: float, max_val: float, current_val: float, on_change: Callable, step: float = 1.0, fmt_fn: Callable = Callable()) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	grid.add_child(lbl)
	
	var hbox := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	# Range defaults to step 1.0, which turned the 0..1 volume slider into a mute
	# switch and snapped a saved 0.7 to 1 the moment the tab was built
	slider.step = step
	slider.value = current_val
	slider.custom_minimum_size = Vector2(220, 24)
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	hbox.add_child(slider)
	
	var val_lbl := Label.new()
	var format_val = func(v: float) -> String:
		if fmt_fn.is_valid():
			return fmt_fn.call(v)
		return _fmt_setting(step, v)
	val_lbl.text = format_val.call(current_val)
	val_lbl.custom_minimum_size = Vector2(210, 0) if fmt_fn.is_valid() else Vector2(45, 0)
	hbox.add_child(val_lbl)
	
	slider.value_changed.connect(func(v: float):
		val_lbl.text = format_val.call(v)
		on_change.call(v)
	)
	grid.add_child(hbox)

func _fmt_setting(step: float, v: float) -> String:
	return "%.1f" % v if step < 1.0 else "%d" % int(v)

func _add_toggle_setting(grid: GridContainer, label_text: String, initial_val: bool, on_change: Callable) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	grid.add_child(lbl)
	
	var check := CheckBox.new()
	check.button_pressed = initial_val
	check.toggled.connect(on_change)
	grid.add_child(check)

func _build_recent_dialog() -> void:
	recent_overlay = PanelContainer.new()
	recent_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(recent_overlay)

	var panel_style := StyleBoxFlat.new()
	panel_style.content_margin_left = 60.0
	panel_style.content_margin_right = 60.0
	panel_style.content_margin_top = 40.0
	panel_style.content_margin_bottom = 40.0
	recent_overlay.add_theme_stylebox_override("panel", panel_style) # colors set in _apply_theme
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	recent_overlay.add_child(vbox)
	
	var header := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Bookmarks & Recent"
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(lbl)
	
	var btn_back := Button.new()
	btn_back.text = "Back to Menu"
	btn_back.pressed.connect(func(): _show_state(State.MENU))
	header.add_child(btn_back)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var list_container := VBoxContainer.new()
	list_container.name = "RecentList"
	list_container.add_theme_constant_override("separation", 10)
	list_container.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list_container)

func _populate_recent_list() -> void:
	var list := recent_overlay.find_child("RecentList", true, false) as VBoxContainer
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
		
	var items := manager.get_recent_files()
	if items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No saved reading history yet. Open a document to start reading!"
		empty_lbl.add_theme_color_override("font_color", WOOD_INK_DIM)
		list.add_child(empty_lbl)
		return

	for item in items:
		var panel := PanelContainer.new()
		var row_style := StyleBoxFlat.new()
		row_style.set_corner_radius_all(10)
		row_style.bg_color = Color("2e241a")
		row_style.set_border_width_all(1)
		row_style.border_color = Color("5a4632")
		row_style.content_margin_left = 16.0
		row_style.content_margin_right = 16.0
		row_style.content_margin_top = 12.0
		row_style.content_margin_bottom = 12.0
		panel.add_theme_stylebox_override("panel", row_style)
		list.add_child(panel)
		
		var hbox := HBoxContainer.new()
		panel.add_child(hbox)
		
		var vinfo := VBoxContainer.new()
		vinfo.size_flags_horizontal = SIZE_EXPAND_FILL
		hbox.add_child(vinfo)
		
		var title_lbl := Label.new()
		title_lbl.text = item.title
		title_lbl.add_theme_font_size_override("font_size", 17)
		vinfo.add_child(title_lbl)
		
		var pct: int = 0
		if item.total_slides > 0:
			pct = int((float(item.slide_index + 1) / float(item.total_slides)) * 100.0)
		var meta_lbl := Label.new()
		meta_lbl.text = "Slide %d of %d (%d%%)  •  %s" % [item.slide_index + 1, item.total_slides, pct, item.path]
		meta_lbl.add_theme_font_size_override("font_size", 12)
		meta_lbl.add_theme_color_override("font_color", WOOD_INK_DIM)
		vinfo.add_child(meta_lbl)
		
		var missing: bool = not FileAccess.file_exists(item["path"])
		if missing:
			title_lbl.modulate.a = 0.55
			meta_lbl.text += "   (file missing)"

		var btn_read := Button.new()
		btn_read.text = "Resume"
		btn_read.custom_minimum_size = Vector2(90, 36)
		btn_read.pressed.connect(func():
			if FileAccess.file_exists(item["path"]):
				load_document(item["path"], item["slide_index"], item.get("total_slides", -1))
			else:
				OS.alert("File not found:\n" + item["path"] + "\n\nIt may have been moved or deleted. Use Remove to drop this entry.", "File Not Found")
		)
		hbox.add_child(btn_read)
		
		var btn_del := Button.new()
		btn_del.text = "Remove"
		btn_del.pressed.connect(func():
			manager.remove_recent(item.path)
			_populate_recent_list()
		)
		hbox.add_child(btn_del)

func _build_backlog_dialog() -> void:
	backlog_overlay = PanelContainer.new()
	backlog_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(backlog_overlay)

	var panel_style := StyleBoxFlat.new()
	panel_style.content_margin_left = 60.0
	panel_style.content_margin_right = 60.0
	panel_style.content_margin_top = 40.0
	panel_style.content_margin_bottom = 40.0
	backlog_overlay.add_theme_stylebox_override("panel", panel_style) # colors set in _apply_theme
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	backlog_overlay.add_child(vbox)
	
	var header := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Reading History"
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(lbl)
	
	var btn_close := Button.new()
	btn_close.text = "Close"
	btn_close.pressed.connect(func(): _show_state(State.READING))
	header.add_child(btn_close)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var log_label := RichTextLabel.new()
	log_label.name = "LogLabel"
	log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	log_label.size_flags_vertical = SIZE_EXPAND_FILL
	log_label.bbcode_enabled = true
	scroll.add_child(log_label)

func _open_backlog() -> void:
	if slides.is_empty():
		return
	var log_label := backlog_overlay.find_child("LogLabel", true, false) as RichTextLabel
	if log_label:
		var log_text := ""
		var start := maxi(0, current_slide_idx - 30) # Show up to last 30 slides
		for i in range(start, current_slide_idx + 1):
			var is_current := (i == current_slide_idx)
			var accent_col: Color = _look["accent"]
			var accent_hex := "#" + accent_col.to_html(false)
			var ink_hex := "#" + WOOD_INK.to_html(false)
			var dim_hex := "#" + WOOD_INK_DIM.to_html(false)
			var prefix := "[color=%s][b]Slide %d:[/b][/color] " % [accent_hex, i + 1]
			if is_current:
				log_text += prefix + "[color=%s][u]%s[/u][/color]\n\n" % [ink_hex, _bbcode_safe(slides[i])]
			else:
				log_text += prefix + "[color=%s]%s[/color]\n\n" % [dim_hex, _bbcode_safe(slides[i])]
		log_label.text = log_text
	_show_state(State.BACKLOG)

# ==============================================================================
# CHAPTERS (jump list from the parser's TOC / headings / fence detection)
# ==============================================================================

func _build_chapters_dialog() -> void:
	chapters_overlay = PanelContainer.new()
	chapters_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(chapters_overlay)

	var panel_style := StyleBoxFlat.new()
	panel_style.content_margin_left = 60.0
	panel_style.content_margin_right = 60.0
	panel_style.content_margin_top = 40.0
	panel_style.content_margin_bottom = 40.0
	chapters_overlay.add_theme_stylebox_override("panel", panel_style) # colors set in _apply_theme

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	chapters_overlay.add_child(vbox)

	var header := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Chapters"
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(lbl)

	var btn_close := Button.new()
	btn_close.text = "Close"
	btn_close.pressed.connect(func(): _show_state(State.READING))
	header.add_child(btn_close)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list_container := VBoxContainer.new()
	list_container.name = "ChapterList"
	list_container.add_theme_constant_override("separation", 10)
	list_container.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list_container)

func _open_chapters() -> void:
	if slides.is_empty():
		return
	_populate_chapter_list()
	_show_state(State.CHAPTERS)

func _populate_chapter_list() -> void:
	var list := chapters_overlay.find_child("ChapterList", true, false) as VBoxContainer
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

	var entries: Array = []
	if book_start_slide > 0:
		entries.append({"slide": book_start_slide, "title": "Start of Book (skip front matter)"})
	entries.append_array(chapter_list)
	if entries.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No chapters detected in this document."
		empty_lbl.add_theme_color_override("font_color", WOOD_INK_DIM)
		list.add_child(empty_lbl)
		var hint := Label.new()
		hint.text = "EPUB contents, .md/.docx headings, or 'Chapter 1' lines."
		hint.add_theme_color_override("font_color", WOOD_INK_DIM)
		hint.add_theme_font_size_override("font_size", 13)
		list.add_child(hint)
		return

	var current_i := -1
	for i in entries.size():
		if int(entries[i]["slide"]) <= current_slide_idx:
			current_i = i
	for i in entries.size():
		list.add_child(_chapter_button(str(entries[i]["title"]), int(entries[i]["slide"]), i == current_i))

func _chapter_button(title: String, slide_idx: int, is_current: bool) -> Button:
	var btn := Button.new()
	btn.text = title
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.size_flags_horizontal = SIZE_FILL
	if is_current:
		btn.add_theme_color_override("font_color", _look["accent"])
		btn.add_theme_color_override("font_hover_color", _look["accent"])
		btn.add_theme_color_override("font_pressed_color", _look["accent"])
	btn.pressed.connect(func(): _jump_to_slide(slide_idx))
	return btn

func _jump_to_slide(idx: int) -> void:
	if slides.is_empty():
		return
	current_slide_idx = clampi(idx, 0, slides.size() - 1)
	slides_since_bg = 0
	slides_since_sprite = 0
	_release_book_image()
	_show_state(State.READING)
	_display_current_slide()

# ==============================================================================
# STATE & THEMING
# ==============================================================================

func _show_state(target_state: State) -> void:
	var redundant := _state_initialized and target_state == current_state
	var previous := current_state
	current_state = target_state
	_state_initialized = true
	# Leaving the reader is the one moment the exact slide must hit disk; the
	# per-slide write is throttled to every 10.
	if previous == State.READING and target_state != State.READING:
		_write_progress()
	if target_state == State.SETTINGS and previous in [State.MENU, State.READING]:
		# Only real origins count. ESC back from My Media re-enters Settings, and if
		# that overwrote the origin, Save & Close would bounce into My Media forever.
		_settings_return_to = previous
	if target_state == State.READING:
		_sync_book_to_textbox_height()
		# drop keyboard focus so Space/Enter belong to the reader, not to the
		# last-clicked button (it would re-activate on every advance press)
		var focused := get_viewport().gui_get_focus_owner()
		if focused is BaseButton:
			focused.release_focus()
	if target_state == State.MENU and not redundant:
		_update_menu_background()
		_check_asset_folders_changed()
		_populate_book_shelf(true)
	if boot_done and not redundant:
		if target_state in [State.SETTINGS, State.RECENT, State.BACKLOG, State.CHAPTERS, State.MEDIA]:
			_play_sfx(sfx_open, 0.7)
		elif target_state in [State.MENU, State.READING]:
			_play_sfx(sfx_back, 0.5)
	
	menu_overlay.visible = (target_state == State.MENU)
	settings_overlay.visible = (target_state == State.SETTINGS)
	recent_overlay.visible = (target_state == State.RECENT)
	backlog_overlay.visible = (target_state == State.BACKLOG)
	chapters_overlay.visible = (target_state == State.CHAPTERS)
	media_overlay.visible = (target_state == State.MEDIA)
	if target_state == State.MEDIA:
		_populate_media()
	if target_state == State.SETTINGS:
		# rebuild the visible tab: its Menu Background list and picker undo are
		# derived from the media inventory, which My Media may have just changed
		_select_settings_tab(_settings_tab)
	
	var in_reading: bool = (target_state == State.READING)
	top_bar.visible = in_reading
	dialogue_box.visible = in_reading
	sprite_holder.visible = in_reading

func _tex_style(path: String, tex_margin: float, content_margin: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	sb.texture_margin_left = tex_margin
	sb.texture_margin_right = tex_margin
	sb.texture_margin_top = tex_margin
	sb.texture_margin_bottom = tex_margin
	sb.content_margin_left = content_margin
	sb.content_margin_right = content_margin
	sb.content_margin_top = content_margin
	sb.content_margin_bottom = content_margin
	return sb

func _scaled_icon(path: String, height: int) -> Texture2D:
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	img.decompress()
	var w := int(float(img.get_width()) * float(height) / float(img.get_height()))
	img.resize(w, height, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _apply_theme() -> void:
	# Wooden skin — textures from the Cozy UI Pack demo (credits in DESIGN.md).
	var ui_theme := Theme.new()
	ui_theme.set_color("font_color", "Label", WOOD_INK)
	ui_theme.set_color("font_color", "CheckBox", WOOD_INK)
	ui_theme.set_color("font_color", "Button", WOOD_INK)
	ui_theme.set_color("font_hover_color", "Button", WOOD_INK)
	ui_theme.set_color("font_pressed_color", "Button", WOOD_INK)
	ui_theme.set_color("font_focus_color", "Button", WOOD_INK)
	ui_theme.set_color("font_color", "LineEdit", WOOD_BTN_INK)
	ui_theme.set_color("caret_color", "LineEdit", WOOD_BTN_INK)
	# never set before: the placeholder fell to the engine's translucent white on a
	# cream field (1.06:1), so the only hint of what a search box does was unreadable
	ui_theme.set_color("font_placeholder_color", "LineEdit", Color("6b5233"))
	ui_theme.set_color("font_color", "ProgressBar", WOOD_INK)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.set_corner_radius_all(10)
	btn_normal.bg_color = _look["face"]
	btn_normal.set_border_width_all(1)
	btn_normal.border_color = _look["edge"]
	btn_normal.content_margin_left = 16.0
	btn_normal.content_margin_right = 16.0
	btn_normal.content_margin_top = 8.0
	btn_normal.content_margin_bottom = 8.0
	var btn_hover: StyleBoxFlat = btn_normal.duplicate()
	btn_hover.bg_color = _look["face"].lightened(0.06)
	var btn_pressed: StyleBoxFlat = btn_normal.duplicate()
	btn_pressed.bg_color = _look["face"].darkened(0.08)
	ui_theme.set_stylebox("normal", "Button", btn_normal)
	ui_theme.set_stylebox("hover", "Button", btn_hover)
	ui_theme.set_stylebox("pressed", "Button", btn_pressed)

	# Amber ring: DESIGN.md reserves it for focus, but no focus style existed, so
	# keyboard users had nothing to follow. Ring only, the control keeps its own face.
	var focus_ring := StyleBoxFlat.new()
	focus_ring.draw_center = false
	focus_ring.set_border_width_all(2)
	focus_ring.border_color = _look["accent"]
	focus_ring.set_corner_radius_all(11)
	focus_ring.expand_margin_left = 2.0
	focus_ring.expand_margin_right = 2.0
	focus_ring.expand_margin_top = 2.0
	focus_ring.expand_margin_bottom = 2.0
	for focusable in ["Button", "CheckBox", "OptionButton", "HSlider", "LineEdit", "ScrollContainer"]:
		ui_theme.set_stylebox("focus", focusable, focus_ring)

	ui_theme.set_icon("checked", "CheckBox", _scaled_icon("res://assets/ui/checkbox_checked.png", 26))
	ui_theme.set_icon("unchecked", "CheckBox", _scaled_icon("res://assets/ui/checkbox_unchecked.png", 26))

	var le_style := StyleBoxFlat.new()
	le_style.set_corner_radius_all(6)
	le_style.bg_color = Color("f5ead6")
	le_style.set_border_width_all(1)
	le_style.border_color = _look["edge"]
	le_style.content_margin_left = 10.0
	le_style.content_margin_right = 10.0
	le_style.content_margin_top = 6.0
	le_style.content_margin_bottom = 6.0
	ui_theme.set_stylebox("normal", "LineEdit", le_style)

	var slider_bg := StyleBoxFlat.new()
	# lifted from the button face, not a fixed brown: the old #4a3826 was 1.4:1
	# against the panel and the unfilled track vanished
	slider_bg.bg_color = _look["face"].lightened(0.18)
	slider_bg.set_corner_radius_all(4)
	slider_bg.content_margin_top = 4.0
	slider_bg.content_margin_bottom = 4.0
	var slider_fill: StyleBoxFlat = slider_bg.duplicate()
	slider_fill.bg_color = _look["accent"]
	ui_theme.set_stylebox("slider", "HSlider", slider_bg)
	ui_theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	ui_theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	_build_progressbar_styles(ui_theme)

	# Font: Settings picker > My Media picks (first ticked) > bundled Atkinson >
	# engine default. Kaph stays bundled because people who like it can tick it.
	var font_path := manager.custom_font_path
	if font_path.is_empty():
		for e in _media.get("font", []):
			if not manager.off_fonts.has(e["name"]):
				font_path = e["path"]
				break
	# Unticking every font means exactly that: no bundled fallback either
	if font_path.is_empty() and not manager.off_fonts.has("Atkinson Hyperlegible") \
			and ResourceLoader.exists("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"):
		font_path = "res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"
	if not font_path.is_empty():
		# res:// fonts are imported resources: in an exported build the raw .ttf is
		# not on disk, so load() is the only form that works in both editor and exe
		var resolved: Font = null
		if font_path.begins_with("res://"):
			resolved = load(font_path) if ResourceLoader.exists(font_path) else null
		elif FileAccess.file_exists(font_path):
			var dyn := FontFile.new()
			if dyn.load_dynamic_font(font_path) == OK:
				resolved = dyn
		if resolved != null:
			ui_theme.default_font = resolved
			_ui_font = resolved

	self.theme = ui_theme

	# Dialogue box — the reader's own texture (My UI), or the built-in panel with
	# the look's tint. A custom texture is dimmed just enough that cream ink keeps
	# 4.5:1 against its average tone, so a bright or busy file can never make the
	# book text unreadable; the look tint does the same job for the built-in.
	if manager.textbox_style == 2:
		var box_empty := StyleBoxEmpty.new()
		box_empty.content_margin_left = 24.0
		box_empty.content_margin_right = 24.0
		box_empty.content_margin_top = 20.0
		box_empty.content_margin_bottom = 16.0
		dialogue_box.add_theme_stylebox_override("panel", box_empty)
		_active_textbox_stylebox = box_empty
		_ui_tex_dim = 1.0
	elif manager.textbox_style == 1 or manager.textbox_flat_style:
		var box_flat := StyleBoxFlat.new()
		box_flat.set_corner_radius_all(12)
		box_flat.bg_color = Color(_look["flat"], manager.textbox_opacity)
		box_flat.set_border_width_all(1)
		box_flat.border_color = _look["edge"].darkened(0.25)
		box_flat.content_margin_left = 26.0
		box_flat.content_margin_right = 26.0
		box_flat.content_margin_top = 26.0
		box_flat.content_margin_bottom = 22.0
		dialogue_box.add_theme_stylebox_override("panel", box_flat)
		_active_textbox_stylebox = box_flat
		_ui_tex_dim = 1.0
	else:
		var box_tex := _textbox_texture_style()
		dialogue_box.add_theme_stylebox_override("panel", box_tex)
		_active_textbox_stylebox = box_tex

	_apply_surface_styles()

## Resolve + build the active textbox stylebox. Builtin: look tint x opacity.
## Custom: measured dim x opacity. Unreadable custom file: fall back to builtin.
func _textbox_texture_style() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture_margin_left = 30.0
	sb.texture_margin_right = 30.0
	sb.texture_margin_top = 22.0
	sb.texture_margin_bottom = 22.0
	sb.content_margin_left = 28.0
	sb.content_margin_right = 28.0
	sb.content_margin_top = 28.0
	sb.content_margin_bottom = 24.0
	var path := _ui_texture_path()
	if path == BUILTIN_PANEL_TEX:
		sb.texture = load(BUILTIN_PANEL_TEX)
		_ui_tex_dim = 1.0
		sb.modulate_color = Color(_look["tint"], manager.textbox_opacity)
		return sb
	var custom: Variant = _custom_panel_texture(path)
	if custom == null or custom["tex"] == null:
		# unreadable file: the box must never render empty, so use the builtin
		sb.texture = load(BUILTIN_PANEL_TEX)
		_ui_tex_dim = 1.0
		sb.modulate_color = Color(_look["tint"], manager.textbox_opacity)
		return sb
	sb.texture = custom["tex"]
	_ui_tex_dim = float(custom["dim"])
	sb.modulate_color = Color(_ui_tex_dim, _ui_tex_dim, _ui_tex_dim, manager.textbox_opacity)
	return sb

## Selected custom UI texture wins; falls back to the built-in wood panel.
func _ui_texture_path() -> String:
	if not manager.custom_ui_name.is_empty():
		for e in _media.get("ui", []):
			if e["name"] == manager.custom_ui_name and not manager.off_ui.has(e["name"]):
				return String(e["path"])
	return BUILTIN_PANEL_TEX

## Progress bar: textured carved groove + accent fill adapting to App Look,
## or custom track/fill images if found in My UI.
func _build_progressbar_styles(ui_theme: Theme) -> void:
	var custom_track: Texture2D = _find_custom_bar_texture(false)
	var custom_fill: Texture2D = _find_custom_bar_texture(true)
	var pb_bg: StyleBox = null
	var pb_fill: StyleBox = null

	if custom_track != null:
		var sb_track := StyleBoxTexture.new()
		sb_track.texture = custom_track
		sb_track.texture_margin_left = 6.0
		sb_track.texture_margin_right = 6.0
		sb_track.texture_margin_top = 4.0
		sb_track.texture_margin_bottom = 4.0
		pb_bg = sb_track
	else:
		# Built-in: textured recessed groove using panel texture tinted with theme shade
		var sbt_bg := StyleBoxTexture.new()
		sbt_bg.texture = load(BUILTIN_PANEL_TEX)
		sbt_bg.texture_margin_left = 8.0
		sbt_bg.texture_margin_right = 8.0
		sbt_bg.texture_margin_top = 6.0
		sbt_bg.texture_margin_bottom = 6.0
		sbt_bg.modulate_color = _look["shade"].darkened(0.25)
		sbt_bg.content_margin_left = 2.0
		sbt_bg.content_margin_right = 2.0
		sbt_bg.content_margin_top = 2.0
		sbt_bg.content_margin_bottom = 2.0
		pb_bg = sbt_bg

	if custom_fill != null:
		var sb_fill := StyleBoxTexture.new()
		sb_fill.texture = custom_fill
		sb_fill.texture_margin_left = 6.0
		sb_fill.texture_margin_right = 6.0
		sb_fill.texture_margin_top = 4.0
		sb_fill.texture_margin_bottom = 4.0
		pb_fill = sb_fill
	else:
		# Built-in: textured inlaid accent bar using panel texture tinted with theme accent
		var sbt_fill := StyleBoxTexture.new()
		sbt_fill.texture = load(BUILTIN_PANEL_TEX)
		sbt_fill.texture_margin_left = 6.0
		sbt_fill.texture_margin_right = 6.0
		sbt_fill.texture_margin_top = 4.0
		sbt_fill.texture_margin_bottom = 4.0
		sbt_fill.modulate_color = _look["accent"]
		pb_fill = sbt_fill

	ui_theme.set_stylebox("background", "ProgressBar", pb_bg)
	ui_theme.set_stylebox("fill", "ProgressBar", pb_fill)

	if progress_bar != null:
		progress_bar.add_theme_stylebox_override("background", pb_bg)
		progress_bar.add_theme_stylebox_override("fill", pb_fill)
		progress_bar.queue_redraw()

func _find_custom_bar_texture(is_fill: bool) -> Texture2D:
	for e in _media.get("ui", []):
		if e.get("builtin", false):
			continue
		var nm: String = str(e["name"]).to_lower()
		if is_fill:
			if nm.contains("fill") or nm.contains("progress") or nm.contains("bar_fill"):
				if ResourceLoader.exists(String(e["path"])):
					return load(String(e["path"]))
				var im := Image.load_from_file(String(e["path"]))
				if im:
					return ImageTexture.create_from_image(im)
		else:
			if nm.contains("track") or nm.contains("groove") or nm.contains("bar_bg") or nm.contains("empty"):
				if ResourceLoader.exists(String(e["path"])):
					return load(String(e["path"]))
				var im := Image.load_from_file(String(e["path"]))
				if im:
					return ImageTexture.create_from_image(im)
	return null

## Loads a My UI texture and measures the dimming its average tone needs.
## Keyed by mtime so replacing the file invalidates the cached dim.
func _custom_panel_texture(path: String) -> Variant:
	var stamp := "%s|%d" % [path, FileAccess.get_modified_time(path)]
	if _ui_tex_cache.has(stamp):
		return _ui_tex_cache[stamp]
	var im := Image.load_from_file(path)
	if im == null:
		return null
	if im.is_compressed():
		im.decompress()
	var entry := {"tex": ImageTexture.create_from_image(im), "dim": _readability_dim(im)}
	_ui_tex_cache[stamp] = entry
	return entry

## Average tone of the texture's centre region (text never sits on the frame),
## then the dimming that keeps cream ink readable against it.
func _readability_dim(im: Image) -> float:
	var avg := Color(0, 0, 0)
	var n := 0
	var w := im.get_width()
	var h := im.get_height()
	var x0 := mini(30, w / 4)
	var y0 := mini(22, h / 4)
	var step_x := maxi(1, (w - 2 * x0) / 48)
	var step_y := maxi(1, (h - 2 * y0) / 48)
	var y := y0
	while y < h - y0:
		var x := x0
		while x < w - x0:
			avg += im.get_pixel(x, y)
			n += 1
			x += step_x
		y += step_y
	if n == 0:
		return 1.0
	avg /= float(n)
	return _dim_for(avg)

func _apply_textbox_opacity() -> void:
	# Opacity slider fast path only: never rebuild the whole theme for one alpha.
	if _active_textbox_stylebox == null:
		_apply_theme()
		return
	if _active_textbox_stylebox is StyleBoxEmpty:
		return
	if manager.textbox_style == 1 or manager.textbox_flat_style:
		var flat := _active_textbox_stylebox as StyleBoxFlat
		if flat != null:
			flat.bg_color = Color(_look["flat"], manager.textbox_opacity)
	else:
		var tex_sb := _active_textbox_stylebox as StyleBoxTexture
		if tex_sb != null:
			if _ui_texture_path() == BUILTIN_PANEL_TEX:
				tex_sb.modulate_color = Color(_look["tint"], manager.textbox_opacity)
			else:
				tex_sb.modulate_color = Color(_ui_tex_dim, _ui_tex_dim, _ui_tex_dim, manager.textbox_opacity)

## Every wooden surface. Called from _apply_theme: living anywhere else means it
## only runs once the reader moves the opacity slider.
func _apply_surface_styles() -> void:
	# Nameplate & dialogue text styling
	if manager.textbox_style == 2:
		# Frameless / floating mode: transparent nameplate with accent text and dark outline
		var empty_np := StyleBoxEmpty.new()
		empty_np.content_margin_left = 0.0
		empty_np.content_margin_right = 0.0
		empty_np.content_margin_top = 0.0
		empty_np.content_margin_bottom = 2.0
		nameplate_panel.add_theme_stylebox_override("panel", empty_np)
		nameplate_label.add_theme_color_override("font_color", _look["accent"])
		nameplate_label.add_theme_constant_override("outline_size", 4)
		nameplate_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 0.95))

		# High-contrast outline & shadow ensure readable text across bright skies, clouds, or dark scenes
		dialogue_label.add_theme_color_override("default_color", WOOD_INK)
		dialogue_label.add_theme_constant_override("outline_size", 4)
		dialogue_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 0.95))
		dialogue_label.add_theme_constant_override("shadow_offset_x", 2)
		dialogue_label.add_theme_constant_override("shadow_offset_y", 2)
		dialogue_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
		dialogue_label.add_theme_constant_override("shadow_outline_size", 2)
	else:
		# Boxed mode (wood or flat):
		var name_style := StyleBoxFlat.new()
		name_style.set_corner_radius_all(6)
		name_style.bg_color = _look["namebg"]
		name_style.content_margin_left = 12.0
		name_style.content_margin_right = 12.0
		name_style.content_margin_top = 4.0
		name_style.content_margin_bottom = 4.0
		nameplate_panel.add_theme_stylebox_override("panel", name_style)
		nameplate_label.add_theme_color_override("font_color", WOOD_INK)
		nameplate_label.add_theme_constant_override("outline_size", 0)

		dialogue_label.add_theme_color_override("default_color", WOOD_INK)
		dialogue_label.add_theme_constant_override("outline_size", 0)
		dialogue_label.add_theme_constant_override("shadow_offset_x", 0)
		dialogue_label.add_theme_constant_override("shadow_offset_y", 0)

	nameplate_panel.visible = not manager.speaker_name.strip_edges().is_empty()

	# Top bar: flat dark wood strip
	var bar := StyleBoxFlat.new()
	bar.bg_color = _look["topbar"]
	bar.content_margin_left = 16.0
	bar.content_margin_right = 16.0
	bar.content_margin_top = 8.0
	bar.content_margin_bottom = 8.0
	top_bar.add_theme_stylebox_override("panel", bar)

	# Book shelf: wooden plank texture; hover card: dark inset strip.
	# The plank gets the same tint as the dialogue box: the audit intended this,
	# but the modulate was never issued, so the plank rendered raw light peach.
	if shelf_panel != null:
		var plank := _tex_style(BUILTIN_PANEL_TEX, 26.0, 12.0)
		plank.modulate_color = _look["tint"]
		shelf_panel.add_theme_stylebox_override("panel", plank)
	if hover_strip != null:
		var strip_style := StyleBoxFlat.new()
		strip_style.bg_color = _look["shade"]
		strip_style.set_corner_radius_all(8)
		strip_style.set_border_width_all(1)
		strip_style.border_color = _look["edge"]
		strip_style.content_margin_left = 14.0
		strip_style.content_margin_right = 14.0
		strip_style.content_margin_top = 4.0
		strip_style.content_margin_bottom = 4.0
		hover_strip.add_theme_stylebox_override("panel", strip_style)

	# Full-screen overlays: flat wood (the drip-card texture is retired; it smeared when stretched)
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = _look["overlay"]
	overlay_style.set_border_width_all(1)
	overlay_style.border_color = _look["edge"]
	overlay_style.content_margin_left = 60.0
	overlay_style.content_margin_right = 60.0
	overlay_style.content_margin_top = 40.0
	overlay_style.content_margin_bottom = 40.0
	for overlay in [settings_overlay, recent_overlay, backlog_overlay, chapters_overlay, media_overlay]:
		overlay.add_theme_stylebox_override("panel", overlay_style)

	# The one accent action per screen (menu continue / save & close)
	for primary in [menu_primary_btn, settings_save_btn]:
		if primary == null:
			continue
		var p_normal := StyleBoxFlat.new()
		p_normal.set_corner_radius_all(10)
		p_normal.bg_color = _look["primary"]
		p_normal.set_border_width_all(1)
		p_normal.border_color = _look["primary"].darkened(0.3)
		p_normal.content_margin_left = 16.0
		p_normal.content_margin_right = 16.0
		p_normal.content_margin_top = 8.0
		p_normal.content_margin_bottom = 8.0
		var p_hover: StyleBoxFlat = p_normal.duplicate()
		p_hover.bg_color = _look["primary"].lightened(0.08)
		var p_pressed: StyleBoxFlat = p_normal.duplicate()
		p_pressed.bg_color = _look["primary"].darkened(0.12)
		primary.add_theme_stylebox_override("normal", p_normal)
		primary.add_theme_stylebox_override("hover", p_hover)
		primary.add_theme_stylebox_override("pressed", p_pressed)
		primary.add_theme_color_override("font_color", WOOD_INK)
		primary.add_theme_color_override("font_hover_color", WOOD_INK)
		primary.add_theme_color_override("font_pressed_color", WOOD_INK)

	# Unstyled until now: these fell through to Godot's bluish default panel
	_panel_style_dark = StyleBoxFlat.new()
	_panel_style_dark.bg_color = Color(_look["topbar"].r, _look["topbar"].g, _look["topbar"].b, 1.0)
	_panel_style_dark.set_border_width_all(1)
	_panel_style_dark.border_color = _look["edge"]
	_panel_style_dark.set_corner_radius_all(6)
	spot_cover.add_theme_stylebox_override("panel", _panel_style_dark)

	_media_tile_style = StyleBoxFlat.new()
	_media_tile_style.bg_color = _look["shade"]
	_media_tile_style.set_border_width_all(1)
	_media_tile_style.border_color = _look["edge"]
	_media_tile_style.set_corner_radius_all(8)
	_media_tile_style.content_margin_left = 8.0
	_media_tile_style.content_margin_right = 8.0
	_media_tile_style.content_margin_top = 8.0
	_media_tile_style.content_margin_bottom = 8.0

	if update_banner != null:
		var ub_style := StyleBoxFlat.new()
		ub_style.bg_color = _look["shade"]
		ub_style.set_border_width_all(1)
		ub_style.border_color = _look["accent"]
		ub_style.set_corner_radius_all(6)
		ub_style.content_margin_left = 16.0
		ub_style.content_margin_right = 16.0
		ub_style.content_margin_top = 4.0
		ub_style.content_margin_bottom = 4.0
		update_banner.add_theme_stylebox_override("panel", ub_style)
		if update_label != null:
			update_label.add_theme_color_override("font_color", WOOD_INK)
		if update_now_btn != null:
			var btn_style := StyleBoxFlat.new()
			btn_style.set_corner_radius_all(6)
			btn_style.bg_color = _look["primary"]
			btn_style.content_margin_left = 12.0
			btn_style.content_margin_right = 12.0
			btn_style.content_margin_top = 4.0
			btn_style.content_margin_bottom = 4.0
			update_now_btn.add_theme_stylebox_override("normal", btn_style)
			var btn_hover: StyleBoxFlat = btn_style.duplicate()
			btn_hover.bg_color = _look["primary"].lightened(0.08)
			update_now_btn.add_theme_stylebox_override("hover", btn_hover)
			update_now_btn.add_theme_color_override("font_color", WOOD_INK)

func _apply_settings_to_ui() -> void:
	nameplate_label.text = manager.speaker_name
	nameplate_panel.visible = not manager.speaker_name.strip_edges().is_empty()
	_refit_current_slide()

func _on_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty():
		return
	var path := files[0]
	# anything dropped becomes a document, so an unsupported file has to be refused
	# rather than rendered as binary mojibake
	if not TextParser.SUPPORTED_EXTENSIONS.has(path.get_extension().to_lower()):
		OS.alert("That file type is not supported. Supported: %s." % ", ".join(TextParser.SUPPORTED_EXTENSIONS), "Unsupported File")
		return
	load_document(path, 0)

# Updater callbacks

func _on_update_checked(has_update: bool, latest_ver: String, _notes: String, _download_url: String, _html_url: String) -> void:
	if has_update and update_banner != null:
		update_label.text = "VN Reader %s is available!" % latest_ver
		update_banner.visible = true
	if settings_update_status != null:
		if has_update:
			settings_update_status.text = "Update %s is available!" % latest_ver
			settings_update_status.add_theme_color_override("font_color", _look["accent"])
		else:
			var cur_ver: String = updater.CURRENT_VERSION if updater != null else "1.0"
			settings_update_status.text = "You are up to date! (v%s)" % cur_ver
			settings_update_status.add_theme_color_override("font_color", WOOD_INK_DIM)

func _on_update_now_pressed() -> void:
	if updater == null:
		return
	_play_click()
	update_now_btn.visible = false
	update_dismiss_btn.visible = false
	update_progress_bar.visible = true
	update_progress_bar.value = 0
	update_label.text = "Downloading update..."
	updater.start_download_and_apply()

func _on_update_download_progress(downloaded: int, total: int, percent: int) -> void:
	if update_progress_bar != null and update_progress_bar.visible:
		update_progress_bar.value = percent
		var mb_down: float = float(downloaded) / 1048576.0
		var mb_total: float = float(total) / 1048576.0
		if total > 0:
			update_label.text = "Downloading: %.1f / %.1f MB (%d%%)" % [mb_down, mb_total, percent]
		else:
			update_label.text = "Downloading: %.1f MB" % mb_down

func _on_update_download_finished(success: bool, error_msg: String) -> void:
	if not success:
		if update_label != null:
			update_label.text = "Update: " + error_msg
			update_label.add_theme_color_override("font_color", _look["accent"])
		if update_progress_bar != null:
			update_progress_bar.visible = false
		if update_now_btn != null:
			update_now_btn.text = "Retry"
			update_now_btn.visible = true
		if update_dismiss_btn != null:
			update_dismiss_btn.visible = true
