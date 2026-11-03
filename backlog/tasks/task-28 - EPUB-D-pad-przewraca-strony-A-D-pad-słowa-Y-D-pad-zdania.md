---
id: TASK-28
title: 'EPUB: D-pad przewraca strony, A + D-pad = słowa, Y + D-pad = zdania'
status: To Do
assignee: []
created_date: '2026-11-03 20:52'
labels:
  - gamepad
  - ux
dependencies: []
priority: high
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-03: wspólne wejście w zaznaczanie dla EPUB i PDF przez kombinację przycisku z D-padem, bo D-pad w czytaniu ma nawigować (w PDF przesuwa widok, w EPUB ma przewracać strony). W czytaniu EPUB: D-pad ←/→ = poprzednia / następna strona (↑/↓ do ustalenia przy implementacji, domyślnie też strona). A przytrzymane + D-pad = słowa (→/↓ od pierwszego słowa strony, ←/↑ od ostatniego). Y przytrzymane + D-pad = zdania (→/↓ od pierwszego zdania, ←/↑ od ostatniego). Stuknięcie A (puszczenie bez D-pada) = tryb 'wskaż od-do' (osobny tiket), stuknięcie Y = podkreślenia strony (jak dziś, ale przy puszczeniu). X + D-pad = menu (bez zmian), B = wstecz. Starsza ścieżka klawiszy bez puszczenia: do ustalenia (prawdopodobnie A/Y od razu jak dziś). Kontrakt z koligilo (akcje ról) sprawdzić.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 D-pad w czytaniu EPUB przewraca strony
- [ ] #2 A + D-pad otwiera słowa, Y + D-pad zdania, z kierunkiem wyznaczającym początek / koniec strony
- [ ] #3 Stuknięcia A i Y liczone przy puszczeniu; A i Y przytrzymane bez D-pada nic nie robią
- [ ] #4 Nagłówki, ściągawka, README, CLAUDE.md, testy zgodne
<!-- AC:END -->
