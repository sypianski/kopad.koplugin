---
id: TASK-20
title: 'UX: warianty — koło dialogów'
status: Done
assignee: []
created_date: '2026-11-03 19:37'
updated_date: '2026-11-03 19:57'
labels:
  - ux
dependencies: []
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Selektor wariantów (/ux) dla koła dialogów: wheel.lua (Panel, _paint_wheel, paintTo), wpięcie w padnav.lua (kontekst wheel). Powiązane: TASK-19.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Wdrożone wg wyboru z artefaktu https://claude.ai/artifact/FtbNLZLUMkjNaZQHoujup1 (wybor/kolo, wersja 37): bez ramki (biały krążek, tytuł i przyciski w pigułkach), pierścień z liniami, tyle sektorów ile przycisków (angle_of/nearest, remis zgodnie z zegarem), wybrany sektor czarny i wysunięty o R/12, nazwa w piaście (r0 = R/2, do 3 linii), przyciski A/B/X/LB RB jako znaczki, numer strony obok LB/RB, tytuł z tekstem zaznaczenia w menu akcji kopada (_kopad_snippet) i w obu menu zakreślenia KOReadera (onShowHighlightMenu, showHighlightDialog), położenie: środek. Testy: tests/wheel_test.lua sekcje 1, 3, 4b, 9. Nie oglądane na urządzeniu.
<!-- SECTION:NOTES:END -->
