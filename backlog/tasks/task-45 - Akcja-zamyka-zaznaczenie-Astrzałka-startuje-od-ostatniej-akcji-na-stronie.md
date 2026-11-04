---
id: TASK-45
title: Akcja zamyka zaznaczenie; A+strzałka startuje od ostatniej akcji na stronie
status: Done
assignee: []
created_date: '2026-11-04 09:32'
updated_date: '2026-11-04 09:43'
labels: []
dependencies: []
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Feedback usera po 0.1.15 (2026-11-04): (1) po wykonaniu akcji (zakreślenie, notatka, słownik, AI, Vortuyo, kopiowanie; z menu akcji i bezpośrednio X / Y) wychodzenie przez kolejne B trwa za długo — akcja ma od razu zamykać nakładkę zaznaczenia. (2) Wejście w tryb słów przez A trzymane + D-pad (czytanie, EPUB i PDF): gdy na bieżącej stronie była w tej sesji wykonana akcja na słowie / słowach, kursor startuje od ostatniego słowa tej ostatniej akcji zamiast od pierwszego (→/↓) / ostatniego (←/↑) słowa na ekranie; inaczej jak dziś.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Każda akcja na zaznaczeniu (menu akcji i X / Y w zaznaczeniu) zamyka nakładkę od razu; słownik / AI / notatka / Vortuyo dalej działają (także Y = AI w okienku słownika)
- [x] #2 A trzymane + D-pad przy czytaniu zaczyna od ostatniego słowa ostatniej akcji, gdy jest ono na bieżącej stronie / ekranie; bez niej jak dziś; EPUB i PDF
- [x] #3 Testy zielone; CLAUDE.md, README zaktualizowane
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: 12 testów zielonych, luac czysto; przejrzane SelectorOverlay:act, Selector:_acted, dict_selection, _resume_land. Wybory: wznowienie także dla akcji padmapy word_walk (ten sam _open_walk); act zamyka także przy pustym słowie / braku Vortuyo, zostaje tylko bez zaznaczenia. Na urządzeniu do sprawdzenia: Y = AI w okienku słownika po zamknięciu nakładki.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Akcja zamyka zaznaczenie; A+strzałka wznawia od ostatniej akcji na stronie
<!-- SECTION:FINAL_SUMMARY:END -->
