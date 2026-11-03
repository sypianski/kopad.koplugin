---
id: TASK-33
title: 'EPUB: B + D-pad = rozmiar czcionki i marginesy (jak zoom w PDF)'
status: To Do
assignee: []
created_date: '2026-11-03 21:07'
updated_date: '2026-11-03 21:08'
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
- [ ] #1 B + ↑/↓ w EPUB zmienia rozmiar czcionki, B + ←/→ marginesy (lub wybrany przez usera parametr)
- [ ] #2 Stuknięcie B = wstecz przy puszczeniu; B + D-pad nie cofa
- [ ] #3 Przytrzymany D-pad powtarza z bezpiecznym odstępem
- [ ] #4 Nagłówki, ściągawka, README, CLAUDE.md, testy
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User 2026-11-03: ←/→ = marginesy (nie interlinia).
<!-- SECTION:NOTES:END -->
