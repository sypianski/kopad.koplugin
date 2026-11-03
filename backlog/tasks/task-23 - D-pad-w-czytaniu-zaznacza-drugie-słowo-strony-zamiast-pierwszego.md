---
id: TASK-23
title: D-pad w czytaniu zaznacza drugie słowo strony zamiast pierwszego
status: To Do
assignee: []
created_date: '2026-11-03 19:55'
labels:
  - gamepad
  - bug
dependencies: []
priority: medium
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Zgłoszenie usera ze Steam Decka (2026-11-03, kopad 7456838): w czytaniu EPUB D-pad ↓/→ ma zaznaczyć pierwsze słowo strony (TASK-15), a zaznacza drugie. Do sprawdzenia, czy ↑/← trafia w ostatnie słowo i czy to samo dzieje się przy przejściu przez brzeg strony (TASK-18, ten sam _ww_land).

Kod: Selector:_open_walk -> SelectorOverlay:_ww_land(1) bierze self.words[1].xp0 z paginmapo i przepuszcza przez _ww_word_from_xp, który liczy koniec słowa jako doc:getNextVisibleWordEnd(xp). Hipotezy:
1. xp0 pierwszego słowa wskazuje miejsce PRZED słowem (początek akapitu / spacja / znacznik), więc getNextVisibleWordEnd daje koniec następnego słowa albo słowo zaczyna się za wcześnie.
2. getNextVisibleWordEnd z pozycji będącej już początkiem słowa przeskakuje do końca następnego.
3. words[1] to końcówka słowa przeniesionego z poprzedniej strony (fragment) albo niewidoczny element, a zaznaczenie wygląda na drugie słowo.
Diagnoza: ślad kopad-trace na Decku (zalogować xp0 i tekst words[1..2] oraz pos0/pos1/word wyniku _ww_word_from_xp).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Przyczyna ustalona na urządzeniu (ślad lub log)
- [ ] #2 D-pad ↓/→ zaznacza pierwsze słowo strony, ↑/← ostatnie, także po przejściu przez brzeg strony
- [ ] #3 Przypadek dopisany do tests/selector_test.lua
<!-- AC:END -->
