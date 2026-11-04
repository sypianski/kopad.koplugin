---
id: TASK-43
title: 'Wskaż od-do: lewa gałka ↑↓ = linia w trybie słów (także z RT)'
status: Done
assignee: []
created_date: '2026-11-04 08:54'
updated_date: '2026-11-04 09:04'
labels: []
dependencies: []
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Uzupełnienie TASK-42 / PC-024. W trybie słów D-pad ↑↓ = początek zdania; ruch o linię zniknął (TASK-42 usunął _ww_line jako martwy kod w 66fdf23). Lewa gałka w zaznaczeniu robi dziś to samo co D-pad. Decyzja usera 2026-11-04: lewa gałka ←→ = słowo (jak D-pad), ↑↓ = linia (słowo pod kursorem w linii wyżej / niżej, jak dawny _ww_line, z obsługą wyrazów dzielonych); z RT trzymanym (i aliasem A trzymanym) gałka ↑↓ = zakres o linię, nie wychodzi poza stronę. Bez zakresu linia przez krawędź strony jak dawniej. Ścieżka legacy: tylko gdy userpatch daje LStickUp/Down (osobne klawisze), inaczej bez zmian.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Lewa gałka ↑↓ w trybie słów przesuwa kursor o linię (EPUB i PDF, wyrazy dzielone, przez krawędź strony bez zakresu); D-pad ↑↓ dalej o zdanie
- [x] #2 Z RT trzymanym (i A trzymanym) gałka ↑↓ poszerza / zwęża zakres o linię, w obrębie strony; auto-repeat gałki działa jak D-pada
- [x] #3 Testy (selector_test, pdfwords_test, padmap_test) zielone; CLAUDE.md, README, nagłówek padnav.lua, linia statusu zaktualizowane
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: testy zielone, luac -p czysto; diff padnav: _lstick -> _sel_move(dx,dy,true) -> ov:line(dy,range,true), D-pad bez zmian. Gałka ma auto-repeat KOReadera (bez przyspieszenia kopada); PDF: linia w kolejności czytania (dwie kolumny przechodzą).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Lewa gałka ↑↓ = linia w trybie słów, z RT zakres o linię
<!-- SECTION:FINAL_SUMMARY:END -->
