---
id: TASK-19
title: Dialogi z przyciskami (ButtonDialog) jako koło wyboru jak w konsolowych RPG
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 19:25'
updated_date: '2026-11-03 20:08'
labels:
  - gamepad
dependencies: []
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Prośba usera 2026-11-03: gdy kopad jest włączony, okna dialogowe na środku ekranu, dotąd tabelka przycisków w dwóch kolumnach (ButtonDialog), mają się wyświetlać jako menu koła jak w Baldur's Gate na konsoli: monochromatyczne glify, pod całym kołem podpis wybranej akcji, wybór lewą albo prawą gałką, akceptacja przyciskiem A.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Każdy zwykły ButtonDialog (2-16 przycisków, bez dodanych widżetów) przy włączonym kopadzie rysuje się jako koło z 8 slotami i glifami
- [x] #2 Podpis wybranego przycisku pod kołem, tytuł dialogu nad nim
- [x] #3 Lewa i prawa gałka wskazują slot (8 kierunków), A uruchamia, B zamyka, X = długie przytrzymanie, D-pad poprzedni/następny, LB/RB i LT/RT strony
- [x] #4 Dotyk: tapnięcie slotu uruchamia, środek = następna strona, poza kołem = zamknij
- [x] #5 Przełącznik w menu kopada (to urządzenie), domyślnie włączony
- [x] #6 Testy: tests/wheel_test.lua + sekcja 13 tests/padmap_test.lua
- [x] #7 Sprawdzone na Steam Decku: wygląd, gałki, akcje w menu zaznaczenia i przytrzymaniu pliku
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Sprawdzone na Steam Decku 2026-11-03 przez usera (wersja c8a82a0): „Wszystko działa”.
<!-- SECTION:NOTES:END -->
