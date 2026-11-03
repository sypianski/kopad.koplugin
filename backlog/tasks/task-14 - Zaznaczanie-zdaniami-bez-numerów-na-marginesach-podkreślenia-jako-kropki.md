---
id: TASK-14
title: 'Zaznaczanie zdaniami: bez numerów na marginesach, podkreślenia jako kropki'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 18:49'
updated_date: '2026-11-03 18:50'
labels:
  - gamepad
dependencies: []
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Selektor kopada (selector.lua) rysował numery zdań (lewy margines, _draw_labels) i numery podkreśleń (prawy margines, _draw_hl_labels) — pozostałość po viselu, gdzie numer wpisuje się z klawiatury. Kopad nie ma wejścia cyframi, więc numery są zbędne. Decyzja usera 2026-11-03: lewy margines bez znaczników; na prawym kropka przy każdym podkreśleniu na stronie (bez cyfry), bieżące (hl_cur) wypełnione; licznik w pasku stanu (SENT 3/12, WORD 2/9, HL 2/5) zostaje.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Brak numerów zdań na lewym marginesie w trybie struct
- [x] #2 Podkreślenia na stronie oznaczone kropką na prawym marginesie, bieżące wypełnione, bez cyfr
- [x] #3 Pasek stanu bez zmian
- [x] #4 Dokumentacja (README, nagłówki) bez wzmianek o numerach
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
selector.lua: usunięte _draw_labels (numery zdań) i LABEL_FACE; _draw_hl_labels -> _draw_hl_marks: kropka (promień Screen:scaleBySize(5), ograniczony marginesem) przy każdym podkreśleniu na stronie, bieżące (hl_cur) wypełnione, pozostałe jako pierścień; ukryte w trybie słowa jak dotąd. Pasek stanu bez zmian. README / nagłówki nie wspominały numerów. Test: luac -p, padmap_test (selektor bez testów automatycznych) — wygląd do sprawdzenia na urządzeniu.
<!-- SECTION:NOTES:END -->
