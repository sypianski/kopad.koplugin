# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`kopad` is a **KOReader plugin** (pure Lua, AGPL-3.0) that turns a connected SDL3
gamepad into a reading controller: page-turning, menu navigation, and selecting
words or sentences for highlight / dictionary / AI lookup. Name = KO(Reader) +
(game)pad.

There is **no build step and no package manager**. Development is
edit-Lua → load into KOReader → observe. The repo *is* the plugin source. The
automated tests are `lua tests/padmap_test.lua` (pure remapping layer, plus the
padnav wiring), `lua tests/vkb_test.lua` (InputDialog keyboard patch),
`lua tests/padconfirm_test.lua` (button letters on confirmation dialogs),
`lua tests/padopen_test.lua` (opening every gamepad), `lua tests/wheel_test.lua` (wheel.lua: sectors, pages, stick
directions, glyphs, controller), `lua tests/selector_test.lua` (selector.lua
on a fake three-page document: moves, page crossing, ranges, levels,
highlights, point from-to) and `lua tests/kopad_hints_test.lua` (kopad_hints.lua: label
placement, prefix filter, B, lines from word boxes, the pointer's two
steps, word labels (letters first, three symbols past 21, 147-word window),
every arrow shortcut, RTL) and `lua tests/pdfwords_test.lua` (pdfwords.lua, plus the PDF overlay
on a fake three-page PDF in a zoomed, panned page view: screen boxes, moves
over page edges, sentences, point from-to, scan / reflow), `lua tests/pdfpara_test.lua` (pdfpara.lua: columns, paragraph heuristics), `lua tests/pdfhl_test.lua`
(highlights in PDF, TASK-31: X saves / removes through a stub ReaderHighlight /
ReaderAnnotation, Y browses the page's highlights, boxes under zoom / pan,
notes); `lua tests/statusbar_test.lua` (statusbar.lua: where the status bar fits, never over the text); `lua tests/pdftext_test.lua` (pdftext.lua: words split by glyph gaps); plain `assert`,
KOReader stubbed.

## Runtime requirements

**KOReader >= 2026.07 (stock, e.g. the Flatpak build): nothing else is needed.**
It has built-in gamepad support (`frontend/device/sdl/gamepad.lua` + `device.lua`)
and broadcasts `GamepadButtonDown` / `GamepadButtonUp` / `GamepadAxisMotion`
events; `padnav.lua` handles them itself. The old `sdl3_gamepad.patch` and the
`1-lstick-keys.lua` userpatch from `sypianski/koreader-konfig` are obsolete
there (the userpatch hooks internals that no longer exist).

Only **older builds** still need those two upstream pieces, and then `padnav.lua`
runs on the legacy key-event path (the `key_events` table):

1. **KOReader built with the SDL3 gamepad patch** (`sdl3_gamepad.patch`) — feeds
   gamepad buttons in as standard KOReader key names.
2. **The `1-lstick-keys.lua` userpatch** — splits the left analog stick into
   distinct `LStickUp/Down/Left/Right` key events. Without it, `padnav.lua`
   falls back to `Up/Down/Left/Right` (the `KP*2` bindings), which also carry
   the D-pad — so L-stick and D-pad become indistinguishable.

## Install / test loop

The plugin directory must be named `kopad.koplugin/` when deployed. Copy the
repo's `.lua` files into it, then drop it into KOReader's `plugins/` dir:

| Platform | Path |
|---|---|
| Linux (native) | `~/.config/koreader/plugins/` |
| Linux (Flatpak) | `~/.var/app/rocks.koreader.KOReader/config/koreader/plugins/` |

Restart KOReader, plug in a gamepad, enable via menu → *more tools* → *kopad* →
*Enable kopad*. Settings persist to KOReader's settings dir as `kopad.lua`
(`enabled` flag + the shared `padmap` remapping table; synced between devices
by koligilo) and `kopad_device.lua` (`padmap_layout`, device-local, never
synced). Debug via KOReader's `logger` output (`logger.warn`
calls in `main.lua`, `logger.dbg` elsewhere).

**Version.** `version` in `_meta.lua` (KOReader shows it in the plugin list) is
the only place the plugin keeps one; the family does the same (`keyreader`,
`vortpaf`). Bump it FIRST on every deploy to the devices (patch for ordinary
changes, minor for bigger ones), commit, push, then move koligilo's gallery
entry `sypianski/kopad.koplugin` to the pushed commit -- that is what reaches
the readers (Steam Deck included; its `plugins/kopad.koplugin` carries a
`.koligilo` marker): on this VPS, with the token from
`~/.local/share/koligilo/admin-token.txt`, `POST
http://127.0.0.1:7210/api/admin/gallery/updates/check`, then `POST
/api/admin/gallery/update {"repo":"sypianski/kopad.koplugin"}` (or the panel).
Each reader installs it on its next sync, after a confirmation on the reader
(PC-004 in koligilo). The Syncthing folder `~/modi/koreader/koplugins/` does
NOT reach the Deck. The `version = 1` of the `padmap`
data is a different thing: the data contract with koligilo.

## Architecture

Three-layer design. Understanding the split is the fastest way to be productive.

### `main.lua` — plugin shell (`WidgetContainer`)
Thin glue. On `init` it opens `LuaSettings`, then lazily loads two sub-modules
into `self.subs` via `safe_require` (pcall-wrapped so a failure warns instead of
crashing KOReader):
- `self.subs.nav` = `PadNav` (always)
- `self.subs.selector` = `Selector` (when `ui.rolling` or, since TASK-30,
  `ui.paging` exists; `paged = true` for PDF / DjVu — created lazily in
  `_ensure_selector`, retried on `onReaderReady`).

The main-menu toggle flips `self.enabled` and calls
`nav:_suppress_reader_keys()` / `nav:restore_reader_keys()`. Sub-modules
contribute menu entries via an optional `getMenuItems()` method that
`addToMainMenu` collects reflectively.

`self.subs.keyhints` = `keyhints.lua` (plain module, global state): `apply()` /
`restore()` hide / put back KOReader's Q-W-E-R-T-Y shortcut letter labels on
file browser items by `rawset`-ing `BookList.is_enable_shortcut`; main.lua calls
it via `_sync_key_hints()` from `init` and the toggle (idempotent, pcall-guarded).

### `padnav.lua` — event router (`InputContainer`, `PadNav`)
Owns all gamepad `key_events` bindings and the **key-suppression** mechanism.
It inserts itself at the front of `ui.active_widgets` so it sees events first,
then *removes* conflicting bindings (`MoveUp`, `GotoNextView`, any `Press`
binding, …) from every reader module (`ui.rolling`, `ui.paging`, `ui.view`,
footer, highlight, bookmark, and every active widget) — saving them in
`_saved_keys` for restore on disable. This is why toggling the plugin, or
`onReaderReady` re-applying suppression, matters: KOReader modules set their
`key_events` at different lifecycle points.

**Context is the core rule (TASK-7): menus and reading have separate controls.**
`PadNav:_context()` classifies the topmost non-toast window of
`UIManager._window_stack`: `off`, `foreign` (another family overlay owns
`_kokb_overlay`; a text dialog on top -- `text_dialog(true)`, also found under
the on-screen keyboard -- is `window` even then, for dictation), `reading` / `paged` / `filemanager` (the top window IS
`self.ui`), `selection` (kopad's own overlay), `wheel` (a ButtonDialog drawn by `wheel.lua`,
checked before `foreign`), `dict` (a DictQuickLookup, found
via `DictQuickLookup.window_list` — the class has no `name` field), `top_menu`
(a TouchMenu in the top window) or `window` (anything else: TOC, bookmarks,
history, ConfigDialog, dialogs, …). It is a positive rule on purpose:
`Pluginaro.is_modal_active()` only checks the class of the top window, and
KOReader wraps the top menu, the TOC and the bookmark list in a
`CenterContainer`, so the pad used to drive the page under an open menu.
`_button_down` / `_trigger_event` / `onGamepadAxisMotion` dispatch on the
context first (`_menu_button`, `_menu_trigger`, `_dict_button`,
`_filemanager_button`); outside the reading contexts the pad is stock KOReader
plus those few additions. Unknown windows fall into `window`, i.e. stock — new
code must keep it that way. Tests: section 11 of `tests/padmap_test.lua` builds
real window stacks (`CenterContainer{TouchMenu}`, `CenterContainer{Menu}`).

Every `on<Key>` handler first checks `_is_enabled()` (true only in the
`PAD_CONTEXTS`: reading, paged, selection, filemanager — so the legacy key path
stands down in menus too). Handlers
branch on whether `selector.overlay` exists and which `mode` it's in, then
delegate to overlay methods (`step` / `line` for the arrows, `to_words` /
`to_sentences` for the R-stick, `action_menu`). Reading-mode-only state:
`_x_mode` (X button acts as a modifier for D-pad/shoulder combos: menu / footer
/ history / files / TOC / bookmarks; only in a document, dropped by
`_drop_x_mode` whenever the pad is used in any other context). RTL languages
flip horizontal directions via `_is_rtl()` (in `_sel_move`, once).

**Holds (TASK-16, Gamepad* path only).** `onGamepadButtonUp` (relayed by
main.lua, remapped through padmap like the press) ends five holds. The rule
(TASK-28): a letter held + D-pad = a mode, a tapped letter = its action, so
A, Y and B act on the RELEASE, and only when no D-pad came in between.
- **A**: `_press_a` sets `_a_down` (and `_a_reading` when pressed while
  reading); nothing happens on the press. While it is set, `_dpad` opens the
  words (reading; `_a_opened`) and `_sel_move` / `_trigger_page` pass
  `range = true` (the overlay keeps an anchor) and mark `_a_moved` -- but
  NOT for the A hold that opened the words (`_a_opened`): while that one is
  held the arrows only move the cursor, so the start point (or a single word)
  can be picked; a range needs the next A hold. `_release_a` acts only for a
  tap: reading = "point from-to" (`_open_point_select` ->
  `Selector:_open_point`, TASK-29; a page without text = a message; also
  in context `paged`, TASK-30),
  selection = action menu. The legacy `Press` key goes to `onKPConfirm`
  (sentences / menu on the press; the legacy path has no point from-to).
- **Point from-to (TASK-29)**: while the overlay is in mode `point` (context
  `selection`), `_button_dispatch` hands D-pad + A/B/X/Y to `_point_button`
  BEFORE everything else (`POINT_SYMBOLS`): one symbol per press, on the
  press, so it clears the A / Y / B holds (their release then does nothing)
  and starts no `_dpad_start` repeat. `ov:point_press(sym) == "cancel"` (B
  with nothing typed on the sentence labels) closes the overlay. Other buttons,
  triggers and sticks take the selection's path; the overlay ignores
  `step` / `line` / `para` / `action_menu` / `to_words` / `to_sentences`
  in mode `point`. The D-pad arrows are label symbols on the sentence
  labels and the shortcuts on the word labels (TASK-36, PC-023: kopad_hints
  decides). The R-stick there (`_rstick`, both input paths) is consumed and
  does nothing (the TASK-35 refinement is gone).
- **Y**: `_press_y` = Vortuyo at once in the selection; while reading it sets
  `_y_down`, `_dpad` then opens the sentences (`Selector:_open(from_end)`,
  `_y_used`), and `_release_y` shows the highlights for a tap. Legacy:
  `onKPMenu` on the press.
- **B** (TASK-33): `_press_b` closes the selection at once; while reading
  (EPUB, or `_paged_idle()`) it sets `_b_down`, and B + D-pad
  (`_view_dpad`, branch in `_button_dispatch` before the paged pan and the
  EPUB page turn) changes the view: PDF / DjVu zoom ↑/↓ (`_zoom_step`) and fit
  ←/→ (`ZOOM_DPAD`), EPUB font ↑/↓ (`IncreaseFontSize` / `DecreaseFontSize`
  with 1) and margins ←/→ (`_margins_step`: `configurable.h_page_margins`
  ±`MARGIN_STEP`, clamped 0..`MARGIN_MAX`, `SetPageHorizMargins`). Repeated by
  `_dpad_start` (EPUB at the fixed `VIEW_REPEAT_S`). `_release_b` goes back
  (`onKPBack`) only for a tap. B + D-pad is the ONLY zoom on the pad in a
  PDF (the A + D-pad zoom, `_a_zoom`, was removed in TASK-30).
- **A / Y in a PDF / DjVu (TASK-30)**: the paged selector is hidden from
  `PadNav:_selector()` while no overlay is open (`selector.paged`;
  `_any_selector()` sees it), so the idle paged pad keeps its view controls
  and every "no selector -> pass" branch. In `_button_dispatch` (after the
  B + D-pad branch, before the paged pan) A / Y in `_paged_idle()` only set
  `_a_down` (+ `_a_reading`) / `_y_down`; A / Y held + D-pad ->
  `_paged_select(btn)` (`Selector:_open_walk` / `_open`, from the first
  word on the screen for →/↓, the last for ←/↑; `false, "no_text" |
  "reflow"` -> `no_select_text` message). A tap -> `_release_a` ->
  `_open_point_select` (both use `_any_selector`). Y tap -> `_release_y`
  (context `paged` as well as `reading`, `_any_selector`) ->
  `PadNav:_open_highlights` = the page's highlights (TASK-31; none = "No
  highlights on this page", reflow = `no_select_text`). The `highlights`
  action reaches the hidden paged selector too. Once the overlay is open the context is `selection`
  and everything is the EPUB path; `PadNav:_turn_page` (LB / RB in the
  selection) turns a whole page there (`_paged_page`).
- **X**: `_button_down` wraps `_button_dispatch`; a press that arms `_x_mode`
  records its role in `_x_hold`, and its release clears the modifier.
  `_x_combo` keeps the modifier armed while `_x_hold` is set. A trigger acting
  as a button (`_trigger_as_button`, no release) and the legacy key path keep
  the latch.
- **D-pad**: in an EPUB (reading / selection) `_button_dispatch` calls the
  `KPUp2`.. handlers itself and, in the selection, `_dpad_start` repeats the
  step via `UIManager:scheduleIn` (`DPAD_REPEAT_*`) until the release, a context
  other than `selection`, or `DPAD_REPEAT_MAX`. X combos, page turns and the
  press that opened the selection are not repeated. While reading without a
  held letter `_dpad` turns the page (`GotoViewRel`, ←/→ mirrored for RTL),
  on the legacy key path too. The interval shrinks after `DPAD_ACCEL_AFTER` repeats (`dpad_interval`,
  TASK-25) down to `DPAD_REPEAT_MIN_S`.

In the selection LB / RB close it and turn the page (`_turn_page`, in
`_button_dispatch`); `onKPPgBk` / `onKPPgFwd` with an overlay are reached only
from the legacy key path, where they step the range (`step(±1, true)`).
LT / RT (`onKPPgBk2` / `onKPPgFwd2` -> `_trigger_page`) jump by paragraph in
the selection (`Selector:para`, TASK-25) and turn the page otherwise; in
context `selection` `_trigger_event` lets the stock trigger auto-repeat
through (`held`), everywhere else it stays filtered.
While reading, the L-stick is consumed and does nothing (TASK-12 / TASK-15).

**Quick-action wheel (TASK-26, PC-021).** The R-stick in context `reading`,
`paged` and `filemanager` (`onGamepadAxisMotion`, before the menu branch) calls
`_quick_stick`: it opens a `ButtonDialog` of the `quick` set (`reading` /
`files`, from `self._padmap.quick`, built by `padmap.build_quick`) in
`QUICK_DIRS` order with empty directions left out, flagged
`_kopad_force_wheel` + `_kopad_stick = "right"` so wheel.lua always converts it
and aims at the pushed direction. Each button: label from `ACTION_LABELS`,
`kopad_glyph` from `ACTION_GLYPHS`, `kopad_hint` (reading only) from
`_quick_hint` (the role whose effective action it is, B = `back_location`,
else `X_COMBO_HINTS`); its callback closes the dialog, then `_run_action`.
Title = `_quick_title` (chapter · page n / m · time · battery; file browser:
time · battery). One action = run at once, none = nothing; X modifier armed =
nothing. The dialog's `onCloseWidget` is wrapped to call `_quick_rearm`: while
`Gamepad.held_axis_directions` still holds axis 2 or 3, `_quick_blocked` eats
the R-stick (the stock auto-repeat would reopen the wheel at once). This
replaced the PDF R-stick zoom (zoom = B held + D-pad since TASK-30). Tests: section 16 of
`tests/padmap_test.lua`.

### `padmap.lua` — button remapping (pure, PC-011)
No KOReader dependencies. `build(padmap, layout, warn)` turns the shared
`padmap` value (`{version=1, layouts={<xbox|playstation|nintendo|valve>={<physical>=<role>}}, actions={<role>=<action>}, quick={<reading|files>={<direction>=<action>}}}`,
overrides on top of the layout's built-in default) plus the device's layout into
a lookup table; `resolve(tbl, kind, id)` maps a physical SDL button/trigger to
the logical role id. **Role-level actions (PC-014):** `res.actions` (`build_actions`)
is a second stage AFTER the layout — role → reading action from the closed list
`M.ACTION_ORDER` (52 ids: `next_page`, `next_chapter`, `top_menu`, `toc`, `zoom_in`,
`sentence_select`, `night_mode`, `x_modifier`, `none`, …; each needs a runner in
`ACTION_RUNNERS` and a label in `ACTION_LABELS`, checked by the test), keyed by role so it is shared by every layout; values equal to
`M.DEFAULT_ACTIONS` are dropped so the built-in handler (and its pass-through in
paged documents) is untouched. `padnav.lua` applies it in `_button_down` /
`_trigger_event` via `_override_action(role)` — only in the idle reading context
(`_context()` = `reading` / `paged`, no selection overlay, no X-combo; never in
menus, dialogs, the dictionary popup or the FileManager) — and runs it from `ACTION_RUNNERS`. Elsewhere the
role's `on<Key>` handler runs unchanged. Actions are part of the vocabulary
contract with koligilo (`padmap.go`/`web/padmap.js`, TASK-27 there). Malformed data → `warn` + skip, never raises; no data =
identity. `main.lua:_apply_padmap()` builds it (init, `onReaderReady`,
`onResume`, layout menu) and calls `nav:set_padmap()`; `PadNav:onGamepadButtonDown`
/ `onGamepadAxisMotion` resolve first, then `_button_down` / `_trigger_event` /
`_trigger_as_button` run on roles. Legacy `key_events` path is not remapped.
**Quick-action wheel (PC-021):** `res.quick` (`build_quick`) always holds both
sets (`M.QUICK_SETS`): a set in the data replaces `M.DEFAULT_QUICK[set]` whole
(missing direction = empty, `none` dropped), a missing or broken set is the
default. Directions `M.QUICK_DIRS` (clockwise from `up`); `x_modifier` never,
`files` only `M.QUICK_FILES_ACTIONS` (`quick_allowed`). Contract with koligilo
(`padmapQuick*` in `padmap.go`, `QUICK_*` in `web/padmap.js`).
The vocabulary (physical names, roles, layouts, actions) is a contract with koligilo's
panel editor (TASK-25 there) — change both sides together. Layout ids are a
closed list kept in `M.LAYOUTS` / `M.LAYOUT_ORDER` (`xbox`, `playstation`,
`nintendo`, `valve`; `valve` = Steam Deck / Steam Controller was added in
PC-013 / koligilo TASK-26, appended last) plus the menu labels in
`main.lua:_layout_menu()`. `xbox`, `playstation` and `valve` have identity
defaults; `nintendo` swaps A/B and X/Y. Layout data for an id the
installed kopad does not know (e.g. `valve` on an older kopad) is ignored with a
warning, so deployment order across devices does not matter.
The Deck back paddles (L4/L5/R4/R5, SDL ids 16+) are deliberately NOT in the
physical vocabulary: KOReader >= 2026.07 does not deliver them (see the header
of `padnav.lua`).

### `wheel.lua` — ButtonDialogs as a radial menu (TASK-19)
`main.lua:_install_wheel()` calls `Wheel.install(state_fn)`, which wraps
`ButtonDialog.init` ONCE per KOReader run (only when `device/sdl/gamepad` loads,
i.e. the >= 2026.07 path); `state_fn` (= kopad enabled + device setting
`wheel_dialogs`, default on, in `kopad_device.lua`) is replaced by every kopad
instance. After the stock init, `maybe_convert` turns an eligible dialog (exact
class `ButtonDialog`, no `_added_widgets`, 2..`MAX_ITEMS` = 16 text buttons, one
enabled) into a wheel: it replaces only `self[1]` and `self.movable` (a `Panel`
widget whose `dimen` stock `onShow` / `onCloseWidget` / `getContentSize` use)
and installs instance overrides (`onTapClose`, `onFocusMove`, `onPress`,
`onHold`, `onShow`, `onCloseWidget`) that fall back to the class methods when
the dialog is not a wheel (a reinit that added widgets). The dialog object stays
the same, so callbacks doing `UIManager:close(dlg)` / `dlg:reinit()` work; a
reinit keeps the selection (`prev`). The controller is `dlg._kopad_wheel`
(`Ctl`: `point`, `rotate`, `page_step`, `activate(hold)`, `close`, `stick`,
`aim`, `tap`). Dialog fields kopad sets for its quick-action wheel (TASK-26):
`_kopad_force_wheel` (convert even with `wheel_dialogs` off), `_kopad_stick`
(`Ctl:aim`: select the held direction at once, then follow the stick); button
entries may carry `kopad_glyph` and `kopad_hint` (a line under the hub label). As many sectors as buttons on the page (TASK-20: `angle_of`, 0 = up,
clockwise; at most 8, more buttons → pages, `paginate`); the stick's 8
directions, taps and painting all go through `nearest` / `page_items`. Look
(TASK-20, chosen in the /ux selector): no frame, a white disc, the selected
sector black and popped out by R/12, its label in the hub (r0 = R/2), the title
and the A / B / X / LB RB buttons in pills (taps outside them and the disc
close). No title → `M.snippet_title` of `dlg._kopad_snippet` (selector.lua's
action menu) or of `M._pending_snippet`, set around ReaderHighlight's
`onShowHighlightMenu` / `showHighlightDialog` (wrapped once in `install`). Sticks: KOReader broadcasts an axis only when it crosses the dead
zone, never its angle or the release, so `Ctl:stick` polls
`Gamepad.held_axis_directions` every `POLL_S` while the stick is pushed and a
direction counts after `STABLE_S` (diagonal snap-back). Glyphs: `GLYPHS` maps
KOReader msgids to Font Awesome 4 code points of the bundled
`fonts/nerdfonts/symbols.ttf` (exact translated label first, then English words,
else the label's first letter). The top half of the file is pure Lua (tested);
KOReader modules are required lazily. padnav: context `"wheel"` (top window has
`_kopad_wheel`) is checked BEFORE `"foreign"` and routes everything through
`_wheel_button` / `_wheel_call`; every pad event is consumed there.

### `kopad_hints.lua` — "point from-to" labels (pure, TASK-29, sentences TASK-35, words TASK-36)
No KOReader dependencies; tested by `tests/kopad_hints_test.lua`. Port of the
Vivaldi-on-the-Deck labels (`~/aparati/steamdeck/vivaldi-deck/ext/hints.js`):
`M.DIRS` = eight symbols (`up down left right` + `A B X Y`) with anchors in a
region (left half D-pad, right half the letter diamond: Y top, A bottom, X
left, B right). `M.assign(points, first)` = the hints.js tree split (`split`:
one group per anchor, at most `cap` each, most obvious items first by regret,
ties in reading order), always TWO levels -> every label is two symbols (a
lone item repeats its symbol: `up,up`). Coordinates are snapped to
1/`M.GRID` of the region, so an indent does not reorder a column. Labels
never START with `M.BACK` = B (`M.FIRST`), because B with nothing typed is
back / one word -> at most 7 * 8 = 56 targets, the rest get no label.
**Word labels (TASK-36, PC-023)**: `M.word_labels(n)` = labels for n words
in READING order (not by position: the A / X / Y anchors all sit on the
right half, a position split would scatter a sentence's neighbours and could
not keep letters first): contiguous blocks Y, X, A (`M.WORD_FIRST`), each
split again into contiguous sub-blocks; on every position the symbols are
letters before arrows (`M.WORD_SYMBOLS` = Y X A ↑ ← → ↓, the parent letter
first, so a block's first word doubles it: `YY`), as few children as keep the
letters. Never B, never an arrow first (a lone arrow is a shortcut). Two
symbols up to `M.WORD_MAX2` = 21, three up to `M.WORD_MAX3` = 147 (all labels
of that sentence then have three).
**The pointer is document-independent** (TASK-35, TASK-36 / PC-023):
`M.Pointer.new(sentences, boxes, {rtl})` with `sentences = { {first, last,
para}, ... }` (word indices, reading order; `para` compared with `==`, nil =
its own paragraph) and `boxes[i]` = word i's SCREEN box or false (off the
screen). Only visible words count: a sentence over the page edge / out of a
zoomed view is labelled at its visible part, one without a visible word gets
no label. Step `start`, level `sentence`: `M.assign` labels left of each
sentence's first visible word (right in RTL); a label returns `sentence` =
level `word`: `M.word_labels` over that sentence's visible words (side
`top`, centred on the word's top edge), a word label = `start`. Lone arrows
on the word level (`_shortcut`, nothing typed; ← / → swapped in RTL): start
step ← = the sentence's first word, ↑ = the first visible word of its
paragraph (the run of sentences with equal `para`), → / ↓ ignored. Step
`end` begins at once on level `word` with E = `self.sent` = the start
sentence (from the start word on): a label / ← (end of E) / ↓ (end of E's
paragraph) = `done`; → = the next sentence with a visible word (`sentence`;
none = `ignored`: a range stays on the page), ↑ = the previous one, never
before `start_sent`. `preview()` = start .. last visible word of E (what
selector.lua inverts). `typed` is a list (three-symbol prefixes); `press(sym)`
-> `prefix` / `unprefix` (B drops the LAST symbol when no label goes on with
B) / `sentence` / `back` (B on the start step's word labels) / `start` /
`done` (`self.start`, `self.stop` = WORD indices; stop nil = B in the end
step = one word) / `cancel` (B on the sentence labels) / `ignored`. More than
147 words: a window of the first 147 (end step: from the start word).
`visible()` = the labels to draw (only those continuing the typed prefix;
`sent`, `word`, `typed` = count, `side`, anchor `x`, `y`, word height `h`).
The R-stick refinement of TASK-35 (`refine_to_word`) is gone.
`M.lines_from_boxes(boxes)` (word boxes -> lines `{ x, y, w, h, first, last
}`) draws the end step's preview. The adapter is
`SelectorOverlay:_point_begin`, the same for EPUB and PDF:
`_point_sentences()` turns `self.word_to_sent` into the word ranges plus
`para` (paginmapo sentences' block xpointer in an EPUB, `pdfwords.sentences`
/ pdfpara in a PDF), the boxes are the words' `sbox`;
`PagedOverlay:_point_begin` refreshes the screen boxes first, so only what is
on the screen gets labels.

### `vkb.lua` — no on-screen keyboard while a pad is connected
`main.lua:_install_vkb()` calls `Vkb.install(state_fn)` (state = kopad
enabled), which wraps `InputDialog.init` ONCE per run (`ID._kopad_stock_init`;
`MultiInputDialog:init` calls it too). On a first init (not a reinit) of an
editable dialog, when kopad is enabled and SDL reports a connected gamepad, it
sets what stock sets for a physical keyboard with `virtual_keyboard_enabled`
off: `keyboard_visible = false`, `skip_first_show_keyboard = true`. Tapping the
field or the dialog's ⌨ toggle still opens the keyboard. The focus is the
second way in: on a D-pad device stock `InputText:onFocus` (FocusManager, the
D-pad / L-stick back onto the field) calls `onShowKeyboard()`, in a
MultiInputDialog through `onSwitchFocus`. `M.wrap_focus` replaces
`InputText.onFocus`: while `quiet_focus` (dialog qualifies, keyboard not up
already) it only focuses the field (`onSwitchFocus` with
`skip_first_show_keyboard` set for the call). `InputText.initInputEvents()`
redefines `onFocus`, so the wrapper is re-checked on every `InputDialog.init`.
The third keyboard is Steam's: `InputText:focus()` -> `Device:startTextInput()`
= `SDL_StartTextInput`, which SDL3 on a Steam Deck turns into
`steam://open/keyboard` (visible in Steam's `logs/console_log.txt`). While it
is up Steam drives the pad with its "Keyboard" action set (RT = press the key
under the right trackpad, B / hide = Back -> the dialog closes), kopad gets
nothing useful. `M.wrap_text_input` wraps `Device.startTextInput` once and
sets the SDL hint `SDL_ENABLE_SCREEN_KEYBOARD` = `"0"` before every start in
`pad_mode()` (kopad enabled + pad), `SDL_ResetHint` (cdef'd here) otherwise;
SDL text input itself stays on, so a physical keyboard still types. Pad check:
`SDL_GetJoysticks` + `SDL_IsGamepad` through `require("ffi/SDL3").SDL`, only
when `Device:isSDL()` — not ffi/SDL3's `S.controller`, which stays stale after
the last pad is unplugged. Text input with a pad: RT held = dictation, X =
backspace, A = accept (`_text_field_button`, `_dictate_hold`). Test:
`lua tests/vkb_test.lua`. Related: TASK-34 (kopad off without a pad).

### `padconfirm.lua` — A / B / X / Y on confirmation dialogs
`main.lua:_install_confirm()` (after `_install_vkb`, so it wraps vkb's
`InputDialog.init`) calls `PadConfirm.install(state_fn, warn)`, which wraps
`init` ONCE per run (`_kopad_confirm_init`) of the classes in `M.SPECS`
(`ConfirmBox`, `MultiConfirmBox`, `SpinWidget`, `DoubleSpinWidget`,
`DateTimeWidget`, `RadioButtonWidget`) and of `InputDialog`. On the first init
of a dialog (kopad enabled + `vkb.pad_connected()`), it prefixes the instance
texts with the letter: `ok_text` = A, `cancel_text` = B. Prefix = `Ⓐ Ⓑ Ⓧ Ⓨ` + space
when `glyph_check` (once per run, `M.circled`) finds all four in `cfont` or
`Font.fallbacks` (the `RenderText:getGlyph` lookup), else `"A · "`.
MultiConfirmBox goes by content (`multi_spec`, user decision 2026-11-03): the
choice whose translated text is in `M.PRIMARY` (or whose partner is in
`M.SECONDARY`) = A, the other = X; no main choice (Default / Fallback, unknown
texts) = X left, Y right, no A. `*_text_func` is read and wrapped; disabled
choices and `no_ok_button` are not labelled. InputDialog: the caller's
`buttons` rows are COPIED, then the `is_enter_default` button = A and the
first `_("Cancel")` / `_("Close")` = B. `dlg._kopad_confirm` = the letters set
(also the reinit guard). padnav `_confirm_button` (context `window`, after
`_diktonoti_route` and `_text_field_button`): A = `press(dlg, "A")` unless
`focus_shown(dlg)` (any `frame` / `_frame` / `image` with `invert == true`: on a
touch device the initial FocusManager focus is not painted, so painted = the
user moved it -> stock press of the highlighted thing); Start = A always;
B / X / Y = their buttons. `press` finds the Button by its label prefix in the
widget tree (array children only) and runs its `callback`; a disabled button
is consumed without action. Why: stock A pressed the unpainted focus at
x = 1, y = 1, which in a ConfirmBox is Cancel. Not covered (no OK/Cancel pair
or no need): TextViewer and InfoMessage (B closes), FrontLight /
NaturalLight, SkimTo, SortWidget, PathChooser, KeyboardLayoutDialog,
ButtonDialog (wheel.lua). diktonoti's label line describes only RT and X
(A / B are on the buttons). Tests: `lua tests/padconfirm_test.lua`, section 17 of `tests/padmap_test.lua`.

### `padopen.lua` — every connected gamepad, not only the first
koreader-base's `openGameController` (ffi/SDL3.lua) opens ONE gamepad (the
first `SDL_IsGamepad` joystick, then `break`), and SDL sends events only for
opened gamepads. On the Deck started from Steam, Steam's virtual pad (the
built-in controller) comes first and a Bluetooth pad Steam Input does not
manage (8BitDo Ultimate 2C, 2dc8:301b) was never opened = dead.
`main.lua:_install_padopen()` calls `PadOpen.start(state_fn, log)`: one poll
per run (`POLL_S` = 3 s, SDL only via `vkb.is_sdl`; KOReader passes nothing on
`SDL_EVENT_GAMEPAD_ADDED` up to Lua) that, while kopad is enabled, opens
every gamepad not opened yet (`scan(api)`, pure; SDL refcounts opens).
Handles live in `M.handles` by joystick id WITHOUT `ffi.gc`: before a fork
KOReader quits the gamepad subsystem, which closes all gamepads, so a
finalizer would close a freed handle; a gone pad is closed only when
`SDL_GetGamepadFromID` (cdef'd here, missing from koreader-base's SDL3_h)
still returns our handle. Test: `lua tests/padopen_test.lua`.

### `kopad_trace.lua` — optional diagnostic trace
Zero-dependency logger (`Trace.log/active/begin_event/end_event`, always pcall-guarded); writes `<settings dir>/kopad-trace.log` ONLY while the flag file `<settings dir>/kopad-trace` exists (cached ~2 s; capped ~256 KB, ~20 lines/s, axis repeats collapsed). `main.lua` and `padnav.lua` load it via `pcall(require, "kopad_trace")` with a no-op stub fallback; trace points never alter return values. Named `kopad_trace` (not `trace`) to avoid `package.loaded` collisions.

### `pdftext.lua` — words split by the gap between glyphs (TASK-37 tests it on more PDFs)
`document:getTextBoxes(page)` is koreader-base `page:getPageText()`, which cuts
words ONLY at space characters. A PDF whose text layer has none (TeX / Typst
output, e.g. papeteria's PDFs) has the word gap only as a gap between glyph
positions, and mupdf's own synthetic space starts at ~0.15 em; a squeezed
justified line (gap ~0.13 em) came out as ONE "word" -- one box, no spaces --
and A + D-pad could select nothing smaller than the line. `M.install(doc,
state_fn, warn)` (main.lua `_install_pdftext`, from `onReaderReady`, paging
documents only) replaces `getPageText` on the mupdf page class ONCE per run:
a copy of the stock function whose word loop (`M.split_line`, pure, over plain
chars) also breaks where the gap along the line exceeds `M.GAP_EM` = 0.10 em
of the larger glyph (calibrated on 7 000 glyph pairs of one Alegreya PDF:
inside words <= 0.066 em, between words >= 0.125 em). It must sit THERE and
not in pdfwords.lua: saving a selection goes through `getTextFromPositions`,
which takes the word boundaries from the same boxes, so kopad and KOReader
have to see the same words (a touch selection benefits too). Everything else
is stock: the same whitespace / bullet / CJK / General Punctuation rules (so
`”,` still splits into two words, as in KOReader). `state_fn` is asked on every
call (kopad off = stock), a failing adapter warns once and falls back to the
original for the rest of the run; non-mupdf documents (DjVu) and bare Lua get
`false`. Text boxes already in KOReader's DocCache keep their old words until
the document is reopened. Not tried in KOReader yet; `GAP_EM` is known on one
font only (TASK-37).

### `pdfpara.lua` — paragraphs of a PDF / DjVu page (pure, TASK-32)
No KOReader dependency; tested by `tests/pdfpara_test.lua`. PDF knows no
paragraphs, so they are guessed from the line rectangles of
`document:getTextBoxes(page)`. `paragraphs(lines, {rtl}) -> paras, info`
(`paras[n] = {first, last, lines}`; `info.order` = input line indices in
reading order, `info.para_of[line]`, `info.col_of`, `info.ncols`, `info.gap`);
`columns(lines, opts)` finds one or two columns (a gutter, full-width lines
such as titles stay between the bands). A new paragraph starts at a line
after: a different line height, a list marker, a larger line pitch than the
typical one, a first-line indent, or a short previous line that ends a
sentence; thresholds are fractions of the median line height / column width
(`M.OPTS`). Between two columns the pitch rule is off, so a paragraph may run
from the bottom of the left column to the top of the right one. Wired in by
`pdfwords.lua` (below): `sentences[].para` is what selector.lua's
`_para_target` / `_para_start` compare, so ↑/↓ in sentences and LT / RT (words
and sentences) use it unchanged.

### `pdfwords.lua` — word source for PDF / DjVu (pure, TASK-30)
No KOReader dependency (paginmapo only); tested by `tests/pdfwords_test.lua`.
`words_from_boxes(document:getTextBoxes(page), page)` -> word items `{text,
page, idx, line, pos0 = pos1 = xp0 = xp1 = "pdf/<page>/<idx>", pbox (native
page box: word x, LINE y / h), cx, cy (centre of the word's own box),
sent_end}`; the overlay adds `sbox` (screen). `ends_sentence(text, next)`
is paginmapo's rule on the word's own end (`!?؟۔` always, `.` before an
uppercase word) -- a COPY, because paginmapo's `is_sent_boundary` is local;
keep the two in step. `sentences(words)` groups through paginmapo's
`collect_sentences_from_words` (vendored, unchanged) and adds `first` /
`last` word indices and `para` (= the paragraph of the sentence's first
word, TASK-32). `words_from_boxes(boxes, page[, {rtl, info}])` returns
`words, info`: the words come out in READING order (a two-column page: the
left column before the right one, `info.order`) and carry `para`;
`paragraph_info(boxes, rtl)` is the pcall-guarded pdfpara call (PagedOverlay
caches it per page in `_pinfo`, next to `_boxes`, and passes `is_rtl`).
Also `has_text` (a scan's optical boxes have no
`word`), `line_target` (↑/↓: nearest word by centre x on the next line of
the engine's line order), `line_boxes(words, i0, i1[, field])` (one box per
line), `pos(w, view.state)` = `{page, x, y, zoom, rotation}` at the word's
centre, which `getTextFromPositions` snaps to exactly that word (what
PagedOverlay passes to `saveHighlight` as pos0 / pos1, TASK-31).

### `selector.lua` — stateful overlay widget (`SelectorOverlay` + `Selector`)
The visual selection engine. `Selector` is the factory/lifecycle wrapper
(`_open` = sentences, `_open_walk(from_end)` = words, `_open_highlights` =
saved highlights or `false` when the page has none, `_open_point` = point
from-to or `false` when the page has no text, `_close`; all share
`_new_overlay`, which holds the pluginaro claim); `SelectorOverlay` is the
painted widget with a single `self.mode` state machine (no crosshair any more:
removed in TASK-15; the padmap id `crosshair` stays as an alias of
`word_walk`). In a PDF / DjVu (`ui.paging`; main.lua creates the selector
with `paged = true`) `_new_overlay` makes a **`PagedOverlay`**
(`SelectorOverlay:extend`, TASK-30) instead, or returns `nil, "reflow"`
(`text_wrap == 1` / `is_reflowable`); the openers return `false, "no_text"`
for a page without words (`Selector:_no_text`). PagedOverlay replaces only
the crengine-specific methods: `_collect` (one page, `self.page` = the top
page in continuous view; `_extends_before/after` decided with the
neighbouring page's first / last word), `_ww_step` / `_ww_line` / `_ww_land`
/ `_ww_word_from_xp` / `_xp_before` (word index on the page), `_turn_page`
(`GotoPage`), `_get_selection` (`getTextFromPositions`, pboxes native,
sboxes screen), `_draw_walk` / `_draw_struct`, `_page_text`, and the
highlights (TASK-31, below). Screen boxes
(`word.sbox`, `{x, y, w, h}` or nil off the screen) come from
`view:pageToScreenTransform` and are recomputed on every paint and every
move (`_screen_boxes`), never cached; `_refresh` first pans an off-screen
cursor into view (`_reveal`: `PanningUpdate` in page view,
`onScrollPanRel` in continuous view). Sentences, paragraphs, levels, point
from-to and the dictionary / Vortuyo / AI / copy actions are the base
class's. One page at a time; a range never leaves it:

**Highlights in PDF / DjVu (TASK-31, PagedOverlay).** Saved the way a finger
selection is: `_save_highlight` sets `ui.highlight.selected_text = {text,
pos0, pos1, pboxes}` (pos = copies of `PdfWords.pos`, `{page, x, y, zoom,
rotation}` native) and calls `saveHighlight()`, which builds the stock item
(`page`, `pboxes`, the user's `saved_drawer` / `saved_color`, chapter),
writes it into the PDF when "write highlights into PDF" is on, files it with
`annotation:addItem` (the sidecar -> still there after reopening) and sends
`AnnotationsModified`; the previous `selected_text` is put back.
`_collect_highlights` walks `ui.annotation.annotations` (index = annotation
index, what `deleteHighlight` takes): every item with a `drawer` (bookmarks
have none) whose `pos0.page .. pos1.page` covers `self.page`; a multi-page one
(`ext`) contributes its piece on the page (`getSavedExtendedHighlightPage`,
else `ext[page]`). Native boxes from `doc:getPageBoxesFromPositions` (what
ReaderView draws; else the stored `pboxes`), sorted top to bottom; screen
boxes (`item.boxes`, `item.sbox` = top one or nil) are recomputed in
`_screen_boxes` with the words'. Mode `hl`: `_get_selection` = the stored
text / positions + `hl_index` / `hl_ann`; `_cursor_word` = the top box, so a
step pans an off-screen highlight into view; `_draw_struct` inverts its
boxes. **X** (`_do_toggle_highlight`): `_highlight_of(sel)` = the browsed one,
or a single-page highlight on the page whose pos0 / pos1 snap (`_word_at`,
nearest word box) to the selection's end words (finger highlights do not sit
at word centres, so never compare positions with `==`); found -> 
`rh:deleteHighlight(index)` (index re-checked by identity; deletes from the
PDF, `index_modified` shifts the box cache), else save. Highlight in the menu
on a browsed highlight does nothing (no duplicate). **The note window** (`SelectorOverlay:_do_note`, EPUB and PDF): opens with the target's saved note (`a.note`), `width` / `text_height` from `_note_size` (85 % of the width, at most 1.3 x the height; text 30 % of the screen height, 62 % = large), `allow_newline`; `edited_callback` -> `UIManager:nextTick(grow)`: once the text overflows (`getAllLineCount` > `getVisLineCount` of the ScrollTextWidget's TextBoxWidget) it re-inits ONCE to large (`text_height` and `orig_text_height`); a long note opens large. Saved unchanged = no event, emptied = the note is removed (`nb_notes_added = -1`, the highlight stays). diktonoti writes its live transcript into this field and follows the new InputText after the re-init. In an EPUB the browsed highlight is the target too (`hl_ann` in the mode `hl` selection). **Note**: base
`_do_note` is split into `_note_target(sel)` (EPUB: a new highlight;
PagedOverlay: the browsed highlight itself, else a new one) and
`_note_saved(a, note)` (PagedOverlay: `writePdfAnnotation("content")`, as the
stock note editor, then refresh); a note on a highlight that already had one
counts 0 / 0 in `AnnotationsModified`. The EPUB `_do_toggle_highlight` still
compares `a.pos0 == sel.pos0` (xpointer strings, which works there) and
removes with `table.remove` (no `index_modified`) -- left as it was.

- **`struct`** — sentences (`self.sentences[]` from `paginmapo`). Cursor
  `sel_cur`, optional `sel_anchor`; `_set_sent` derives the selected span
  `sel_sent`..`sel_tail`. ←/→ `_sent_step`, ↑/↓ `_para_step` (↓ next paragraph,
  ↑ start of this one or the previous one).
- **`walk`** — words (`ww_word`, optional `ww_anchor`; `_ww_span` orders them
  with `compareXPointers`, 1 = first argument earlier). ←/→ `_ww_step`, ↑/↓
  `_ww_line`, with split-word fragment handling for hyphenated/wrapped words
  (`_is_split_word`, `_resolve_split_fragment`).
- **`hl`** — the page's saved highlights (`hl_items` / `hl_cur`, opened by Y);
  every arrow steps between them (`_hl_step`, wrapping).
- **`point`** — point from-to (TASK-29, A tapped; on sentences since TASK-35):
  `self.pointer` (kopad_hints.lua) over the sentences / word boxes built by
  `_point_begin`; `point_press(sym)` feeds it (labels and arrow shortcuts,
  TASK-36), and on `done` `_point_finish` turns the
  overlay into `walk` with `ww_anchor` = the start word (`p.start`),
  `ww_word` = the end word (`p.stop`; no end = the start word alone, no
  anchor). `_draw_point` paints the labels (white pill, D-pad symbols as
  rounded squares with an arrow, letters as circles, a pressed symbol grey;
  beside the sentence start / end when the margin allows, else over the
  text; word labels, two or three symbols, centred on the word's top edge)
  and, in the end step, the preview `pointer:preview()` = start .. the end
  of the current end sentence inverted ALWAYS (also while that is the start
  sentence: the range ← would give; line boxes via `lines_from_boxes`).
  Status `_point_status(short)`: `FROM · label = sentence · B close`, `FROM
  WORD · ← sentence ↑ paragraph · B sentences`, `TO · ← end → next [↑
  previous] ↓ paragraph · B one word` (arrows mirrored in RTL; `B undo` after
  a typed symbol; short = step + B).

Public entry points for padnav: `step(dir, range)` / `line(dir, range)` (dir in
document order, already RTL-flipped), `para(dir, range)` (LT / RT, TASK-25:
`_ww_para` = first word of the next / this or previous paragraph, a paragraph
begun on the previous page is reached there; sentences = `_para_step`;
highlights = `_hl_step`), `to_words()` / `to_sentences()` (the two
levels, TASK-17), `action_menu()`. Without a range the moves cross the page edge
in both directions (`_turn_page` + `_ww_land` / `_sent_land` / `_para_land`,
TASK-18); a sentence running over the edge is skipped on the other side, so it
counts once. A range never leaves its page. Use `_adjacent_word`, never
`dir > 0 and next() or prev()`: a nil next word falls through to the previous
one. Status line (`_status_text(short)`): level + buttons, no counters. It never covers the page text (`statusbar.lua`, pure, `tests/statusbar_test.lua`; chosen in /ux, 2026-11-03): `_draw_status` measures the free strips above the first and below the last line (`StatusBar.extent` over the `sbox` of `self.words`, down to the top of the reader's footer via `_footer_height`) and `StatusBar.layout` puts the compact bar (text + rule) in the top strip, else the bottom one, else a shortened one (`_status_text(true)`: mode + A / B, no rule) in the larger strip when it holds a line of text, else nothing is drawn. The same rule in a PDF (its word boxes are screen coordinates too).

Actions on the current selection (`_get_selection`): `_do_dict`, `_do_ai`,
`_do_vortuyo`, `_do_highlight`/`_do_toggle_highlight`, `_do_copy`, `_do_note`.
`_hook_dict_widget` patches the open dictionary popup so Y → AI explain and
LB/RB cycle dictionaries — LEGACY key path only (on >= 2026.07
`PadNav:_dict_button` handles Y and LB/RB are the popup's own stock keys); it
finds the popup via `DictQuickLookup.window_list`. Painting is done with manual blitbuffer inversion
(`invert_rounded_rect`, `_draw_*` methods) — no standard widgets for the
selection rectangles.

### Vendored family libraries: `paginmapo.lua`, `pluginaro.lua`, `llm.lua`

**These three files are vendored, not authored here.** Verbatim copies ship in
the sibling plugins (`keyreader`/`visel`, `marjenoti`, `assistant`, `wordsearch`)
so each stays runtime-independent. Canonical sources live upstream in
`lib/` of the plugin-family repo (propagated by `bin/sync-*.fish`, drift-guarded
by a pre-commit hook there). Edit them upstream, or mirror any local edit — do
not let copies diverge. Recent history ("Sync paginmapo", "sync pluginaro")
shows they arrive as sync commits.

- **`paginmapo.lua`** — CRengine helper (`WordSource`) that walks the visible
  page and returns word items `{ text, xp0, xp1, next_xp0, sbox, sent_end }`
  plus sentence groupings. Sentence-boundary logic is deliberately careful:
  `.` ends a sentence only when the next word is capitalized (avoids `M.I.T.`,
  `Dr.`, `e.g.`); `!?؟۔` and paragraph breaks always end. Public API:
  `collect_words` (memoized per page), `collect_sentences`,
  `collect_sentences_from_words`, `find_sentence_start/end`,
  `page_starts_at_boundary`.
- **`pluginaro.lua`** — opt-in extension registry + overlay arbitration shared
  by the plugin family. `main.lua` registers extensions and builds the
  extension menu; `selector` calls `claim_overlay`/`release_overlay` so only one
  family plugin owns the screen/keys at a time; `padnav` yields
  (`return false`) when `overlay_active` for another owner (context `foreign`).
  `is_modal_active` is NOT used for menus any more (see the context rule above);
  its blind spot for `CenterContainer`-wrapped menus lives upstream.
  Extensions are strictly opt-in (`default_enabled` must be literally `false`).
  Requirable in bare Lua (deps injected via `Pluginaro._deps`).
- **`llm.lua`** — self-contained one-shot chat-completion POST to OpenRouter
  (`LLM.query`/`LLM.ask`), used by `selector`'s AI action. Needs a gitignored
  `llm_config.lua` with an `api_key` in the plugin root; without it
  `LLM.available()` is false. Never commit that file.

## Coordination with the plugin family

The family: `keyreader` (with `visel` and `hilite`), `marjenoti`, `textolimiti`,
`kotheme`, `frontespico` and kopad. Each is its own GitHub repo. **Today there are two
gamepad integrations: kopad ↔ visel** (`visel.ext.kopad.gamepad_select`) **and
kopad ↔ diktonoti** (`diktonoti.ext.kopad.gamepad_dictate`: in a text-input
dialog (context `window`) **RT held** = dictation into the focused field —
start on the press, stop on the release, which is polled from
`Gamepad.held_axis_directions` because KOReader reports no trigger release
(`PadNav:_dictate_hold`, before `_menu_trigger`); B during a recording =
cancel, every other button, LT and the sticks are eaten while it runs
(`_diktonoti_route`, `_recording`). Dictation comes first in a text dialog:
it is found under the on-screen keyboard (`text_dialog`: the keyboard's
`inputbox.parent`; there A stays stock = types the key) and over a foreign
overlay (context `window`), and with the D-pad focus on a button row RT
first moves it back to the field (`focus_field`, FocusManager
`FORCED_FOCUS`; vkb.lua keeps that from opening the keyboard). Not a stick click: on the Deck Steam Input never
passes L3 / R3 to KOReader. kopad's own text-field controls, with or without
diktonoti (`_text_field_button`): X = backspace, A = the dialog's
`is_enter_default` button (Save / Search) while the focus is on the field,
B stays the stock Back = close;
section 15 of `tests/padmap_test.lua`); every
other plugin's windows simply get stock keys from kopad (context `window`) and
need no pad code. The rules below describe how that integration works and how to
add the next one. The sibling repos carry the same rules in their own `CLAUDE.md`.

### Who owns what

| Question | Belongs in |
|---|---|
| How the pad is read: SDL ids, roles, layouts, contexts, `padmap`, actions | **kopad** (`padnav.lua`, `padmap.lua`) |
| What a host plugin's feature can do (move / extend / close a selection, jump to a note…) | the **host plugin**, which publishes it |
| Which pad event calls which published method | **kopad** (`PadNav:_<host>_route`) |
| Registry, overlay claim, `paginmapo`, `llm` | canonical copy in `koreader-konfig` `lib/`, never edited here |

Rule of thumb: a change about *which button* is a kopad-only change. A change that
needs *a capability the host does not expose yet* is two changes — first an
optional method in the host's `provide` table, then a route to it from kopad.

### Rules

1. **No plugin `require`s another.** Cross-plugin contact goes only through
   `pluginaro` (`_G._pluginaro_registry`, `_G._pluginaro_provided`) and the
   overlay claim `ui._kokb_overlay`.
2. **Opt-in.** `default_enabled = false` (literally), flag
   `<host>.ext.<provider>.<id>` in `G_reader_settings`, toggle in the *host's*
   menu (for visel: Keyreader → Extensions). kopad's own menu only shows the
   signpost row that `Pluginaro.build_ext_menu` generates.
3. **Absence-tolerant in both directions.** `register` / `provide` without a
   counterpart is harmless; `call_provided` returns `nil` when the toggle is off,
   nothing was provided, the method is missing or the implementation errors, and
   kopad then behaves exactly as it did before the integration. Deployment order
   across devices must not matter, so: new methods are optional, existing ones are
   never renamed or given a new meaning.
4. **The contract is `(host, provider, id)` plus method names and arguments.**
   Today `visel / kopad / gamepad_select`: `is_active()`, `move(dir)`,
   `extend(dir)`, `close()`; `diktonoti / kopad / gamepad_dictate`:
   `is_active()`, `is_recording()`, `start()`, `stop()`, `toggle()`, `cancel()`. Change it in both repos and name the other repo's
   commit in each commit message.
5. **Route before `_is_enabled()`, and know the two rounds.** A foreign overlay
   makes the context `foreign`, which disables PadNav's own handlers — and that is
   exactly the state an opt-in route is for. `PadNav:_visel_route` therefore runs
   first in the `key_events` handlers and re-checks the master switch and
   `is_modal_active()` itself. On KOReader >= 2026.07 the route is reached in a
   *second round*: in context `foreign`, `_button_down` / `onGamepadAxisMotion`
   return `false`, stock (`gamepad.lua` `button_key_names` / `axis_key_names`)
   then sends its default key — D-pad / L-stick X → `Left`/`Right`, LB/RB →
   `RPgBack`/`RPgFwd`, B → `Back` — and that key hits `onKPLeft2` / `onKPPgBk` /
   `onKPBack`, which route. So `foreign` must keep passing those controls
   through; consuming them there would cut visel off. Side effects of the same
   mapping: Select / Guide (`RPgBack`/`RPgFwd`) also trim / extend, and R-stick Y
   does so with auto-repeat. `Back` reaches PadNav before visel's own `ViselBack`
   only because kopad loads after keyreader and inserts PadNav at the front of
   `active_widgets`. Section 12 of `tests/padmap_test.lua` covers both rounds.
6. **One overlay at a time.** `claim_overlay(ui, name)` when opening,
   `release_overlay` when closing, `overlay_active` checked before opening.
   Claim names in use: `kopad`, `visel`, `hilite`. A foreign claim makes kopad
   stand down unless an opt-in route handles the event.
7. **Only kopad consumes `Gamepad*` events globally.** A plugin that wants the pad
   exposes a method through `provide` and lets kopad call it; it does not add its
   own `GamepadButtonDown` / `GamepadAxisMotion` handler outside its own modal
   widget (two consumers would both act on one press).

### Adding an integration

1. Agree the `id` and the method list with the host; the host `provide`s them,
   reusing the handlers its keyboard path already calls (so RTL and mode
   branching come for free).
2. kopad: `Pluginaro.register(host, {...})` in `main.lua:init` (see the visel
   block), a `PadNav:_<host>_route` next to `_visel_route`, called first in the
   relevant `on<Key>` handlers.
3. Test: add a case like section 12 of `tests/padmap_test.lua` (stub
   `call_provided`, set `ui._kokb_overlay`, assert round 1 passes and the stock
   key's handler routes).
4. Docs, in the same change pair: this section, the README ("Visel overlay"
   section is the model), and the host's `CLAUDE.md` / `README.md`.
5. If `pluginaro.lua` itself must change: edit `koreader-konfig` `lib/pluginaro.lua`,
   run `bin/sync-pluginaro.fish`, never patch the local copy.

### Working copies

Develop in `~/utensili/koreader/<name>`. `~/modi/koreader/koplugins/<name>.koplugin`
is a submodule checkout of the same GitHub repo used for deployment to devices:
pull there after pushing, do not commit there.

## Key events reference

Two input paths end in the same `on<Key>` handlers:

- **KOReader >= 2026.07:** `device.lua` calls `UIManager:broadcastEvent` with
  `GamepadButtonDown {button}` / `GamepadAxisMotion {axis,value,time}`; if a
  handler returns `true` the stock default key press is suppressed.
  `PadNav:onGamepadButtonDown` / `onGamepadAxisMotion` map SDL ids (A0 B1 X2 Y3
  Select4 Guide5 Start6 L3=7 R3=8 LB9 RB10 D-pad11-14; axes LX0 LY1 RX2 RY3
  LT4 RT5) onto the handlers. `GamepadButtonUp {button}` is broadcast too (no
  stock key follows; `PadNav:onGamepadButtonUp`, see Holds above). **`main.lua`
  must relay these three events to
  `subs.nav`**: the broadcast reaches the window widgets and their children (the
  kopad plugin widget) but not `ui.active_widgets`, where PadNav lives. Triggers
  are de-bounced (stock auto-repeats held axes and never reports release; own
  `time.now()` clock, not `ax.time`). Axes 2/3 (R-stick) are always consumed
  in the reading contexts (reading / paged / selection), because stock maps
  R-stick Y to `RPgBack`/`RPgFwd`: in reading / paged (and the FileManager)
  they open the quick-action wheel, in the selection they switch the level; in
  menus, dialogs and the dictionary popup both sticks are stock, in the
  FileManager the L-stick.
  **Menus (context `top_menu` / `window`):** `_menu_button` / `_menu_trigger`.
  Top menu (reader *and* FileManager): LB/RB = previous/next category (wrapping,
  action tabs with `remember == false`/callback skipped, via `bar:switchToTab`;
  consumed, so the stock `RPgBack`/`RPgFwd` menu page turn is suppressed), LT/RT =
  `TouchMenu:onPrevPage`/`onNextPage` with the auto-repeat filter, Select =
  `closeMenu`, everything else stock (Start's stock key `Menu` closes it).
  Other windows: LT/RT = `onPrevPage`/`onNextPage` of the first pager in the
  window. Bottom menu (ConfigDialog, duck-typed by `config_options` +
  `closeDialog`; TASK-13: reading Start opens it via `ShowConfigMenu`): Start =
  close, LB/RB = previous/next tab, D-pad / L-stick ←/→ on its tab bar (the LAST
  layout row) = tab at once; `config_switch_tab` (`onShowConfigPanel`) keeps the
  focus level like `menu_switch_tab`. On both tab bars the current tab's icon is
  not inverted for the focus (`quiet_current_tab_focus` wraps each bar icon's
  `onFocus` once, lazily from `_quiet_tab_focus` on the first pad event); the
  open-tab frame already marks it. Select/Start/Guide/L3/R3 otherwise
  swallowed, the rest stock. Dictionary popup
  (`dict`): stock (LB/RB = its own RPgBack/RPgFwd, B closes), Y = AI explain,
  triggers eaten. FileManager: stock list navigation, LT/RT = `file_chooser`
  page, Select = top menu, B = `FileChooser:onFolderUp` (stock Back asks
  "Exit KOReader?"). Reading without a selection: B = `ReaderLink:onGoBackLink`
  only, never the stock Back (ReaderBack ends in "Exit KOReader?"). Top menu:
  D-pad / L-stick ←/→ with the focus on the tab bar (`selected.y == 1`) switch
  the tab at once; `menu_switch_tab` keeps the focus level (bar -> new icon,
  items -> first item). Sticks outside the reading contexts drop release
  bounces (`_stick_bounce` with `MENU_STICK_LOCK_S`).
- **Older patched builds:** physical button → KOReader key name → `padnav`
  binding in the `key_events` table in `PadNav:init`. Names come from SDL3 + the
  userpatch. L4/R4 back paddles (`ScrollLock`/`Pause`) are LB/RB aliases on these
  builds only; the `Gamepad*` path (>= 2026.07) does not handle them.

When adding/changing controls, edit the matching `on<Key>` handler (and the
`key_events` table / the id tables at the top of `padnav.lua`); the docstring
blocks at the top of `main.lua` and `padnav.lua` are the human-facing control
maps and should be kept in sync with behavior. Note the two docstrings
currently describe slightly different layouts — **`padnav.lua`'s handlers are
the source of truth**, not the `main.lua` header comment.

## Conventions

- Load KOReader modules with `require` at file top (`ui/...`, `device`, etc.);
  never assume they exist off the reader — guard with `pcall`/nil-checks the way
  `safe_require` and `_ensure_selector` do.
- Return `false` from an `on<Key>` handler to let KOReader handle the event;
  return `true` to consume it.
- RTL correctness: any new horizontal navigation must respect `_is_rtl()`
  direction flipping.

## Task tracking

`backlog/` is a Backlog.md workspace (`TASK-N`; commits reference e.g.
`TASK-1`). Currently untracked in git. Task files live in `backlog/tasks/`.
