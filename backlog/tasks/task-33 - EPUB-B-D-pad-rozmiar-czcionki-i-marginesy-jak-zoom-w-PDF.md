---
id: TASK-33
title: 'EPUB: B + D-pad = rozmiar czcionki i marginesy (jak zoom w PDF)'
status: Done
assignee: []
created_date: '2026-11-03 21:07'
updated_date: '2026-11-03 21:26'
labels:
  - gamepad
  - ux
dependencies:
  - TASK-28
priority: medium
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Pomysł usera 2026-11-03: ten sam tryb, który w PDF powiększa i dopasowuje do szerokości (B + D-pad, TASK-30), w EPUB zmienia rozmiar widoku tekstu. B + ↑/↓ = większa / mniejsza czcionka (ReaderFont, zdarzenia IncreaseFontSize / DecreaseFontSize), B + ←/→ = węższe / szersze marginesy (odpowiednik dopasowania do szerokości; alternatywa: interlinia, do potwierdzenia przez usera). Przytrzymany D-pad powtarza, wolniej niż ruch w zaznaczeniu (każda zmiana przelicza układ książki). Stuknięcie B = wstecz przy puszczeniu, tylko bez D-pada w międzyczasie (zasada z TASK-28). Spójnie z PDF: ta sama kombinacja = rozmiar widoku.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 B + ↑/↓ w EPUB zmienia rozmiar czcionki, B + ←/→ marginesy (lub wybrany przez usera parametr)
- [x] #2 Stuknięcie B = wstecz przy puszczeniu; B + D-pad nie cofa
- [x] #3 Przytrzymany D-pad powtarza z bezpiecznym odstępem
- [x] #4 Nagłówki, ściągawka, README, CLAUDE.md, testy
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User 2026-11-03: ←/→ = marginesy (nie interlinia).

Zrobione 2026-11-03 (padnav._press_b / _release_b / _view_dpad / _margins_step): B + ↑/↓ = IncreaseFontSize / DecreaseFontSize (1), B + ←/→ = h_page_margins ±5 (0..100) przez SetPageHorizMargins; powtarzanie co VIEW_REPEAT_S = 0,4 s (pierwsze po 0,45 s). W PDF B + D-pad = ten sam zoom / dopasowanie co A + D-pad (A zostaje do TASK-30). Stuknięcie B = wstecz przy puszczeniu; legacy: od razu.
<!-- SECTION:NOTES:END -->
