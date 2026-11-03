---
id: TASK-17
title: 'Dwa poziomy zaznaczania: słowo i zdanie, przełączanie prawą gałką'
status: Done
assignee: []
created_date: '2026-11-03 19:14'
updated_date: '2026-11-03 19:37'
labels:
  - ux
dependencies: []
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A w czytaniu = zdania (struct), D-pad = słowa (walk). W zdaniach ←/→ zdanie, ↑/↓ akapit; w słowach ←/→ słowo, ↑/↓ linia. R-stick ↓ w zdaniu = pierwsze słowo tego zdania (walk), R-stick ↑ w słowie = zdanie z tym słowem (struct). Podtryb słowa wewnątrz zdania (sel_word) usunięty — poziom słowa to walk.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 R-stick ↑/↓ przełącza poziom, ←/→ bez akcji
- [x] #2 Brak podtrybu sel_word w struct
- [x] #3 Testy przełączania
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Selector:to_words() (pierwsze słowo zdania) / to_sentences() (zdanie ze słowem). sel_word usunięty.
<!-- SECTION:NOTES:END -->
