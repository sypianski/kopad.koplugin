---
id: TASK-39
title: 'Wskaż od-do: fragmenty po 3 słowa, literki A/X/Y w stałym miejscu'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-04 00:33'
updated_date: '2026-11-04 00:42'
labels:
  - gamepad
  - ux
  - pdf
dependencies:
  - TASK-38
priority: high
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decyzja usera 2026-11-04 po próbie 0.1.6 na Decku: bloki z TASK-38 są nieintuicyjne i nieprzewidywalne (3 bloki do 7 słów, plakietka raz przed słowem raz nad, słowa na przemian nad / pod, podkreślenia). Zastępuje schemat etykiet słów z TASK-36 / TASK-38 (poziom zdań i skróty strzałek bez zmian).

Nowy schemat poziomu słów (start i koniec):
- Drzewo trójkowe w kolejności czytania. n widocznych słów w danym kroku (w kroku końca od słowa początku), k = liczba etapów = najmniejsze k z 3^k >= n (n = 1 -> k = 1). Etap i dzieli bieżący zakres na kolejne kawałki po 3^(k-i) słów (ostatni krótszy), od początku zakresu: najmniejsze fragmenty = 3 słowa.
- Każdy etap: najwyżej 3 znaki, symbole zawsze A, X, Y w kolejności czytania (pierwszy kawałek A, drugi X, trzeci Y). Znak przy PIERWSZYM słowie kawałka. Wciśnięcie litery = wejście w ten kawałek (poprzednie znaki znikają, pojawiają się znaki następnego etapu); na ostatnim etapie litera = to słowo (start / koniec).
- Koszt: do 9 słów 2 wciśnięcia, do 27 3, do 81 4.
- Wygląd: znak to mała plakietka z jedną literą (ok. 60–70% wysokości wiersza, minimum czytelne), ZAWSZE nad początkiem słowa (lewa krawędź; RTL prawa), w odstępie między wierszami; gdy nad wypada poza ekran — pod. Bez podkreśleń, bez plakietek przed słowem, bez naprzemiennego nad / pod.
- Strzałki są skrótami na KAŻDYM etapie (litery są jedynymi symbolami etykiet słów): krok początku ← początek zdania, ↑ początek akapitu; krok końca ← koniec bieżącego zdania, → następne zdanie (powtarzalne, etykiety przechodzą), ↑ o zdanie mniej, ↓ koniec akapitu. B: cofnij jeden etap; bez wpisanych etapów jak dziś (krok początku: wróć do zdań; krok końca: jedno słowo).
- RTL: ← i → zamienione jak dziś; znak przy prawej krawędzi.
- Wspólne dla EPUB i PDF.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Poziom słów: trójkowe drzewo po 3 słowa, A/X/Y w kolejności czytania, znak przy pierwszym słowie kawałka, liczba etapów wg długości (2 do 9, 3 do 27, 4 do 81)
- [x] #2 Znak zawsze nad początkiem słowa (RTL prawa krawędź), poza ekranem pod; bez podkreśleń; żaden znak nie nachodzi na ramkę słowa
- [x] #3 Strzałki działają jako skróty na każdym etapie; B cofa etap
- [x] #4 Testy czystej logiki (kopad_hints) i rysowania (selector EPUB, pdfwords PDF, padmap), docs (CLAUDE.md, README, nagłówki, CHEAT_*)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. kopad_hints.lua: M.word_labels(n) = drzewo trójkowe (k = najmniejsze z 3^k >= n, n = 1 -> 1; etykieta = k cyfr trójkowych indeksu, A / X / Y = 0 / 1 / 2 w kolejności czytania); bez okna 147 (WORD_MAX2/3, WORD_ARROWS, word_fill usunięte). Pointer:press na poziomie słów: strzałka = skrót zawsze (też po prefiksie), litera filtruje, B = cofnij etap / jak dziś. stage() na poziomie słów: kind "words", jeden element na kawałek bieżącego etapu {symbol, word (pierwsze słowo kawałka), box, x (lewa krawędź, RTL prawa), y (górna krawędź plakietki), d, place above / below (below gdy b.y - d < 0)}; d z opts.badge (funkcja h -> px) albo 65 % h. Usunięte blocks / room / _room_before / opts.width.
2. selector.lua: badge_size przeniesione przed _point_begin i podane jako opts.badge; _draw_point: słowa = tylko plakietki z jedną literą (paint_badge), bez podkreśleń; above_or_below usunięte; _point_status: litery etapu + skróty + B back.
3. Testy: kopad_hints_test (drzewo n = 1, 3, 4, 9, 10, 27, 28, 81, 82; press po etapach; B; strzałki po prefiksie; RTL; place below), selector_test i pdfwords_test (znaki tylko nad początkami słów, nic na ramkach słów, bez podkreśleń; zdanie -> litera -> litera -> ←).
4. Docs: CLAUDE.md (kopad_hints, tryb point, Point from-to), README, nagłówki kopad_hints / selector / padnav, CHEAT_SELECTION.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: 12/12 testów, luac -p ok, diff padnav tylko point. Symulacja zdania 20 słów: A@1 X@10 Y@19 -> X -> trójki -> A -> słowa -> Y = start, ← = koniec zdania. Do obejrzenia na Decku: plakietka nad słowem przy ciasnej interlinii może zahaczać o wiersz wyżej.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Wskaż od-do: słowa zdania jako drzewo trójkowe A/X/Y, plakietki nad pierwszym słowem kawałka
<!-- SECTION:FINAL_SUMMARY:END -->
