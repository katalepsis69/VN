class_name ReaderManager
extends RefCounted

## Manages persistence, saves, bookmarks, user settings, and external asset loading.
## Saves are crash-safe: write to a temp file, keep the previous version in a
## .bak, and recover from the .bak when the main file is ever half-written.

var config_path := "user://reader_config.cfg" # tests point this at a scratch file
const BACKUP_SUFFIX := ".bak"
const SHELF_CAP := 200 # shelf rows kept; progress for older books survives on disk

var typewriter_speed: float = 45.0
var font_size: int = 24
var sentences_per_slide: int = 2
var auto_delay: float = 3.0

var bg_change_freq: int = 4
var bg_change_random: bool = true
var sprite_change_freq: int = 2
var sprite_change_random: bool = true

var character_bounce: bool = true
var sound_enabled: bool = true
var sound_volume: float = 0.7
var speaker_name: String = "Ginger"
var reactive_expressions: bool = true
var sprite_position: int = 1 # 0 left, 1 center, 2 right
var sprite_portrait: bool = false
var textbox_opacity: float = 1.0
var textbox_height: int = 260
var textbox_flat_style: bool = false
var ui_look: String = "Cozy Wood" # whole-app preset name (LOOKS in main.gd)
var bg_fit_mode: int = 0 # 0 auto, 1 always fill, 2 always fit with border

var custom_sprites_dir: String = ""
var custom_bgs_dir: String = ""
var custom_font_path: String = ""

## Menu background: "" = random rotation, otherwise a background name to pin.
var menu_bg: String = ""
## My Media: names the reader unticked. Everything is on unless listed here.
var off_backgrounds: PackedStringArray = PackedStringArray()
var off_sprites: PackedStringArray = PackedStringArray()
var off_sounds: PackedStringArray = PackedStringArray()
var off_fonts: PackedStringArray = PackedStringArray()
var off_ui: PackedStringArray = PackedStringArray()

## Parse error text when the config had to be recovered from backup ("" = none).
## The UI shows this once so the reader knows a crash ate one save at most.
var recovery_note: String = ""

func _normalize_path(path: String) -> String:
	# Windows file dialogs may return C:\... or C:/... — same book, one shelf entry
	return path.replace("\\", "/")

## Loads the config. Two distinct failures, two distinct repairs:
##  - the file will not parse at all  -> it was cut mid-write; restore the .bak
##  - it parses but lists a book with no doc_ section -> drop that one entry
## The second case must NOT reach for the .bak: the backup is an older file that
## carries the same orphan, so replacing main with it reverts every other book's
## progress and re-triggers on the next load, forever.
func _load_config() -> ConfigFile:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(config_path):
		return cfg # first run (or a fresh test scratch): nothing to load
	if cfg.load(config_path) == OK:
		_prune_orphan_entries(cfg)
		return cfg
	if FileAccess.file_exists(config_path + BACKUP_SUFFIX):
		var bak := ConfigFile.new()
		if bak.load(config_path + BACKUP_SUFFIX) == OK and bak.has_section("recent"):
			# main file is corrupt; keep the backup's content and rewrite main from it
			bak.save(config_path)
			recovery_note = "A partially saved settings file was found and repaired from its backup.\nThe last slide you were on may be one step behind."
			return bak
	push_error("Settings file unreadable: " + config_path)
	return cfg # corrupt with no backup: start empty rather than crash

## A file_list row without a matching doc_ section is unreadable progress: either
## a legacy clipboard:// entry (never resumable) or a save cut before the section
## was written. Dropping the row is the whole repair.
func _prune_orphan_entries(cfg: ConfigFile) -> void:
	var fl: PackedStringArray = cfg.get_value("recent", "file_list", PackedStringArray())
	var kept: PackedStringArray = []
	for p in fl:
		if cfg.has_section("doc_" + String(p).md5_text()):
			kept.append(p)
	if kept.size() != fl.size():
		cfg.set_value("recent", "file_list", kept)

## Garbage collection: a doc_ section nobody lists and whose file is gone can
## never be read again, so it and its generated cover are deleted. Sections for
## files still on disk are kept even when off the shelf, so re-opening a book
## restores where the reader stopped.
func _sweep_dead_sections(cfg: ConfigFile, listed: PackedStringArray) -> void:
	for sec in cfg.get_sections():
		var s := String(sec)
		if not s.begins_with("doc_"):
			continue
		var p := String(cfg.get_value(s, "path", ""))
		if p == "" or listed.has(p):
			continue
		if FileAccess.file_exists(p):
			continue
		_erase_doc_section(cfg, p)

## Atomic save: write a temp copy first, rotate the current file into .bak, then
## put the new file in place. A crash can strand a temp file, never a half-written
## main file.
func _save_config(cfg: ConfigFile) -> void:
	var base := config_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base):
		DirAccess.make_dir_recursive_absolute(base)
	var dir := DirAccess.open(base)
	if dir == null:
		push_error("Cannot save settings: user folder missing")
		return
	var tmp := config_path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		push_error("Settings save failed (disk full or read-only?): error %d" % err)
		return
	if FileAccess.file_exists(config_path):
		# Stage the rotation under its own temp name. Deleting .bak first would leave
		# no backup at all if the copy were interrupted, so the next truncation would
		# have nothing to recover from.
		var bak := config_path + BACKUP_SUFFIX
		var stage := bak + ".staging"
		if FileAccess.file_exists(stage):
			dir.remove(stage)
		var copy_err := dir.copy(config_path, stage)
		if copy_err != OK:
			push_error("Settings backup copy failed: error %d" % copy_err)
		else:
			var rot_err := dir.rename(stage, bak)
			if rot_err != OK:
				push_error("Settings backup rotate failed: error %d" % rot_err)
	var rename_err := dir.rename(tmp, config_path)
	if rename_err != OK:
		push_error("Settings save failed at final step: error %d" % rename_err)

func load_settings() -> void:
	var cfg := _load_config()

	typewriter_speed = cfg.get_value("settings", "typewriter_speed", typewriter_speed)
	font_size = cfg.get_value("settings", "font_size", font_size)
	sentences_per_slide = cfg.get_value("settings", "sentences_per_slide", sentences_per_slide)
	auto_delay = cfg.get_value("settings", "auto_delay", auto_delay)

	bg_change_freq = cfg.get_value("settings", "bg_change_freq", bg_change_freq)
	bg_change_random = cfg.get_value("settings", "bg_change_random", bg_change_random)
	sprite_change_freq = cfg.get_value("settings", "sprite_change_freq", sprite_change_freq)
	sprite_change_random = cfg.get_value("settings", "sprite_change_random", sprite_change_random)

	character_bounce = cfg.get_value("settings", "character_bounce", character_bounce)
	sound_enabled = cfg.get_value("settings", "sound_enabled", sound_enabled)
	sound_volume = cfg.get_value("settings", "sound_volume", sound_volume)
	speaker_name = cfg.get_value("settings", "speaker_name", speaker_name)
	if speaker_name == "Study Buddy":
		speaker_name = "Ginger" # pre-Ginger default name; migrate once
	reactive_expressions = cfg.get_value("settings", "reactive_expressions", reactive_expressions)
	sprite_position = cfg.get_value("settings", "sprite_position", sprite_position)
	sprite_portrait = cfg.get_value("settings", "sprite_portrait", sprite_portrait)
	textbox_opacity = cfg.get_value("settings", "textbox_opacity", textbox_opacity)
	textbox_height = cfg.get_value("settings", "textbox_height", textbox_height)
	textbox_flat_style = cfg.get_value("settings", "textbox_flat_style", textbox_flat_style)
	ui_look = cfg.get_value("settings", "ui_look", ui_look)
	bg_fit_mode = cfg.get_value("settings", "bg_fit_mode", bg_fit_mode)

	custom_sprites_dir = cfg.get_value("settings", "custom_sprites_dir", custom_sprites_dir)
	custom_bgs_dir = cfg.get_value("settings", "custom_bgs_dir", custom_bgs_dir)
	custom_font_path = cfg.get_value("settings", "custom_font_path", custom_font_path)

	menu_bg = cfg.get_value("settings", "menu_bg", menu_bg)
	off_backgrounds = PackedStringArray(cfg.get_value("settings", "off_backgrounds", []))
	off_sprites = PackedStringArray(cfg.get_value("settings", "off_sprites", []))
	off_sounds = PackedStringArray(cfg.get_value("settings", "off_sounds", []))
	off_fonts = PackedStringArray(cfg.get_value("settings", "off_fonts", []))
	off_ui = PackedStringArray(cfg.get_value("settings", "off_ui", []))

func save_settings() -> void:
	var cfg := _load_config()

	cfg.set_value("settings", "typewriter_speed", typewriter_speed)
	cfg.set_value("settings", "font_size", font_size)
	cfg.set_value("settings", "sentences_per_slide", sentences_per_slide)
	cfg.set_value("settings", "auto_delay", auto_delay)

	cfg.set_value("settings", "bg_change_freq", bg_change_freq)
	cfg.set_value("settings", "bg_change_random", bg_change_random)
	cfg.set_value("settings", "sprite_change_freq", sprite_change_freq)
	cfg.set_value("settings", "sprite_change_random", sprite_change_random)

	cfg.set_value("settings", "character_bounce", character_bounce)
	cfg.set_value("settings", "sound_enabled", sound_enabled)
	cfg.set_value("settings", "sound_volume", sound_volume)
	cfg.set_value("settings", "speaker_name", speaker_name)
	cfg.set_value("settings", "reactive_expressions", reactive_expressions)
	cfg.set_value("settings", "sprite_position", sprite_position)
	cfg.set_value("settings", "sprite_portrait", sprite_portrait)
	cfg.set_value("settings", "textbox_opacity", textbox_opacity)
	cfg.set_value("settings", "textbox_height", textbox_height)
	cfg.set_value("settings", "textbox_flat_style", textbox_flat_style)
	cfg.set_value("settings", "ui_look", ui_look)
	cfg.set_value("settings", "bg_fit_mode", bg_fit_mode)

	cfg.set_value("settings", "custom_sprites_dir", custom_sprites_dir)
	cfg.set_value("settings", "custom_bgs_dir", custom_bgs_dir)
	cfg.set_value("settings", "custom_font_path", custom_font_path)

	cfg.set_value("settings", "menu_bg", menu_bg)
	cfg.set_value("settings", "off_backgrounds", Array(off_backgrounds))
	cfg.set_value("settings", "off_sprites", Array(off_sprites))
	cfg.set_value("settings", "off_sounds", Array(off_sounds))
	cfg.set_value("settings", "off_fonts", Array(off_fonts))
	cfg.set_value("settings", "off_ui", Array(off_ui))

	_save_config(cfg)

func save_progress(file_path: String, title: String, slide_index: int, total_slides: int, book_start: int = -1) -> void:
	file_path = _normalize_path(file_path)
	var cfg := _load_config()

	var rec_list: PackedStringArray = cfg.get_value("recent", "file_list", PackedStringArray())
	if not rec_list.has(file_path):
		rec_list.insert(0, file_path)
	else:
		# Move to front
		var idx := rec_list.find(file_path)
		rec_list.remove_at(idx)
		rec_list.insert(0, file_path)

	# The shelf list is capped, but a book pushed off it keeps its progress: with
	# My Books the file is still there, and re-opening should not start over.
	# Growth is bounded instead by sweeping sections whose file no longer exists.
	while rec_list.size() > SHELF_CAP:
		rec_list.remove_at(rec_list.size() - 1)
	cfg.set_value("recent", "file_list", rec_list)
	_sweep_dead_sections(cfg, rec_list)

	var sec := "doc_" + file_path.md5_text()
	cfg.set_value(sec, "path", file_path)
	cfg.set_value(sec, "title", title)
	cfg.set_value(sec, "slide_index", slide_index)
	cfg.set_value(sec, "total_slides", total_slides)
	cfg.set_value(sec, "timestamp", Time.get_unix_time_from_system())
	if book_start >= 0:
		# remembered so "Read Again" on a finished book skips licence front matter
		# even after a restart, when the parse has not run yet
		cfg.set_value(sec, "book_start", book_start)

	_save_config(cfg)

func get_recent_files() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cfg := _load_config()

	var rec_list: PackedStringArray = cfg.get_value("recent", "file_list", PackedStringArray())
	for path in rec_list:
		if path.begins_with("clipboard://"):
			continue # old configs may carry unresumable clipboard entries
		var sec := "doc_" + path.md5_text()
		if cfg.has_section(sec):
			result.append({
				"path": path,
				"title": cfg.get_value(sec, "title", path.get_file()),
				"slide_index": cfg.get_value(sec, "slide_index", 0),
				"total_slides": cfg.get_value(sec, "total_slides", 0),
				"timestamp": cfg.get_value(sec, "timestamp", 0),
				"preview": cfg.get_value(sec, "preview", ""),
				"cover": cfg.get_value(sec, "cover", ""),
				"book_start": cfg.get_value(sec, "book_start", -1),
			})
	return result

func save_book_meta(file_path: String, preview: String, cover_path: String) -> void:
	# Written once per document open (not per slide): first-line preview + optional
	# cover thumbnail for the menu shelf. Same doc_ section as save_progress.
	file_path = _normalize_path(file_path)
	var cfg := _load_config()
	var sec := "doc_" + file_path.md5_text()
	if preview != "":
		cfg.set_value(sec, "preview", preview)
	if cover_path != "":
		cfg.set_value(sec, "cover", cover_path)
	_save_config(cfg)

func remove_recent(file_path: String) -> void:
	file_path = _normalize_path(file_path)
	var cfg := _load_config()
	var rec_list: PackedStringArray = cfg.get_value("recent", "file_list", PackedStringArray())
	if rec_list.has(file_path):
		var idx := rec_list.find(file_path)
		rec_list.remove_at(idx)
		cfg.set_value("recent", "file_list", rec_list)
	_erase_doc_section(cfg, file_path)
	_save_config(cfg)

## Removes one book's config section and, if no other shelf entry uses it, the
## cover thumbnail PNG saved next to the config.
func _erase_doc_section(cfg: ConfigFile, file_path: String) -> void:
	var sec := "doc_" + file_path.md5_text()
	# Derived rather than read back out of the config: a stored string must never
	# decide which file gets deleted. _save_cover_png uses exactly this name.
	var cover := "user://covers/%s.png" % file_path.md5_text()
	var had_cover := str(cfg.get_value(sec, "cover", "")) != ""
	cfg.erase_section(sec)
	if had_cover and not _cover_used_by_other(cfg, file_path, cover):
		DirAccess.remove_absolute(cover)

func _cover_used_by_other(cfg: ConfigFile, exclude_path: String, cover: String) -> bool:
	for path in cfg.get_value("recent", "file_list", PackedStringArray()):
		if path != exclude_path and str(cfg.get_value("doc_" + String(path).md5_text(), "cover", "")) == cover:
			return true
	return false
