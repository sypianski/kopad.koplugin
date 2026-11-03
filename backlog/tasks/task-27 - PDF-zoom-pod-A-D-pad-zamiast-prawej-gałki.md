---
id: TASK-27
title: 'PDF: zoom pod A + D-pad zamiast prawej gałki'
status: Done
assignee: []
created_date: '2026-11-03 20:42'
labels:
  - pdf
dependencies: []
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Prawa gałka w PDF-ie oddała miejsce kołu szybkich akcji (TASK-26), więc zoom przeniesiony na przytrzymane A + D-pad: ↑/↓ zoom in/out o 3 % (trzymany D-pad powtarza krok z przyspieszeniem), ←/→ cała strona / szerokość tekstu. Prawa gałka w trybie paged była na czas przejścia tylko pochłaniana. Zob. padnav.lua (ZOOM_DPAD, _button_dispatch, _dpad_start), README, tests/padmap_test.lua. Commit 2c992c2; sprawdzone na czytniku.
<!-- SECTION:DESCRIPTION:END -->
