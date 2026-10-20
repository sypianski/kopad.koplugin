<div align="center">
  <h1>kopad</h1>
  <p>A gamepad as a reading remote.</p>
  <p>by <a href="https://sypian.ski/">Jakub Sypiański</a> · License: AGPL-3.0</p>
  <p>Updated 13 October 2026</p>

  [![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
  ![Platform](https://img.shields.io/badge/platform-KOReader%202026.07%2B-brightgreen)
</div>

> **Part of the KOReader family.** Related apps:
> [Rosetta](https://github.com/sypianski/rosetta.koplugin), a translation under the book text;
> [Hairline](https://github.com/sypianski/hairline.koplugin), a thin progress bar at the bottom edge;
> [KoTheme](https://github.com/sypianski/kotheme.koplugin), rounded corners and thinner borders;
> and others.

A [KOReader](https://github.com/koreader/koreader) plugin that turns a connected **gamepad** into a reading controller — page-turning, menu navigation, and a crosshair cursor that snaps to nearest words for highlight / dictionary / AI lookup.

> *Kopad* — KO(Reader) + (game)pad.

E-readers and reading-mode laptops often sit far from your hands. A gamepad is more relaxed than a keyboard, easier to use one-handed in a recliner or in bed. *Kopad* maps the standard SDL3 gamepad layout to reading actions and adds a structured word/sentence selector you can drive entirely with the right stick + face buttons.

## Install

**KOReader 2026.07 or newer** (stock, e.g. the Flatpak release) works as is: it has built-in gamepad support and kopad takes over its `GamepadButtonDown` / `GamepadAxisMotion` events. No patch, no userpatch.

Older KOReader builds need SDL3 gamepad support from a separate patch: `sdl3_gamepad.patch` (button/axis key events) plus the `1-lstick-keys.lua` userpatch (separate L-stick keys). Those builds are still supported through key events, but the patch and userpatch are obsolete on 2026.07+. The patch files are not part of this repository.

Copy the files of this repository into a folder named `kopad.koplugin/` (the name must end in `.koplugin`) inside KOReader's `plugins/` directory:

| Platform | Path |
|---|---|
| Linux (native) | `~/.config/koreader/plugins/` |
| Linux (Flatpak) | `~/.var/app/rocks.koreader.KOReader/config/koreader/plugins/` |
| Other | `koreader/plugins/` on the device |

Restart KOReader, plug in a gamepad and enable the plugin under *menu > more tools > kopad > Enable kopad*.

## What it does

On KOReader 2026.07+ the plugin takes over the gamepad events and maps them to reading actions. The controls are described below.

The canonical, up-to-date key map lives in the header of `padnav.lua` (the
actual gamepad event handler) — read that file if these tables and the code
ever drift. Summary as of this writing:

Written for a Steam Deck / DualSense (via Steam Input) on stock KOReader 2026.07+. LT/RT are the lower trigger buttons under the index fingers; LB/RB the bumpers above them. The same map is available on-device under *menu > kopad > Button cheat sheet*.

### Reading mode

| Button | Action |
|---|---|
| **RT** / **LT** | next / previous page |
| **RB** / **LB** | next / previous page (**X** + RB = bookmarks, **X** + LB = table of contents) |
| **Select** | top menu |
| **Start** | footer (bottom) menu |
| **D-pad** | open word walk |
| **R-stick** | open crosshair |
| **L-stick** | ↑/← page turn, ↓ crosshair, → word walk |
| **A** | sentence selector |
| **Y** | highlight mode (crosshair if the page has none) |
| **X** + D-pad | ↑ menu, ↓ footer, ← history, → files |

### Top menu open (reader and FileManager)

| Button | Action |
|---|---|
| **RB** / **LB** | next / previous category (tab with an icon), wrapping at the ends |
| **RT** / **LT** | next / previous page of the menu, one page per press |
| **D-pad** / **A** | as before (stock navigation / press) |

Tabs that are actions rather than categories (the reader's "file browser" tab, which closes the book) are skipped. The bumpers are consumed in the menu, so the stock page turn on them no longer happens there. Outside a top menu (other dialogs, plain lists) the bumpers and triggers behave as in reading mode. This works on the `Gamepad*` path (KOReader 2026.07+) only.

### Selection mode (sentence / word walk / crosshair)

| Button | Action |
|---|---|
| **L-stick** | ←/→ sentence, ↑/↓ paragraph |
| **D-pad** / **R-stick** | word navigation (R-stick ↑/↓ cycles page highlights) |
| **A** | action menu (dictionary, AI, copy, note) |
| **Y** | Vortuyo lookup |
| **X** | toggle highlight |
| **RB** / **LB** | extend selection right / left (again = quick extend) |
| **B** | exit extend mode / close selection |
| **RT** / **LT** | close selection and turn page |
| **Select** / **Start** | close selection and open top / footer menu |

In the dictionary popup **LB** / **RB** cycle dictionaries and **Y** asks the AI to explain.

### Input paths, Select / Start and the triggers

On **KOReader 2026.07+** every button and axis arrives as a `Gamepad*` event and is mapped by id in `padnav.lua` (`onGamepadButtonDown` / `onGamepadAxisMotion`, relayed from `main.lua`). While kopad is enabled:

- **Select** / **Start** open the top / footer menu; **LT** / **RT** turn the page, one page per press (the stock auto-repeat of held axes is filtered out). With the top menu open they turn the menu page instead (same one-press filter), and **LB** / **RB** switch the category.
- The **R-stick** never turns pages by itself any more (stock maps its Y axis to page back/forward with auto-repeat, which flipped pages endlessly). Its auto-repeat is kept for navigation.
- **Guide**, **L3** and **R3** are swallowed so a stick click cannot open a menu or turn a page. The D-pad is passed through to the original Up/Down/Left/Right keys.
- With kopad disabled, or while a menu/dialog is on top, nothing is intercepted and KOReader behaves as stock.

On **older patched builds** there are no such events; buttons arrive as key names (`LPgBack`/`LPgFwd` for LT/RT, F-keys for the R-stick and X). Select and Start are then bound to **F12** / **F2**: add a hunk to `sdl3_gamepad.patch` that sends keycodes `1073741893` (F12) for `SDL_GAMEPAD_BUTTON_BACK` and `1073741883` (F2) for `SDL_GAMEPAD_BUTTON_START`. Until then those two bindings are inert and the menus stay reachable via **X** + D-pad. The back paddles **L4** / **R4** (`ScrollLock` / `Pause`) are aliases of **LB** / **RB** on these patched builds only; on KOReader 2026.07+ they are not handled (SDL paddle ids have no stock mapping and Steam Input usually does not expose them).

### Visel overlay (opt-in via pluginaro)

With `visel.ext.kopad.gamepad_select` enabled: **D-pad** / **L-stick ←/→** move the selection, **RB** / **LB** extend / trim it, **B** closes it.

### Button remapping (gamepad layouts)

Button names in this README are Xbox-style **roles** (A = bottom face button, etc.). On KOReader 2026.07+ you can tell kopad which physical button plays which role, per known pad layout:

- **menu → kopad → Gamepad layout (this device)** picks the layout of the pad used on *this* device. The choice is stored in `settings/kopad_device.lua`, which koligilo never syncs, so a Steam Deck and a reader can use different pads. Layouts (a closed list; `xbox` is the default):

  | Menu entry | Layout id | Default mapping |
  |---|---|---|
  | *Xbox / generic* | `xbox` | identity: A/B/X/Y by position (default) |
  | *PlayStation (DualShock / DualSense)* | `playstation` | identity: same positions as Xbox, only the symbols differ |
  | *Nintendo (A/B and X/Y swapped)* | `nintendo` | A↔B and X↔Y swapped, so "press A" means the A-labelled key (printed A is on the right) |
  | *Valve (Steam Deck / Steam Controller)* | `valve` | identity: same positions as Xbox (A/B/X/Y); only the printed labels differ — *View* is Select, *Menu* is Start, L1/R1 are the bumpers (LB/RB), L2/R2 the triggers (LT/RT) |

  Known limitation: the Steam Deck back paddles (L4/L5/R4/R5, SDL button ids 16+) are not remappable. KOReader 2026.07+ does not pass them on (no stock mapping, and Steam Input usually does not expose them), so kopad never sees them and they have no entry in the layout vocabulary.
- Per-layout overrides live in `settings/kopad.lua` under `padmap` (shared; koligilo syncs and edits it):

```lua
["padmap"] = {
    ["version"] = 1,
    ["layouts"] = {
        ["nintendo"] = { ["south"] = "a", ["east"] = "b" },   -- keep A/B by position
        ["xbox"]     = { ["ltrigger"] = "rt", ["rtrigger"] = "lt" },
    },
    ["actions"] = { ["rb"] = "top_menu", ["select"] = "next_page" },   -- optional, see below
},
```

Keys are physical controls by position — `south east west north back start lshoulder rshoulder ltrigger rtrigger` — and values are roles — `a b x y select start lb rb lt rt`. A button may take a trigger role and vice versa. Controls not listed keep the layout's default. Anything malformed (other `version`, unknown names, wrong types) is skipped with a log warning; with no data kopad behaves exactly as without remapping. The D-pad, sticks, Guide/L3/R3 and the older patched-build key path are not remappable, and when kopad passes an event through to KOReader (kopad off, a dialog on top), KOReader sees the physical button. The pure logic is `padmap.lua`, tested by `lua tests/padmap_test.lua`.

**Changing what a role does.** `actions` goes one step further: it says what a *role* does while you are plainly reading, e.g. RB opening the top menu (where KOReader's settings live) instead of turning the page. It is keyed by role, not by physical button, so it is shared by every layout and survives switching pads. Values (a closed list, grouped as in the koligilo panel): pages — `next_page prev_page pages_forward_10 pages_back_10 next_chapter prev_chapter first_page last_page back_location forward_location goto_page skim`; menus — `top_menu footer_menu config_menu`; book — `toc bookmarks toggle_bookmark next_bookmark prev_bookmark book_map page_browser fulltext_search book_status book_info reading_progress`; library — `history file_browser last_book favorites collections`; selection and dictionary — `sentence_select highlights word_walk crosshair dict_lookup`; display — `font_bigger font_smaller night_mode rotate full_refresh frontlight_toggle frontlight_up frontlight_down`; other — `screenshot cheat_sheet x_modifier none`. Most of them send the same KOReader event its own gestures and profiles use, so an action KOReader has no handler for on this device or document (frontlight on a desktop, font size in a PDF, `reading_progress` without the statistics plugin) does nothing. Defaults: A `sentence_select`, X `x_modifier`, Y `highlights`, LB/LT `prev_page`, RB/RT `next_page`, Select `top_menu`, Start `footer_menu`; B has no kopad action (KOReader's own Back runs). Roles not listed keep their default.

An override applies only in the idle reading context: a document is open and no selection overlay, dictionary popup, top menu or X combo is active. Everywhere else the role keeps what it does today (RB still extends a selection and switches menu categories, LT/RT still turn menu pages, X + D-pad / X + LB / X + RB still reach the menus, TOC and bookmarks), and in the file browser buttons act as before. `sentence_select`, `highlights`, `word_walk` and `crosshair` need the selector (EPUB and other reflowable documents); in a PDF the press is swallowed. The cheat sheet in the menu lists the roles you changed. kopad versions without this stage ignore the `actions` key and read `layouts` as before. koligilo edits it in the panel under *Wtyczki → Ustawienia wtyczek → Gamepad (KOPad): akcje w czytaniu*.

### Scope

The selector (word walk / struct / crosshair) only exists for crengine (rolling) documents. In paged documents (PDF/DjVu) and in the FileManager no reader keys are suppressed and selector-dependent handlers pass through — only page turns and X-combos remain active there.

## Technical notes

### How it works

- **padmap.lua** — pure (KOReader-free) remapping layer: physical SDL button/trigger → logical role, per layout (see Button remapping).
- **padnav.lua** — gamepad event handler. Maps buttons + axes (`Gamepad*` events on KOReader 2026.07+, key events on older patched builds) to KOReader events.
- **selector.lua** — crosshair widget + word-snap logic. Pulls visible word positions from the bundled `paginmapo.lua` (Ido for "page-map") and finds the nearest by Euclidean distance.
- **keyhints.lua** — while kopad is on, hides KOReader's keyboard-shortcut letter labels (q w e r t y…) on file browser covers/lists by flipping `BookList.is_enable_shortcut`; restored verbatim when kopad is switched off (nothing is persisted).
- **kopad_trace.lua** — optional flag-file-gated diagnostic trace (see Diagnostics).
- **main.lua** — glues the two together as a `WidgetContainer` and relays the `Gamepad*` broadcasts to `padnav.lua`.

### Diagnostics

If kopad seems to do nothing on a device (and KOReader gives you no log), switch on the on-device trace by creating an empty flag file in KOReader's settings directory:

```sh
touch ~/.var/app/rocks.koreader.KOReader/config/koreader/settings/kopad-trace   # Flatpak
# native Linux: ~/.config/koreader/settings/kopad-trace ; other devices: koreader/settings/kopad-trace
```

From then on (no restart needed, the flag is re-checked every ~2 s) `kopad-trace.log` next to it collects timestamped lines: the mtimes of `main.lua` / `padnav.lua` / `keyhints.lua` (which code actually loaded), the result of loading each sub-module, the `enabled` state, every `Gamepad*` event reaching kopad and why `padnav.lua` passed it through or which handler consumed it. Remove the flag file to stop; without it nothing is written. The log is capped (~256 KB, then only the newest ~64 KB are kept) and rate-limited (~20 lines/s, repeated stick events are collapsed). Implemented in `kopad_trace.lua`; the plugin works without that file.

### Bundled `paginmapo.lua`

This plugin vendors `paginmapo.lua` — a 411-line CRengine helper that extracts visible words with screen positions and xpointer anchors. It is also used by sibling plugins keyreader, marjenoti, and assistant. Each ships its own copy so they remain runtime-independent.

If you maintain a fork or copy and edit `paginmapo.lua` here, keep it identical to the upstream copies in those plugins.

### Compatibility

Targets stock KOReader 2026.07+ (the `Gamepad*` event interface was taken from the 2026.07.1 Flatpak sources; the new handlers are unit-tested against mocks, not yet confirmed on the Steam Deck). Earlier tested with a generic Bluetooth gamepad on KOReader 2026.03 desktop Linux with the patched SDL3 backend, which keeps working through key events.

### Tests

The only automated test covers the pure remapping layer (`padmap.lua`):

```bash
lua tests/padmap_test.lua
```

## How this was made

kopad was written largely by Claude, working from my specifications and
under my direction ("vibe coding"). I reviewed and tested the results, but
the code has not had an independent audit. Treat it as you would any young
project and report what you find.

## Feedback

kopad is a young project. If something breaks, behaves oddly or is missing, tell me:

<!-- feedback-form: https://sypian.ski/uwagi/?app=kopad -->
- [Open an issue on GitHub](https://github.com/sypianski/kopad.koplugin/issues/new). Bug reports, ideas and questions are all fine there; include your KOReader version and your gamepad model.
- Or email jakub.sypianski@gmail.com.

## Support

kopad is free. If it is useful to you, you can [buy me a coffee on Ko-fi](https://ko-fi.com/sypianski).

## License and credits

kopad is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0), see [LICENSE](LICENSE).

kopad matches KOReader's license. It vendors `paginmapo.lua`, a CRengine word-extraction helper that is shared with the sibling plugins (see Technical notes).

---

<p align="center">kopad · <a href="https://sypian.ski/">Jakub Sypiański</a> · AGPL-3.0</p>
