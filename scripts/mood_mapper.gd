class_name MoodMapper
extends RefCounted

## Rule-based mood detection for reactive character expressions.
## Returns a mood keyword that matches sprite filenames ("" = no cue).
## Designed for the Ginger set: normal, confused, thoughtfull, sad,
## shy, embarrassing, annoyed, angry. It pattern-matches punctuation and
## keywords — it does not "understand" the text.

const ANGRY_WORDS := ["stop", "hate", "damn", "angry", "furious", "terrible", "awful", "worst", "shut"]
const SAD_WORDS := ["cry", "tears", "miss", "lost", "alone", "lonely", "sorry", "grief", "died", "death", "sad"]
const SHY_WORDS := ["blush", "shy", "whisper", "um", "maybe", "perhaps", "secret"]
const ANNOYED_WORDS := ["boring", "tedious", "annoying", "ugh", "whatever", "dull", "again"]

static func mood_for(text: String) -> String:
	var t := " " + text.to_lower() + " "
	# whole words only: substring matching made "debate" angry, "against" annoyed
	# and "commanding" furious
	var w := _word_spaced(text)
	if "!!!" in t or _has_any(w, ANGRY_WORDS):
		return "angry"
	if "?" in t:
		return "confused"
	if "!" in t:
		return "embarrassing"
	if "…" in t or "..." in t:
		return "thoughtfull"
	if _has_any(w, SAD_WORDS):
		return "sad"
	if _has_any(w, SHY_WORDS):
		return "shy"
	if _has_any(w, ANNOYED_WORDS):
		return "annoyed"
	return ""

## Lower-cased text with every non-letter replaced by a space, so a keyword can
## only ever match a whole word.
static func _word_spaced(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else " "
	return " " + out + " "

static func _has_any(spaced: String, words: Array) -> bool:
	for w in words:
		if spaced.contains(" %s " % w):
			return true
	return false
