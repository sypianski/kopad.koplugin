---
id: TASK-37
title: Testy zaznaczania na PDF-ach z internetu (losowa próba)
status: Done
assignee: []
created_date: '2026-11-04 00:14'
updated_date: '2026-11-04 00:56'
labels:
  - gamepad
  - pdf
  - testy
dependencies: []
priority: medium
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sprawdzić całość zaznaczania padem w PDF-ach (A/Y + D-pad, wskaż od-do, podział na słowa w pdftext.lua) na losowych dokumentach z internetu, a nie tylko na własnych plikach. Powód: błąd z pogrubionymi/ściśniętymi wierszami (cały wiersz = jedno 'słowo', bo warstwa tekstowa PDF-a nie ma spacji) wyszedł dopiero na realnym piśmie z papeterii. Próg luki pdftext.GAP_EM = 0.10 em skalibrowany na jednym PDF-ie (Alegreya, luki w słowach <= 0.066 em, między słowami >= 0.125 em) — trzeba go sprawdzić na innych fontach i składach.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Zmierzone na 16 PDF-ach (arXiv LaTeX x4, wydruki Chromium x2, Word, RFC 9110, W3C dummy, 6 czasopism, papeteria; 216 tys. par glifów; wzorzec: pdftotext -bbox). Stały próg 0,10 em dawał 43 fałszywe podziały w nagłówku 'journal homepage' (tracking 0,114 em) -> próg jest teraz względny wobec wiersza (pdftext.baseline = dolny kwartyl luk wiersza). Wynik: 210 podziałów dodanych regułą, 207 zgodnych z pdftotext, 3 fałszywe (śmieciowy OCR w skanie). Czułość: 0,06/0,08 -> 85/56 fałszywych; 0,12/0,14 -> chybienia rosną 127 -> 166/205; 0,10 zostaje. Nie sprawdzone: DjVu, tekst RTL/arabski, pionowy (wmode 1 = reguła wyłączona), PDF-y bez warstwy tekstowej. Wiersze z matematyką (F(x)+x) pozostają sklejone jak w stocku.
<!-- SECTION:NOTES:END -->
