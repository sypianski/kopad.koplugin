---
id: TASK-29
title: >-
  Tryb 'wskaż od-do': etykiety ABXY/D-pad przy liniach, początek i koniec
  zaznaczenia
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 20:52'
updated_date: '2026-11-03 21:50'
labels:
  - gamepad
  - ux
dependencies: []
priority: high
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-03, wzorzec: sioyek keyboard_select (etykieta słowa początkowego, potem końcowego) i nasze etykiety z Vivaldi na Decku (~/aparati/steamdeck/vivaldi-deck/ext/hints.js: osiem symboli, D-pad ↑↓←→ + A/B/X/Y, etykieta wg położenia, lewa część od D-pada, prawa od ABXY; dwa wciśnięcia = 64 cele). Stuknięcie A w czytaniu pokazuje etykiety przy początkach linii strony (30-50 linii, zawsze dwa wciśnięcia). Pierwsza etykieta = początek (pierwsze słowo linii), od razu etykiety końca; druga = koniec linii; B = bez końca (jedno słowo). Potem zwykłe zaznaczenie słów: A + strzałki poprawiają zakres, stuknięcie A = menu akcji. Najpierw EPUB, z warstwą linii/słów niezależną od dokumentu, żeby PDF (osobny tiket) użył jej bez zmian.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Etykiety przy liniach, przydział symboli wg położenia jak w hints.js, maks. dwa wciśnięcia
- [x] #2 Początek i koniec wyznaczane etykietami; B = jedno słowo; dalej zwykłe zaznaczenie
- [x] #3 Działa w EPUB; logika etykiet czysta i testowana (bez KOReadera)
- [x] #4 Dokumentacja i ściągawka
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. kopad_hints.lua (pure, no KOReader): 8 symbols with hints.js anchors, assign() = hints.js tree split (always 2 symbols, first symbol never B so B stays back/one-word -> max 56 lines), lines_from_boxes() (EPUB/PDF-independent line layer), Pointer state machine (start labels -> end labels -> done / cancel, prefix filter, B).
2. selector.lua: mode "point" (Selector:_open_point, SelectorOverlay:point_press), EPUB adapter = paginmapo word sboxes -> lines; result -> mode walk with anchor (start line first word .. end line last word) or one word; drawing of labels (pill + badges) and the start word.
3. padnav.lua: A tapped while reading = point mode (sentences stay on Y + D-pad); in the selection with mode point D-pad + ABXY are label symbols (on the press, no repeat, no holds).
4. Tests: tests/kopad_hints_test.lua (assign by position, uniqueness, caps, prefix filter, B, Pointer flow, lines), selector_test (point -> walk), padmap_test (A tap, routing).
5. Docs: CLAUDE.md, padnav/main headers, cheat sheets, README.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-03: wszystkie 6 plików testów OK (nowy tests/kopad_hints_test.lua: przydział etykiet wg położenia, max 56, prefiks, B, linie ze słów, Pointer; selector_test sekcja 10: start+koniec, B = jedno słowo, A+strzałki poprawiają zakres; padmap_test sekcja 14: tap A = wskaż od-do, symbole na wciśnięciu bez powtarzania i holdów). Moduł przemianowany hints -> kopad_hints (kolizje package.loaded). Na urządzeniu do obejrzenia: wygląd etykiet, grupowanie linii przy inicjałach/indeksach górnych, odświeżanie. Otwarte: (1) 56 zamiast 64 celów, bo B nie zaczyna etykiety (B = zamknij / jedno słowo); (2) akcja padmap 'point_select' w kontrakcie z koligilo — DEFAULT_ACTIONS.a = sentence_select dziś daje wskaż od-do.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Tap A w czytaniu = 'wskaż od-do': dwusymbolowe etykiety pada przy liniach (kopad_hints.lua, czysta warstwa linii dla PDF), początek i koniec, B = jedno słowo
<!-- SECTION:FINAL_SUMMARY:END -->
