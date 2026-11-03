---
id: TASK-25
title: >-
  Szybsze poruszanie w zaznaczeniu: LT/RT o akapit, przyspieszenie trzymanego
  D-pada
status: To Do
assignee: []
created_date: '2026-11-03 20:10'
labels:
  - gamepad
  - ux
dependencies: []
priority: high
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-03: poruszanie się słowami linijka po linijce jest za wolne. Wybrane dwa uzupełniające się rozwiązania. (1) LT/RT w zaznaczeniu = poprzedni / następny akapit. Dotąd zamykały zaznaczenie i przewracały stronę, tak jak LB/RB. W słowach kursor ląduje na pierwszym słowie akapitu, w zdaniach na pierwszym zdaniu. Skok przechodzi przez brzeg strony, z przytrzymanym A zaznacza zakres akapitami (w obrębie strony), a trzymany spust powtarza skok (powtórzenia stockowe przepuszczone w kontekście selection). W trybie podkreśleń (Y) to następne / poprzednie podkreślenie. (2) Trzymany D-pad przyspiesza: po kilku powtórzeniach odstęp maleje aż do minimum.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Selector:para(dir, range): słowa / zdania / podkreślenia, z przejściem przez brzeg strony
- [ ] #2 LT/RT w zaznaczeniu wywołują para (także trzymane i na starszej ścieżce klawiszy); LB/RB dalej zamykają i przewracają stronę
- [ ] #3 Trzymany D-pad przyspiesza do minimalnego odstępu
- [ ] #4 Nagłówki padnav/main, ściągawka, README, CLAUDE.md zgodne
- [ ] #5 Testy: selector_test (para w słowach i zdaniach, brzeg strony, zakres) i padmap_test (spusty w zaznaczeniu, przyspieszenie)
<!-- AC:END -->
