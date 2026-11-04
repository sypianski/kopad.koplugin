---
id: TASK-35
title: '''Wskaż od-do'' na zdaniach, słowo na życzenie (EPUB i PDF)'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 23:25'
updated_date: '2026-11-03 23:37'
labels:
  - gamepad
  - ux
  - pdf
dependencies:
  - TASK-29
  - TASK-30
references:
  - >-
    ../../libraro/decyzje/PC-022-wskaz-od-do-w-kopadzie-na-zdaniach-slowo-na-zycz.md
priority: high
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-04 (wariant B z czterech: A zawsze zdanie+słowo, B zdanie ze słowem na życzenie, C zdania + strzałki, D przełącznik linie/zdania). Zastępuje etykiety przy liniach z TASK-29. Krok początku: etykiety przy początkach zdań strony; wybór etykiety = początek zaznaczenia na pierwszym słowie zdania i od razu krok końca. Krok końca: etykiety przy końcach zdań od zdania początkowego w dół; wybór = koniec na ostatnim słowie zdania. Doprecyzowanie do słowa: prawa gałka ↓ w danym kroku włącza tryb 'słowo' (widoczny w pasku stanu), R↑ go wyłącza; w trybie 'słowo' wybór etykiety zdania pokazuje etykiety słów tylko tego zdania, wybór słowa = początek / koniec na tym słowie; B na etykietach słów = wróć do etykiet zdań. B na etykietach początku = zamknij, B na etykietach końca = jedno słowo (jak dziś). Potem zwykłe zaznaczenie słów (A + strzałki poprawiają, stuknięcie A = menu akcji). Etykiety dwusymbolowe jak w kopad_hints.lua (maks. 56); zdanie dłuższe niż 56 słów: etykiety na pierwszych 56 albo stronicowanie — do wyboru przy implementacji. Wspólne dla EPUB (paginmapo) i PDF (pdfwords). Zdanie przechodzące na następną / z poprzedniej strony: etykieta przy jego widocznej części.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Krok początku i końca na etykietach zdań (EPUB i PDF), wybór zdania = początek / koniec zdania
- [x] #2 R↓ / R↑ włącza i wyłącza doprecyzowanie do słowa w bieżącym kroku, widoczne w pasku stanu; etykiety słów tylko w wybranym zdaniu
- [x] #3 B: zamknij (początek), jedno słowo (koniec), wróć do zdań (etykiety słów)
- [x] #4 Logika kroków czysta i testowana bez KOReadera (kopad_hints / nowy moduł), testy selektora EPUB i PDF
- [x] #5 Dokumentacja i ściągawka (CLAUDE.md, README, nagłówek padnav.lua, CHEAT_*)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. kopad_hints.lua: Pointer przepisany z linii na zdania (czysty): Pointer.new(sentences{first,last}, boxes, {rtl}); kroki start/end, poziom sentence/word, refine(on) dla R↓/R↑ (per krok, reset przy zmianie kroku); etykiety zdań przy pierwszym / ostatnim WIDOCZNYM słowie (zdanie przez krawędź strony = jego widoczna część), etykiety słów tylko wybranego zdania (w kroku końca od słowa początku); B: start=cancel, end=done bez końca, słowa=back do zdań; >56 słów: okno pierwszych 56 (początek) / ostatnich 56 (koniec). lines_from_boxes zostaje (pomocnik). 2. selector.lua: _point_begin buduje zdania z word_to_sent (wspólne EPUB/PDF), _point_finish na indeksach słów, point_refine(on), _draw_point (etykiety słów nad słowem), _status_text (FROM/TO + WORD, R↓/R↑). 3. padnav.lua: _rstick w trybie point -> point_refine (ścieżka Gamepad i legacy). 4. Testy: kopad_hints_test, selector_test sekcja 10, pdfwords_test point, padmap_test R-stick w point. 5. Docs: CLAUDE.md, README, nagłówek padnav.lua i selector.lua, CHEAT_*.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: 11/11 tests/*_test.lua ok, luac -p ok, diff przejrzany. Zdanie > 56 słów: okno 56 słów (początek: pierwsze 56, koniec: ostatnie 56 od słowa początku), reszta A + strzałki. Niesprawdzone na urządzeniu: położenie etykiet słów (wyśrodkowane nad słowem, mogą nachodzić przy krótkich słowach). Commit 3f063b2.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Wskaż od-do na etykietach zdań, R↓ doprecyzowuje krok do słowa (EPUB i PDF)
<!-- SECTION:FINAL_SUMMARY:END -->
