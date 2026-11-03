---
id: TASK-30
title: >-
  PDF/DjVu: zaznaczanie słów i zdań (getTextBoxes), wejście A/Y + D-pad i 'wskaż
  od-do'
status: To Do
assignee: []
created_date: '2026-11-03 20:53'
updated_date: '2026-11-03 20:58'
labels:
  - gamepad
  - pdf
dependencies:
  - TASK-28
  - TASK-29
priority: medium
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-03. W PDF D-pad zostaje przesuwaniem widoku, a zaznaczanie wchodzi tymi samymi kombinacjami co w EPUB (A + D-pad słowa, Y + D-pad zdania, stuknięcie A = wskaż od-do). Źródło słów: document:getTextBoxes(page) (linie słów z prostokątami we współrzędnych strony); zdania tą samą regułą tekstową co paginmapo (vendorowane: zmiany tylko upstream w koreader-konfig lib/). Rysowanie: przeliczenie strona -> ekran z zoomem i przesunięciem widoku. Akcje tekstowe (słownik, Vortuyo, AI, kopiuj) od razu; podkreślenia osobny tiket; akapity osobny tiket. Skany bez warstwy tekstu: komunikat. KOLIZJA: druga sesja ma w toku (bez commita) A + D-pad = zoom w PDF, bo R-stick ma przejąć koło szybkich akcji (TASK-26) — przed startem ustalić, gdzie idzie zoom.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Słowa i zdania na stronie PDF/DjVu z warstwą tekstu, ruch jak w EPUB, przejście przez brzeg strony
- [ ] #2 Prostokąty zgodne z widokiem przy zoomie i przesunięciu
- [ ] #3 Słownik, Vortuyo, AI, kopiuj działają; bez warstwy tekstu komunikat
- [ ] #4 Zoom w PDF przeniesiony z A + D-pad na B + D-pad (↑/↓ powiększ / pomniejsz z powtarzaniem, ←/→ cała strona / szerokość tekstu); stuknięcie B = wstecz przy puszczeniu
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-03, od kopad-aa: zoom A + D-pad w PDF jest od sesji kopad-1d (2c992c2, wypchnięte); R-stick w czytaniu = koło szybkich akcji (TASK-26). Propozycje przeniesienia zoomu do decyzji usera: (1) X przytrzymane + LT / RT = pomniejsz / powiększ (wolne pod X; powtarzanie jak _dpad_start); (2) dopasowanie strona / szerokość tekstu na R3 w kontekście paged (dziś połykane) albo zoom_fit_* w kole szybkich akcji (wymagałoby osobnego zestawu PDF, PC-021). Zoom zostaje też w dolnym menu (Start). Miejsca w kodzie: ACTION_RUNNERS zoom_in / zoom_out (_zoom_step), ZOOM_DPAD / _a_zoom w _button_dispatch.

Decyzja usera 2026-11-03: żadnych połączeń liter z tylnymi przyciskami (spusty, bumpery) — wszystko na literach i strzałkach. Zoom w PDF = B + D-pad (propozycje kopad-aa X + LT/RT i R3 odrzucone). Zasada: litera + strzałka = tryb, samo stuknięcie litery = jej akcja (A + D-pad słowa / A wskaż od-do, Y + D-pad zdania / Y podkreślenia, X + D-pad menu, B + D-pad zoom w PDF / B wstecz). Wariant zapasowy: przytrzymanie litery (~0,5 s) włącza tryb, gdyby kombinacje okazały się niewygodne.
<!-- SECTION:NOTES:END -->
