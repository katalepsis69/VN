extends SceneTree

## Headless verification for the ADHD VN Reader.
## Run: godot --headless --path . --script res://scripts/test_verification.gd
## Writes only to user://test_config/ so it never touches the real shelf.

const TEST_CFG := "user://test_config/reader_config.cfg"

func _init() -> void:
	print("--- Running ADHD VN Reader Headless Verification ---")

	# 1. Test Text Parser
	var sample_path := "res://assets/sample_paper.txt"
	var slides := TextParser.parse_file(sample_path, 2)
	assert(slides.size() > 0, "Parser failed to parse sample paper!")
	print("Parsed %d slides from %s" % [slides.size(), sample_path])
	for i in range(mini(3, slides.size())):
		print("  Slide %d: %s" % [i + 1, slides[i]])

	# 1b. Test PDF parsing via pdfium-gde (routed through PDFReader)
	var pdf_slides := TextParser.parse_file("res://assets/sample_paper.pdf", 2)
	if pdf_slides.is_empty():
		print("PDF PARSING FAILED")
		quit(1)
		return
	print("PDF parsed: %d slides, first: %s" % [pdf_slides.size(), pdf_slides[0]])

	# 1c. Test EPUB parsing (entities decoded, tags stripped, spine order, images mapped)
	var epub_res := TextParser.parse_file_with_images("res://assets/sample_story.epub", 2)
	var epub_slides: Array[String] = epub_res["slides"]
	var epub_imgs: Dictionary = epub_res["images"]
	if epub_slides.is_empty() or epub_imgs.is_empty():
		print("EPUB PARSING FAILED (slides=%d images=%d)" % [epub_slides.size(), epub_imgs.size()])
		quit(1)
		return
	var joined := "\n".join(epub_slides)
	# the literal & sequence (an UNdecoded entity) must never survive decoding;
	# a plain & inside "Smith & Sons" is correct text
	if joined.contains("<em>") or joined.contains("tracking") or joined.contains("\uE000") or RegEx.create_from_string("&[a-zA-Z#]").search(joined):
		print("EPUB content not cleaned: ", epub_slides)
		quit(1)
		return
	var first_img_refs: Array = epub_imgs[epub_imgs.keys()[0]]
	var img_bytes: PackedByteArray = first_img_refs[0]
	if img_bytes.size() < 8 or img_bytes[0] != 0x89 or img_bytes[1] != 0x50:
		print("EPUB image bytes are not a PNG")
		quit(1)
		return
	print("EPUB parsed: %d slides, %d image slide(s), first: %s" % [epub_slides.size(), epub_imgs.size(), epub_slides[0]])

	# 1d. Chapters: epub real TOC, txt/md headings, docx Heading styles, Gutenberg fence
	var epub_chapters: Array = epub_res["chapters"]
	if epub_chapters.size() != 2 or int(epub_chapters[0]["slide"]) != 0 \
			or str(epub_chapters[0]["title"]) != "Chapter One" or str(epub_chapters[1]["title"]) != "Chapter Two":
		print("CHAPTERS FAIL: epub TOC chapters = ", epub_chapters)
		quit(1)
		return
	if int(epub_res["book_start"]) != -1:
		print("CHAPTERS FAIL: sample epub should have no Gutenberg fence")
		quit(1)
		return
	print("EPUB chapters: ", epub_chapters)
	var txt_res := TextParser.parse_file_with_images("res://assets/sample_paper.txt", 2)
	var txt_chapters: Array = txt_res["chapters"]
	if txt_chapters.size() != 1 or str(txt_chapters[0]["title"]).is_empty():
		print("CHAPTERS FAIL: txt md-heading chapters = ", txt_chapters)
		quit(1)
		return
	print("TXT chapters: ", txt_chapters)
	var docx_res := TextParser.parse_file_with_images("res://assets/sample_essay.docx", 2)
	var docx_chapters: Array = docx_res["chapters"]
	var docx_titles: PackedStringArray = []
	for ch in docx_chapters:
		docx_titles.append(str(ch["title"]))
	if docx_res["slides"].is_empty() or docx_chapters.size() != 3 \
			or " ".join(docx_titles) != "Introduction Methods Results":
		print("CHAPTERS FAIL: docx heading chapters = ", docx_chapters)
		quit(1)
		return
	print("DOCX chapters: ", docx_chapters)
	var fence_chapters: Array = []
	var fence_slides := TextParser.parse_string("License boilerplate text.\n\n*** START OF THE PROJECT GUTENBERG EBOOK DEMO ***\n\nChapter 1\n\nIt began on a quiet morning.", 2, fence_chapters)
	var start: int = TextParser.find_book_start(fence_slides)
	if fence_chapters.size() != 1 or start != 2 or int(fence_chapters[0]["slide"]) != 2:
		print("CHAPTERS FAIL: fence/heuristic chapters=", fence_chapters, " book_start=", start)
		quit(1)
		return
	print("Fence + heuristic OK: book_start=%d, chapters=%s" % [start, fence_chapters])

	# 1e. Hostile inputs: truncated zip, hostile entities — must return empty, not crash
	DirAccess.make_dir_recursive_absolute("user://test_config")
	var real_bytes := FileAccess.open("res://assets/sample_story.epub", FileAccess.READ).get_buffer(28)
	var tf := FileAccess.open("user://test_config/truncated.epub", FileAccess.WRITE)
	assert(tf != null, "could not write truncated epub fixture")
	if tf:
		tf.store_buffer(real_bytes)
		tf.close()
	var broken := TextParser.parse_file("user://test_config/truncated.epub", 2)
	assert(broken.is_empty(), "truncated epub should parse to no slides, got %d" % broken.size())
	print("Truncated epub handled cleanly (0 slides, no crash)")
	var hostile := TextParser._decode_entities("ok&#xD800;ok&#x110000;ok&#48;ok")
	assert(hostile.contains("ok") and not hostile.contains("\uFFFD\uFFFD\uFFFD"), "entity guard: " + hostile)
	print("Hostile entities handled cleanly: ", hostile.replace("\uFFFD", "[U+FFFD]"))

	# 1f. Sentence boundaries: dash-butted topic lists, initials, whole sentences
	# (regression: pg79737 "Myself and Others" chapter topic lists became 850-char walls)
	var topic_list := "I!\u2014Henry Irving and my mother.\u2014My father, Charles Millward.\u2014Liverpool associations." \
		+ "\u2014The \u201cPorcupine.\u201d\u2014Greeks in Liverpool.\u2014E. A. Sothern.\u2014Justin McCarthy.\u2014M. J. Whitty.\u2014The Walker Art Gallery."
	var topics := TextParser.parse_string(topic_list, 1)
	if topics.size() != 10 or topics.any(func(s): return s.length() > 60 or s.begins_with("\u2014")):
		print("SPLIT FAIL: topic list = ", topics)
		quit(1)
		return
	if not topics.has("E. A. Sothern.") or not topics.has("M. J. Whitty."):
		print("SPLIT FAIL: initials fragmented = ", topics)
		quit(1)
		return
	print("Topic list split into %d slides: %s" % [topics.size(), " | ".join(topics)])

	# A slide must never end on a dangling word. The first attempt at a length cap
	# cut at the last space and emitted "...for two weeks, and" — that is the bug.
	# Now an over-long sentence may only split at ";" or ":", else it stays whole.
	var long_sentence := "No, I brought up bile and what little I'd managed to keep down over the last couple of days, " \
		+ "then dry heaved through the aftershocks, shaking and coated in cold sweat; the nightmares " \
		+ "had lashed at me for two weeks, and by morning I was alone again."
	var halves := TextParser.parse_string(long_sentence, 2)
	if halves.size() != 2 or not halves[0].ends_with(";") or not halves[1].ends_with("again."):
		print("CLAUSE SPLIT FAIL: ", halves)
		quit(1)
		return
	print("Over-long sentence split at its semicolon: %d + %d chars" % [halves[0].length(), halves[1].length()])

	var no_boundary := "and ".repeat(70) + "end."
	var kept := TextParser.parse_string(no_boundary, 1)
	if kept.size() != 1 or not kept[0].ends_with("end."):
		print("WHOLE SENTENCE FAIL: %d slides" % kept.size())
		quit(1)
		return
	print("Sentence with no clause boundary kept whole (%d chars, 1 slide)" % no_boundary.length())

	# every slide from ordinary prose must end on sentence or clause punctuation
	var run_on := ""
	for k in 6:
		run_on += "Point %d runs on through commas, clauses and semicolons; there is plenty of text here to trip any cap, and it keeps going. " % k
	var ok_ends := [".", "!", "?", "…", ";", ":"]
	var ends_ok := true
	for s in TextParser.parse_string(run_on, 2):
		var last := s.right(1)
		var before := s.right(2).left(1)
		if not (last in ok_ends or (last in ["\"", "”", ")", "]"] and before in ok_ends)):
			ends_ok = false
			print("DANGLING SLIDE: ", s.right(40))
	if not ends_ok:
		quit(1)
		return
	print("No slide ends mid-clause across 6 long prose sentences")

	# grouping must respect the cap too: two 200-char sentences must not merge into 400
	var pairs := ("one " + "a".repeat(200) + ". ") + ("two " + "b".repeat(200) + ". ") + ("three " + "c".repeat(200) + ".")
	var grouped := TextParser.parse_string(pairs, 2)
	var group_max := 0
	for s in grouped:
		group_max = maxi(group_max, s.length())
	if grouped.size() != 3 or group_max > TextParser.MAX_SLIDE_CHARS:
		print("GROUP FAIL: %d slides, longest=%d" % [grouped.size(), group_max])
		quit(1)
		return
	print("Slide grouping caps at %d chars (3 separate slides)" % group_max)

	var prose := TextParser.parse_string("She went home. He stayed behind.", 1)
	var spaced := TextParser.parse_string("He left \u2014 quietly \u2014 and nobody spoke.", 1)
	if prose.size() != 2 or spaced.size() != 1:
		print("PROSE FAIL: prose=", prose, " spaced=", spaced)
		quit(1)
		return
	print("Ordinary prose unaffected (2 sentences -> 2 slides; spaced dash stays whole)")

	# Quotations: a split must never land inside an open quote. The tag after a
	# closed quote belongs to its quotation; speech-internal periods stay put.
	var tag_slide := TextParser.parse_string("\"Stop! Don't move!\" he shouted.", 1)
	if tag_slide.size() != 1 or not tag_slide[0].begins_with("\"") or not tag_slide[0].ends_with("shouted."):
		print("QUOTE TAG FAIL: ", tag_slide)
		quit(1)
		return
	print("Dialogue tag stays with its quote: ", tag_slide[0])
	var upper_next := TextParser.parse_string("\"Fine.\" She left the room and never came back.", 1)
	if upper_next.size() != 2 or not upper_next[0].ends_with("\"") or not upper_next[1].begins_with("She"):
		print("QUOTE NEXT FAIL: ", upper_next)
		quit(1)
		return
	print("Uppercase sentence after a quote still splits (2 slides)")
	var speech := TextParser.parse_string("\"Have to go outside. You can do it again. You can do it.\"", 1)
	if speech.size() != 1 or speech[0].count("\"") != 2:
		print("SPEECH FAIL: ", speech)
		quit(1)
		return
	print("In-quote periods do not split: %s" % speech[0])
	var dialog := "\"You have to go outside,\" she said. \"You can do it. You can do it.\" Her voice was patient. \"One more try.\""
	var dialog_slides := TextParser.parse_string(dialog, 1)
	# 4 slides: quote+tag, the two-sentence speech, the narration sentence, the last speech
	var quotes_ok := dialog_slides.size() == 4
	for s in dialog_slides:
		if s.count("\"") % 2 != 0:
			quotes_ok = false
			print("UNBALANCED SLIDE: ", s)
	if not quotes_ok:
		print("DIALOG FAIL: ", dialog_slides)
		quit(1)
		return
	print("Quote-rich paragraph: %d slides, every one balanced" % dialog_slides.size())
	var never_closes := "\"You can do it. " + "Keep breathing steady. ".repeat(40)
	var escaped := TextParser.parse_string(never_closes, 1)
	var escape_max := 0
	for s in escaped:
		escape_max = maxi(escape_max, s.length())
	if escaped.size() < 2 or escape_max > 700:
		print("QUOTE ESCAPE FAIL: %d slides, longest=%d" % [escaped.size(), escape_max])
		quit(1)
		return
	print("Stray unclosed quote still splits at the length guard (%d slides, longest %d)" % [escaped.size(), escape_max])

	# 2. Test Sound Generator
	var blip := SoundGenerator.create_typewriter_blip(650.0)
	assert(blip != null and blip.data.size() > 0, "Sound generator failed to generate blip!")
	var click := SoundGenerator.create_advance_click()
	assert(click != null and click.data.size() > 0, "Sound generator failed to generate click!")
	print("Procedural audio generated successfully!")

	# 3. Test Reader Manager (scratch config: the real shelf is never touched)
	var manager := ReaderManager.new()
	manager.config_path = TEST_CFG
	DirAccess.open("user://").remove("test_config/reader_config.cfg.bak") if FileAccess.file_exists(TEST_CFG + ".bak") else null
	manager.load_settings()
	manager.save_progress("res://assets/sample_paper.txt", "Sample Paper", 2, slides.size())
	var rec := manager.get_recent_files()
	assert(rec.size() > 0, "Reader manager failed to save/load progress!")
	print("Recent saves verified: %s, slide %d of %d" % [rec[0].title, rec[0].slide_index, rec[0].total_slides])

	# 3b. Book shelf meta: preview + cover path must survive the roundtrip
	manager.save_progress("test://shelf_book.txt", "Shelf Test", 1, 10)
	manager.save_book_meta("test://shelf_book.txt", "Once upon a time...", "user://covers/x.png")
	var meta_found := false
	for r in manager.get_recent_files():
		if r.path == "test://shelf_book.txt" \
				and r.preview == "Once upon a time..." and r.cover == "user://covers/x.png":
			meta_found = true
	manager.remove_recent("test://shelf_book.txt")
	assert(meta_found, "Book shelf meta (preview/cover) failed to roundtrip!")
	print("Book shelf meta verified")

	# 3c. Crash-safe saves: a half-written config must recover from its .bak
	manager.save_progress("test://crash_book.txt", "Crash Test", 3, 9)
	manager.save_progress("test://crash_book.txt", "Crash Test", 4, 9) # 2nd save: 1st is now the .bak
	var raw := FileAccess.open(TEST_CFG, FileAccess.READ).get_as_text()
	var wf := FileAccess.open(TEST_CFG, FileAccess.WRITE)
	# End the file with an unterminated quoted value: a guaranteed parse error.
	# Where a plain half-length cut lands is content luck, and ConfigFile tolerates
	# dangling keys, tags and bare words at EOF, so those cuts sometimes parse fine
	# and silently test the prune path instead of the backup path.
	wf.store_string(raw.substr(0, raw.length() / 2) + "\nx=\"never_closed")
	wf.close()
	var healed := ReaderManager.new()
	healed.config_path = TEST_CFG
	healed.load_settings()
	var healed_rec := healed.get_recent_files()
	var crash_ok := false
	for r in healed_rec:
		if r.path == "test://crash_book.txt" and r.slide_index in [3, 4]:
			crash_ok = true
	assert(crash_ok and healed.recovery_note != "", "corrupt config did not recover from backup!")
	print("Crash recovery verified: ", healed.recovery_note.split("\n")[0])

	# 3d. Backslash normalization: C:\... and C:/... are one book, one section
	manager.save_progress("X:/books/tale.txt", "Tale", 1, 9)
	manager.save_book_meta("X:\\books\\tale.txt", "", "user://covers/tale.png")
	var norm_ok := false
	for r in manager.get_recent_files():
		if r.path == "X:/books/tale.txt" and r.cover == "user://covers/tale.png":
			norm_ok = true
	manager.remove_recent("X:/books/tale.txt")
	assert(norm_ok, "backslash path wrote meta to a different section than progress!")
	print("Backslash normalization verified")

	# Abbreviation suffixes must not match inside ordinary words: "al." used to
	# stop "general.", "ideal." and "festival." from ever ending a sentence.
	var word_boundary := TextParser.parse_string("The general. She left the room.", 1)
	var word_boundary2 := TextParser.parse_string("It was ideal. Nobody argued.", 1)
	var real_abbrev := TextParser.parse_string("Mr. Darcy arrived. He bowed.", 1)
	if word_boundary.size() != 2 or word_boundary2.size() != 2 or real_abbrev.size() != 2:
		print("ABBREV FAIL: ", word_boundary, " ", word_boundary2, " ", real_abbrev)
		quit(1)
		return
	print("Abbreviation word boundary OK (general./ideal. split, Mr. does not)")

	# a clause boundary only past the limit must still be found
	var late_clause := "x ".repeat(130) + "; tail of the sentence here."
	var late := TextParser.parse_string(late_clause, 1)
	if late.size() != 2 or not late[0].ends_with(";"):
		print("LATE CLAUSE FAIL: %d slides" % late.size())
		quit(1)
		return
	print("Clause past the limit still cut (%d slides, first ends ';')" % late.size())

	# hostile markup must not forge chapters or hide text. The guard sits at the
	# reader boundary, so this has to go through parse_file, not parse_string.
	DirAccess.make_dir_recursive_absolute("user://test_config")
	var inj := FileAccess.open("user://test_config/injected.txt", FileAccess.WRITE)
	assert(inj != null, "could not write injection fixture")
	if inj:
		inj.store_string("Plain sentence.\n\n\uE000CH:Fake Chapter\uE001\n\nAnother one.\n")
		inj.close()
	var injected := TextParser.parse_file_with_images("user://test_config/injected.txt", 1)
	var injected_slides: Array[String] = injected["slides"]
	var leaked := false
	for s in injected_slides:
		if s.contains("\uE000") or s.contains("\uE001"):
			leaked = true
	# the marker chars are gone, so the payload degrades to ordinary visible text
	# rather than forging a chapter entry. Deleting the reader's own text would be worse.
	var forged := false
	for ch in injected["chapters"]:
		if str(ch["title"]).contains("Fake"):
			forged = true
	if leaked or forged:
		print("MARKER INJECTION FAIL: ", injected_slides, " chapters=", injected["chapters"])
		quit(1)
		return
	print("Reserved marker chars cannot be injected from a document")

	# a Windows-1252 .txt must decode, not arrive as a wall of replacement chars.
	# 0x92 is a right single quote and 0x97 an em dash in cp1252; both are invalid
	# UTF-8 sequences, which is what triggers the fallback.
	var cp := FileAccess.open("user://test_config/cp1252.txt", FileAccess.WRITE)
	assert(cp != null, "could not write cp1252 fixture")
	if cp:
		var cp_bytes := PackedByteArray()
		cp_bytes.append_array("It".to_utf8_buffer())
		cp_bytes.append(0x92)
		cp_bytes.append_array("s a test".to_utf8_buffer())
		cp_bytes.append(0x97)
		cp_bytes.append_array(" done.".to_utf8_buffer())
		cp.store_buffer(cp_bytes)
		cp.close()
	var cp_slides := TextParser.parse_file("user://test_config/cp1252.txt", 1)
	var cp_joined := " ".join(cp_slides)
	if cp_joined.contains("\uFFFD") or not cp_joined.contains("’") or not cp_joined.contains("—"):
		print("CP1252 FAIL: ", cp_joined)
		quit(1)
		return
	print("cp1252 .txt decoded: ", cp_joined)

	# 7. 2-Digit Version Comparison (Updater)
	var UpdaterScript = load("res://scripts/updater.gd")
	if UpdaterScript:
		assert(UpdaterScript.is_remote_newer("v1.1", "1.0"), "1.1 should be newer than 1.0")
		assert(UpdaterScript.is_remote_newer("1.2", "1.1"), "1.2 should be newer than 1.1")
		assert(UpdaterScript.is_remote_newer("2.0", "1.9"), "2.0 should be newer than 1.9")
		assert(not UpdaterScript.is_remote_newer("v1.0", "1.0"), "1.0 should not be newer than 1.0")
		assert(not UpdaterScript.is_remote_newer("1.0", "1.1"), "1.0 should not be newer than 1.1")
		print("2-digit version comparison verified: v1.1 > 1.0, 2.0 > 1.9, v1.0 == 1.0")

	print("--- All Headless Verifications Passed! ---")
	quit()
