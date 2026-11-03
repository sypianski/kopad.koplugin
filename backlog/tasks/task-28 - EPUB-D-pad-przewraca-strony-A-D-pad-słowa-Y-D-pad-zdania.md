---
id: TASK-28
title: 'EPUB: D-pad przewraca strony, A + D-pad = słowa, Y + D-pad = zdania'
status: Done
assignee: []
created_date: '2026-11-03 20:52'
updated_date: '2026-11-03 21:04'
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
- [x] #1 D-pad w czytaniu EPUB przewraca strony
- [x] #2 A + D-pad otwiera słowa, Y + D-pad zdania, z kierunkiem wyznaczającym początek / koniec strony
- [x] #3 Stuknięcia A i Y liczone przy puszczeniu; A i Y przytrzymane bez D-pada nic nie robią
- [x] #4 Nagłówki, ściągawka, README, CLAUDE.md, testy zgodne
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
D-pad w czytaniu = strony (↑/↓ też, ←/→ lustrzane w RTL, bez powtarzania), także na starej ścieżce klawiszy. A + D-pad = słowa, Y + D-pad = zdania (Selector:_open(from_end)); stuknięcie A = zdania, Y = podkreślenia, przy puszczeniu (_release_a / _release_y). Naciśnięcie, które otwiera zaznaczenie, nie uruchamia powtarzania. Stara ścieżka: A/Y przy naciśnięciu jak dotąd. Testy: padmap_test sekcja 14, selector_test 5a.
<!-- SECTION:NOTES:END -->
