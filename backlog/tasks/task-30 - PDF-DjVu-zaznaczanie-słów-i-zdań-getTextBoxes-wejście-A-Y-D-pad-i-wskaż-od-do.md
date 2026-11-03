---
id: TASK-30
title: >-
  PDF/DjVu: zaznaczanie słów i zdań (getTextBoxes), wejście A/Y + D-pad i 'wskaż
  od-do'
status: To Do
assignee: []
created_date: '2026-11-03 20:53'
labels:
  - gamepad
  - pdf
dependencies: []
priority: medium
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-03. W PDF D-pad zostaje przesuwaniem widoku, a zaznaczanie wchodzi tymi samymi kombinacjami co w EPUB (A + D-pad słowa, Y + D-pad zdania, stuknięcie A = wskaż od-do). Źródło słów: document:getTextBoxes(page) (linie słów z prostokątami we współrzędnych strony); zdania tą samą regułą tekstową co paginmapo (vendorowane: zmiany tylko upstream w koreader-konfig lib/). Rysowanie: przeliczenie strona -> ekran z zoomem i przesunięciem widoku. Akcje tekstowe (słownik, Vortuyo, AI, kopiuj) od razu; podkreślenia osobny tiket; akapity osobny tiket. Skany bez warstwy tekstu: komunikat. KOLIZJA: druga sesja ma w toku (bez commita) A + D-pad = zoom w PDF, bo R-stick ma przejąć koło szybkich akcji (TASK-26) — przed startem ustalić, gdzie idzie zoom.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Słowa i zdania na stronie PDF/DjVu z warstwą tekstu, ruch jak w EPUB, przejście przez brzeg strony
- [ ] #2 Prostokąty zgodne z widokiem przy zoomie i przesunięciu
- [ ] #3 Słownik, Vortuyo, AI, kopiuj działają; bez warstwy tekstu komunikat
- [ ] #4 Kolizja zoomu rozstrzygnięta z drugą sesją
<!-- AC:END -->
