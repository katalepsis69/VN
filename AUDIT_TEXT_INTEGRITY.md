# Text Garbling Research & Audit Brief

Compiled 2026-10-10. Two parts:

1. Research report: what the wider software world knows about garbled text, checked
   against real sources (not just one agent's summary), and how it maps to this app.
2. Audit category: ready-to-paste audit instructions for the auditor, covering current
   bugs, future bugs, and format compatibility for every scramble cause found.

Zero em dashes below, per project style.

================================================================
AUDIT RESULT (run 2026-10-10, do not re-flag these as open)
================================================================
Part 2 was executed against the real code with an adversarial probe of every input
listed in 2a to 2h. Seven confirmed holes were fixed and pinned by 15 new asserts in
test_verification.gd sections 4h to 4o. Details are in AGENTS.md.

Two claims in this brief turned out to be wrong, so future audits should start from
the code and not from this document:
- 2b: the named-entity table did NOT lack trade, copy, reg, deg, plusmn, ndash,
  lsquo, rsquo, sbquo, bdquo, dagger, bull, euro, pound, sect, para, middot, laquo,
  raquo, times, divide or frac12. All were already there. The real gaps were the
  structural five plus thinsp, curren, brvbar, not, macr, cedil, acute, grave, tilde,
  superscripts, micro, arrows, math symbols, card suits and Greek, all now added.
- 2f: "a user font with an existing fallback list never gets the SystemFont" is
  unreachable. Fonts come from load_dynamic_font or an imported .ttf, and both leave
  fallbacks empty, so the system font always attaches.

Confirmed and fixed: off-centre and narrow PDF gutters, cross-column titles, private
use markers from PDF and clipboard text, UTF-16 without a BOM, uppercase numeric
entities, double entity decoding of EPUB and DOCX bodies, and the silent no-op when a
paste parses to nothing.

Confirmed and deliberately left alone (each is a limit, not a bug): cascading
mojibake, BOM plus one bad byte, pages under 20 blocks, three or more columns,
rotated text, tables, superscript exponents, steeply tilted scans, right-to-left PDF
word order, and typed zero width joiners.

================================================================
PART 1: RESEARCH REPORT (verified against primary sources)
================================================================

The other agent's six-cause report is CONFIRMED and correct in all six causes. Below,
each cause is cross-checked against authoritative sources, with corrections and
additions where the research goes deeper than the first report.

CAUSE 1. Encoding mismatch (mojibake)

What the sources say:
- Joel Spolsky, "The Absolute Minimum Every Software Developer Must Know About
  Unicode and Character Sets": a string means nothing without its encoding; almost
  every "my text looks like gibberish" bug comes from decoding bytes with the wrong
  charset. UTF-8 stores 0-127 as single ASCII bytes and uses multi-byte sequences
  for everything above; Windows-1252 is single-byte Western European. Decoding one
  as the other produces systematic garbage.
- Wikipedia "Mojibake": causes are underspecification (no encoding declared, so
  software guesses), mis-specification (wrong label), overspecification (conflicting
  declarations), and legacy locale-only support. Canonical look of UTF-8-read-as-
  Windows-1252: apostrophe becomes â€™, em dash becomes â€”, £ becomes Â£.

Additions the first report missed:
- CASCADING MOJIBAKE: re-encoding already-garbled text again compounds it
  (Â£ becomes Ã‚Â£, and so on). A book file that was corrupted by an earlier tool
  is unrecoverable by detection; the fingerprint check only catches LIVE mistakes.
- Detection heuristics are fundamentally fragile: the Spolsky article explicitly
  warns that statistical guessing (as browsers do) can misidentify text. This app's
  fingerprint method is a heuristic, and the audit must probe its failure edges.

App status: fixed with the multi-layer byte detector (_decode_bytes: BOM checks,
UTF-8 probe, mojibake fingerprint, CP1252 fallback). Audit the edges, not the idea.

CAUSE 2. Missing font glyphs ("tofu" boxes)

What the sources say:
- Ren'Py's own documentation: "The system font should be able to express both ASCII
  and the translated language." That is exactly the fallback strategy this app uses.
- Standard industry practice: attach a fallback font with wide coverage behind any
  display font; the OS text renderer pulls missing glyphs from it automatically.

Additions the first report missed:
- The fallback only fires when the active font does not have the glyph. Emoji,
  CJK, and right-to-left scripts (Arabic, Hebrew) are common gaps even with a
  system font fallback on minimal Windows installs.
- A USER-supplied font (My Fonts picker) that already has its own fallback list
  will NOT get the SystemFont added by the current code. That path needs an audit.

App status: fixed (SystemFont attached as fallback in _apply_theme). Audit the
user-font path and the emoji/CJK edge.

CAUSE 3. Typographic ligatures

What the sources say:
- Academic and print typography uses presentation-form ligatures (fi, fl, ff, ffi,
  ffl, plus the long-s forms ft and st) as single code points U+FB00 through U+FB06.
  Fonts aimed at games and UI rarely include them, so they render as missing-glyph
  boxes or vanish, producing broken words like "nally" for "finally".
- Decomposing them into plain letter pairs at parse time is the standard fix.

Additions the first report missed:
- The app handles all seven presentation forms (FB00-FB06). Arabic and Hebrew
  presentation-form blocks (U+FB50 onwards) are NOT handled; they would be rare in
  this app's expected input, so this is a LOW-priority awareness item only.

App status: fixed (_normalize_typography). Verify FB05 and FB06 (ft, st) handling
and interaction with soft-hyphen removal.

CAUSE 4. Typewriter reflow (words jumping lines mid-type)

What the sources say:
- Godot official TextServer docs, VerifiedCharactersBehavior enum:
  VC_CHARS_BEFORE_SHAPING (0) trims characters BEFORE shaping, so hidden characters
  "are not accounted for in line breaking and size calculations". That is precisely
  why before-shaping causes reflow: every revealed character changes the layout.
  VC_CHARS_AFTER_SHAPING (1) shapes the full text first and only hides glyphs after
  layout, so line breaks and sizes stay fixed during reveal.
- Correction to the first report: the enum has values 0 through 4 (the 2-4 values
  are ratio-based glyph variants); there is no "VC_HINTING" value. The app uses
  VC_CHARS_AFTER_SHAPING, which is the correct choice per the official docs.

App status: fixed (dialogue_label.visible_characters_behavior set at build time).
Audit: confirm the constant exists in Godot 4.7 exactly as named, and check the
interaction with shrink-to-fit font sizing on very long slides.

CAUSE 5. PDF coordinate scramble (words out of reading order)

What the sources say:
- PDFs store text as positioned glyph runs, not paragraphs. PyMuPDF documentation:
  raw extraction order follows the document's content-stream creation order, NOT
  visual reading order; their "sort" flag sorts by vertical then horizontal
  coordinates and "should suffice to generate a natural reading order" in many
  cases, but is NOT guaranteed.
- Explicitly documented failure modes: multi-column layouts interleave incorrectly
  under simple vertical-then-horizontal sorting; rotated or vertical text needs
  full geometry recovery; OCRed pages have jittery glyph heights that distort
  bounding boxes.
- This validates both of the app's PDF fixes: two-column gutter detection (because
  naive sorting interleaves columns) and adaptive line-height clustering (because
  static grid bucketing breaks under baseline jitter).

Additions the first report missed:
- Three-column layouts and rotated text are known-unhandled in most extractors,
  this app included. Audit what the user sees (garble vs. acceptable degrade).
- Scanned PDFs (image-only, no text layer) produce zero words: the page reads as
  empty. Audit whether the user gets a clear message.

App status: fixed for the two common cases (two-column detection, adaptive
clustering). Audit the thresholds and the unhandled layouts.

CAUSE 6. Raw web codes and invisible formatting

What the sources say:
- MDN "Entity": named (&mdash;), decimal (&#8212;), and hex (&#x2014;) character
  references. Documented pitfalls: entities never decoded (user sees the raw code),
  and DOUBLE ENCODING, where an already-encoded string is escaped again and the user
  sees "&amp;mdash;" or worse. Rule of thumb from the source: encode once at the
  output boundary, decode once at the input boundary.
- Invisible characters (soft hyphen U+00AD, non-breaking spaces U+00A0/U+202F,
  zero-width characters) break wrapping and search if left in flowing text.

Additions the first report missed:
- The app's amp-last decode order is the documented correct defense against double-
  decoding. The audit should verify triple-encoded input survives intact.
- The named-entity table should be checked against the full HTML5 named-entity set
  for gaps (trade, copy, reg, ndash, lsquo, rsquo, euro, and friends).

App status: fixed (entity decoder + typography normalizer). Audit table coverage
and multi-pass edge cases.

VERDICT ON THE FIRST REPORT
All six causes are real, well-documented industry problems, and all six have
corresponding fixes in this codebase. The first report is accurate. The additions
above are the new audit material: cascading mojibake, user-font fallback gap,
three-column/rotated/scanned PDFs, triple-encoded entities, and the entity-table
coverage gap.

================================================================
PART 2: AUDIT CATEGORY (paste into the audit prompt as Category 2,
replacing or extending the existing text-integrity section)
================================================================

2. TEXT ENCODING, RENDERING & FORMAT COMPATIBILITY (priority area)

Audit the entire text pipeline from raw bytes to rendered pixels for every supported
format (.txt, .md, .docx, .pdf, .epub, clipboard paste). The goal: find any input
that produces garbled, scrambled, missing, or wrongly rendered text. Think
adversarially about real-world books. The six known scramble causes and the app's
fixes are listed in AUDIT_TEXT_INTEGRITY.md; audit the implementations for holes,
edge cases, and cross-format regressions. Do not re-flag the design decisions.

2a. Encoding detection (_decode_bytes)
- Mojibake fingerprint ("â€" and "Ã" in the CP1252 output): construct a valid UTF-8
  file whose CP1252 misreading contains NEITHER fingerprint and trace what happens.
- Cascading mojibake: a file containing "Ã‚Â£" (already-garbled text). Does the
  fingerprint fire on it and misroute it to UTF-8? What does the reader see?
- UTF-16 BE byte-swap loop: odd-length input (lone trailing byte), and a file that
  is only the 2-byte BOM with no content.
- A file containing a literal U+FFFD character typed by the author: the UTF-8 probe
  sees the replacement char and falls toward CP1252. Trace the result.
- Mixed-encoding files (concatenated documents): what does the reader see?
- Empty file, single-byte file, BOM-only file at every entry point.

2b. Entity decoding (_decode_entities)
- Named-entity table coverage: check for missing common HTML5 entities (trade,
  copy, reg, deg, plusmn, ndash, lsquo, rsquo, sbquo, bdquo, dagger, bull, euro,
  pound, sect, para, middot, laquo, raquo, times, divide, frac12). Report each gap
  with the character a real book would display raw.
- Double encoding ("&amp;mdash;" must display as "&mdash;"): verify the amp-last
  rule. Triple encoding ("&amp;amp;mdash;"): verify it displays "&amp;mdash;".
- Numeric edges: &#0; &#x0; &#65533; &#1114111; &#1114112;. Verify no engine
  parse warnings and no marker forgery (the PUA block).
- Unrecognized long entities ("&CounterClockwiseContourIntegral;"): they pass
  through as literal text. Is that acceptable at this scale?

2c. Typography normalization (_normalize_typography)
- Soft hyphen inside a word ("stra\u00ADtegic") vs. the hyphenated line-join logic
  in parse_string: verify the word becomes "strategic", not "stra-tegic", and that
  a real end-of-line hyphen join still works after normalization.
- Zero-width joiner (U+200D) and non-joiner (U+200C) are NOT removed. Confirm they
  are benign for this app's expected input or report the failure case.
- Exotic spaces (U+2007 figure, U+2008 punctuation, U+2009 thin): do they render
  sanely or produce layout oddities?
- Ligatures: verify all seven (FB00-FB06) decompose, and that a real word like
  "office" (which contains ffi) survives the full pipeline intact.

2d. Multi-column PDF detection (_extract_page_lines)
- Off-center gutter: a two-column page whose gutter sits at 40% of the span. Does
  detection still fire, or does it silently interleave?
- Sparse two-column pages under the thresholds (< 20 blocks or < 250pt span): they
  fall to single-column interleaving. Acceptable degrade or visible scramble?
- Three-column layouts and rotated text: known unhandled. What does the user see?
- A centered heading spanning both columns: does it split, duplicate, or land in
  one column?
- Tables: do cell words merge into garbled lines under adaptive clustering?

2e. Adaptive PDF line clustering (_lines_from_column)
- Threshold sanity: max(word_height, 10) * 0.5. Tight leading (lines closer than
  half a line height): merged lines. Superscripts in fractions (math PDFs): orphan
  lines. Report real document classes that break.
- Running-average cluster center drift on tilted baselines (scanned pages): can the
  average pull the next line's first word into the previous line?
- Right-to-left scripts in PDFs: words sorted left-to-right reverse reading order.
  One line on expected impact for this app's audience.

2f. Rendering pipeline (main.gd)
- VC_CHARS_AFTER_SHAPING: confirm the constant and its value (1) exist in Godot
  4.7 as used; the official docs confirm after-shaping prevents reflow by shaping
  the full text before hiding glyphs. Verify nothing resets the property later
  (theme changes, style swaps, font swaps).
- SystemFont fallback: attached only when a FontFile's fallbacks list is empty.
  Trace the My Fonts picker path: a user font with an existing fallback list never
  gets the system font. A user font missing common punctuation renders boxes.
  Report whether that is acceptable or needs an always-append.
- Emoji and CJK book text: does the fallback chain cover them, or are they boxes?
- Typewriter + shrink-to-fit interaction: a 641-char slide shrinks its font; does
  the shaped-layout reveal still hold (no reflow during type)?
- BBCode + visible_characters: reveal mid-entity; verify no raw bracket flash.

2g. Cross-format regression matrix (verify one fragile case per format)
- .txt: pure ASCII / UTF-8 with BOM / UTF-8 without BOM / UTF-8 with one bad byte /
  genuine CP1252 with curly quotes / UTF-16 LE / UTF-16 BE / ASCII plus one emoji.
- .md: same set, plus a heading containing an entity ("# Chapter 1 &amp; 2").
- .docx: document.xml with a UTF-8 BOM: does the BOM survive into the XML string
  and break tag matching? Corrupted XML: does _decode_bytes help or is the XML
  parser the failure point?
- .epub: chapters with different declared encodings; the XML declaration says
  encoding="..." but the code ignores it. Construct a CP1252 chapter and trace.
- .pdf: non-Latin fonts (CJK, Cyrillic): correct Unicode or substitution boxes?
  Scanned image-only PDF: empty pages, is there a user-facing message?
- Clipboard: pasting from a PDF viewer that puts RTF or HTML on the clipboard:
  does the paste path get clean text or formatting codes?

2h. Future-proofing
- Interaction order for a UTF-8 + BOM + CRLF file: BOM strip, CRLF normalize,
  entity decode, typography normalize. Verify no step undoes another and the order
  cannot produce artifacts.
- A document literally containing the fingerprint string "â€" (a book about
  encoding, or a corrupted-recovery story): trace the detection path.
- New formats later (the roadmap mentions none beyond PDF; if any are added, this
  section defines the test bar: every new format must pass 2g's matrix).

Severity notes for this category: any input that produces VISIBLE scramble on a
plausible real book is at least MEDIUM; scramble or crash on a COMMON book
(Gutenberg EPUB, two-column academic PDF, cp1252 .txt) is HIGH; silent empty
results with no message are MEDIUM.

================================================================
MEASUREMENT APPENDIX (add to the audit's measurement list)
================================================================
For SUSPECTED findings in this category, the owner can verify with:
- New .txt test files: create in Notepad, choose the encoding at save time (ANSI =
  CP1252, UTF-8, UTF-8 with BOM, UTF-16 LE, UTF-16 BE), drop into My Books, open,
  and read the first slide. Scrambled quotes/dashes = finding confirmed.
- Entity test: paste "Tom &amp;amp; Jerry &mdash; said the &ldquo;cat&rdquo;" via
  the Paste menu button and check the slide text.
- PDF two-column check: open a two-column academic PDF from My Books and watch the
  first paragraph of a dense page for interleaved left-right fragments.
- Headless parser checks go through test_verification.gd sections 1c, 1e, 4b-4f
  (commands in AGENTS.md).
- Anything export-sensitive: verify in build/VNReader.exe, not the editor.

================================================================
SOURCES CONSULTED
================================================================
- Joel Spolsky, "The Absolute Minimum Every Software Developer Absolutely,
  Positively Must Know About Unicode and Character Sets" (joelonsoftware.com, 2003):
  encodings, code pages, wrong-charset decoding, why guessing is fragile.
- Wikipedia, "Mojibake": underspecification, mis-specification, cascading re-
  encoding (Â£ to Ã‚Â£), UTF-8-as-Windows-1252 examples (â€™, â€”, Ã¶).
- Godot Engine stable docs, class TextServer: VisibleCharactersBehavior enum;
  VC_CHARS_BEFORE_SHAPING excludes hidden chars from line breaking;
  VC_CHARS_AFTER_SHAPING shapes full text then hides glyphs (stable layout).
- Godot Engine stable docs, class RichTextLabel: visible_characters counts Unicode
  code points; designed for dialog animation; scroll_following_visible_characters.
- MDN Web Docs, "Entity" glossary: named vs numeric entities, the common set,
  not-decoded and double-encoding pitfalls, encode-once/decode-once rule.
- PyMuPDF documentation, TextPage: raw extraction follows creation order not
  reading order; sort flag is vertical-then-horizontal and not guaranteed;
  multi-column interleaving, rotated text, and OCR jitter are documented failure
  modes.
- Ren'Py documentation, Translation chapter: system font must cover ASCII and the
  target language (confirms the fallback-font strategy).

</content>