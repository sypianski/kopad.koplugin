# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`kopad` is a **KOReader plugin** (pure Lua, AGPL-3.0) that turns a connected SDL3
gamepad into a reading controller: page-turning, menu navigation, and a
crosshair cursor that snaps to nearest words for highlight / dictionary / AI
lookup. Name = KO(Reader) + (game)pad.

There is **no build step, no test suite, no package manager**. Development is
edit-Lua → load into KOReader → observe. The repo *is* the plugin source.

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
(`enabled` flag only). Debug via KOReader's `logger` output (`logger.warn`
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

Every `on<Key>` handler first checks `_is_enabled()` (returns `false` to pass
the event through when disabled or when a `_kokb_overlay` is up). Handlers
branch on whether `selector.overlay` exists and which `mode` it's in, then
delegate to overlay methods. Reading-mode-only state: `_x_mode` (X button acts
as a modifier for D-pad/shoulder combos: menu / footer / history / files / TOC /
bookmarks). RTL languages flip horizontal directions via `_is_rtl()`.

### `kopad_trace.lua` — optional diagnostic trace
Zero-dependency logger (`Trace.log/active/begin_event/end_event`, always pcall-guarded); writes `<settings dir>/kopad-trace.log` ONLY while the flag file `<settings dir>/kopad-trace` exists (cached ~2 s; capped ~256 KB, ~20 lines/s, axis repeats collapsed). `main.lua` and `padnav.lua` load it via `pcall(require, "kopad_trace")` with a no-op stub fallback; trace points never alter return values. Named `kopad_trace` (not `trace`) to avoid `package.loaded` collisions.

### `selector.lua` — stateful overlay widget (`SelectorOverlay` + `Selector`)
The visual selection engine. `Selector` is the factory/lifecycle wrapper
(`_open`, `_open_walk`, `_close`); `SelectorOverlay` is the painted widget with
a single `self.mode` state machine:

- **`cross`** — free crosshair driven by R-stick; snaps to nearest word by
  Euclidean distance (`_nearest_word`). Entry mode.
- **`struct`** — sentence/paragraph/word structured selection after confirming.
  Navigates `self.sentences[]` (from `paginmapo`), tracks `sel_sent`/`sel_tail`/
  `sel_word`, cycles page highlights (`hl_items`/`hl_cur`), supports
  extend/trim (`enter_extend`, `quick_extend_*`, `extend_dpad`).
- **`walk`** — linear word-by-word walk across the whole page (`_ww_move`,
  `_ww_line`), including split-word fragment handling for hyphenated/wrapped
  words (`_is_split_word`, `_resolve_split_fragment`).

Actions on the current selection (`_get_selection`): `_do_dict`, `_do_ai`,
`_do_vortuyo`, `_do_highlight`/`_do_toggle_highlight`, `_do_copy`, `_do_note`.
`_hook_dict_widget` patches the open dictionary popup so Y → AI explain and
LB/RB cycle dictionaries. Painting is done with manual blitbuffer inversion
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
  (`return false`) when `overlay_active` for another owner or `is_modal_active`.
  Extensions are strictly opt-in (`default_enabled` must be literally `false`).
  Requirable in bare Lua (deps injected via `Pluginaro._deps`).
- **`llm.lua`** — self-contained one-shot chat-completion POST to OpenRouter
  (`LLM.query`/`LLM.ask`), used by `selector`'s AI action. Needs a gitignored
  `llm_config.lua` with an `api_key` in the plugin root; without it
  `LLM.available()` is false. Never commit that file.

## Key events reference

Two input paths end in the same `on<Key>` handlers:

- **KOReader >= 2026.07:** `device.lua` calls `UIManager:broadcastEvent` with
  `GamepadButtonDown {button}` / `GamepadAxisMotion {axis,value,time}`; if a
  handler returns `true` the stock default key press is suppressed.
  `PadNav:onGamepadButtonDown` / `onGamepadAxisMotion` map SDL ids (A0 B1 X2 Y3
  Select4 Guide5 Start6 L3=7 R3=8 LB9 RB10 D-pad11-14; axes LX0 LY1 RX2 RY3
  LT4 RT5) onto the handlers. **`main.lua` must relay these two events to
  `subs.nav`**: the broadcast reaches the window widgets and their children (the
  kopad plugin widget) but not `ui.active_widgets`, where PadNav lives. Triggers
  are de-bounced (stock auto-repeats held axes and never reports release; own
  `time.now()` clock, not `ax.time`). Axes 2/3 (R-stick) are always consumed
  while enabled, because stock maps R-stick Y to `RPgBack`/`RPgFwd`.
  **Top menu:** with a `TouchMenu` on top of the window stack (reader *and*
  FileManager) `onGamepadButtonDown`/`onGamepadAxisMotion` handle LB/RB and LT/RT
  *before* the `_is_enabled()` guard (`PadNav:_top_menu`, `_menu_button`,
  `_menu_trigger`, `find_touch_menu`): LB/RB = previous/next category (wrapping,
  action tabs with `remember == false`/callback skipped, via `bar:switchToTab`;
  consumed, so the stock `RPgBack`/`RPgFwd` menu page turn is suppressed), LT/RT =
  `TouchMenu:onPrevPage`/`onNextPage` with the auto-repeat filter. Outside a
  TouchMenu everything is as before.
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
