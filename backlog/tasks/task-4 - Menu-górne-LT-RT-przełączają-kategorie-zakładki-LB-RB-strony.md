---
id: TASK-4
title: 'Menu górne: bumpery LB/RB przełączają kategorie, spusty LT/RT strony'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-11 07:00'
updated_date: '2026-10-11 07:06'
labels: []
dependencies: []
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Zmiana decyzji usera: w górnym menu KOReadera (TouchMenu) LB/RB (bumpery) = poprzednia/następna kategoria (zakładka, z zawijaniem), LT/RT (spusty) = poprzednia/następna strona w obrębie kategorii (spójnie z trybem czytania, gdzie spusty = strony). Stock mapuje LB/RB na RPgBack/RPgFwd (strony menu) — w menu trzeba to przejąć (onGamepadButtonDown 9/10 -> true), a spusty (osie 4/5, stock bez mapowania) obsłużyć przez TouchMenu:onPrevPage/onNextPage (jedno wciśnięcie = jedna strona, filtr auto-repeatu). TouchMenu: tab_item_table, cur_tab, switchMenuTab(n). Przy okazji poprawić dokumentację L4/R4 (tylko stare buildy z patchem).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Gdy kopad jest włączony i na wierzchu jest górne menu (TouchMenu w czytniku i w FileManagerze), RB przełącza na następną kategorię, LB na poprzednią (zawijanie na końcach), ikona aktywnej zakładki i lista pozycji odświeżają się poprawnie; stockowe RPgBack/RPgFwd z bumperów nie przewraca już stron menu
- [x] #2 RT przewraca stronę menu w przód, LT wstecz (TouchMenu:onNextPage/onPrevPage), jedno wciśnięcie = jedna strona (filtr auto-repeatu); D-pad i Press działają jak dotychczas
- [x] #3 Poza górnym menu (inne dialogi/Menu bez tab_item_table, brak menu) LB/RB/LT/RT zachowują się jak dotąd; wyłączony kopad = zero zmian; luac -p i test w bare Lua z mockiem TouchMenu przechodzą
- [x] #4 Ściągawka, docstring padnav.lua, README i CLAUDE.md opisują nowe zachowanie w menu (LB/RB kategorie, LT/RT strony) oraz poprawnie L4/R4 (tylko stare buildy z patchem)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Plan (wg zmiany decyzji): (1) padnav.lua: find_touch_menu() (okno z góry stosu, płytkie przeszukanie dzieci, guard na cykle, pomija toasty) + menu_tab_step(menu, dir) (cur_tab±1 z zawijaniem, bar:switchToTab(k) = ta sama sekwencja co tap na ikonę, pomija zakładki-akcje remember==false/callback), pcall; (2) PadNav:_top_menu() — bramka: kopad włączony, brak obcego overlayu, menu na wierzchu; (3) onGamepadButtonDown: PRZED guardem _is_enabled przyciski 9/10 (LB/RB) w menu -> zmiana kategorii (RB następna, LB poprzednia), return true (tłumi stockowy RPgBack/RPgFwd); (4) onGamepadAxisMotion: PRZED guardem osie 4/5 w menu -> po _trigger_is_new_press menu:onNextPage()/onPrevPage() (RT/LT), return true także dla powtórek; (5) dokumentacja: docstring padnav.lua, CHEAT_READING, README, CLAUDE.md, main.lua header + korekta L4/R4 (tylko stare buildy z patchem); (6) testy w bare Lua z mockiem TouchMenu + uruchomienie wszystkich testów i luac -p.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta: luac -p OK; testy 148/0 fail + keyhints + main_integration OK; kierunki zweryfikowane w kodzie (_menu_button: RB=+1/LB=-1 przez bar:switchToTab; _menu_trigger: RT=onNextPage, LT=onPrevPage z filtrem auto-repeatu). Pomijane w cyklu zakładki-akcje (remember==false / callback: 'filemanager' w czytniku). Niezweryfikowane na urządzeniu. Poza zakresem: w menu Select = stockowe RPgBack (przewraca stronę menu).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
W górnym menu LB/RB przełączają kategorie, LT/RT strony; poprawiona dokumentacja L4/R4
<!-- SECTION:FINAL_SUMMARY:END -->
