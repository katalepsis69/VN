class_name TextParser
extends RefCounted

## Parses plain text, markdown, docx documents, or raw text into visual novel sentence slides.

## What the shelf and the My Books folder accept. Single source so a new format
## only has to be added once.
const SUPPORTED_EXTENSIONS := ["txt", "md", "docx", "pdf", "epub"]
## Guard rails for archives and PDFs that are hostile rather than merely large.
## Real books measured here: pg79737 EPUB is 52 entries / 4.7 MB uncompressed.
const MAX_ZIP_ENTRIES := 3000
const MAX_IMAGE_BYTES := 256 * 1024 * 1024

static func parse_file(path: String, sentences_per_slide: int = 2) -> Array[String]:
	var result := parse_file_with_images(path, sentences_per_slide)
	var slides: Array[String] = result["slides"]
	return slides

## Returns {"slides": Array[String], "images": {slide_index: Array[PackedByteArray]},
##          "chapters": Array[{slide: int, title: String}], "book_start": int}
## EPUB text keeps invisible markers where its images sit in the flow; they are
## mapped to the slides they belong to and stripped from the displayed text.
## Chapter sources: EPUB table of contents, DOCX Heading styles, or short
## "Chapter N"-style lines in plain text. book_start points at the first slide
## after Gutenberg boilerplate (-1 when none).
static func parse_file_with_images(path: String, sentences_per_slide: int = 2) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"slides": [], "images": {}, "chapters": [], "book_start": -1}

	var ext := path.get_extension().to_lower()
	var raw_content := ""
	var images: Array = []
	var toc_chapters: Array = []

	if ext == "docx":
		raw_content = read_docx(path)
	elif ext == "epub":
		raw_content = read_epub(path, images, toc_chapters)
	elif ext == "pdf":
		# via PDFReader so a missing pdfium dll only breaks PDFs, not the app
		raw_content = PDFReader.read_pdf(path)
	else:
		raw_content = read_plain_text(path)

	var heuristic: Array = []
	var slides := parse_string(raw_content, sentences_per_slide, heuristic)
	var raw_to_clean := {}
	var image_map := _map_images_to_slides(slides, images, raw_to_clean)
	# TOC chapters ride through text markers; the index-based heuristic is only
	# used when there is no real TOC (it would double-count heading markers).
	var indexed: Array = [] if not toc_chapters.is_empty() else heuristic
	return {
		"slides": slides,
		"images": image_map,
		"chapters": _map_chapters_to_slides(slides, indexed, raw_to_clean),
		"book_start": find_book_start(slides),
	}

## Slide index of the first real content after Gutenberg boilerplate (-1 if none)
static func find_book_start(slides: Array[String]) -> int:
	for i in slides.size():
		if slides[i].contains("START OF THE PROJECT GUTENBERG"):
			return mini(i + 1, slides.size() - 1)
	return -1

## Strips CH markers (EPUB TOC / DOCX headings) from slides, collects their slide
## indices, and folds in the plain-text heuristic chapters (raw indices -> cleaned).
static func _map_chapters_to_slides(slides: Array[String], indexed: Array, raw_to_clean: Dictionary) -> Array:
	var re := RegEx.create_from_string("\uE000CH:(.*?)\uE001")
	var space_re := RegEx.create_from_string("[ \\t]{2,}")
	var out: Array = []
	for i in slides.size():
		var found := re.search_all(slides[i])
		if found.is_empty():
			continue
		slides[i] = space_re.sub(re.sub(slides[i], "", true), " ", true).strip_edges()
		for m in found:
			out.append({"slide": i, "title": m.get_string(1)})
	for ch in indexed:
		out.append({"slide": int(raw_to_clean.get(ch["slide"], ch["slide"])), "title": ch["title"]})
	out.sort_custom(func(a, b): return int(a["slide"]) < int(b["slide"]))
	var dedup: Array = []
	var last := -1
	for ch in out:
		if int(ch["slide"]) == last:
			continue
		last = int(ch["slide"])
		dedup.append(ch)
	return dedup

## remap (optional) is filled with raw slide index -> cleaned slide index, for
## callers that tracked positions before marker-only slides were dropped.
static func _map_images_to_slides(slides: Array[String], images: Array, remap: Dictionary = {}) -> Dictionary:
	var out := {}
	if images.is_empty():
		return out
	var re := RegEx.create_from_string("\uE000IMG:(\\d+)\uE001")
	var space_re := RegEx.create_from_string("[ \\t]{2,}")
	var cleaned: Array[String] = []
	var carry: Array = []
	for raw_i in slides.size():
		var slide: String = slides[raw_i]
		var refs: Array = []
		for m in re.search_all(slide):
			var idx := m.get_string(1).to_int()
			if idx >= 0 and idx < images.size() and not refs.has(images[idx]):
				refs.append(images[idx])
		var text: String = space_re.sub(re.sub(slide, "", true), " ", true).strip_edges()
		if text.is_empty():
			# a marker-only slide: attach its image to the text that follows
			carry.append_array(refs)
			continue
		var new_idx := cleaned.size()
		remap[raw_i] = new_idx
		if not refs.is_empty() or not carry.is_empty():
			out[new_idx] = carry + refs
			carry = []
		cleaned.append(text)
	if not carry.is_empty() and not cleaned.is_empty():
		var last := cleaned.size() - 1
		out[last] = out.get(last, []) + carry
	_spread_multi_images(out, cleaned.size())
	slides.assign(cleaned)
	return out

## Marker-only slides collapse into the text that follows them, so a paragraph
## carrying two illustrations lands both on one slide and the reader only ever
## sees the first. Push the extras onto the next empty slots instead.
static func _spread_multi_images(out: Dictionary, slide_count: int) -> void:
	for i in slide_count:
		if not out.has(i):
			continue # never assign an empty array: callers index [0] on every key
		var refs: Array = out[i]
		while refs.size() > 1:
			var moved: Variant = refs.pop_back()
			var placed := false
			for j in range(i + 1, slide_count):
				if not out.has(j):
					out[j] = [moved]
					placed = true
					break
			if not placed:
				refs.append(moved)
				break # nowhere left to put it: keep the rest on this slide

## The private-use chars used as invisible markers. They must never survive in
## text that came from the file: a document carrying them could otherwise forge a
## chapter entry or hide a passage from display.
static func _strip_reserved(text: String) -> String:
	return text.replace("\uE000", "").replace("\uE001", "")

## Windows-1252 glyphs for 0x80-0x9F, where older Gutenberg and WordPad .txt files
## put curly quotes, dashes and accents. Other bytes in that block are controls.
const CP1252_HIGH := [
	"€", "","‚", "ƒ", "„", "…", "†", "‡", "ˆ", "‰", "Š", "‹", "Œ", "", "Ž", "",
	"", "‘", "’", "“", "”", "•", "–", "—", "˜", "™", "š", "›", "œ", "", "ž", "Ÿ",
]

## Decode bytes as UTF-8, falling back to Windows-1252, and drop a leading BOM.
## get_as_text() is UTF-8 only, so a cp1252 book arrived as a page of U+FFFD.
static func _decode_bytes(bytes: PackedByteArray) -> String:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		bytes = bytes.slice(3)
	var as_utf8 := bytes.get_string_from_utf8()
	# get_string_from_utf8 substitutes U+FFFD for invalid sequences. That is how a
	# cp1252 book announces itself; a real replacement char in a novel is negligible.
	if not as_utf8.contains("\uFFFD"):
		return as_utf8
	var out := ""
	for b in bytes:
		if b < 0x80:
			out += String.chr(b)
		elif b < 0xA0:
			out += CP1252_HIGH[b - 0x80]
		else:
			out += String.chr(b)
	return out

static func read_plain_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content := _decode_bytes(file.get_buffer(file.get_length()))
	file.close()
	return _strip_reserved(content)

static func read_docx(path: String) -> String:
	var reader := ZIPReader.new()
	var err := reader.open(path)
	if err != OK:
		return ""
	# A crafted archive can declare tens of thousands of entries; reading them all
	# is how a 200 KB file becomes gigabytes of allocation.
	if reader.get_files().size() > MAX_ZIP_ENTRIES:
		reader.close()
		push_warning("DOCX has too many entries: " + path)
		return ""
	
	# word/document.xml holds the text body in standard OOXML format
	if not reader.file_exists("word/document.xml"):
		reader.close()
		return ""
		
	var data := reader.read_file("word/document.xml")
	reader.close()
	
	var xml_string := _strip_reserved(data.get_string_from_utf8())	# Heading 1-3 paragraphs get a chapter marker so the parser can map them
	xml_string = _mark_docx_headings(xml_string)
	# Replace paragraph ends with double newline
	xml_string = xml_string.replace("</w:p>", "\n\n")
	# Strip XML tags
	var regex := RegEx.create_from_string("<[^>]+>")
	var clean_text: String = regex.sub(xml_string, "", true)
	return _decode_entities(clean_text).strip_edges()

static func _mark_docx_headings(xml: String) -> String:
	var para_re := RegEx.create_from_string("(?s)<w:p\\b.*?</w:p>")
	var style_re := RegEx.create_from_string("w:pStyle\\s+w:val=\"[Hh]eading\\s*0?[1-3]\"")
	var text_re := RegEx.create_from_string("(?s)<w:t\\b[^>]*>(.*?)</w:t>")
	var out := ""
	var pos := 0
	for m in para_re.search_all(xml):
		var block := m.get_string()
		if style_re.search(block) == null:
			continue
		var title := ""
		for t in text_re.search_all(block):
			title += t.get_string(1)
		title = " ".join(_decode_entities(title).split(" ", false))
		if title.is_empty():
			continue
		var open_end := block.find(">") + 1
		var marked := block.substr(0, open_end) + " \uE000CH:%s\uE001 " % title.left(80) + block.substr(open_end)
		out += xml.substr(pos, m.get_start() - pos) + marked
		pos = m.get_end()
	return out + xml.substr(pos)

static func read_epub(path: String, out_images: Array = [], out_toc: Array = []) -> String:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		push_warning("EPUB unreadable: " + path)
		return ""
	if reader.get_files().size() > MAX_ZIP_ENTRIES:
		reader.close()
		push_warning("EPUB has too many entries: " + path)
		return ""

	# 1. container.xml points at the OPF package file
	var opf_path := ""
	if reader.file_exists("META-INF/container.xml"):
		var container := reader.read_file("META-INF/container.xml").get_string_from_utf8()
		var cm := RegEx.create_from_string("full-path=\"([^\"]+)\"").search(container)
		if cm:
			opf_path = cm.get_string(1)
	if opf_path.is_empty() or not reader.file_exists(opf_path):
		reader.close()
		push_warning("EPUB has no readable OPF: " + path)
		return ""

	# 2. OPF manifest (id -> href for content documents) + spine order
	var opf := reader.read_file(opf_path).get_string_from_utf8()
	var base_dir := opf_path.get_base_dir()
	var id_to_href := {}
	var toc_item := ""
	var item_re := RegEx.create_from_string("<item\\b[^>]*>")
	var id_re := RegEx.create_from_string("id=\"([^\"]+)\"")
	var href_re := RegEx.create_from_string("href=\"([^\"]+)\"")
	var type_re := RegEx.create_from_string("media-type=\"([^\"]+)\"")
	var prop_re := RegEx.create_from_string("properties=\"([^\"]+)\"")
	for m in item_re.search_all(opf):
		var tag := m.get_string()
		var id_m := id_re.search(tag)
		var href_m := href_re.search(tag)
		if id_m == null or href_m == null:
			continue
		var type_m := type_re.search(tag)
		var mt := type_m.get_string(1) if type_m else ""
		var href := href_m.get_string(1)
		if mt == "application/x-dtbncx+xml":
			toc_item = href
		var prop_m := prop_re.search(tag)
		if prop_m and prop_m.get_string(1).split(" ").has("nav"):
			toc_item = href # epub3 nav wins over the older ncx
		if mt == "application/xhtml+xml" or href.get_extension().to_lower() in ["xhtml", "html", "htm"]:
			id_to_href[id_m.get_string(1)] = href

	var order: PackedStringArray = []
	var ref_re := RegEx.create_from_string("<itemref\\b[^>]*idref=\"([^\"]+)\"")
	for m in ref_re.search_all(opf):
		var idref := m.get_string(1)
		if id_to_href.has(idref):
			order.append(id_to_href[idref])
	if order.is_empty():
		# no usable spine: take all content documents in name order
		for k in id_to_href:
			order.append(id_to_href[k])
		order.sort()

	# 2b. table of contents (epub3 nav or epub2 ncx) -> titles for chapter jumps
	if not toc_item.is_empty():
		var toc_path := toc_item if base_dir.is_empty() else base_dir.path_join(toc_item)
		toc_path = toc_path.simplify_path()
		if reader.file_exists(toc_path):
			_collect_epub_toc(reader.read_file(toc_path).get_string_from_utf8(), toc_path.get_base_dir(), out_toc)

	# 3. read each chapter in reading order and convert to plain text,
	#    replacing inline images with position markers and keeping their bytes
	var parts: PackedStringArray = []
	var seen_images := {}
	for href in order:
		# root-absolute hrefs ("/text/ch1.xhtml") are zip-root-relative already:
		# strip the slash; everything else resolves from the OPF's folder
		var full := href.substr(1) if href.begins_with("/") else (href if base_dir.is_empty() else base_dir.path_join(href))
		var hash_at := full.find("#")
		if hash_at >= 0:
			full = full.substr(0, hash_at)
		if not reader.file_exists(full):
			continue
		var html := _strip_reserved(reader.read_file(full).get_string_from_utf8())
		html = _extract_epub_images(html, full.get_base_dir(), reader, out_images, seen_images)
		var chapter := _html_to_text(html)
		if not chapter.strip_edges().is_empty():
			parts.append(_toc_marker_for(full, out_toc) + chapter)
	reader.close()
	return "\n\n".join(parts)

static func _collect_epub_toc(xml: String, toc_dir: String, out_toc: Array) -> void:
	var entries: Array = []
	if xml.contains("<navPoint"):
		# epub2 ncx: each navPoint's own label + content appear before its children
		var np_re := RegEx.create_from_string("(?is)<navPoint\\b.*?</navPoint>")
		var t_re := RegEx.create_from_string("(?is)<text>(.*?)</text>")
		var c_re := RegEx.create_from_string("(?is)<content\\b[^>]*src=\"([^\"]+)\"")
		for m in np_re.search_all(xml):
			var t := t_re.search(m.get_string())
			var c := c_re.search(m.get_string())
			if t and c:
				entries.append({"href": c.get_string(1), "title": _clean_toc_title(t.get_string(1))})
	else:
		# epub3 nav: plain anchor list
		var a_re := RegEx.create_from_string("(?is)<a\\s[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
		for m in a_re.search_all(xml):
			entries.append({"href": m.get_string(1), "title": _clean_toc_title(m.get_string(2))})
	for e in entries:
		if e["title"].is_empty():
			continue
		var href: String = e["href"]
		var hash_at := href.find("#")
		if hash_at >= 0:
			href = href.substr(0, hash_at)
		if href.is_empty():
			continue
		e["href"] = (href if toc_dir.is_empty() else toc_dir.path_join(href)).simplify_path()
		e["used"] = false
		out_toc.append(e)

static func _clean_toc_title(raw: String) -> String:
	var t := _decode_entities(RegEx.create_from_string("<[^>]+>").sub(raw, "", true))
	# split(" ", false): a bare split() defaults to an empty delimiter = per-character
	return " ".join(t.split(" ", false)).left(80)

static func _toc_marker_for(resolved_href: String, toc: Array) -> String:
	var want := resolved_href.simplify_path()
	for e in toc:
		if not e["used"] and String(e["href"]) == want:
			e["used"] = true
			return " \uE000CH:%s\uE001 " % e["title"]
	return ""

static func _extract_epub_images(html: String, image_dir: String, reader: ZIPReader, out_images: Array, seen: Dictionary) -> String:
	var img_re := RegEx.create_from_string("(?i)<img\\b[^>]*>")
	var src_re := RegEx.create_from_string("(?i)src=\"([^\"]+)\"")
	var out := ""
	var pos := 0
	for m in img_re.search_all(html):
		out += html.substr(pos, m.get_start() - pos)
		pos = m.get_end()
		var src_m := src_re.search(m.get_string())
		if src_m == null:
			continue
		var src := src_m.get_string(1)
		var hash_at := src.find("#")
		if hash_at >= 0:
			src = src.substr(0, hash_at)
		if src.is_empty():
			continue
		var resolved := src if image_dir.is_empty() else image_dir.path_join(src)
		resolved = resolved.simplify_path()
		if not reader.file_exists(resolved):
			continue
		var idx: int = seen.get(resolved, -1)
		if idx < 0:
			# image bytes are held for the whole session, so stop accumulating once
			# the archive has given us enough. n is small (tens), so recounting is fine.
			var held := 0
			for b in out_images:
				held += (b as PackedByteArray).size()
			if held >= MAX_IMAGE_BYTES:
				break
			var blob := reader.read_file(resolved)
			idx = out_images.size()
			out_images.append(blob)
			seen[resolved] = idx
		out += " \uE000IMG:%d\uE001 " % idx
	out += html.substr(pos)
	return out

static func _html_to_text(html: String) -> String:
	var s := html
	# drop non-content blocks entirely (including their text)
	s = RegEx.create_from_string("(?is)<(script|style|head)\\b[^>]*>.*?</\\1\\s*>").sub(s, " ", true)
	s = RegEx.create_from_string("(?s)<!--.*?-->").sub(s, " ", true)
	# block boundaries become paragraph breaks (blank line, not a soft wrap)
	s = RegEx.create_from_string("(?i)</(p|div|h[1-6]|li|tr|blockquote|section|article|figure|figcaption)\\s*>|<br\\s*/?>").sub(s, "\n\n", true)
	s = RegEx.create_from_string("<[^>]+>").sub(s, "", true)
	s = _decode_entities(s)
	# tidy: collapse runs of blank lines, trim line edges
	s = RegEx.create_from_string("[ \t]+\n").sub(s, "\n", true)
	s = RegEx.create_from_string("(?:\n[ \t]*){3,}").sub(s, "\n\n", true)
	return s.strip_edges()

static func _decode_entities(text: String) -> String:
	var s := text
	s = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'")
	s = s.replace("&nbsp;", " ").replace("&#160;", " ")
	# One pass for both decimal and hex. Two passes let the decimal pass invent a
	# hex entity the second pass then decodes, so text meant to display "&#60;"
	# arrived as "<".
	s = _sub_numeric_entities(RegEx.create_from_string("&#(x?[0-9a-fA-F]+);"), s)
	# amp LAST, or "&amp;lt;" would double-decode
	return s.replace("&amp;", "&")

static func _sub_numeric_entities(re: RegEx, text: String) -> String:
	var out := ""
	var pos := 0
	for m in re.search_all(text):
		out += text.substr(pos, m.get_start() - pos)
		var digits := m.get_string(1)
		var is_hex := digits.begins_with("x") or digits.begins_with("X")
		if is_hex:
			digits = digits.substr(1)
		var code: int = digits.hex_to_int() if is_hex else digits.to_int()
		# forbidden surrogates and out-of-range points become U+FFFD; leaving them
		# in makes String.chr() emit a parse warning per occurrence
		if code < 0 or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF):
			code = 0xFFFD
		elif code < 0x20 and code != 9 and code != 10:
			code = 32 # NUL, backspace and friends: they break matching and layout
		elif code >= 0x7F and code <= 0x9F:
			code = 32
		elif code in [0x200B, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2060, 0x2061, 0x2062, 0x2063, 0x2064, 0xFEFF]:
			code = 32 # zero-width and bidi overrides: they spoof what the reader sees
		elif code >= 0xE000 and code <= 0xF8FF:
			# The whole private-use area. U+E000/U+E001 are our own invisible
			# chapter and image markers, and stripping them after insertion would
			# delete them too, so a document cannot be allowed to mint them here.
			code = 32
		out += String.chr(code)
		pos = m.get_end()
	out += text.substr(pos)
	return out

## out_chapters (optional) is filled with {slide, title} for detected chapter headings
static func parse_string(raw_text: String, sentences_per_slide: int = 2, out_chapters: Array = []) -> Array[String]:
	var slides: Array[String] = []
	if raw_text.strip_edges().is_empty():
		return slides
		
	# Normalize newlines
	var text := raw_text.replace("\r\n", "\n").replace("\r", "\n")
	
	# Build paragraphs: a single newline is a soft wrap (hard-wrapped books break
	# lines mid-sentence), a blank line is a real paragraph break.
	var paragraphs: PackedStringArray = []
	var current := ""
	for line in text.split("\n"):
		var l := line.strip_edges()
		if l.is_empty():
			if not current.is_empty():
				paragraphs.append(current)
				current = ""
			continue
		if l.begins_with("#") and not current.is_empty():
			paragraphs.append(current) # markdown heading starts its own paragraph
			current = ""
		current = l if current.is_empty() else current + " " + l
	if not current.is_empty():
		paragraphs.append(current)
	
	for para in paragraphs:
		var p := para.strip_edges()
		if p.is_empty():
			continue

		var chapter_slide := slides.size()
		var chapter_title := _chapter_heading_title(p)

		# ATX headings may close with the same run of hashes they opened with
		while p.ends_with("#"):
			p = p.substr(0, p.length() - 1).strip_edges()
		while p.begins_with("#"):
			p = p.substr(1).strip_edges()
		p = p.replace("**", "").replace("`", "")
		if p.is_empty():
			continue

		# Split paragraph into sentences
		var sentences := _split_into_sentences(p)
		
		# Group sentences into slides according to sentences_per_slide
		var current_chunk := ""
		var count := 0
		
		for s in sentences:
			var sentence := s.strip_edges()
			if sentence.is_empty():
				continue
				
			if current_chunk.is_empty():
				current_chunk = sentence
				count = 1
			elif count + 1 > sentences_per_slide \
					or current_chunk.length() + sentence.length() + 1 > MAX_SLIDE_CHARS:
				# flush BEFORE appending, so a slide never overshoots the cap by a whole sentence
				slides.append(current_chunk)
				current_chunk = sentence
				count = 1
			else:
				current_chunk += " " + sentence
				count += 1
				
		if not current_chunk.is_empty():
			slides.append(current_chunk)

		if not chapter_title.is_empty():
			out_chapters.append({"slide": chapter_slide, "title": chapter_title})

	return slides

## Short standalone "Chapter 12" / "CHAPTER I" / "Part Two" lines, or any
## markdown "#" heading, mark where a chapter (or paper section) starts.
static func _chapter_heading_title(para: String) -> String:
	var p := para.strip_edges()
	var is_md := p.begins_with("#")
	if is_md:
		while p.begins_with("#"):
			p = p.substr(1).strip_edges()
		while p.ends_with("#"):
			p = p.substr(0, p.length() - 1).strip_edges()
	p = p.replace("**", "").replace("`", "")
	if p.is_empty() or p.length() > 60:
		return ""
	if is_md:
		return p
	if RegEx.create_from_string("(?i)^(chapter|part|prologue|epilogue|interlude)\\b").search(p) == null:
		return ""
	return p

## Longest a slide should get. A sentence past this is cut only at an
## author-written clause boundary (_break_at_clause), never at a comma or a
## space — a slide ending "...for two weeks, and" reads far worse than a full
## textbox, which _fit_dialogue_text shrinks to fit.
const MAX_SLIDE_CHARS := 220
## A quotation may run well past one slide, so inside an open quote the splitter
## keeps accumulating until the buffer reaches this length and only then gives up.
## Real speeches measure p90 177 chars; the guard is for paragraphs whose quote
## never closes (mangled source), and 640 stays inside what shrink-to-fit renders.
const _QUOTE_ESCAPE_CHARS := 640
const _EM_DASHES := ["—", "–"]
const _CLOSERS := ["\"", "'", "”", "’", ")", "]", "}"]
const _CLAUSE_BREAKS := [";", ":"]
const _QUOTE_CHARS := ["\"", "“", "”"]

static func _split_into_sentences(text: String) -> Array[String]:
	var result: Array[String] = []
	var len_text := text.length()
	var buffer := ""
	var quote_parity := 0
	var i := 0
	
	var abbrevs := ["mr.", "mrs.", "ms.", "dr.", "prof.", "e.g.", "i.e.", "vs.", "etc.", "fig.", "al."]
	
	while i < len_text:
		var c := text[i]
		buffer += c
		if c in _QUOTE_CHARS:
			quote_parity += 1
		
		var is_punct := c in [".", "!", "?", "…", "。", "！", "？"]
		if is_punct:
			# Only the tail can matter: the longest abbreviation is 5 chars and an
			# initial is 3. Lower-casing the whole buffer at every terminator made
			# text that never splits quadratic in its length.
			var tail := buffer.to_lower().substr(maxi(0, buffer.length() - 8))
			var is_abbrev := _is_initial(tail)
			for ab in abbrevs:
				# " al." not "al.", or "general." and "rooms." would never end a
				# sentence. The bare compare covers an abbreviation at buffer start.
				if tail.ends_with(" " + ab) or tail == ab:
					is_abbrev = true
					break
					
			if not is_abbrev:
				# Absorb trailing closing quotes/brackets into this sentence, then
				# require whitespace or end — otherwise a lone " ends up on its own slide
				var j := i + 1
				while j < len_text and text[j] in _CLOSERS:
					j += 1
				# A dash butted straight onto the terminator is also a boundary:
				# chapter topic-lists ("Liverpool associations.—The "Porcupine."—Greeks…")
				# have no space after the period and would otherwise become one wall.
				var eats_dash := j < len_text and text[j] in _EM_DASHES
				if j >= len_text or eats_dash or text[j] in [" ", "\t", "\n"]:
					var candidate_parity := quote_parity
					for k in range(i + 1, j):
						if text[k] in _QUOTE_CHARS:
							candidate_parity += 1
					# Inside an open quotation this is speech-internal punctuation
					# ("You can do it. You can do it.”"), not a sentence end: splitting
					# there strands a lone quote mark on the next slide. The length
					# guard lets a quote that never closes run out of rope.
					if candidate_parity % 2 == 0 or buffer.length() >= _QUOTE_ESCAPE_CHARS:
						for k in range(i + 1, j):
							buffer += text[k]
						_commit_sentence(result, buffer)
						buffer = ""
						quote_parity = 0
						# the dash is a separator here, so drop it rather than lead the next slide with it
						i = j if eats_dash else j - 1
		i += 1
	
	_commit_sentence(result, buffer)
		
	var capped: Array[String] = []
	for s in result:
		capped.append_array(_break_at_clause(s, MAX_SLIDE_CHARS))
	return capped

## Commits a sentence, except a dialogue tag: after a closed quote ("...!" he said)
## the lowercase tag belongs to its quotation. The previous sentence must END with
## a quote mark for this to fire, so ordinary prose that happens to start lowercase
## is never glued onto the sentence before it.
static func _commit_sentence(result: Array[String], buffer: String) -> void:
	var sentence := buffer.strip_edges()
	if sentence.is_empty():
		return
	if _starts_lower(sentence) and not result.is_empty() \
			and result[result.size() - 1].right(1) in ["\"", "”", "’", "'"] \
			and result[result.size() - 1].length() + sentence.length() + 1 <= _QUOTE_ESCAPE_CHARS:
		result[result.size() - 1] += " " + sentence
	else:
		result.append(sentence)

static func _starts_lower(s: String) -> bool:
	if s.is_empty():
		return false
	var c := s[0]
	return c >= "a" and c <= "z"

## "E. A. Sothern." / "M. J. Whitty." — a lone letter before the period is an
## initial, so splitting there would emit two-character slides.
static func _is_initial(lower_buf: String) -> bool:
	if lower_buf.length() < 2 or not lower_buf.ends_with("."):
		return false
	var letter := lower_buf[lower_buf.length() - 2]
	if not ("a" <= letter and letter <= "z"):
		return false
	if lower_buf.length() == 2:
		return true
	return lower_buf[lower_buf.length() - 3] in [" ", ".", "—", "–"]

## Split an over-long sentence at an author-written clause boundary (";"/":").
## Boundaries inside an open quotation are skipped: cutting there strands half a
## quoted clause on each slide. With no usable boundary the sentence stays whole
## (an unbroken long slide is acceptable, a slide ending on a dangling word is not).
static func _break_at_clause(s: String, limit: int) -> Array[String]:
	if s.length() <= limit:
		return [s]
	var cuts: Array[int] = []
	var depth := 0
	for idx in s.length():
		var c := s[idx]
		if c in _QUOTE_CHARS:
			depth += 1
		elif c in _CLAUSE_BREAKS and depth % 2 == 0:
			cuts.append(idx)
	if cuts.is_empty():
		return [s]
	var out: Array[String] = []
	var start := 0
	var ci := 0
	while s.length() - start > limit and ci < cuts.size():
		# the LAST boundary inside the window, else the first one past it
		var chosen := -1
		var k := ci
		while k < cuts.size() and cuts[k] - start <= limit:
			chosen = cuts[k]
			k += 1
		if chosen < 0:
			chosen = cuts[ci]
			k = ci + 1
		ci = k
		out.append(s.substr(start, chosen - start + 1).strip_edges())
		start = chosen + 1
	var tail := s.substr(start).strip_edges()
	if not tail.is_empty():
		out.append(tail)
	return out
