---
id: TASK-11
title: >-
  Pad w menu i B: zakładki strzałkami, LB/RB bez gubienia kursora, B nie
  wychodzi z KOReadera
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 17:37'
updated_date: '2026-11-03 17:42'
labels:
  - gamepad
  - ux
dependencies: []
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Test usera na Decku 2026-11-03 (ślad kopad-trace.log): w menu górnym zmiana zakładki strzałkami wymaga Prawo + A (FocusManager przesuwa tylko kursor po pasku), kursor po zmianie zakładki jest niewidoczny na pasku; B kilka razy w czytaniu (ReaderBack: pusta historia -> powiadomienie -> 'Exit KOReader?') i raz w przeglądarce plików (FileChooser:onBack -> 'Exit KOReader?') prowadzi do wyjścia z KOReadera.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Menu górne: gdy kursor jest na pasku zakładek, D-pad ←/→ od razu przełącza zakładkę (z pominięciem zakładek-akcji), kursor zostaje widoczny na nowej ikonie
- [x] #2 Menu górne: LB/RB (i ←/→ na pasku) zostawiają kursor na tym samym poziomie: na pasku -> nowa ikona, w pozycjach -> pierwsza pozycja nowej zakładki
- [x] #3 Czytanie (EPUB i PDF) bez nakładki: B = powrót do poprzedniego miejsca (ReaderLink:onGoBackLink), nigdy pytanie o wyjście z KOReadera
- [x] #4 Przeglądarka plików: B = folder wyżej (FileChooser:onFolderUp), nigdy pytanie o wyjście
- [x] #5 Testy w tests/padmap_test.lua, README, CLAUDE.md, nagłówek padnav.lua i ściągawka zaktualizowane
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
padnav.lua: menu_switch_tab/menu_focus_on_bar (pasek zakładek: D-pad i L-gałka ←/→ przełączają od razu; LB/RB trzymają poziom kursora), Select zamyka menu, filtr odbicia gałki w menu (MENU_STICK_LOCK_S). B w czytaniu = ReaderLink:onGoBackLink(true), zawsze pochłaniane; w przeglądarce plików = FileChooser:onFolderUp. Testy: sekcja 11 w tests/padmap_test.lua. Dokumentacja: README, CLAUDE.md, nagłówek padnav.lua, ściągawka, komentarz DEFAULT_ACTIONS w padmap.lua.
<!-- SECTION:NOTES:END -->
