---
id: TASK-30
title: >-
  PDF/DjVu: zaznaczanie słów i zdań (getTextBoxes), wejście A/Y + D-pad i 'wskaż
  od-do'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 20:53'
updated_date: '2026-11-03 22:10'
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
- [x] #1 Słowa i zdania na stronie PDF/DjVu z warstwą tekstu, ruch jak w EPUB, przejście przez brzeg strony
- [x] #2 Prostokąty zgodne z widokiem przy zoomie i przesunięciu
- [x] #3 Słownik, Vortuyo, AI, kopiuj działają; bez warstwy tekstu komunikat
- [x] #4 Zoom w PDF przeniesiony z A + D-pad na B + D-pad (↑/↓ powiększ / pomniejsz z powtarzaniem, ←/→ cała strona / szerokość tekstu); stuknięcie B = wstecz przy puszczeniu
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. pdfwords.lua (pure adapter): getTextBoxes -> words {text, page, line, pbox, pos0/pos1 = key, sent_end}, has_text, sentence end rule (replica of paginmapo is_sent_boundary, local there), sentences via paginmapo.collect_sentences_from_words, line targets for up/down, range -> per-line screen boxes, centre positions for getTextFromPositions.
2. selector.lua: PagedOverlay = SelectorOverlay:extend, overriding only the document-specific methods (collect, word step/line/land, compare = index, page turn = GotoPage, screen boxes recomputed from view:pageToScreenTransform on every paint, reveal = pan to an off-screen cursor, get_selection via getTextFromPositions, highlight/note = message until TASK-31). Selector:_new_overlay picks the class; reflow / no text -> false + reason.
3. main.lua: selector also for ui.paging (flag paged).
4. padnav.lua: _selector() hides an idle paged selector (paged stays pan/zoom), _any_selector(); paged: A/Y held + D-pad = words / sentences, A tap = point from-to, remove _a_zoom (zoom only B + D-pad), LB/RB in a PDF selection = whole page.
5. Tests: tests/pdfwords_test.lua (adapter, zoom+pan screen boxes, moves over page edges, point from-to, no text, reflow); padmap_test paged section (A + D-pad = words, B + D-pad = zoom, B tap = back).
6. Docs: CLAUDE.md, padnav header + CHEAT_*, README.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-03, od kopad-aa: zoom A + D-pad w PDF jest od sesji kopad-1d (2c992c2, wypchnięte); R-stick w czytaniu = koło szybkich akcji (TASK-26). Propozycje przeniesienia zoomu do decyzji usera: (1) X przytrzymane + LT / RT = pomniejsz / powiększ (wolne pod X; powtarzanie jak _dpad_start); (2) dopasowanie strona / szerokość tekstu na R3 w kontekście paged (dziś połykane) albo zoom_fit_* w kole szybkich akcji (wymagałoby osobnego zestawu PDF, PC-021). Zoom zostaje też w dolnym menu (Start). Miejsca w kodzie: ACTION_RUNNERS zoom_in / zoom_out (_zoom_step), ZOOM_DPAD / _a_zoom w _button_dispatch.

Decyzja usera 2026-11-03: żadnych połączeń liter z tylnymi przyciskami (spusty, bumpery) — wszystko na literach i strzałkach. Zoom w PDF = B + D-pad (propozycje kopad-aa X + LT/RT i R3 odrzucone). Zasada: litera + strzałka = tryb, samo stuknięcie litery = jej akcja (A + D-pad słowa / A wskaż od-do, Y + D-pad zdania / Y podkreślenia, X + D-pad menu, B + D-pad zoom w PDF / B wstecz). Wariant zapasowy: przytrzymanie litery (~0,5 s) włącza tryb, gdyby kombinacje okazały się niewygodne.

2026-11-03 (TASK-33): B + D-pad w PDF już robi zoom / dopasowanie (AC4 częściowo); A + D-pad zoom nadal działa i zostaje do wejścia zaznaczania w PDF — wtedy usunąć gałąź _a_zoom.

Weryfikacja dyrygenta 2026-11-03: 9/9 plików testów OK. tests/pdfwords_test.lua: słowa/zdania na fałszywym 3-stronicowym PDF z przejściem przez brzeg strony (AC1), prostokąty ekranu liczbowo przy zoom 2 + przesunięciu (AC2), skan = no_text, reflow wykluczony (AC3); padmap_test sekcja 10: A/Y + D-pad = słowa/zdania, B + D-pad = zoom z powtarzaniem / dopasowanie, B tap = wstecz, gałąź _a_zoom usunięta (AC4). Do obejrzenia na Decku: zgodność prostokątów z tekstem po zoomie, przesuwanie widoku do kursora, czas getTextBoxes na skanie, tryb ciągły. Upstream paginmapo: wystawić is_sent_boundary (dziś kopia w PdfWords.ends_sentence).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF/DjVu: słowa i zdania (A/Y + D-pad), 'wskaż od-do' (tap A), akcje tekstowe; adapter pdfwords.lua + PagedOverlay; zoom tylko pod B + D-pad
<!-- SECTION:FINAL_SUMMARY:END -->
