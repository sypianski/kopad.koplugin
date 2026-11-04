---
id: TASK-36
title: 'Wskaż od-do: litery na słowach, strzałki jako skróty zdań i akapitu'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 23:58'
updated_date: '2026-11-04 00:10'
labels:
  - gamepad
  - ux
  - pdf
dependencies:
  - TASK-35
references:
  - >-
    ../../libraro/decyzje/PC-023-wskaz-od-do-litery-na-slowach-strzalki-jako-skro.md
priority: high
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Zastępuje sposób doprecyzowania z TASK-35 (PC-022 zrewidowana przez PC-023 w libraro/decyzje). Problem na Decku (0.1.1): R↓ działa tylko na bieżący krok i trzeba go użyć przed wyborem zdania, więc w praktyce dało się zaznaczać tylko od początku zdania do słowa.

Nowy przebieg (decyzja usera 2026-11-04):
- Krok początku, poziom zdań: etykiety przy początkach zdań jak dziś (8 symboli, B nie jako pierwszy, maks. 56). B = zamknij. Wybór etykiety zdania NIE ustawia od razu początku, tylko pokazuje poziom słów tego zdania.
- Krok początku, poziom słów: etykiety LITEROWE na słowach zdania (pierwszy symbol A / X / Y; drugi: A, X, Y, potem strzałki — litery najpierw, strzałki gdy brakuje; B po pierwszym symbolu = cofnij symbol). Etykieta = początek na tym słowie. ← = początek zdania, ↑ = początek akapitu tego zdania. B = wróć do etykiet zdań. Po wyborze -> krok końca.
- Krok końca: 'bieżące zdanie końca' E, na starcie = zdanie początku. Etykiety literowe na słowach E (w zdaniu początku od słowa początku). Etykieta = koniec na tym słowie, gotowe. ← = koniec E, gotowe. → = E+1 (podgląd zaznaczenia do końca E+1, etykiety słów przechodzą na E+1). ↑ = E-1 (nie przed zdaniem początku). ↓ = koniec akapitu E, gotowe. B = jedno słowo (jak dziś); B po pierwszym symbolu = cofnij symbol.
- Etykiety słów: 21 słów (A/X/Y x 7). Gdy zdanie (jego część w danym kroku) ma więcej niż 21 widocznych słów: wszystkie etykiety słów w tym zdaniu trzysymbolowe (A/X/Y x 7 x 7 = 147); powyżej tego okno pierwszych 147.
- RTL: ← i → zamienione (dalej = w lewo).
- Tryb R↓ / R↑ (refine_to_word) znika; prawa gałka w trybie point nic nie robi (konsumowana).
- Zakres nigdy nie wychodzi poza stronę: → na ostatnim zdaniu strony nic nie robi.
- Wspólne dla EPUB i PDF. Akapity: sentences[].para (paginmapo / pdfwords + pdfpara).
- Po 'gotowe' jak dziś: tryb walk z kotwicą (A + strzałki poprawiają, stuknięcie A = menu akcji).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Krok początku: etykieta zdania -> etykiety literowe słów; etykieta słowa / ← / ↑ ustawiają początek; B wraca do zdań, na zdaniach zamyka
- [x] #2 Krok końca: etykieta słowa / ← / ↓ kończą; → i ↑ zmieniają bieżące zdanie z podglądem i przeniesieniem etykiet; B = jedno słowo
- [x] #3 Etykiety słów: pierwszy symbol A/X/Y, litery przed strzałkami; >21 słów = trzy symbole; RTL zamienia ← i →
- [x] #4 R↓ / R↑ usunięte z trybu point; pasek stanu opisuje bieżący krok i skróty
- [x] #5 Testy czystej logiki (kopad_hints) oraz selektora EPUB i PDF i padnav; dokumentacja (CLAUDE.md, README, nagłówki, CHEAT_*)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. kopad_hints.lua: Pointer na nowo — krok start (poziom zdań: M.assign, 8 symboli, 56; poziom słów), krok end od razu na słowach zdania początku (E). M.word_labels(n): etykiety literowe w kolejności czytania (bloki Y/X/A, w bloku litery przed strzałkami, pierwszy = podwojony symbol), 2 symbole do 21 słów, 3 symbole do 147, okno. typed = lista symboli, B = cofnij ostatni. Skróty strzałek na poziomie słów (RTL zamienia ←/→): start ← zdanie, ↑ akapit; end ← koniec E, → E+1, ↑ E-1, ↓ koniec akapitu. Usunąć refine_to_word. Pole para w zdaniach. preview() = start..koniec E.
2. selector.lua: _point_sentences przekazuje para; usunąć point_refine; _draw_point: 2/3 symbole, podgląd start..koniec E (linie z lines_from_boxes); _status_text dla kroków.
3. padnav.lua: _rstick w trybie point konsumuje i nic nie robi; nagłówek + CHEAT_*.
4. Testy: kopad_hints_test, selector_test, pdfwords_test, padmap_test.
5. Docs: CLAUDE.md, README, nagłówki main.lua/selector.lua/padnav.lua.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: 11/11 testów, luac -p ok, refine API usunięte, niezależna symulacja Pointera: zdanie → słowo 3 → ← = 3..koniec zdania; → → ↑ przenosi etykiety; ↓ = koniec akapitu. Etykiety słów w kolejności czytania (bloki Y/X/A). Do obejrzenia na Decku: czytelność etykiet i podglądu.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Wskaż od-do: litery na słowach zdania, strzałki jako skróty zdania i akapitu, bez R↓
<!-- SECTION:FINAL_SUMMARY:END -->
