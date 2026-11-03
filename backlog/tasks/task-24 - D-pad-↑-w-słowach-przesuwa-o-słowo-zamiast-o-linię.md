---
id: TASK-24
title: D-pad ↑ w słowach przesuwa o słowo zamiast o linię
status: To Do
assignee: []
created_date: '2026-11-03 20:00'
labels:
  - gamepad
  - bug
dependencies: []
priority: high
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Zgłoszenie usera ze Steam Decka (2026-11-03, kopad 7456838): w zaznaczaniu słowami D-pad ↑ przesuwał o jedno słowo w lewo zamiast do linii wyżej. Ślad: onKPUp2 -> SelectorOverlay:line -> _ww_line, czyli przekierowanie było dobre. Przyczyna: CreDocument:getScreenPositionFromXPointer zwraca GÓRĘ linii (doc_y - top_y), a _ww_line porównywał ją ze środkiem prostokąta słowa minus 0.3 wysokości. Słowo po lewej (ta sama góra) wypadało wyżej niż próg, więc ↑ uznawał je za linię wyżej. Przy ↓ próg wypadał poniżej środka i ruch działał przypadkiem. Błąd był też przed TASK-15. Atrapa w tests/selector_test.lua zwracała środek, dlatego test go nie łapał.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 _ww_line porównuje linie przez getScreenPositionFromXPointer po obu stronach (kursor i kandydat), słowo w docelowej linii szuka na jej środku
- [ ] #2 Atrapa w selector_test zwraca górę linii jak CreDocument; dopisany przypadek ↑ w obrębie strony
- [ ] #3 Sprawdzone na Decku: ↑ i ↓ przechodzą o linię
<!-- AC:END -->
