---
id: TASK-46
title: >-
  Przytrzymanie litery bez krzyżaka otwiera przeglądarkę: Y definicje, X
  podkreślenia, B noty
status: To Do
assignee: []
created_date: '2026-11-04 09:49'
updated_date: '2026-11-04 09:49'
labels: []
dependencies: []
priority: medium
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Propozycja usera (2026-11-04). Podczas czytania (EPUB i PDF/DjVu, kontekst reading/paged) każda litera rozróżnia trzy gesty: krótkie naciśnięcie (jak dziś), przytrzymanie + D-pad (tryb, jak dziś), przytrzymanie dłuższe niż próg (ok. 0,6 s) i puszczenie bez D-pada = przeglądarka. Po przekroczeniu progu krótki napis (np. „→ definicje”), żeby było wiadomo, co otworzy puszczenie; D-pad po progu nadal przełącza w tryb.

Mapowanie (decyzja usera):
- Y przytrzymane → przeglądarka glos Vortpafa (akcja Dispatchera z koreader TASK-9 w ~/utensili/koreader/backlog, np. vortpaf_glosses; bez Vortpafa komunikat, nie błąd),
- X przytrzymane → lista podkreśleń książki (stock: lista zakładek KOReadera z filtrem podkreśleń); X jest dziś modyfikatorem (x_modifier, X-combo) — przytrzymanie bez kombinacji nie może psuć kombinacji,
- B przytrzymane → noty marginalne (marjenoti pokazuje notatki z podkreśleń KOReadera; stock lista zakładek z filtrem notatek),
- krótkie Y zostaje na razie przy podkreśleniach strony; user przypisze mu później coś innego (nie zmieniać teraz).
Do rozważenia w padmap: akcje przytrzymania jako konfigurowalne (np. , addytywnie w version 1, koligilo TASK-25/26 edytuje te dane) — decyzja przy implementacji, zapisać jako PC.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Przytrzymanie Y/X/B bez D-pada otwiera odpowiednio glosy Vortpafa, podkreślenia, notatki; krótkie naciśnięcia i tryby z D-padem działają jak dziś
- [ ] #2 Po przekroczeniu progu widać, co otworzy puszczenie
- [ ] #3 Kombinacje z X (X-combo) bez regresji; testy w tests/
- [ ] #4 Brak Vortpafa = komunikat zamiast błędu
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Uzupełnienie opisu (fragment wypadł przy zakładaniu): akcje przytrzymania jako konfigurowalne w padmap, np. klucz hold = { y = "vortpaf_glosses", x = "bookmarks_highlights", b = "bookmarks_notes" }, addytywnie w version 1.
<!-- SECTION:NOTES:END -->
