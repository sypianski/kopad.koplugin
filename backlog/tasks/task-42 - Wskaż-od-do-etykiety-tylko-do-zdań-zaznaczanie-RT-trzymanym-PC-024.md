---
id: TASK-42
title: 'Wskaż od-do: etykiety tylko do zdań, zaznaczanie RT trzymanym (PC-024)'
status: Done
assignee: []
created_date: '2026-11-04 08:20'
updated_date: '2026-11-04 08:39'
labels: []
dependencies: []
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Zastępuje schemat TASK-36..41 (drzewo liter A X Y na słowach, krok końca, plakietki strzałek, przerywana linia). Decyzja: ~/utensili/libraro/decyzje/PC-024 (zastępuje PC-023).

Przepływ: A stuknięte = etykiety zdań (bez zmian). Etykieta = kursor na pierwszym widocznym słowie zdania, bez zaznaczenia (tryb słów). Dalej:
- bez spustu: ←/→ słowo, ↑ początek bieżącego zdania (na początku: poprzedniego), ↓ początek następnego (przez krawędź strony, jak inne ruchy bez zakresu).
- RT trzymany = zaznaczanie (kotwica = kursor przy pierwszym ruchu z RT): ←/→ zakres o słowo; ↓ koniec zakresu do końca bieżącego zdania, gdy już na końcu = koniec następnego; ↑ zdejmuje zdanie (koniec na koniec poprzedniego zdania, nie przed kotwicę; na kotwicy = rozszerza wstecz do początku zdania). Zakres nie wychodzi poza stronę. Po puszczeniu RT zakres zostaje.
- A stuknięte = menu akcji; B = cofa krok: jest zakres -> kasuje go (kursor zostaje), nie ma -> z powrotem etykiety zdań (gdy tryb słów wszedł z etykiety), inaczej zamyka.
- LT/RT nie ruszają kursora w trybie słów (bez skoku o akapit); linii brak. LB/RB jak dziś (strona).
- RTL: ←/→ odwrócone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Etykieta zdania stawia kursor na jego pierwszym widocznym słowie bez zaznaczenia; drzewo liter, krok końca, plakietki strzałek i przerywana linia usunięte (kopad_hints.lua, selector.lua, testy)
- [x] #2 W trybie słów ↑/↓ skaczą o początek zdania (↑ bieżące/poprzednie, ↓ następne, przez krawędź strony bez zakresu)
- [x] #3 RT trzymany zaznacza: ←/→ o słowo, ↓ do końca zdania i kolejne zdania, ↑ zdejmuje zdanie / na kotwicy do początku zdania; puszczenie RT zostawia zakres; zakres nie wychodzi poza stronę
- [x] #4 B: zakres -> kasuje, bez zakresu -> etykiety zdań (wejście z etykiety) albo zamyka; A stuknięte = menu akcji; LT/RT bez ruchu w trybie słów
- [x] #5 EPUB i PDF, RTL; testy (selector_test, kopad_hints_test, pdfwords_test, padmap_test) zielone; CLAUDE.md, README, nagłówek padnav.lua i linia statusu zaktualizowane
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: 12 plików testów zielonych, luac -p bez błędów; przejrzany diff (_rt_hold z polowaniem held_axis_directions[5] jak _dictate_hold, _ww_range_target, _ww_sent, SelectorOverlay:back). Wybory sub-agenta: B po przejściu strony = etykiety strony bieżącej; ↓ przez krawędź pomija dokończenie zdania z poprzedniej strony; zdalnie zmapowany RT = zatrzask. Do sprawdzenia na Decku: czy auto-repeat RT nie przewraca strony, odczucie polowania 0,05 s.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Wskaż od-do: etykiety tylko do zdań, kursor ↑↓ o zdanie, RT trzymany zaznacza (PC-024)
<!-- SECTION:FINAL_SUMMARY:END -->
