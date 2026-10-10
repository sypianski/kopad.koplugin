---
id: TASK-1
title: Zmapować przyciski na Steam Decku i DualSense
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-09 17:49'
updated_date: '2026-10-09 17:58'
labels: []
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Należy poprawić mapowanie przycisków na Steam Decku i kontrolerze DualSense (dual shock) podłączonym do Steam Decka. Główne przyciski kciuków powinny służyć do zmiany stron (prawy na następną, lewy na poprzednią). Trzeba też zapewnić łatwy dostęp do menu górnego i dolnego oraz podpowiedzi do przycisków.

Z nagrania: „W kopadzie trzeba lepiej zmapować przyciski na Steam Decku i na dual shooku podłączonym do Steam Decka. Główne przyciski na kciukach powinny zmieniać strony prawy na następną i lewy na poprzednią. Powinien być łatwy dostęp do menu górnego, menu dolnego. Powinny być znaczenie wielu znaków, wielu, wielu słów powinno być. też prawidłowe podpowiedzi do tych przycisków.”
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spusty LT/RT (F6/F7) przewracają strony: RT = następna, LT = poprzednia, w trybie czytania; LB/RB zachowują funkcje extend/trim/słowniki
- [ ] #2 Select otwiera górne menu, Start dolne menu (footer) w trybie czytania, bez kombinacji z X; mapowanie nie psuje działania gdy nazwa klawisza nieznana (udokumentowane założenie)
- [x] #3 Ekranowa ściągawka przycisków dla trybu czytania i zaznaczania dostępna z menu kopad, zgodna z faktycznymi handlerami
- [x] #4 Docstringi padnav.lua/main.lua i README zsynchronizowane z handlerami; luac -p przechodzi dla zmienionych plików
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Rozdzielić LT/RT (F6/F7) od LB/RB: nowe handlery onKPPgBk2/Fwd2 zawsze przewracają strony (RT=następna, LT=poprzednia, RTL-aware), niezależnie od overlay/słownika. LB/RB bez zmian. L4/R4 zostają aliasem LB/RB.
2. Select -> górne menu (ShowMenu), Start -> dolne menu (footer), bez X; bindowanie kandydatów nazw klawiszy (Menu, Select), założenie udokumentowane w kodzie; hunk do sdl3_gamepad.patch jako propozycja w scratchpadzie.
3. Ściągawka: pozycje w menu kopad (tryb czytania, zaznaczanie) generowane z jednej tabeli zgodnej z handlerami.
4. Synchronizacja docstringów padnav.lua/main.lua i README; luac -p.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC1: onKPPgFwd2/Bk2 -> _turn_page(±1), GotoViewRel +1=next (zweryfikowane diffem; keyremap.lua potwierdza znak). AC3: 2 pozycje ściągawki w menu + About, teksty zgodne z handlerami (przegląd diffu). AC4: luac -p padnav.lua main.lua OK, docstringi i README przepisane. AC2: kod gotowy (Select=F12, Start=F2), ale NIE działa bez zmiany upstream w sdl3_gamepad.patch (BACK->1073741893 F12, START->1073741883 F2; hunk w scratchpadzie select_start.hunk) albo remapu w Steam Input. Nie zweryfikowane na urządzeniu. Zmiana poza opisem: znaki GotoViewRel dla LB/RB odwrócone (RB=next, LB=prev). Do sprawdzenia: rozjechana kopia w modi/koreader/koplugins/kopad.koplugin, L4/R4 nadal aliasy LB/RB.
<!-- SECTION:NOTES:END -->
