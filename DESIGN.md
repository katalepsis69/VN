# DESIGN.md — ADHD VN Reader

The source of truth for this app's look and feel. Agents: apply these values; do not invent new colors or reintroduce default AI styling.

## Identity

A cozy wooden reading companion — a warm game UI, not a website. The product's job is sustained, comfortable reading for people with ADHD: the interface must be inviting and gently alive, and never compete with the book text for attention.

- **ENERGY 2 / RHYTHM 1 / MOTION 2** (declared dials)
- **Preset looks (owner override 2026-10-09).** The one-skin rule is retired: the owner asked for built-in customization without needing new assets. Settings → Look offers five whole-app looks (Cozy Wood, Ember, Forest, Slate, Dusk), defined in the `LOOKS` table at the top of `scripts/main.gd`. "Cozy Wood" is the exact pre-looks skin — every measured claim below is that row — and every look must clear the per-look contrast vetting in `test_verification.gd` (cream ink 4.5:1+ on every surface, accent and edge 3:1+ on the dark faces). Beyond the looks there is no free color picker: a free picker could silently break readability, and nothing can auto-test an arbitrary color.

## Skin (assets in `assets/ui/`)

| Surface | Asset |
|---|---|
| Menu | Full-bleed **pixel-art landscape** (one image pinned in Settings → My Art, or rotating per visit when set to Random), over a warm **70%** dim, with flat `#241C14` fallback. Layout (top to bottom): "Now Reading" spotlight (cover + Continue), search + All/Reading/Finished tabs, hover card strip, **book shelf**, compact action row. The whole stack fits a 1280x720 window (content min ~677px); re-measure if anything is added |
| Book shelf | **Wooden plank** `container_wood.png` nine-patch multiplied by the look's tint (the plank shipped untinted raw peach until 2026-10-09: the audit intended a tint but never issued the modulate), 208px with 20px top headroom so a hovered spine lifts from the plank instead of painting over the edge; books are code-drawn spines (hue hashed from the file path, sat 0.42 / **val 0.44**) with vertical titles, and the progress fill is added **before** the title so it sits under the letters; finished books get a 3px accent border; missing files are drawn **desaturated dark** (sat 0.10 / val 0.28) at 62% alpha rather than merely faded, so their titles stay readable |
| Hover card strip | **Flat wood** `#2E241A` + `#8A6A44` border, radius 8 — shows the hovered book's first sentence, progress, last-read time, and a Delete button (only while a book is on the card; the card lingers 0.3s so the mouse can reach it, and deletion asks first, saying exactly what happens to the file) |
| Dialogue box | `container_wood.png` (nine-patch, 30px margins, **app-generated 2026-10-09** by `scripts/generate_wood_texture.gd` — the pack panel was 12KB of near-flat peach that read as a washed-out smear; the replacement keeps the pack's exact average tone `#DD9A79` and dimensions so the measured claims hold) multiplied by the look's tint. Cream book text on raw peach measured **1.96:1**; the Cozy tint lands the box near `#8A5A40`, where cream clears 5:1. **Customizable in Settings**: Textbox Position (Bottom / Top), Textbox Style (Wooden box / Plain flat / Frameless floating text with high-contrast outline and drop shadow), Textbox Opacity (40–100%), and Textbox Height (160–400px). **Custom texture:** drop a PNG/JPG in the `My UI` folder and tick it in My Media (single-select, beats the built-in); it skins the reading textbox only and is **auto-dimmed** to whatever level keeps cream ink at 4.5:1+ against its average tone, so a bright or busy file reads as muted at worst, never unreadable |
| Full-screen overlays (settings / bookmarks / backlog / chapters / my media) | **Flat wood** `#2A2018` + `#8A6A44` border |
| Recent-list rows | **Flat wood** `#2E241A` + `#8A6A44` border |
| All buttons | **Flat wood-tone** StyleBoxFlat (`#3A2E22`, hover `#4A3A2C`, pressed `#2C2218`, radius 10, border `#8A6A44` at 3.2:1 — `#5A4632` was 1.8:1 and left the edge carried by the label alone) — primary buttons flat brick red `#9C3A2C` (hover `#B04536`, pressed `#7D2F24`) with cream text. *Never nine-patch the square button sprite into wide buttons — the grain smears into lumps (that's why the file dialog buttons looked broken too; they inherit the theme).* |
| Selected tab | Amber text **plus** a filled face (`#4A3A2C`) and a 2px amber edge. Font colour alone was a 1.84:1 shift, which fails as a state signal. |
| Checkboxes | `checkbox_checked/unchecked.png` (scaled to 26px) |
| Focus | One shared `focus` stylebox on Button / CheckBox / OptionButton / HSlider / LineEdit: `draw_center = false`, 2px look-accent outline, radius 11, 2px expand margin. The accent stays reserved for progress fill and this outline. |
| Next-arrow indicator | `arrow_brown.png` (scaled to 26px) |
| Sliders, text field, progress bar, top bar, nameplate | engine-drawn, tinted to the wood palette (the pack doesn't ship these). Slider groove is `#6B5638`: the old `#4A3826` was 1.4:1 against the panel, so the unfilled track was invisible. The grabber is still the engine default sprite — the pack ships none — which is the one "tinted to the palette" claim not held. |

**Retired textures (do not reuse):** `card_wood.png`, `button_red.png` (baked white decorations that read as glow), and `button_wood.png`/`container_plain.png` as stretched nine-patches on wide surfaces (grain smear). Files for the first two were deleted.

## Background pool (`assets/backgrounds/`, 45 images, scanned + lazy-loaded)

- Nature Landscapes Free Pixel Art, Free Sky with Clouds, and New Free Backgrounds parts 1–5 (all by free-game-assets). Pruned twice: the packs ship layer files and near-empty base layers that read as "no background" when picked.
- **2026-10-09 prune:** 15 more files moved out to `../adhdvnreader_removed_art/` (recoverable, not deleted) after a pixel audit of every image — 13 featureless colour washes (flat gradients, no clouds/moon/stars/horizon; one a solid purple rectangle) and 2 byte-identical duplicates (`nature_2_origbig` = `nature_2_orig`, `nature_8_1` = `nature_8_orig`). Pool went 60 → 45. Sky images that genuinely contain clouds, a moon, stars, a horizon, or a sunset were kept — they are real backdrops, not defects.
- **Do not judge a background by file size.** These are flat pixel-art scenes, so a legitimate sky image can be 5KB while a blank one is 2KB. The audit that works is decoded pixel content: unique-colour count plus luminance spread.
- The folder is scanned at startup; dropping any fully-opaque PNG/JPG in adds it to the rotation automatically. Pool entries are paths loaded on first use.
- **Background fit is a decision, not a fixed rule (2026-10-09):** Settings → Stimulation → Background fit offers **Auto / Always fill the screen / Always fit with border**. Auto: a landscape image whose aspect is within 15% of the window's and has at least half the window's pixels **covers** the screen (a sliver of edge is cropped — the owner wanted wide scenic pieces to fill); portrait or small images sit **framed** (`STRETCH_KEEP_ASPECT_CENTERED`). The darkened `STRETCH_SCALE` copy behind stays in every mode so a framed image's letterbox reads as a soft backdrop instead of flat bars. Portrait book illustrations from EPUBs were the case that made cropping the *default* wrong; Auto keeps them framed.
- Menu dim is 0.7 so even dark night scenes stay visible; dark starry nights are legitimate picks, not bugs.
- **The reader chooses per item.** Settings → My Art → "Choose Which Art To Use" opens the My Media screen: Backgrounds / Sprites / Sounds / Fonts / UI textures, each split into Built-in and My Own tabs, every item a thumbnail with a checkbox. Unticked never appears. New files default to ticked. Selections persist by filename. Fonts and UI textures are single-select (only one is ever active).

## Book folders

`My Backgrounds/ My Sprites/ My Sounds/ My Fonts/ My UI/` next to the exe are the drop-in art folders. **`My Books/`** (added 2026-10-09) is the drop-in library: every `.txt/.md/.docx/.pdf/.epub` in it appears on the shelf without using Open Document. The shelf mirrors the folder — delete the file and the book, its progress, and its generated cover leave with it. **`My UI/`** (added 2026-10-09) holds textbox textures: tick one in My Media and it skins the reading textbox (auto-dimmed to keep text readable; unticking everything restores the built-in panel).

Text on wood: cream `#F5EAD6` (secondary `#D9C9A8`). **Text on the wooden buttons and the dialogue box is cream, not dark** — `#3A2A18` on the `#3A2E22` button fill is 1.52:1, and dark ink is only used on the cream `LineEdit` field. The look's accent (amber `#E8A04C` in Cozy Wood) is for progress fill and focus outlines only. Radii: 8px controls, 12px dialogue box; nothing pill-shaped.

**Contrast is measured, not assumed.** Every pairing below was computed with the WCAG formula (2026-10-09): cream on the overlay `13.4`, on the hover strip `12.7`, on buttons `11.1`, on the primary red `5.8`, on the top bar `14.1`, on the nameplate `5.7`; `WOOD_INK_DIM` on those same surfaces `9.8 / 9.3 / 8.1 / 10.3 / 9.9`; amber text on the overlay `7.3`. Two pairings needed a code change to become true: the dialogue box (peach texture, was 1.96) and the menu labels (dim 0.5, was 2.2–3.1). **Since the Look system (2026-10-09), every look is vetted by `test_verification.gd` with the same formula on every surface** (cream ink 4.5:1+, accent and edge 3:1+ against the dark faces); adding or retinting a look means recomputing, never restating.

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

- **UI:** Cozy UI Pack (demo) by dobo_ui — https://dobo-ui.itch.io — *demo license: fine for personal use; buy the full pack before distributing the app.* Supplies the checkbox and arrow textures. The panel texture `container_wood.png` was replaced 2026-10-09 with an app-generated one (`scripts/generate_wood_texture.gd`, no external license needed); the original pack panel is archived in `../adhdvnreader_removed_art/`.
- **SFX:** lolurio Free Cozy Game UI SFX Pack by lolurio — https://lolurio.itch.io — CC BY 4.0, credit required (this file satisfies it; repeat in an About screen when one exists).
- **Reading font:** Atkinson Hyperlegible by the Braille Institute of America — https://brailleinstitute.org — SIL OFL 1.1, license file bundled (`assets/fonts/OFL-AtkinsonHyperlegible.txt`).
- **Display font:** Kaph by GGBotNet — SIL OFL 1.1, license file bundled (`assets/fonts/Kaph-License-OFL.txt`).
- **Backgrounds:** all by free-game-assets — https://free-game-assets.itch.io — Nature Landscapes Free Pixel Art, Free Sky with Clouds Pixel Art Set, and New Free Backgrounds parts 1–5. Free packs with attribution-style licenses (this file covers them); confirm the itch pages before sharing the app.
