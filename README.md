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

### Reading mode

| Button | Action |
|---|---|
| **D-pad ↑** / **↓** | scroll up / down |
| **D-pad ←** / **→** | previous / next page |
| **L1** / **R1** (shoulders) | previous / next chapter |
| **L2** / **R2** (triggers) | font size − / + |
| **A** (south) | open selector / confirm word |
| **B** (east) | dictionary lookup of current word |
| **X** (west) | highlight |
| **Y** (north) | AI assistant on current word |
| **Start** | menu |
| **Select** | book map |

### Selector mode (right-stick crosshair)

Press **A** to enter selector mode. A crosshair appears at the screen centre.

- **Right stick** — move crosshair freely
- **A** — snap to nearest word, then enter word mode
- **D-pad** — in word mode, step word-by-word
- **B** — dictionary lookup
- **X** — highlight selected word
- **Y** — AI assistant
- **A** (again) — exit selector

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
