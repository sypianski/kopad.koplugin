---
id: TASK-9
title: 'Przeglądarka plików i tryb X: LB/RB/LT/RT przewijają listę, tryb X nie wisi'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 17:14'
updated_date: '2026-11-03 17:27'
labels:
  - gamepad
  - bug
dependencies:
  - TASK-7
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
W FileManagerze kopad zjada LB/RB (GotoViewRel nic nie robi), a stock RPgBack/RPgFwd przewija stronę listy; LT/RT też nic. X włącza _x_mode, ale X+D-pad tam nie działa (FileChooser zjada strzałki), więc tryb wisi. _x_mode nie jest kasowany po wejściu w menu/dialog.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 W FileManagerze LB/RB przewijają stronę listy (stock), LT/RT też przewijają stronę listy
- [x] #2 _x_mode jest kasowany, gdy kontekst przestaje być reading/paged; w FileManagerze X nie włącza martwego trybu
- [x] #3 Test w tests/
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Kontekst filemanager w Gamepad*: _filemanager_button (Select = menu górne, reszta stock lub BUTTON_SWALLOW), LB/RB stockowe RPgBack/RPgFwd = strona listy, LT/RT przez _menu_trigger na ui.file_chooser, obie gałki stockowe. onKPExtend nie włącza trybu X bez dokumentu. _drop_x_mode kasuje _x_mode, gdy pad jest używany poza reading/paged (menu, okno, słownik, zaznaczanie, FileManager). Testy w sekcjach 10 i 11. Niezweryfikowane na urządzeniu.
<!-- SECTION:NOTES:END -->
