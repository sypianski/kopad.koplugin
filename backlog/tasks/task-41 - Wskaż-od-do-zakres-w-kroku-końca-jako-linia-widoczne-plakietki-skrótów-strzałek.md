---
id: TASK-41
title: >-
  Wskaż od-do: zakres w kroku końca jako linia, widoczne plakietki skrótów
  strzałek
status: Done
assignee:
  - '@claude'
created_date: '2026-11-04 01:13'
updated_date: '2026-11-04 01:22'
labels:
  - gamepad
  - ux
dependencies:
  - TASK-40
priority: high
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Uwagi usera 2026-11-04 po próbie 0.1.12 na Decku: (1) w kroku końca podgląd (odwrócony tekst od słowa początku do końca bieżącego zdania) wygląda jak gotowe zaznaczenie, a to tylko zakres, z którego wybiera się koniec; (2) start od początku zdania jest częsty, a skrót ← (po etykiecie zdania) jest niewidoczny — user przeklikiwał się przez fragmenty i słowa.

Zmiany (wybór usera):
1. Krok końca, rysowanie: ODWRÓCONE tylko słowo początku. Reszta zakresu (od słowa po starcie do końca bieżącego zdania końca E) = cienka przerywana linia (1–2 px) pod wierszami (lines_from_boxes), bez wypełnienia; → / ↑ przesuwają ją z E. Pełne odwrócenie dopiero po wyborze końca (tryb walk jak dziś).
2. Plakietki skrótów strzałek na tekście (na poziomie słów; ten sam paint_badge, strzałka w zaokrąglonym kwadracie, rozmiar jak plakietki liter):
   - krok początku: '←' przy początku zdania — na lewo od plakietki A nad pierwszym słowem (ta sama wysokość); gdy brak miejsca (krawędź ekranu) — pod początkiem pierwszego słowa; '↑' nad pierwszym słowem akapitu, jeśli akapit zaczyna się wcześniej niż zdanie i to słowo jest widoczne.
   - krok końca: '←' tuż za ostatnim słowem E (na prawo, ta sama wysokość co plakietki; brak miejsca -> pod końcem słowa); '↓' za ostatnim widocznym słowem akapitu E, jeśli inne niż koniec E; '→' nad pierwszym słowem następnego widocznego zdania (jeśli jest).
   - RTL: lustrzanie (strony i znaczenie ← / → jak dziś).
   - Plakietki skrótów nigdy nie nachodzą na ramki słów ani na plakietki liter.
3. Logika, koszt i skróty bez zmian.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Krok końca: odwrócone tylko słowo początku, reszta zakresu przerywaną linią pod wierszami, przesuwana przez → / ↑
- [x] #2 Plakietki ← / ↑ w kroku początku i ← / ↓ / → w kroku końca w opisanych miejscach, bez nachodzenia na słowa i plakietki liter; RTL lustrzanie
- [x] #3 Testy rysowania (selector EPUB, pdfwords PDF) i czystej logiki pozycji (kopad_hints); docs
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. kopad_hints.lua (czysto): stage() na poziomie słów dostaje st.shortcuts = { {symbol (fizyczny: left/up/down/right, RTL ←/→ zamienione), word, x, y, d, place} } z pozycjami lewego górnego rogu. Kandydaci po kolei (spec), pierwszy na ekranie (opts.width/height) i bez nachodzenia na ramki słów (wszystkie boxes), plakietki liter etapu i wcześniej położone skróty; gdy żaden nie jest wolny — kandydat o najmniejszym nachodzeniu na słowa (nigdy na plakietki). Start: ← obok plakietki A nad pierwszym słowem zdania (lewo; brak miejsca: pod początkiem słowa, potem prawo od A), ↑ nad pierwszym słowem akapitu, gdy cel ↑ inny niż początek zdania. Koniec: ← za ostatnim słowem E (ta sama wysokość; brak miejsca: pod końcem słowa), ↓ za ostatnim widocznym słowem akapitu E, gdy inne niż koniec E, → nad pierwszym słowem następnego widocznego zdania. RTL lustrzanie. Nowe M.dashes(lines, opts) -> odcinki przerywanej linii 1 px pod dolną krawędzią wierszy. preview() bez zmian (start, koniec E).
2. selector.lua _draw_point: w kroku końca odwrócone tylko sbox słowa początku, reszta (start+1..koniec E) = Hints.dashes(lines_from_boxes) jako paintRect; potem plakietki liter, potem skróty (paint_badge z symbolem strzałki). Opcje Pointer: width/height ekranu, gap.
3. Testy: kopad_hints_test (pozycje, krawędzie, ↑/↓/→ warunkowo, RTL, brak nachodzenia, dashes), selector_test (EPUB krok końca, → przesuwa linię, skróty rysowane), pdfwords_test (to samo w PDF); dopasowanie istniejących asercji „tylko plakietki liter”.
4. Docs: CLAUDE.md (kopad_hints / tryb point), README (point) — Edit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: 12/12 testów, luac ok. Decyzja agenta przyjęta: w ciasnym składzie, gdy żadne miejsce nie jest wolne od ramek słów, plakietka skrótu stoi tam, gdzie zakrywa najmniej (nigdy na plakietce liter) — do oceny na Decku.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Zakres w kroku końca jako przerywana linia, plakietki skrótów strzałek na tekście
<!-- SECTION:FINAL_SUMMARY:END -->
