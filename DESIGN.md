# DESIGN.md — ADHD VN Reader

The source of truth for this app's look and feel. Agents: apply these values; do not invent new colors or reintroduce default AI styling.

## Identity

A cozy wooden reading companion — a warm game UI, not a website. The product's job is sustained, comfortable reading for people with ADHD: the interface must be inviting and gently alive, and never compete with the book text for attention.

- **ENERGY 2 / RHYTHM 1 / MOTION 2** (declared dials)
- **One skinned theme.** The UI is wooden (Cozy UI Pack textures) — there is no theme switcher. Palette constants live at the top of `scripts/main.gd` (`WOOD_INK`, `ACCENT`, ...).

## Skin (assets in `assets/ui/`)

| Surface | Asset |
|---|---|
| Menu | Full-bleed **pixel-art landscape** (one image pinned in Settings → My Art, or rotating per visit when set to Random), over a warm **70%** dim, with flat `#241C14` fallback. Layout (top to bottom): "Now Reading" spotlight (cover + Continue), search + All/Reading/Finished tabs, hover card strip, **book shelf**, compact action row. The whole stack fits a 1280x720 window (content min ~677px); re-measure if anything is added |
| Book shelf | **Wooden plank** `container_wood.png` nine-patch, 208px with 20px top headroom so a hovered spine lifts from the plank instead of painting over the edge; books are code-drawn spines (hue hashed from the file path, sat 0.42 / **val 0.44**) with vertical titles, and the amber progress fill is added **before** the title so it sits under the letters; finished books get a 3px amber border; missing files are drawn **desaturated dark** (sat 0.10 / val 0.28) at 62% alpha rather than merely faded, so their titles stay readable |
| Hover card strip | **Flat wood** `#2E241A` + `#8A6A44` border, radius 8 — shows the hovered book's first sentence, progress, last-read time, and a Delete button (only while a book is on the card; the card lingers 0.3s so the mouse can reach it, and deletion asks first, saying exactly what happens to the file) |
| Dialogue box | `container_wood.png` (nine-patch, 30px margins) multiplied by **`WOOD_TEX_TINT` (0.62, 0.58, 0.52)**. The pack's texture is light peach `#DD9A79` and cream book text on it measured **1.96:1**; the tint lands the plank near `#8A5A40`, where cream clears 5:1. **Customizable in Settings**: Textbox Opacity (40–100%), Textbox Height (160–400px), and "Plain Textbox Style" (flat wood color, no texture) |
| Full-screen overlays (settings / bookmarks / backlog / chapters / my media) | **Flat wood** `#2A2018` + `#8A6A44` border |
| Recent-list rows | **Flat wood** `#2E241A` + `#8A6A44` border |
| All buttons | **Flat wood-tone** StyleBoxFlat (`#3A2E22`, hover `#4A3A2C`, pressed `#2C2218`, radius 10, border `#8A6A44` at 3.2:1 — `#5A4632` was 1.8:1 and left the edge carried by the label alone) — primary buttons flat brick red `#9C3A2C` (hover `#B04536`, pressed `#7D2F24`) with cream text. *Never nine-patch the square button sprite into wide buttons — the grain smears into lumps (that's why the file dialog buttons looked broken too; they inherit the theme).* |
| Selected tab | Amber text **plus** a filled face (`#4A3A2C`) and a 2px amber edge. Font colour alone was a 1.84:1 shift, which fails as a state signal. |
| Checkboxes | `checkbox_checked/unchecked.png` (scaled to 26px) |
| Focus | One shared `focus` stylebox on Button / CheckBox / OptionButton / HSlider / LineEdit: `draw_center = false`, 2px `ACCENT` outline, radius 11, 2px expand margin. Amber stays reserved for progress fill and this outline. |
| Next-arrow indicator | `arrow_brown.png` (scaled to 26px) |
| Sliders, text field, progress bar, top bar, nameplate | engine-drawn, tinted to the wood palette (the pack doesn't ship these). Slider groove is `#6B5638`: the old `#4A3826` was 1.4:1 against the panel, so the unfilled track was invisible. The grabber is still the engine default sprite — the pack ships none — which is the one "tinted to the palette" claim not held. |

**Retired textures (do not reuse):** `card_wood.png`, `button_red.png` (baked white decorations that read as glow), and `button_wood.png`/`container_plain.png` as stretched nine-patches on wide surfaces (grain smear). Files for the first two were deleted.

## Background pool (`assets/backgrounds/`, 45 images, scanned + lazy-loaded)

- Nature Landscapes Free Pixel Art, Free Sky with Clouds, and New Free Backgrounds parts 1–5 (all by free-game-assets). Pruned twice: the packs ship layer files and near-empty base layers that read as "no background" when picked.
- **2026-10-09 prune:** 15 more files moved out to `../adhdvnreader_removed_art/` (recoverable, not deleted) after a pixel audit of every image — 13 featureless colour washes (flat gradients, no clouds/moon/stars/horizon; one a solid purple rectangle) and 2 byte-identical duplicates (`nature_2_origbig` = `nature_2_orig`, `nature_8_1` = `nature_8_orig`). Pool went 60 → 45. Sky images that genuinely contain clouds, a moon, stars, a horizon, or a sunset were kept — they are real backdrops, not defects.
- **Do not judge a background by file size.** These are flat pixel-art scenes, so a legitimate sky image can be 5KB while a blank one is 2KB. The audit that works is decoded pixel content: unique-colour count plus luminance spread.
- The folder is scanned at startup; dropping any fully-opaque PNG/JPG in adds it to the rotation automatically. Pool entries are paths loaded on first use.
- **Fit to screen, never cropped:** `STRETCH_KEEP_ASPECT_CENTERED` shows the whole image; a darkened `STRETCH_SCALE` copy of the same image sits behind it so the letterbox reads as a soft backdrop instead of flat bars. Applies to the reading background and the menu. Portrait book illustrations from EPUBs were the case that made cropping obvious.
- Menu dim is 0.5 so even dark night scenes stay visible; dark starry nights are legitimate picks, not bugs.
- **The reader chooses per item.** Settings → My Art → "Choose Which Art To Use" opens the My Media screen: Backgrounds / Sprites / Sounds / Fonts, each split into Built-in and My Own tabs, every item a thumbnail with a checkbox. Unticked never appears. New files default to ticked. Selections persist by filename.

## Book folders

`My Backgrounds/ My Sprites/ My Sounds/ My Fonts/` next to the exe are the drop-in art folders. **`My Books/`** (added 2026-10-09) is the drop-in library: every `.txt/.md/.docx/.pdf/.epub` in it appears on the shelf without using Open Document. The shelf mirrors the folder — delete the file and the book, its progress, and its generated cover leave with it.

Text on wood: cream `#F5EAD6` (secondary `#D9C9A8`). **Text on the wooden buttons and the dialogue box is cream, not dark** — `#3A2A18` on the `#3A2E22` button fill is 1.52:1, and dark ink is only used on the cream `LineEdit` field. Accent amber `#E8A04C` for progress fill and focus outlines only. Radii: 8px controls, 12px dialogue box; nothing pill-shaped.

**Contrast is measured, not assumed.** Every pairing below was computed with the WCAG formula (2026-10-09): cream on the overlay `13.4`, on the hover strip `12.7`, on buttons `11.1`, on the primary red `5.8`, on the top bar `14.1`, on the nameplate `5.7`; `WOOD_INK_DIM` on those same surfaces `9.8 / 9.3 / 8.1 / 10.3 / 9.9`; amber text on the overlay `7.3`. Two pairings needed a code change to become true: the dialogue box (peach texture, was 1.96) and the menu labels (dim 0.5, was 2.2–3.1). If you retint anything, recompute rather than restate this line.

## Motion (purpose, per element)

Subtle persistent motion is a **core product feature** (visual stimulation for ADHD readers), not decoration — but it stays below the attention threshold of the text:

- Next-arrow fade pulse (0.4s loop) — standard VN affordance signaling "click to continue". Purpose: affordance.
- Background crossfade on change (0.75s) — prevents jarring switches. Purpose: comfort.
- Speaker bounce on slide change (one-shot, 0.24s: a 10px hop up on `TRANS_QUAD`/ease-out, then a smooth settle on `TRANS_SINE`) — the character acknowledges each line. Purpose: the line feels "spoken". The return leg used `TRANS_BOUNCE`, whose decaying overshoots at this duration read as a jitter, so it was re-curved 2026-10-09.
- Shelf drop-in (one-shot, per menu open) — books pop up from the plank in a 50ms stagger with a soft thud each; hovering a spine scales it 1.07 and rocks it once (hover sound included). Purpose: the shelf feels like a real, playful bookshelf; progress invites a click. Not loops — they finish in under a second.

No other loops. No bounce/scale/flash stacking.

**Removed 2026-10-09:** the ambient floating particles (a `CPUParticles2D` of 32 warm dots). They were listed here as "gentle environmental stimulation", but the owner found them read as a glow artifact and asked for them gone. The setting is gone too, not just defaulted off.

**Removed 2026-10-09:** the sprite idle breathing loop (2.2s sine at ±1.5% scale). It was listed here as "the character feels alive / companionship", but at that scale it read as the character slowly drifting and vibrating — the owner asked for it to stop. Do not restore it; the bounce above is the remaining character motion.

## Sound (assets in `assets/sfx/`, from lolurio's Cozy Game UI SFX Pack)

Typewriter blip = `menu_hover.ogg` every 3rd character; slide advance = `menu_confirm.ogg`; going back = `menu_back.ogg`; opening settings/bookmarks = `menu_open.ogg`; Save & Close = `menu_save.ogg`. The shelf reuses the pack: spine hover = `menu_hover.ogg`, each book landing = `menu_back.ogg` (low volume, first 10 books only). All respect the Settings volume toggle. Procedural fallbacks exist if files go missing.

## Typography

**Bundled default font: Atkinson Hyperlegible** (`assets/fonts/AtkinsonHyperlegible-Regular.ttf`, by the Braille Institute, SIL OFL 1.1 — license file bundled). Designed for low-vision readers: every letterform is deliberately distinguishable (no `I`/`l` confusion), which is exactly what a reader app needs. Priority chain: Settings picker > My Media tick (My Fonts folder entries first, then bundled Atkinson, then bundled Kaph) > engine default. Fonts are loaded with `load()`, not `FileAccess` + `load_dynamic_font`: in an exported build the raw `.ttf` is not on disk, only its imported form.

**Kaph** (`assets/fonts/Kaph-Regular.ttf`, by GGBotNet, SIL OFL 1.1) stays bundled and selectable: it is a display face with deliberately chipped, inked edges, which the owner liked as a look but found hard to read for body text (2026-10-09). Fonts are single-select in My Media (ticking one unticks the rest), so ticking Kaph makes it the active font. No monospace-as-aesthetic, no tracked-out uppercase labels.

**Button labels are sentence case** ("Open document", "Save & close", "Choose which art to use"). Title Case had crept into roughly twenty labels; anything new you add follows sentence case, and the remainder are being converted.

## Default character

**Ginger** (by Anima Studios, itch.io — free VN sprite pack) — 8 named expressions in `assets/sprites/` (normal, confused, thoughtfull, sad, shy, embarrassing, annoyed, angry; 500×1280 webp). Sprites rotate every N slides / randomly as configured. The sprite folder is scanned, so replacing Ginger = dropping new images in `assets/sprites/` or pointing Settings at your own folder.

## User asset folders (next to the .exe; project root in the editor)

The app creates and scans `My Backgrounds/`, `My Sprites/`, `My Sounds/`, `My Fonts/`:
- **My Backgrounds / My Sprites** — images join the rotation (appended to built-ins). **New files are picked up automatically when you return to the main menu** (folder signature check: file count + newest mtime; no restart needed).
- **My Sprites filename rule** — name a file with a mood word (`angry.png`, `sad.png`, `confused.png`, `shy.png`, `annoyed.png`, `embarrassing.png`, `thoughtfull.png` / `thoughtful.png`) and it reacts to matching text like built-in Ginger. User sprites take priority over built-ins for the same mood. Unmatched names rotate normally.
- **My Sounds** — drop-in SFX overrides matched by filename keywords: type/blip/key → typewriter, confirm/click/advance → advance, back/return → back, open → menus, save → save
- **My Fonts** — first .ttf/.otf becomes the default font
- Settings → "Open Asset Folders" opens them in Explorer; the Settings folder pickers still fully REPLACE pools when used (they take precedence over My folders)

## Non-negotiables (from antislop)

- No decorative emoji in UI text.
- Every control does something real; placeholders are labeled as such.
- Text readability always wins over decoration.

## Asset credits (keep if the app is ever distributed)

- **UI:** Cozy UI Pack (demo) by dobo_ui — https://dobo-ui.itch.io — *demo license: fine for personal use; buy the full pack before distributing the app.*
- **SFX:** lolurio Free Cozy Game UI SFX Pack by lolurio — https://lolurio.itch.io — CC BY 4.0, credit required (this file satisfies it; repeat in an About screen when one exists).
- **Reading font:** Atkinson Hyperlegible by the Braille Institute of America — https://brailleinstitute.org — SIL OFL 1.1, license file bundled (`assets/fonts/OFL-AtkinsonHyperlegible.txt`).
- **Display font:** Kaph by GGBotNet — SIL OFL 1.1, license file bundled (`assets/fonts/Kaph-License-OFL.txt`).
- **Backgrounds:** all by free-game-assets — https://free-game-assets.itch.io — Nature Landscapes Free Pixel Art, Free Sky with Clouds Pixel Art Set, and New Free Backgrounds parts 1–5. Free packs with attribution-style licenses (this file covers them); confirm the itch pages before sharing the app.
