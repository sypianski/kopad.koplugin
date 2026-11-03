---
id: TASK-13
title: >-
  Start w czytaniu = dolne menu ustawień (config_menu) zamiast przełączania
  stopki
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 17:50'
updated_date: '2026-11-03 17:51'
labels:
  - gamepad
  - ux
dependencies: []
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-03 (po teście na Decku): Start przełączał tryb stopki (onToggleFooterMode), co nie jest menu — kolejne naciśnięcia tylko zmieniały pasek. Teraz Start = ShowConfigMenu (dolne menu: czcionka, marginesy, kontrast), symetrycznie do Select = górne menu. Start w otwartym ConfigDialog zamyka go. Przełączanie stopki zostaje na X + D-pad ↓. Zmiana kontraktu DEFAULT_ACTIONS (start: footer_menu -> config_menu) — razem z koligilo (padmap.go, web/padmap.js).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Start w czytaniu (EPUB/PDF) otwiera dolne menu; w nakładce zaznaczania zamyka ją i otwiera dolne menu
- [x] #2 Start w otwartym dolnym menu zamyka je
- [x] #3 DEFAULT_ACTIONS.start = config_menu w kopad i koligilo, testy obu stron
- [x] #4 Nagłówki, ściągawka, README zaktualizowane
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
padnav.lua: onKPStart -> ShowConfigMenu; _menu_button (ctx window) Start zamyka ConfigDialog (is_config_dialog: config_options + closeDialog). padmap.lua DEFAULT_ACTIONS.start = config_menu. koligilo: padmap.go, web/padmap.js (domyślna akcja + etykiety: footer_menu = tryb stopki, config_menu = menu dolne), tests/padmap_test.js. Testy obu stron zielone.
<!-- SECTION:NOTES:END -->
