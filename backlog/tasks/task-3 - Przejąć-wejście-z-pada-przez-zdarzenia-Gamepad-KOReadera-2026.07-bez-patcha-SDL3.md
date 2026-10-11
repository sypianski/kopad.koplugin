---
id: TASK-3
title: >-
  Przejąć wejście z pada przez zdarzenia Gamepad* KOReadera 2026.07 (bez patcha
  SDL3)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-11 06:06'
updated_date: '2026-10-11 06:13'
labels: []
dependencies: []
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Test na Steam Decku (Flatpak KOReader v2026.07.1, stock): LT/RT nie działają, a niektóre przyciski/osie odpalają się w nieskończoność. Przyczyna: KOReader 2026.07 ma wbudowaną obsługę pada (frontend/device/sdl/gamepad.lua + device.lua), a sdl3_gamepad.patch i userpatch 1-lstick-keys.lua są nieaktualne (userpatch hakował nieistniejące już wnętrzności ffi/SDL3.lua). Stock: spusty (osie 4/5) bez mapowania; prawy drążek Y (oś 3) -> RPgBack/RPgFwd z auto-repeatem co 0,2 s po 0,5 s (nieskończone przewracanie); Select(4)->RPgBack (jak LB); Guide(5)->RPgFwd; Start(6) i L3(7)->Menu; X(2) bez mapowania; lewy drążek (osie 0/1) -> Up/Down/Left/Right (jak D-pad) z auto-repeatem. device.lua rozsyła UIManager:broadcastEvent(Event 'GamepadButtonDown' {button}), 'GamepadButtonUp' i 'GamepadAxisMotion' {axis,value,time}; jeśli handler zwróci true, domyślne KeyPress nie jest wysyłane. Zdarzenia osi są wysyłane tylko przy przekroczeniu deadzone (5000) i powtarzane (delay 0,5 s, interwał 0,2 s); zwolnienia osi wtyczka NIE dostaje. Cel: padnav.lua obsługuje te zdarzenia sam, mapuje je na istniejące logiczne akcje i działa na stock KOReaderze bez patchy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 padnav.lua ma handlery onGamepadButtonDown/onGamepadAxisMotion (+ ewentualnie ButtonUp), aktywne tylko gdy kopad włączony (_is_enabled), inaczej zwracają false (domyślne zachowanie KOReadera bez zmian)
- [x] #2 Mapowanie przycisków (id SDL): A0->Confirm, B1->Back, X2->Extend, Y3->Menu, Select4->Select(górne menu), Start6->Start(footer), LB9/RB10->PgBk/PgFwd; D-pad 11-14 przepuszczony (false)
- [x] #3 Spusty LT(oś4)/RT(oś5) przewracają stronę o 1 na jedno wciśnięcie (debounce po event.time: powtórki auto-repeatu nie przewracają kolejnych stron); osie 0/1 -> L-stick, 2/3 -> R-stick wołają istniejące handlery KPUp.. / KPRStick.., prawy drążek NIE wysyła już RPgBack/RPgFwd
- [x] #4 Zachowana zgodność ze starym buildem z patchem (istniejące key_events zostają); luac -p przechodzi; docstring padnav.lua, README i CLAUDE.md (sekcja Runtime requirements) zaktualizowane: patch/userpatch niewymagane na KOReader >= 2026.07
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Zrodla KOReadera 2026.07.1 (device.lua, gamepad.lua, uimanager.broadcastEvent) zweryfikowane: broadcast idzie do widgetow okna -> ReaderUI/FileManager -> ich dzieci (kopad, zarejestrowany przez registerModule); PadNav siedzi tylko w ui.active_widgets, ktore broadcastEvent NIE odwiedza, wiec potrzebny jest cienki relay w main.lua (kopad:onGamepadButtonDown/onGamepadAxisMotion -> subs.nav).
2. padnav.lua: handlery onGamepadButtonDown(ev) i onGamepadAxisMotion(ax), gate _is_enabled() (false = domyslne zachowanie KOReadera). Przyciski: tabela id SDL -> on<Key> (A,B,X,Y,Select,Start,LB,RB); D-pad false; Guide/L3/R3 (+Select/Start gdy handler przepusci) wchlaniane. Osie: 4/5 spusty -> PgBk2/PgFwd2 z filtrem auto-repeatu (zegar time.now(), nie ax.time: pierwszy event ma czas SDL, powtorki time.now() - rozne bazy), 0/1 -> KPLeft/Right/Up/Down (false gdy brak selektora, zeby FM/PDF dalej nawigowal), 2/3 -> KPRStick*, zawsze tlumione gdy kopad wlaczony.
3. Docstring padnav.lua, naglowek main.lua, README.md, CLAUDE.md (Runtime requirements) - patch/userpatch tylko dla KOReadera < 2026.07. Zachowane key_events (F-klawisze) dla starych buildow.
4. Weryfikacja: luac -p padnav.lua main.lua selector.lua + test w bare Lua z mockami (wylaczony -> false; RT x3 w <0.6 s -> jedna strona; os 3 nigdy nie przepuszcza).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta: luac -p OK; test mock 75/75 OK; relay main.lua->PadNav potwierdzony w źródłach KOReadera (broadcastEvent -> handleEvent okien -> dzieci; active_widgets tylko przez sendEvent). Niezweryfikowane na urządzeniu: realny przepływ zdarzeń i timing osi. Ryzyko: L-stick ↑/← (legacy page turn) ma auto-repeat stocka.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
padnav obsługuje zdarzenia Gamepad* KOReadera 2026.07 (LT/RT = strona, Select/Start, tłumienie R-stick Y), bez patcha
<!-- SECTION:FINAL_SUMMARY:END -->
