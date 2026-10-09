class_name PDFReader
extends RefCounted

## PDF text extraction via the pdfium-gde GDExtension. Lives in its own script so
## a missing pdfium.dll only breaks PDF support, not the whole app: when the
## extension is absent this class simply reports "unavailable" and TextParser
## turns that into the normal "could not read" alert for .pdf files only.

static func available() -> bool:
	# string-built call: naming the class directly in this method would make the
	# whole script fail to parse when the extension is missing
	return ClassDB.class_exists("PDFDocument")

const MAX_PDF_BYTES := 80 * 1024 * 1024
const MAX_PDF_PAGES := 3000

static func read_pdf(path: String) -> String:
	if not available():
		push_error("PDF support unavailable: pdfium dll is missing from the app folder.")
		return ""
	# Read bytes via FileAccess: res:// docs live inside the PCK in exported
	# builds, where globalize_path() points at a file that is not on disk.
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("PDF unreadable: " + path)
		return ""
	if f.get_length() > MAX_PDF_BYTES:
		f.close()
		push_warning("PDF too large (%d bytes): " % f.get_length() + path)
		return ""
	var pdf_bytes := f.get_buffer(f.get_length())
	f.close()
	var doc = ClassDB.instantiate("PDFDocument")
	var err: int = doc.load_from_buffer(pdf_bytes)
	if err != OK or not doc.is_loaded():
		push_warning("PDF failed to parse: " + path)
		return ""
	# a small file can declare an enormous page count, and each page is parsed on
	# the main thread inside load_document
	var pages: int = mini(doc.get_page_count(), MAX_PDF_PAGES)
	var parts: PackedStringArray = []
	for i in pages:
		var page = doc.get_page(i)
		if page:
			# get_text_data returns word-level dicts {"text", "rect"}; rebuild
			# visual lines by grouping words on the same baseline (y), then
			# sorting left-to-right so the paragraph merger works.
			var blocks: Array = page.get_text_data()
			var rows := {}
			for b in blocks:
				if b is Dictionary and b.has("text") and b.has("rect"):
					var r: Rect2 = b["rect"]
					var key := int(round(r.position.y / 4.0))
					if not rows.has(key):
						rows[key] = []
					rows[key].append([r.position.x, str(b["text"])])
			var keys := rows.keys()
			keys.sort()
			var page_lines: PackedStringArray = []
			for k in keys:
				var ws: Array = rows[k]
				ws.sort_custom(func(a, b): return a[0] < b[0])
				var line_text := ""
				for w in ws:
					line_text += (" " if line_text != "" else "") + w[1]
				page_lines.append(line_text)
			if not page_lines.is_empty():
				parts.append("\n".join(page_lines))
	# ponytail: PDFs hard-break lines mid-paragraph; merge lines until sentence-ending punctuation
	var lines := "\n\n".join(parts).replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var paras: PackedStringArray = []
	var buf := ""
	for line in lines:
		var l := line.strip_edges()
		if l.is_empty():
			if not buf.is_empty():
				paras.append(buf)
				buf = ""
			continue
		if buf.is_empty():
			buf = l
		else:
			buf += " " + l
		if l.ends_with(".") or l.ends_with("!") or l.ends_with("?") or l.ends_with("…") or l.ends_with(":"):
			paras.append(buf)
			buf = ""
	if not buf.is_empty():
		paras.append(buf)
	return "\n\n".join(paras)
