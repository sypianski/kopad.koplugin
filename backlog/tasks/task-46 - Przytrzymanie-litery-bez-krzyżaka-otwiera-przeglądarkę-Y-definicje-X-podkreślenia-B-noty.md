---
id: TASK-46
title: >-
  Przytrzymanie litery bez krzyżaka otwiera przeglądarkę: Y definicje, X
  podkreślenia, B noty
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-04 09:49'
updated_date: '2026-11-04 11:19'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Bump 0.1.16 -> 0.1.17 (_meta.lua).
2. padmap.lua: three new action ids (vortpaf_glosses, bookmarks_highlights, bookmarks_notes) + optional additive key `hold` (role b/x/y -> action, merged over DEFAULT_HOLD, none = off, bad data skipped with a warning); build() returns res.hold.
3. padnav.lua: generic letter hold (_hold_start/_hold_end, HOLD_S 0.6 s via UIManager:scheduleIn): started only in idle reading/paged (Y/B press, X arming the modifier); any other button / trigger during the hold spends it (D-pad modes, X combos); after the threshold a toast hint "-> <action>"; release after the threshold without another control = the hold action instead of the tap. Runners: VortpafGlosses event (message without Vortpaf), ReaderBookmark list with match_table filter (highlight+note / note).
4. Docs: padnav header, cheat sheet, README/CLAUDE.md.
5. Tests: padmap hold parsing + padnav wiring (tap Y, hold Y, Y+D-pad, X combo after threshold, X/B hold, no Vortpaf, selection Y/B on the press).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Uzupełnienie opisu (fragment wypadł przy zakładaniu): akcje przytrzymania jako konfigurowalne w padmap, np. klucz hold = { y = "vortpaf_glosses", x = "bookmarks_highlights", b = "bookmarks_notes" }, addytywnie w version 1.

Zgoda usera na wdrożenie (2026-11-04), z wydaniem na Decka; push publicznego repo za osobną zgodą.

Wydane 2026-11-04: 0.1.17 (eb40329) pushed, galeria koligilo → Bigyo, ONYX Go6, Onyx NoteAir3C, SteamDeck. Decyzja usera: X = wszystkie podkreślenia (highlight+note), B = tylko z notatką. Testy: 12/12 zestawów OK. Do sprawdzenia na Decku: dymek po ~0,6 s; Y przytrzymane → lista glos Vortpafa 0.7.0 (EPUB); X/B → lista zakładek z filtrem, po zamknięciu lista bez filtra; Y/B w zaznaczeniu działają od razu; w PDF B + krzyżak dalej zoomuje. Koligilo (padmap.go/web) nie zna jeszcze klucza hold ani nowych id akcji.
<!-- SECTION:NOTES:END -->
