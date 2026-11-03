---
id: TASK-16
title: >-
  Przytrzymanie: A + strzałki zaznacza zakres, X jako modyfikator
  przytrzymywany, powtarzanie trzymanego D-pada
status: Done
assignee: []
created_date: '2026-11-03 19:14'
updated_date: '2026-11-03 19:37'
labels:
  - ux
dependencies: []
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KOReader >= 2026.07 wysyła GamepadButtonUp (device.lua:349). main.lua przekazuje je do PadNav; puszczenie idzie przez padmap jak naciśnięcie. A w zaznaczeniu: przytrzymane + strzałki = zakres od kotwicy (obie strony, cofnięcie skraca), stuknięcie (bez strzałek) = menu akcji przy puszczeniu. RB/LB w zaznaczeniu = strony (zamyka zaznaczenie), B = zamknij. X w czytaniu: modyfikator działa tylko przytrzymany (puszczenie kończy), stara ścieżka klawiszowa zostaje na zatrzask. Trzymany D-pad powtarza krok (opóźnienie ~0,45 s, potem co ~0,15 s), stop przy puszczeniu lub zmianie kontekstu.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GamepadButtonUp przekazywane i remapowane
- [x] #2 A przytrzymane + D-pad/L-stick = zakres w obie strony; stuknięcie A = menu akcji
- [x] #3 RB/LB w zaznaczeniu przewracają stronę, B zamyka
- [x] #4 X modyfikator na przytrzymanie
- [x] #5 Powtarzanie D-pada z zatrzymaniem
- [x] #6 Testy sekwencji Down/Up
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
main.lua przekazuje GamepadButtonUp; PadNav:onGamepadButtonUp remapuje przez padmap. A: _a_down/_a_moved, menu przy puszczeniu. X: _x_hold (spust jako X = zatrzask). Powtarzanie D-pada scheduleIn 0.45 s / 0.15 s, max 200, stop przy puszczeniu / wyjściu z zaznaczenia. Ścieżka legacy: A otwiera menu od razu, RB/LB krok zakresu.
<!-- SECTION:NOTES:END -->
