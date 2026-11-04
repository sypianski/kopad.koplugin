---
id: TASK-38
title: 'Wskaż od-do: etykiety słów etapami — najpierw bloki, potem słowa'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-04 00:17'
updated_date: '2026-11-04 00:24'
labels:
  - gamepad
  - ux
  - pdf
dependencies:
  - TASK-36
priority: high
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-04 po próbie 0.1.4 na Decku: etykiety słów (TASK-36) zasłaniają słowa — pigułka ~2 kółka szerokości i wysokości wiersza, wyśrodkowana na górnej krawędzi słowa, zasłania słowo, wiersz nad nim i sąsiednie krótkie słowa; nie da się wybrać słowa. Odrzucone: lupa zdania w pasie ekranu, kursor gałką zamiast etykiet.

Nowy sposób POKAZYWANIA (logika etykiet i koszt wciśnięć bez zmian; drzewo etykiet z TASK-36 zostaje: pierwszy symbol = ciągły blok słów Y / X / A):
- Poziom słów, nic nie wpisane: ŻADNYCH etykiet na słowach. Każdy blok = cienkie podkreślenie pod słowami bloku (pod linią bazową, w odstępie między wierszami) + JEDNA mała plakietka z literą bloku tuż przed pierwszym słowem bloku (po lewej, w RTL po prawej), mniejsza niż dzisiejsza pigułka, nie zasłania słowa.
- Po wpisaniu litery bloku: inne bloki znikają, słowa wybranego bloku (≤7) dostają plakietki z JEDNYM symbolem (drugi symbol etykiety), małe, na przemian nad i pod słowem (nieparzyste nad, parzyste pod, wg kolejności w bloku), przy lewej krawędzi słowa, tak by nie zasłaniały samego słowa.
- Etykiety trzysymbolowe (>21 słów): ten sam wzór o jeden poziom głębiej — po pierwszym symbolu podbloki (podkreślenie + plakietka z drugim symbolem), po drugim plakietki słów z trzecim symbolem.
- Poziom zdań i skróty strzałek bez zmian; B po wpisanym symbolu = cofnij (wraca widok poprzedniego etapu). Podgląd zaznaczenia w kroku końca zostaje.
- Rozmiar plakietek: ze skali wiersza (wysokość słowa), np. ok. 60–70% wysokości wiersza, z minimalnym rozmiarem czytelnym na Decku; podkreślenie 1–2 px.
- Wspólne dla EPUB i PDF.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Bez wpisanego symbolu na poziomie słów widać tylko podkreślenia bloków i po jednej plakietce na blok; słowa nie są zasłonięte
- [x] #2 Po literze bloku tylko słowa tego bloku mają jednosymbolowe plakietki na przemian nad / pod; B wraca do widoku bloków
- [x] #3 Trzy symbole: etap podbloków działa tak samo; RTL po prawej stronie
- [x] #4 Czysta logika etapów (co widać po danym prefiksie) testowana w kopad_hints_test; selector / pdfwords testy rysowania (stuby) zaktualizowane; docs (CLAUDE.md, README)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. kopad_hints.lua: Pointer:stage() (czysta funkcja, widok bieżącego prefiksu): poziom zdań = jak visible() (kind "sentence"); poziom słów, gdy etykiecie zostały >= 2 symbole = kind "blocks": grupy {symbol, typed, words, first, lines (lines_from_boxes), x, y, h, side, room (wolne miejsce przed pierwszym słowem w jego wierszu)}; gdy został 1 symbol = kind "words": {symbol, word, label, box, x, y, side (krawędź słowa: left / right w RTL), place above (nieparzyste) / below (parzyste)}. Opcja Pointer.new opts.width (szerokość ekranu, dla room w RTL). visible() i logika press() bez zmian.
2. selector.lua _draw_point: zdania jak dziś (pigułka); bloki = podkreślenie 1-2 px pod liniami bloku + mała plakietka (ok. 65% wysokości wiersza, min. czytelne) przed pierwszym słowem, gdy brak miejsca nad słowem; słowa = jednosymbolowe plakietki przy krawędzi słowa nad / pod; podgląd końca bez zmian. Kółka dla liter, zaokrąglone kwadraty dla strzałek, mniejsza czcionka.
3. Testy: kopad_hints_test (etapy, naprzemienność, trzy symbole, B cofa, RTL), selector_test i pdfwords_test (stub blitbuffer z prostokątami: nic na prostokątach słów na etapie bloków).
4. Docs: CLAUDE.md (kopad_hints, tryb point) i README (Point from-to).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: 12/12 testów, luac -p ok, diff docs bez cudzych zmian. Do obejrzenia na Decku: plakietka bloku zwykle nad pierwszym słowem (spacja za wąska), plakietki nad/pod w odstępie między wierszami.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Etykiety słów etapami: podkreślone bloki z jedną plakietką, potem plakietki słów nad/pod
<!-- SECTION:FINAL_SUMMARY:END -->
