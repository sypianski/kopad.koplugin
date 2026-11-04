---
id: TASK-40
title: 'Wskaż od-do: w kroku końca te same literki słów co w kroku początku'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-04 00:51'
updated_date: '2026-11-04 00:56'
labels:
  - gamepad
  - ux
dependencies:
  - TASK-39
priority: high
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Uwaga usera 2026-11-04 po próbie 0.1.8: nie da się zaznaczyć pojedynczego słowa ani dwóch słów ze środka. Przyczyna: w kroku końca drzewo A/X/Y (TASK-39) liczy się od nowa od słowa początku (n = słowa od startu), więc to samo słowo ma inne literki niż w kroku początku (zdanie 9 słów: start XX = słowo 5; w kroku końca A = słowo 5, X = słowo 8, XX = słowo 9).

Zmiana: w kroku końca, w zdaniu początku, drzewo i literki są TE SAME co w kroku początku (liczone od pierwszego widocznego słowa zdania, k z liczby widocznych słów całego zdania); słowa przed słowem początku są niedostępne: kawałek w całości przed startem nie ma plakietki, kawałek zawierający start ma plakietkę nad słowem początku (pierwszym dostępnym słowem kawałka), literki dla słów < start są ignorowane. Jedno słowo = te same litery co przy starcie (albo B jak dziś); dwa słowa = litery następnego słowa. Po → / ↑ (inne zdanie końca niż zdanie początku) drzewo liczone od pierwszego widocznego słowa tamtego zdania, jak w kroku początku. Reszta bez zmian (skróty, B, wygląd).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 W zdaniu początku krok końca ma te same literki słów co krok początku; słowa przed startem bez plakietek i ignorowane
- [x] #2 Jedno słowo = powtórzenie liter startu albo B; dwa słowa ze środka = litery następnego słowa (testy EPUB i PDF)
- [x] #3 Inne zdanie końca (po → / ↑): numeracja od początku tamtego zdania; testy kopad_hints, docs
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. kopad_hints.lua: Pointer:_word_labels(si) liczy M.word_labels dla WSZYSTKICH widocznych słów zdania (_visible_words(si) bez from), potem w kroku końca w zdaniu początku odrzuca cele ze słowem < start (bez etykiet w targets). stage() grupuje kawałki z targets, więc kawałek w całości przed startem nie ma plakietki, a kawałek ze startem ma ją nad słowem początku; press: prefiks bez celu = ignored. _vis / preview / skróty / _next_sent bez zmian (od startu). Inne zdanie końca: od pierwszego widocznego słowa jak dziś.
2. Testy kopad_hints_test: zdanie 9 słów, start XX (5): XX = jedno słowo, XY = 5..6, B = jedno, A ignored, YA = 5..7, stage() bez plakietki A, X nad słowem 5; zdanie 22 słów ze startem w środku; → inne zdanie od początku; RTL. selector_test (EPUB) i pdfwords_test (PDF): jedno słowo przez powtórzenie liter startu, dwa słowa ze środka; poprawić istniejące oczekiwania liter w kroku końca.
3. Docs: CLAUDE.md (kopad_hints / point) i README (point), nagłówek kopad_hints.lua.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: 12/12 testów, luac ok; symulacja: start XX (słowo 5) -> koniec XX = jedno słowo, XY = 5..6, A ignorowane, B = jedno słowo.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
W kroku końca słowa zachowują litery z kroku początku: jedno słowo = te same litery, dwa = litery następnego
<!-- SECTION:FINAL_SUMMARY:END -->
