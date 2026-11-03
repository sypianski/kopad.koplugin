---
id: TASK-10
title: 'Sprzątanie po przeglądzie: martwa gałąź spustów, dokumentacja kontekstów'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 17:14'
updated_date: '2026-11-03 17:29'
labels:
  - docs
dependencies:
  - TASK-7
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
onGamepadAxisMotion ma nieosiągalną gałąź spustów (linie ~1427-1439), która przy nieliczbowej wartości osi wywaliłaby się na value > 0. Nagłówki padnav.lua/main.lua, README, CLAUDE.md i ściągawka twierdzą, że TouchMenu jest modalem — trzeba opisać nowy model kontekstów.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Martwa gałąź usunięta, nieliczbowe wartości osi nie wywracają handlera
- [x] #2 Nagłówek padnav.lua, main.lua, README.md, CLAUDE.md i ściągawka opisują konteksty (czytanie EPUB, PDF, zaznaczanie, słownik, menu górne, inne okna, przeglądarka plików)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Usunięta martwa gałąź spustów w onGamepadAxisMotion; nieliczbowa wartość osi przechodzi (false) bez porównania (test). Nagłówki padnav.lua i main.lua, README (sekcja Menus versus reading: menu górne, listy/dialogi, przeglądarka plików, słownik), CLAUDE.md (reguła kontekstu jako rdzeń) i ściągawka CHEAT_READING/CHEAT_SELECTION opisują model kontekstów.
<!-- SECTION:NOTES:END -->
