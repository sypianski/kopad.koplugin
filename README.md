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

A [KOReader](https://github.com/koreader/koreader) plugin that turns a connected **gamepad** into a reading controller — page-turning, menu navigation, and selecting words or sentences for highlight / dictionary / AI lookup.

> *Kopad* — KO(Reader) + (game)pad.

E-readers and reading-mode laptops often sit far from your hands. A gamepad is more relaxed than a keyboard, easier to use one-handed in a recliner or in bed. *Kopad* maps the standard SDL3 gamepad layout to reading actions and adds a word/sentence selector you can drive entirely with the D-pad and the face buttons.

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
| **Start** | bottom menu (font, margins, contrast); **Start** again closes it |
| **D-pad** | next page (→ / ↓) / previous page (← / ↑; in right-to-left books ← / → follow the screen) |
| hold **A** + D-pad | select words: → / ↓ start at the first word of the page, ← / ↑ at the last one; after an action on this page (see *Selection mode*) both start at the last word of that action |
| hold **Y** + D-pad | select sentences: → / ↓ start at the first sentence of the page, ← / ↑ at the last one |
| tap **A** | point from-to: labels at the sentences; a label puts the word cursor at the start of that sentence, then the arrows move it and **RT** held selects (see below) |
| tap **Y** | browse the page's highlights (**D-pad** moves between them); if the page has none, a short message |
| **R-stick** | the quick-action wheel (see below) |
| **L-stick** | nothing |
| hold **X** + D-pad | ↑ menu, ↓ footer, ← history, → files |
| hold **B** + D-pad | ↑ / ↓ font size one step bigger / smaller, ← / → margins narrower / wider (both sides, 5 at a time); hold the D-pad to keep going |
| tap **B** | back to the previous location (after a TOC entry, a link, skimming); never "Exit KOReader?" |
| hold **Y** alone | the Vortpaf glosses on the screen: the first glossed word is inverted, the **D-pad** moves to the next / previous one, **A** opens Vortpaf's card (definition, Other sense, Remove…), **X** its removal (this occurrence / this device / also Vortuyo), **B** closes. Needs Vortpaf 0.7.1+; none on the screen, or no Vortpaf, = a short message |
| hold **X** alone | the page's highlights, noted ones included (as tap **Y**: **A** menu, **X** delete, **B** close) |
| hold **B** alone | the page's notes: the same, only highlights with a note |

The letters follow one rule: a letter held with the D-pad is a mode, a tapped letter is its action, so **A**, **Y** and **B** act when you let go, and only if no arrow was pressed meanwhile. On older patched builds (no button releases) **A**, **Y** and **B** act on the press and the D-pad only turns pages.

**Y**, **X** and **B** held alone for more than about 0.6 s and then let go work on the page you are on instead of their tap: the first gloss / highlight / note is selected and the arrows go on from there (the same in a PDF / DjVu, where Vortpaf has no glosses). Once the 0.6 s are up a short note (e.g. "→ glosses on the page") says what letting go will open; the D-pad or an **X** combo still works after that and then nothing opens. Which action each hold runs can be changed in koligilo (`padmap` key `hold`; `none` turns a hold off); the book-wide lists stay available as actions (`vortpaf_glosses`, `bookmarks_highlights`, `bookmarks_notes`), in Vortpaf's own menu and under **X** + RB.

**X** is a modifier you hold: the combos work while it is down and stop when you let go. On older patched builds (no button releases) and when a trigger is mapped to X, it is a latch instead: press X, then one combo. It is dropped as soon as the pad is used anywhere but plain reading (a menu, a dialog, the selection, the file browser), so it cannot fire as a surprise combo later.

### Quick-action wheel (R-stick)

Push the **R-stick** while reading (EPUB or PDF) and a wheel of quick actions opens, already pointing at the direction you pushed: keep pointing with the stick, **A** runs the action (the wheel closes first), **B** closes the wheel. It looks and works like a dialog wheel (below); its title is a status line (chapter · page n / m · time · battery), and under each action's name the hub shows the other way to it, if there is one (**X** + LB for the table of contents, **B** for going back, …).

| Direction | Reading (EPUB, PDF) | File browser |
|---|---|---|
| ↑ | table of contents | history |
| ↗ | toggle bookmark | favorites |
| → | forward to the next location | collections |
| ↘ | book map | — |
| ↓ | footer mode toggle | previous book |
| ↙ | history | — |
| ← | back to the previous location | top menu |
| ↖ | fulltext search | home folder |

Empty directions are left out, so the wheel has as many sectors as actions. Both sets can be changed in koligilo (`quick` in `padmap`, see Button remapping). After the wheel closes the R-stick does nothing until it is back in the centre, so a stick still held does not open it again. In a PDF the R-stick used to zoom; zoom is now **B** held + D-pad (and the bottom menu).

### Menus versus reading

kopad decides what the pad drives from the window on top of the screen. The reading and selection controls apply **only** while the book itself (or kopad's selection) is on top. Any menu, list, dialog or popup on top gets the pad as plain KOReader keys (D-pad / L-stick navigate, **A** presses, **B** goes back) plus the few additions below. Nothing moves the page underneath it. This works on the `Gamepad*` path (KOReader 2026.07+) only.

#### Top menu open (reader and file browser)

| Button | Action |
|---|---|
| **RB** / **LB** | next / previous category (tab with an icon), wrapping at the ends |
| **RT** / **LT** | next / previous page of the menu, one page per press |
| **Select** | close the menu |
| **D-pad** / **L-stick** ←/→ on the tab bar | previous / next category at once (no **A** needed) |
| **D-pad** / **L-stick** / **A** / **B** / **Start** elsewhere | stock (navigate / press / back / close) |

Tabs that are actions rather than categories (the reader's "file browser" tab, which closes the book) are skipped. The bumpers are consumed in the menu, so the stock page turn on them no longer happens there. Switching the category keeps the cursor where it was: on the tab bar it moves to the new icon, in the items it lands on the first item of the new category. In all menus, lists and the file browser a stick snapping back after release no longer moves the cursor back by one item.

#### Other lists and dialogs (TOC, bookmarks, history, settings, …)

| Button | Action |
|---|---|
| **RT** / **LT** | next / previous page of the list |
| **LB** / **RB** in the bottom menu | previous / next tab |
| **D-pad** / **L-stick** ←/→ on the bottom menu's tab bar | previous / next tab at once (no **A** needed) |
| **Start** in the bottom menu | close it (**Start** opened it) |
| everything else | stock KOReader keys (**Select**, **Start** and stick clicks are swallowed) |

#### Confirmation dialogs (A / B on the buttons)

While kopad is on and a gamepad is connected, KOReader's confirmation and value dialogs carry the pad letter on their buttons — **Ⓐ Delete**, **Ⓑ Cancel** (plain **A · Delete** when the fonts have no circled letters) — and the letters work:

| Dialog | **A** | **B** | **X** / **Y** |
|---|---|---|---|
| Yes/no question (`ConfirmBox`: delete, overwrite, reset, …) | the action (OK, Delete, …) | Cancel | — |
| Three-way question (`MultiConfirmBox`) | the main choice, by its text (Save, Connect, Open, Yes, Download) | Cancel | **X** = the other choice (Discard, Turn Wi-Fi off, Another, No); a pair without a main choice (Default / Fallback, http / https) gets **X** = left, **Y** = right and no **A** |
| Number, two numbers, date / time, list of options (`SpinWidget`, `DoubleSpinWidget`, `DateTimeWidget`, `RadioButtonWidget`) | Apply / Set | Close | — |
| Text input (`InputDialog`) | the main button (Save, Search, …) | Cancel / Close | **X** = backspace, **Y** / **Start** = on-screen keyboard (Steam's on a Steam Deck) |

**A** follows the label only while nothing is highlighted. Once the D-pad has moved the focus (to a button, a ▲/▼ arrow, an option in a list), **A** presses what is highlighted, as in stock KOReader, and **Start** still does the labelled **A** action (in a text dialog **Start** opens the keyboard instead). **LB** / **RB** change the value in the number dialogs (stock).

#### Dialogs as a wheel

Dialogs that KOReader draws as a grid of buttons in the middle of the screen (`ButtonDialog`: kopad's own action menu, a highlight's menu, a file's long-press menu, …) open as a **wheel** while kopad is on, as in console games: the wheel is cut into as many sectors as there are buttons, each with a monochrome glyph; the selected sector is black and pops out of the rim, and its label is printed in the centre. The wheel has no frame: it sits on a white disc over the page, with the dialog's title in a pill above it (or, for kopad's action menu and KOReader's highlight menus, the text they are about) and the buttons A / B (X, LB / RB with the page number when they apply) in a pill below. Switch it off per device in *kopad → Dialogs as a wheel (this device)*.

| Button | Action |
|---|---|
| **L-stick** / **R-stick** | point at a sector (8 directions, the nearest sector wins, a tie goes clockwise; the selection stays when the stick is let go) |
| **D-pad** ←/↑, →/↓ | previous / next sector |
| **A** | run the selected button |
| **X** | its long-press action, when it has one |
| **B** | close |
| **LB** / **RB**, **LT** / **RT** | previous / next page (dialogs with more than 8 buttons; at most 16) |

Touch works too: tap a sector to run it, the centre for the next page, the page around the disc and the pills to close. Dialogs with check boxes or input fields, and dialogs with more than 16 buttons, stay as they are. KOReader reports a stick only when it crosses the dead zone, not its angle, so the wheel has 8 directions (see the header of `wheel.lua`).

#### File browser

| Button | Action |
|---|---|
| **D-pad** / **L-stick** / **A** | stock list navigation |
| **B** | parent folder (KOReader's own Back would ask "Exit KOReader?"; quitting stays in the menu) |
| **RB** / **LB**, **RT** / **LT** | next / previous page of the list |
| **Select** | top menu |
| **R-stick** | the quick-action wheel (library actions) |

### Point from-to (tap A)

A tap on **A** while reading puts a small label next to the start of every sentence on the page. Each label is two pad symbols: a D-pad direction (↑ ↓ ← →, drawn as squares) or a letter (**A** **B** **X** **Y**, drawn as circles); after the first symbol only the labels going on with it stay on screen. Pressing a sentence's whole label puts the word cursor on that sentence's first word (its first word on the screen, for a sentence that began on the previous page or above a zoomed PDF view). Nothing is selected yet: from there it is the word level of the selection (below). **←** / **→** move by a word, **↑** / **↓** by a line (the **D-pad** and the **L-stick** alike), and holding **RT** selects by those same steps.

Right after the label there is a short sentence phase (the status line says START): as long as the cursor is still on the sentence's first word and nothing else has moved it, **RT** + arrows go by whole sentences:

| right after a label | with **RT** held |
|---|---|
| **↓** | the whole sentence (from its first word to its last word on the page); again: to the end of the next sentence |
| **↑** | one sentence off; the last one off = nothing selected, the cursor back on the first word |

The first other move ends the phase: an arrow without **RT** (**↓** then simply goes one line down), or **RT** + **←** / **→**, which moves the end of the sentence range by a word and keeps it. After that **RT** + **↑** / **↓** go by a line. So a whole sentence is: its label, hold **RT**, **↓**; two sentences: one more **↓**; a sentence and one word more: the label, hold **RT**, **↓**, **→**. To start from another sentence, press **B** (back to the labels) and pick a new label. A range never leaves the page. Letting go of **RT** keeps the range; holding it again goes on from there. Tap **A** for the action menu. **B** goes back one step: a range is dropped (the cursor stays where its end was; that also ends the sentence phase), then the sentence labels come back (on the page shown now), then the selection closes.

The sentence labels follow the place of the target, like the link labels of the Vivaldi setup on the Deck: targets near the top start with ↑ or **Y**, those at the bottom with ↓ or **A**, the middle with ←, → or **X**, and neighbours share their first symbol. Every label is two presses, even on a short page (a lone target in its group repeats the symbol, e.g. ↑↑). No label starts with **B**: **B** before any symbol closes the labels; after a symbol it drops that symbol, unless a label goes on with **B**. That leaves room for 56 sentences on a page; sentences beyond that get no label. The R-stick does nothing while the labels are up. In right-to-left scripts **←** and **→** swap. Only on KOReader 2026.07+ (`Gamepad*` events); on older patched builds a tap on **A** still opens the sentences.

(Until TASK-42 / PC-024 the labels went on over the words of the sentence, in stages of **A** / **X** / **Y**, with an end step and arrow shortcuts; that was hard to predict on the Deck and is gone. TASK-42 then made the D-pad ↑ / ↓ jump by sentence in the words and TASK-43 put the lines on the L-stick; that did not work on the Deck either, so since TASK-44 / PC-025 ↑ / ↓ are lines everywhere and sentences go only through the phase right after a label.)

### Selection mode (sentences and words)

The selection has two levels: sentences (opened with **Y** + D-pad) and words (opened with **A** + D-pad, or by point from-to). The arrows do the same on both, one step bigger on the sentence level.

| Button | Words | Sentences |
|---|---|---|
| **D-pad** / **L-stick** ←/→ | previous / next word | previous / next sentence |
| **D-pad** / **L-stick** ↑/↓ | the word on the line above / below, under the cursor (a word hyphenated over two lines counts on both) | start of this or the previous paragraph / next paragraph |
| hold **RT** + arrows | select a range from the word where the first move began: ←/→ by a word, ↑/↓ by a line; right after a sentence label ↓/↑ by whole sentences (see *Point from-to*) | — |
| **RT** / **LT** | **RT** held = the range above, **LT** nothing | next paragraph / start of this or the previous paragraph (as ↓/↑) |
| hold **A** + arrows | the same as **RT** held (the older way) | select a range from the sentence where you pressed A, in both directions (going back past it shrinks the range, then grows it on the other side) |
| tap **A** | action menu (dictionary, AI, copy, note), when you let go | same |
| **R-stick** ↓ | — | go to the first word of this sentence (word level) |
| **R-stick** ↑ | go to the sentence containing this word | — |
| **Y** | Vortuyo lookup | same |
| **X** | toggle highlight | same |
| **B** | drop the range; without one go back to the sentence labels (when you came from them) or close | close the selection |
| **RB** / **LB** | close the selection and turn the page | same |
| **Select** / **Start** | close the selection and open the top / bottom menu | same |

Every action closes the selection at once: highlight or remove a highlight (**X** or the menu), note, dictionary, AI, Vortuyo (**Y** or the menu) and copy. The dictionary popup, the note window, the AI answer and the Vortuyo card open over the page, and there is no selection left to close with **B** afterwards. kopad remembers where the last action ended (only while the book stays open; nothing is saved): the next time you open the words with **A** held + D-pad on that page (in a PDF: with that word on the screen), the cursor starts on the last word of that action instead of the first / last word of the page. Elsewhere, and for the sentences (**Y** + D-pad), it starts as before.

The **A** you hold to open the words is not a range yet: while it is still down the arrows only move the cursor, so you can pick the word where the range starts (or a single word). Let go, then hold **A** again and move to select from there.

The arrows cross the page edge in both directions: ← on the first word goes to the last word of the previous page, ↓ on the last line to the next page's first word, ↑ on the first line to the previous page's last word. A sentence that runs over the edge counts once. A range (RT or A held) stays on its page. A held D-pad repeats its step (after about half a second, then about seven steps a second) and speeds up after a few steps, up to twenty a second; a held **L-stick** repeats as well (KOReader's own stick repeat), with **RT** held too. On the sentence level **RT** / **LT** jump by paragraph, over the page edge too; held, they keep jumping, and with **A** held they grow the range by paragraphs. On the word level they do not move the cursor (**RT** held is the range there). With the highlights (**Y**) they go to the next / previous one. The status line shows the level (WORD / WORDS, START right after a label, SENTENCE / SENTENCES, HIGHLIGHT) and the buttons, with no counters. It never covers the text of the page: it sits in the free strip above the first line or below the last one, shrinks to the level and A / B when the strip is tight, and is not drawn at all when there is no room.

While browsing highlights (**Y**): the **D-pad** moves to the previous / next one (wrapping), **X** removes it (and closes the selection, as every action), and **A**, **Y** and **B** work as above.

On older patched builds there are no button releases, so **A** opens the action menu at once and **RB** / **LB** grow / shrink the selection at its moving end instead of turning the page.

In the dictionary popup **LB** / **RB** cycle dictionaries, **Y** asks the AI to explain the looked-up words (when the popup was opened by kopad's Dictionary action) and **B** closes the popup. Everything else reaches the popup as stock keys; the triggers do nothing there.

### Input paths, Select / Start and the triggers

On **KOReader 2026.07+** every button and axis arrives as a `Gamepad*` event and is mapped by id in `padnav.lua` (`onGamepadButtonDown` / `onGamepadAxisMotion`, relayed from `main.lua`). While kopad is enabled:

- **Select** / **Start** open the top / bottom menu; **LT** / **RT** turn the page, one page per press (the stock auto-repeat of held axes is filtered out; in the selection on the sentence level it goes through, so a held trigger keeps jumping paragraphs; on the word level a held **RT** is the range modifier and its repeat does nothing). With the top menu open they turn the menu page instead (same one-press filter), and **LB** / **RB** switch the category.
- The **R-stick** never turns pages by itself any more (stock maps its Y axis to page back/forward with auto-repeat, which flipped pages endlessly). Its auto-repeat is kept for navigation.
- **Guide**, **L3** and **R3** are swallowed so a stick click cannot open a menu or turn a page. In an EPUB kopad handles the D-pad itself (so that a held D-pad can repeat); elsewhere it is passed through to the original Up/Down/Left/Right keys.
- Button releases (`GamepadButtonUp`) end holding **A** (range, or a tap for the menu), holding **X** and a D-pad repeat. They are remapped like the presses.
- With kopad disabled nothing is intercepted. With a menu, list, dialog or the dictionary popup on top, only the additions listed under *Menus versus reading* are intercepted; everything else behaves as stock.

On **older patched builds** there are no such events; buttons arrive as key names (`LPgBack`/`LPgFwd` for LT/RT, F-keys for the R-stick and X). Select and Start are then bound to **F12** / **F2**: add a hunk to `sdl3_gamepad.patch` that sends keycodes `1073741893` (F12) for `SDL_GAMEPAD_BUTTON_BACK` and `1073741883` (F2) for `SDL_GAMEPAD_BUTTON_START`. Until then those two bindings are inert and the menus stay reachable via **X** + D-pad. The back paddles **L4** / **R4** (`ScrollLock` / `Pause`) are aliases of **LB** / **RB** on these patched builds only; on KOReader 2026.07+ they are not handled (SDL paddle ids have no stock mapping and Steam Input usually does not expose them).

### Visel overlay (opt-in via pluginaro)

If the [keyreader](https://github.com/sypianski/keyreader.koplugin) plugin is installed, kopad can also drive its **visel** selection. It is off by default; switch it on in keyreader's menu under *Extensions* ("visel: Steer also with gamepad (kopad)"). kopad's own menu only points you there.

With `visel.ext.kopad.gamepad_select` enabled: **D-pad** / **L-stick ←/→** move the selection, **RB** / **LB** extend / trim it, **B** closes it.

Without keyreader, or with the switch off, nothing changes. Windows opened by other plugins get the pad as stock KOReader keys (see *Menus versus reading*), apart from dictation below.

### Text fields and dictation (diktonoti, opt-in via pluginaro)

In any dialog with a text field (a note to a highlight, search, dictionary lookup, …): **X** = backspace, **A** = accept (the dialog's main button: Save, Search) while the focus is on the field, **Y** or **Start** = the on-screen keyboard (under Steam — Steam Deck, Big Picture — Steam's own, elsewhere KOReader's), **B** = close without saving. Held **X** deletes whole words, held D-pad **←** / **→** moves the cursor by words (a tap = one character).

The note window of the selection's action menu opens with the highlight's saved note, is wide, and grows from a medium to a large height once the text no longer fits; an emptied note is removed when saved.

While kopad is enabled and a gamepad is connected, these dialogs open **without the on-screen keyboard** (it would cover half of the screen), and moving the focus back onto the field with the D-pad does not bring it up either. On a Steam Deck this includes Steam's own keyboard, which SDL would otherwise open over KOReader (and which takes the pad over: its hide button closed the dialog); press **Y** or **Start** (Steam's keyboard on a Deck), or tap the field (KOReader's keyboard). Dictation and typing go into the same field in any order: dictate, open the keyboard, add by hand, close it, dictate again. While Steam's keyboard is up Steam owns the pad (RT types there); under KOReader's keyboard the D-pad and **A** type, **B** hides it and **RT** still dictates. Hiding a keyboard never closes the dialog, Steam's own (Steam + X) included.

With the diktonoti plugin and its switch on (diktonoti's menu → *Extensions*): **hold RT** and speak — on release the text is recognized by the Diktilo daemon on the Steam Deck and inserted at the cursor; **B** during a recording cancels it, the other buttons do nothing until it ends. Dictation comes first in a text dialog: RT works with the on-screen keyboard open, over another plugin's selection, and with the focus on the dialog's buttons (it moves back to the field). (Not a stick click: on the Deck, Steam Input does not pass L3 / R3 to KOReader.) Without diktonoti, or with the switch off, RT does nothing there.

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
    ["quick"] = { ["reading"] = { ["up"] = "toc", ["left"] = "back_location" } },   -- optional
},
```

Keys are physical controls by position — `south east west north back start lshoulder rshoulder ltrigger rtrigger` — and values are roles — `a b x y select start lb rb lt rt`. A button may take a trigger role and vice versa. Controls not listed keep the layout's default. Anything malformed (other `version`, unknown names, wrong types) is skipped with a log warning; with no data kopad behaves exactly as without remapping. The D-pad, sticks, Guide/L3/R3 and the older patched-build key path are not remappable, and when kopad passes an event through to KOReader (kopad off, a dialog on top), KOReader sees the physical button. The pure logic is `padmap.lua`, tested by `lua tests/padmap_test.lua`.

**Changing what a role does.** `actions` goes one step further: it says what a *role* does while you are plainly reading, e.g. RB opening the top menu (where KOReader's settings live) instead of turning the page. It is keyed by role, not by physical button, so it is shared by every layout and survives switching pads. Values (a closed list, grouped as in the koligilo panel): pages — `next_page prev_page pages_forward_10 pages_back_10 next_chapter prev_chapter first_page last_page back_location forward_location goto_page skim`; menus — `top_menu footer_menu config_menu`; book — `toc bookmarks toggle_bookmark next_bookmark prev_bookmark book_map page_browser fulltext_search book_status book_info reading_progress`; library — `history file_browser last_book favorites collections`; selection and dictionary — `sentence_select highlights word_walk crosshair dict_lookup` (`crosshair` is kept for older koligilo data and now opens the word level, like `word_walk`); display — `font_bigger font_smaller zoom_in zoom_out zoom_fit_width zoom_fit_page night_mode rotate full_refresh frontlight_toggle frontlight_up frontlight_down`; other — `screenshot cheat_sheet x_modifier none`. Most of them send the same KOReader event its own gestures and profiles use, so an action KOReader has no handler for on this device or document (frontlight on a desktop, font size in a PDF, zoom in an EPUB, `reading_progress` without the statistics plugin) does nothing. Defaults: A `sentence_select`, X `x_modifier`, Y `highlights`, LB/LT `prev_page`, RB/RT `next_page`, Select `top_menu`, Start `config_menu` (until kopad TASK-13: `footer_menu`; the footer mode toggle stays on **X** + D-pad ↓); B has no default action id; it goes back to the previous location, like `back_location`. Roles not listed keep their default.

An override applies only in the idle reading context: the book itself is on top (no menu, list, dialog, dictionary popup or selection) and no X combo is pending. Everywhere else the role keeps what it does today (RB still closes a selection and turns the page, and switches menu categories, LT/RT still turn menu pages, X + D-pad / X + LB / X + RB still reach the menus, TOC and bookmarks), and in the file browser buttons act as before. `sentence_select`, `word_walk` and `crosshair` need the selector (EPUB and other reflowable documents); in a PDF the press is swallowed. `highlights` works in a PDF too. The cheat sheet in the menu lists the roles you changed. kopad versions without this stage ignore the `actions` key and read `layouts` as before. koligilo edits it in the panel under *Wtyczki → Ustawienia wtyczek → Gamepad (KOPad): akcje w czytaniu*.

**The quick-action wheel.** `quick` (optional, PC-021) holds the two sets of the R-stick wheel: `reading` (EPUB and PDF) and `files` (the file browser). A set maps a stick direction — `up up_right right down_right down down_left left up_left` — to an action from the list above. A set you give **replaces** the built-in one whole: a direction it does not name is empty (`none` too), and an empty set means the R-stick does nothing there. `x_modifier` is never allowed, and `files` takes only actions that work without a book: `history favorites collections last_book top_menu file_browser night_mode rotate full_refresh frontlight_toggle frontlight_up frontlight_down screenshot cheat_sheet`. Bad entries are skipped with a warning; a missing set is the built-in one. kopad versions without the wheel ignore the key. koligilo edits it in the same card, tab *Koło szybkich akcji*.

### Scope

The selection works in EPUBs and, on pages with a text layer, in PDF / DjVu (words and sentences from KOReader's text boxes; highlights and notes are saved like a finger selection, so KOReader shows them, keeps them after reopening and, if set to, writes them into the PDF). In paged documents no reader keys are suppressed and, while no selection is open, the pad steers the view (stock KOReader 2026.07+ `Gamepad*` path). Only the bumpers and the triggers change the page, always by a whole page, so nothing else turns pages by surprise:

| Button | Action |
|---|---|
| **D-pad** | move around the page slowly (about a tenth of the screen per press); never turns the page |
| **L-stick** | move around the page fast (half a screen per step, keeps moving while held); never turns the page |
| **R-stick** | the quick-action wheel, the same as in an EPUB (it never turns or zooms the page) |
| **hold B + D-pad ↑ / ↓** | zoom in / out in small steps, 3 % each (hold the D-pad to keep zooming) |
| **hold B + D-pad ← / →** | fit the whole page / fit the text width; tap **B** = back |
| **hold A + D-pad** | select words, as in an EPUB: → / ↓ from the first word on the screen, ← / ↑ from the last; after an action on this page, from its last word when that is on the screen |
| **hold Y + D-pad** | select sentences (the same) |
| **tap A** | point from-to: labels at the sentences on the screen; a label = the word cursor at that sentence's start |
| **tap Y** | the page's highlights, as in an EPUB: the D-pad steps between them (the view pans to each), **X** removes one; none = a message |
| **LB / RB**, **LT / RT** | previous / next page (the new page starts at the top) |

Moving around needs page view, so the first time kopad runs enabled on a device it makes page view the default for new documents (`kopt_page_scroll = 0`; continuous view is KOReader's own default and scrolls into the next page). A document that still remembers continuous view switches to page view on the first D-pad or L-stick move, and KOReader remembers that per document. Turning continuous view back on in KOReader afterwards is respected. In page view at text width the page already fits sideways, so ← / → only move once you zoom in.

X + D-pad still opens the menus, and role overrides from koligilo still win over these defaults.

The selection in a PDF / DjVu uses the same buttons as in an EPUB (arrows, ranges with RT or A held, the R-stick levels, **A** action menu, **Y** Vortuyo, **B** back / close); **LB / RB** close it and turn a whole page, every action closes it as in an EPUB, and moving past the first / last word goes on to the previous / next page. The boxes follow zoom and panning, and moving onto a word outside the zoomed view pans the view to it. **X** highlights the selection, or removes the highlight if exactly these words are already highlighted (also one made with a finger); the action menu has Dictionary, Copy, Highlight, Note, AI explain and Vortuyo. Highlights use your KOReader highlight style. A selection stays on one page, so a highlight never spans pages. Paragraphs are guessed from the layout (line spacing, indent, short last line, two columns), so ↑ / ↓ and **LT / RT** in sentences jump by paragraph as in an EPUB; on an unusual layout the guess can be off. A scanned page without a text layer, or reflow mode, shows a message instead of opening the selection.

## Technical notes

### How it works

- **padmap.lua** — pure (KOReader-free) remapping layer: physical SDL button/trigger → logical role, per layout (see Button remapping).
- **padnav.lua** — gamepad event handler. Maps buttons + axes (`Gamepad*` events on KOReader 2026.07+, key events on older patched builds) to KOReader events.
- **kopad_hints.lua** — pure (KOReader-free) labels of point from-to: the eight pad symbols placed by position at the sentences, and the pointer that turns the pressed symbols into a sentence and its first visible word (B). Knows no document type: EPUB and PDF hand it word boxes and sentences as word-index ranges.
- **selector.lua** — the selection overlay: sentence, word, highlight and point from-to modes, ranges, page crossing. Pulls visible word positions and sentences from the bundled `paginmapo.lua` (Ido for "page-map"); in PDF / DjVu its `PagedOverlay` takes them from `pdfwords.lua`.
- **pdfwords.lua** — pure word source for PDF / DjVu: KOReader's `getTextBoxes` lines turned into the overlay's word list (page boxes, sentence ends, lines), sentences grouped by `paginmapo.lua`, words in reading order.
- **pdfpara.lua** — pure paragraph detection for PDF / DjVu pages from the text-line rectangles (one or two columns; line pitch, first-line indent, short last line, list markers). Gives the paragraph numbers behind **LT / RT** and ↑ / ↓ in a PDF.
- **wheel.lua** — turns plain `ButtonDialog`s into a radial menu (wraps `ButtonDialog.init`, replaces only the dialog's content, so button callbacks keep working); glyphs come from KOReader's bundled Nerd Font symbols.
- **keyhints.lua** — while kopad is on, hides KOReader's keyboard-shortcut letter labels (q w e r t y…) on file browser covers/lists by flipping `BookList.is_enable_shortcut`; restored verbatim when kopad is switched off (nothing is persisted).
- **padconfirm.lua** — puts the pad letters on the buttons of confirmation and value dialogs (wraps the dialogs' `init` once, prefixes `ok_text` / `cancel_text` / `choice*_text`; circled letters when a bundled font has them) and presses the labelled button for **A** / **B** / **X** / **Y**.
- **padopen.lua** — opens every connected gamepad: KOReader itself opens only the first one, so a second pad (e.g. an 8BitDo next to the Steam Deck's own controller) sent nothing.
- **kopad_trace.lua** — optional flag-file-gated diagnostic trace (see Diagnostics).
- **main.lua** — glues the two together as a `WidgetContainer` and relays the `Gamepad*` broadcasts to `padnav.lua`.

### Working with other plugins

kopad is the only plugin in the family that reads the gamepad. Another plugin that wants pad control publishes the actions it can do through `pluginaro` (the shared opt-in registry, `pluginaro.lua`, vendored here) and kopad calls them; the plugin does not read the pad itself. Every such integration is off by default, is switched on in the *host* plugin's menu, and does nothing if either side is missing. Visel is the only one today. The rules, the visel contract and a checklist for adding another are in [`CLAUDE.md`](CLAUDE.md); to propose one, open an issue.

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

The automated tests: the remapping layer (`padmap.lua`) with the pad wiring in `padnav.lua`, the wheel's sectors, pages, stick directions, titles, taps, glyphs and controller (`wheel.lua`), and the selection overlay (`selector.lua`):

```bash
lua tests/padmap_test.lua
lua tests/padconfirm_test.lua
lua tests/padopen_test.lua
lua tests/wheel_test.lua
lua tests/selector_test.lua
lua tests/kopad_hints_test.lua
lua tests/pdfwords_test.lua
lua tests/pdfpara_test.lua
```

`selector_test.lua` drives the selection overlay (`selector.lua`) on a fake three-page document: sentence, paragraph, word and line moves, page crossing, ranges (RT held: by word and line; right after a label by whole sentences, and what ends that phase), level switches, highlights, point from-to (label -> words, B back to the labels). `kopad_hints_test.lua` checks the labels of point from-to (`kopad_hints.lua`): placement by position, two symbols, unique, at most 56, the prefix filter, **B**, a label = its sentence's first visible word, RTL.

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
