# kopad.koplugin

A [KOReader](https://github.com/koreader/koreader) plugin that turns a connected **gamepad** into a reading controller — page-turning, menu navigation, and a crosshair cursor that snaps to nearest words for highlight / dictionary / AI lookup.

> *Kopad* — KO(Reader) + (game)pad.

## Why

E-readers and reading-mode laptops often sit far from your hands. A gamepad is more relaxed than a keyboard, easier to use one-handed in a recliner or in bed, and KOReader has no built-in support for one. *Kopad* maps the standard SDL3 gamepad layout to reading actions and adds a structured word/sentence selector you can drive entirely with the right stick + face buttons.

## Install

Requires KOReader built with SDL3 gamepad support. See `sdl3_gamepad.patch` in the upstream konfig repo for the build patch.

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

Written for a Steam Deck / DualSense (via Steam Input) using the SDL3 gamepad patch. LT/RT are the lower trigger buttons under the index fingers; LB/RB the bumpers above them. The same map is available on-device under *menu > kopad > Button cheat sheet*.

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

### Select / Start key names

The stock SDL3 patch does not emit a known key for Select and Start. kopad binds them to **F12** (Select) and **F2** (Start); add a hunk to `sdl3_gamepad.patch` that sends keycodes `1073741893` (F12) for `SDL_GAMEPAD_BUTTON_BACK` and `1073741883` (F2) for `SDL_GAMEPAD_BUTTON_START`. Until then those two bindings are inert and the menus stay reachable via **X** + D-pad.

### Visel overlay (opt-in via pluginaro)

With `visel.ext.kopad.gamepad_select` enabled: **D-pad** / **L-stick ←/→** move the selection, **RB** / **LB** extend / trim it, **B** closes it.

### Scope

The selector (word walk / struct / crosshair) only exists for crengine (rolling) documents. In paged documents (PDF/DjVu) and in the FileManager no reader keys are suppressed and selector-dependent handlers pass through — only page turns and X-combos remain active there.

## How it works

- **padnav.lua** — SDL3 gamepad event handler. Maps buttons + axes to KOReader events.
- **selector.lua** — crosshair widget + word-snap logic. Pulls visible word positions from the bundled `paginmapo.lua` (Ido for "page-map") and finds the nearest by Euclidean distance.
- **main.lua** — glues the two together as a `WidgetContainer`.

## Bundled `paginmapo.lua`

This plugin vendors `paginmapo.lua` — a 411-line CRengine helper that extracts visible words with screen positions and xpointer anchors. It is also used by sibling plugins keyreader, marjenoti, and assistant. Each ships its own copy so they remain runtime-independent.

If you maintain a fork or copy and edit `paginmapo.lua` here, keep it identical to the upstream copies in those plugins.

## Compatibility

Tested with a generic Bluetooth gamepad on KOReader 2026.03 desktop Linux with the SDL3 backend.

## License

[AGPL-3.0](LICENSE). Matches KOReader.
