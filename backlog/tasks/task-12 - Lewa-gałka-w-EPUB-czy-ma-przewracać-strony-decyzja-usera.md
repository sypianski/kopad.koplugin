---
id: TASK-12
title: 'Lewa gałka w EPUB: czy ma przewracać strony (decyzja usera)'
status: Done
assignee: []
created_date: '2026-11-03 17:47'
updated_date: '2026-11-03 19:14'
labels:
  - gamepad
  - ux
dependencies: []
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Obecnie w czytaniu EPUB (padnav.lua onKPUp/onKPLeft/onKPDown/onKPRight): L-gałka ↑ i ← = następna strona (← do przodu jest sprzeczne z kierunkiem i nie respektuje RTL), ↓ = celownik, → = przejście po słowach. W PDF L-gałka tylko przesuwa widok; strony przewracają wyłącznie LB/RB/LT/RT. Opcje: (1) bez przewracania — ↓ celownik, → słowa, ↑/← nic, strony tylko LB/RB/LT/RT jak w PDF (rekomendacja: jedna zasada, brak przypadkowych przeskoków przy odbiciu gałki); (2) kierunkowo — ←/↑ poprzednia, → następna (RTL odwraca ←/→), ↓ celownik, przejście po słowach na prawej gałce (lepsze przy czytaniu jedną ręką); (3) bez zmian. Czeka na decyzję usera po dłuższym czytaniu na Decku (2026-11-03). Po decyzji: handlery, nagłówek padnav.lua, ściągawka, README (tabela czytania), testy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 User wybrał wariant
- [x] #2 Handlery L-gałki, nagłówek padnav.lua, ściągawka, README i testy zgodne z wyborem
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Rozstrzygnięte 2026-11-03 w ramach nowego mapowania pada: wariant 1 (L-stick w czytaniu EPUB bez akcji, strony tylko LB/RB/LT/RT). Realizacja: TASK-15.
<!-- SECTION:NOTES:END -->
