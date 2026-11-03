---
id: TASK-29
title: >-
  Tryb 'wskaż od-do': etykiety ABXY/D-pad przy liniach, początek i koniec
  zaznaczenia
status: To Do
assignee: []
created_date: '2026-11-03 20:52'
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
- [ ] #1 Etykiety przy liniach, przydział symboli wg położenia jak w hints.js, maks. dwa wciśnięcia
- [ ] #2 Początek i koniec wyznaczane etykietami; B = jedno słowo; dalej zwykłe zaznaczenie
- [ ] #3 Działa w EPUB; logika etykiet czysta i testowana (bez KOReadera)
- [ ] #4 Dokumentacja i ściągawka
<!-- AC:END -->
