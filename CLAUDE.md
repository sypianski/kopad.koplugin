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
padnav wiring), `lua tests/wheel_test.lua` (wheel.lua: sectors, pages, stick
directions, glyphs, controller) and `lua tests/selector_test.lua` (selector.lua
on a fake three-page document: moves, page crossing, ranges, levels,
highlights); plain `assert`, KOReader stubbed.

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

## Architecture

Three-layer design. Understanding the split is the fastest way to be productive.

### `main.lua` — plugin shell (`WidgetContainer`)
Thin glue. On `init` it opens `LuaSettings`, then lazily loads two sub-modules
into `self.subs` via `safe_require` (pcall-wrapped so a failure warns instead of
crashing KOReader):
- `self.subs.nav` = `PadNav` (always)
- `self.subs.selector` = `Selector` (only when `ui.rolling` exists, i.e. EPUB/
  reflowable docs — created lazily in `_ensure_selector`, retried on
  `onReaderReady`).

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
`_kokb_overlay`), `reading` / `paged` / `filemanager` (the top window IS
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
main.lua, remapped through padmap like the press) ends three holds:
- **A**: `_press_a` sets `_a_down`; while it is set `_sel_move` passes
  `range = true` (the overlay keeps an anchor) and marks `_a_moved`.
  `_release_a` opens the action menu only for a tap (no arrow, and not the A
  press that opened the selection: `_a_opened`). The legacy `Press` key goes
  to `onKPConfirm` (menu on the press).
- **X**: `_button_down` wraps `_button_dispatch`; a press that arms `_x_mode`
  records its role in `_x_hold`, and its release clears the modifier.
  `_x_combo` keeps the modifier armed while `_x_hold` is set. A trigger acting
  as a button (`_trigger_as_button`, no release) and the legacy key path keep
  the latch.
- **D-pad**: in an EPUB (reading / selection) `_button_dispatch` calls the
  `KPUp2`.. handlers itself and, in the selection, `_dpad_start` repeats the
  step via `UIManager:scheduleIn` (`DPAD_REPEAT_*`) until the release, a context
  other than `selection`, or `DPAD_REPEAT_MAX`. X combos are not repeated.
  The interval shrinks after `DPAD_ACCEL_AFTER` repeats (`dpad_interval`,
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
replaced the PDF R-stick zoom (zoom = A held + D-pad). Tests: section 16 of
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

### `kopad_trace.lua` — optional diagnostic trace
Zero-dependency logger (`Trace.log/active/begin_event/end_event`, always pcall-guarded); writes `<settings dir>/kopad-trace.log` ONLY while the flag file `<settings dir>/kopad-trace` exists (cached ~2 s; capped ~256 KB, ~20 lines/s, axis repeats collapsed). `main.lua` and `padnav.lua` load it via `pcall(require, "kopad_trace")` with a no-op stub fallback; trace points never alter return values. Named `kopad_trace` (not `trace`) to avoid `package.loaded` collisions.

### `selector.lua` — stateful overlay widget (`SelectorOverlay` + `Selector`)
The visual selection engine. `Selector` is the factory/lifecycle wrapper
(`_open` = sentences, `_open_walk(from_end)` = words, `_open_highlights` =
saved highlights or `false` when the page has none, `_close`; all share
`_new_overlay`, which holds the pluginaro claim); `SelectorOverlay` is the
painted widget with a single `self.mode` state machine (no crosshair any more:
removed in TASK-15; the padmap id `crosshair` stays as an alias of
`word_walk`):

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
one. Status line (`_status_text`): level + buttons, no counters.

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
kopad ↔ diktonoti** (`diktonoti.ext.kopad.gamepad_dictate`: in context `window`
R3 toggles dictation into the focused text field, B cancels a running one —
`PadNav:_diktonoti_route`, called first in `_menu_button`'s window branch;
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
   `is_active()`, `is_recording()`, `toggle()`, `cancel()`. Change it in both repos and name the other repo's
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
