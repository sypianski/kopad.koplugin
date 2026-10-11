# kopad.koplugin

A [KOReader](https://github.com/koreader/koreader) plugin that turns a connected **gamepad** into a reading controller — page-turning, menu navigation, and a crosshair cursor that snaps to nearest words for highlight / dictionary / AI lookup.

> *Kopad* — KO(Reader) + (game)pad.

## Why

E-readers and reading-mode laptops often sit far from your hands. A gamepad is more relaxed than a keyboard, easier to use one-handed in a recliner or in bed, and KOReader has no built-in support for one. *Kopad* maps the standard SDL3 gamepad layout to reading actions and adds a structured word/sentence selector you can drive entirely with the right stick + face buttons.

## Install

**KOReader 2026.07 or newer** (stock, e.g. the Flatpak release) works as is: it has built-in gamepad support and kopad takes over its `GamepadButtonDown` / `GamepadAxisMotion` events. No patch, no userpatch.

Older KOReader builds need SDL3 gamepad support from the upstream konfig repo: `sdl3_gamepad.patch` (button/axis key events) plus the `1-lstick-keys.lua` userpatch (separate L-stick keys). Those builds are still supported through key events, but the patch and userpatch are obsolete on 2026.07+.

Drop `kopad.koplugin/` into KOReader's `plugins/` directory:

| Platform | Path |
|---|---|
| Linux (native) | `~/.config/koreader/plugins/` |
| Linux (Flatpak) | `~/.var/app/rocks.koreader.KOReader/config/koreader/plugins/` |
| Other | `koreader/plugins/` on the device |

Restart KOReader and plug in a gamepad.

## Controls

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

- **menu → kopad → Gamepad layout (this device)** picks the layout of the pad used on *this* device. The choice is stored in `settings/kopad_device.lua`, which [koligilo](https://sypian.ski/koligilo) never syncs, so a Steam Deck and a reader can use different pads. Layouts (a closed list; `xbox` is the default):

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
},
```

Keys are physical controls by position — `south east west north back start lshoulder rshoulder ltrigger rtrigger` — and values are roles — `a b x y select start lb rb lt rt`. A button may take a trigger role and vice versa. Controls not listed keep the layout's default. Anything malformed (other `version`, unknown names, wrong types) is skipped with a log warning; with no data kopad behaves exactly as without remapping. The D-pad, sticks, Guide/L3/R3 and the older patched-build key path are not remappable, and when kopad passes an event through to KOReader (kopad off, a dialog on top), KOReader sees the physical button. The pure logic is `padmap.lua`, tested by `lua tests/padmap_test.lua`.

### Scope

The selector (word walk / struct / crosshair) only exists for crengine (rolling) documents. In paged documents (PDF/DjVu) and in the FileManager no reader keys are suppressed and selector-dependent handlers pass through — only page turns and X-combos remain active there.

## How it works

- **padmap.lua** — pure (KOReader-free) remapping layer: physical SDL button/trigger → logical role, per layout (see Button remapping).
- **padnav.lua** — gamepad event handler. Maps buttons + axes (`Gamepad*` events on KOReader 2026.07+, key events on older patched builds) to KOReader events.
- **selector.lua** — crosshair widget + word-snap logic. Pulls visible word positions from the bundled `paginmapo.lua` (Ido for "page-map") and finds the nearest by Euclidean distance.
- **keyhints.lua** — while kopad is on, hides KOReader's keyboard-shortcut letter labels (q w e r t y…) on file browser covers/lists by flipping `BookList.is_enable_shortcut`; restored verbatim when kopad is switched off (nothing is persisted).
- **kopad_trace.lua** — optional flag-file-gated diagnostic trace (see Diagnostics).
- **main.lua** — glues the two together as a `WidgetContainer` and relays the `Gamepad*` broadcasts to `padnav.lua`.

## Diagnostics

If kopad seems to do nothing on a device (and KOReader gives you no log), switch on the on-device trace by creating an empty flag file in KOReader's settings directory:

```sh
touch ~/.var/app/rocks.koreader.KOReader/config/koreader/settings/kopad-trace   # Flatpak
# native Linux: ~/.config/koreader/settings/kopad-trace ; other devices: koreader/settings/kopad-trace
```

From then on (no restart needed, the flag is re-checked every ~2 s) `kopad-trace.log` next to it collects timestamped lines: the mtimes of `main.lua` / `padnav.lua` / `keyhints.lua` (which code actually loaded), the result of loading each sub-module, the `enabled` state, every `Gamepad*` event reaching kopad and why `padnav.lua` passed it through or which handler consumed it. Remove the flag file to stop; without it nothing is written. The log is capped (~256 KB, then only the newest ~64 KB are kept) and rate-limited (~20 lines/s, repeated stick events are collapsed). Implemented in `kopad_trace.lua`; the plugin works without that file.

## Bundled `paginmapo.lua`

This plugin vendors `paginmapo.lua` — a 411-line CRengine helper that extracts visible words with screen positions and xpointer anchors. It is also used by sibling plugins keyreader, marjenoti, and assistant. Each ships its own copy so they remain runtime-independent.

If you maintain a fork or copy and edit `paginmapo.lua` here, keep it identical to the upstream copies in those plugins.

## Compatibility

Targets stock KOReader 2026.07+ (the `Gamepad*` event interface was taken from the 2026.07.1 Flatpak sources; the new handlers are unit-tested against mocks, not yet confirmed on the Steam Deck). Earlier tested with a generic Bluetooth gamepad on KOReader 2026.03 desktop Linux with the patched SDL3 backend, which keeps working through key events.

## License

[AGPL-3.0](LICENSE). Matches KOReader.
