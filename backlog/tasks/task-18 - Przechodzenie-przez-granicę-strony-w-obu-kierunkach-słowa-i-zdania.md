---
id: TASK-18
title: Przechodzenie przez granicę strony w obu kierunkach (słowa i zdania)
status: Done
assignee: []
created_date: '2026-11-03 19:14'
updated_date: '2026-11-03 19:37'
labels:
  - ux
dependencies: []
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Słowa: ← na pierwszym słowie strony = poprzednia strona, ostatnie słowo; ↑/↓ na brzegu = sąsiednia strona. Zdania: ←/→ i ↑/↓ za brzegiem = sąsiednia strona (pierwsze / ostatnie zdanie). Zakres przy przytrzymanym A nie przechodzi przez stronę.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Walk: wstecz i linie przez brzeg strony
- [x] #2 Struct: zdania i akapity przez brzeg strony
- [x] #3 Zakres zostaje na stronie
- [x] #4 Testy
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
_turn_page() + _ww_land / _sent_land / _para_land; zakres (A trzymane) nie przechodzi przez brzeg. Przy okazji naprawiony błąd 'cond and f() or g()' w _ww_line (koniec książki cofał o słowo) — _adjacent_word.
<!-- SECTION:NOTES:END -->
