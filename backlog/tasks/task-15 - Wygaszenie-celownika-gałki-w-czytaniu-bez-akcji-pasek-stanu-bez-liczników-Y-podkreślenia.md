---
id: TASK-15
title: >-
  Wygaszenie celownika, gałki w czytaniu bez akcji, pasek stanu bez liczników, Y
  = podkreślenia
status: Done
assignee: []
created_date: '2026-11-03 19:14'
updated_date: '2026-11-03 19:37'
labels:
  - ux
dependencies: []
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-03 (nowe mapowanie pada). Celownik (tryb cross) usunięty z kodu; akcja padmap 'crosshair' zostaje w słowniku (kontrakt z koligilo) jako alias word_walk. W czytaniu EPUB L-stick i R-stick nic nie robią (rozstrzyga TASK-12, wariant 1). Pasek stanu zaznaczenia bez liczników (SENT 3/12 itd.). Y w czytaniu: przeglądanie podkreśleń na stronie (D-pad ←/→ między nimi), gdy ich brak — komunikat zamiast celownika.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Brak trybu cross w selector.lua i padnav.lua; crosshair = alias word_walk
- [x] #2 L-stick i R-stick w czytaniu EPUB pochłonięte bez akcji
- [x] #3 Pasek stanu bez liczb
- [x] #4 Y: podkreślenia, D-pad ←/→ między nimi; brak podkreśleń = komunikat
- [x] #5 Nagłówki, ściągawka, README, CLAUDE.md, testy zgodne
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
selector.lua przepisany na trzy tryby (struct / walk / hl), krzyżyk usunięty; padmap 'crosshair' = alias word_walk (_open_walk). Gałki w czytaniu pochłonięte. Pasek stanu bez liczników. Y bez podkreśleń = komunikat 'No highlights on this page'. Testy: padmap_test sekcja 14, selector_test.
<!-- SECTION:NOTES:END -->
