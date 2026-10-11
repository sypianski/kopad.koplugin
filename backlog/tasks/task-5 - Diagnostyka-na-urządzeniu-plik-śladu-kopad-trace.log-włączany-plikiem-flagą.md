---
id: TASK-5
title: 'Diagnostyka na urządzeniu: plik śladu kopad-trace.log włączany plikiem-flagą'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-11 07:15'
updated_date: '2026-10-11 07:20'
labels: []
dependencies: []
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Po wdrożeniu TASK-2/3/4 na Steam Decku użytkownik zgłasza 'bez zmian' (restart KOReadera zrobiony), a w Flatpaku nie ma żadnych logów (brak crash.log, stdout niedostępny). Potrzebny lekki ślad diagnostyczny: moduł trace.lua zapisuje do <settings dir>/kopad-trace.log (DataStorage:getSettingsDir()), TYLKO gdy istnieje plik-flaga <settings dir>/kopad-trace (zdalnie włączany/wyłączany bez zmiany kodu). Ślad ma pokazać: który kod się załadował (mtime padnav.lua/main.lua), czy sub-moduły się załadowały (nav, selector, keyhints) lub błąd ładowania, stan enabled, KAŻDE zdarzenie Gamepad* docierające do kopad:onGamepad* (przycisk/oś/wartość, czy subs.nav istnieje) i wynik w padnav (powód false: wyłączony / obcy overlay / modal; gałąź menu; nazwa handlera i jego zwrot). Bez flagi zero narzutu i zero zmian zachowania.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 trace.lua: Trace.log(...) dopisuje linie z czasem do kopad-trace.log tylko gdy istnieje plik-flaga kopad-trace; brak flagi = nic nie jest zapisywane; wszystkie operacje pod pcall (nigdy nie rzuca); limit rozmiaru (np. obcięcie/rotacja powyżej ~256 KB) i rate-limit (np. max ~20 linii/s, powtórki osi zwinięte)
- [x] #2 Punkty logowania: main.lua init (mtime plików padnav/main/keyhints, enabled, wynik ładowania każdego sub-modułu lub błąd), relay kopad:onGamepadButtonDown/AxisMotion (button/axis/value, czy nav istnieje), padnav onGamepadButtonDown/AxisMotion (powód przepuszczenia false lub nazwa handlera + zwrot, gałąź menu)
- [x] #3 Test w bare Lua: bez flagi nic nie zapisuje; z flagą zapisuje oczekiwane linie; błędy I/O nie rzucają; wszystkie dotychczasowe testy (148 asercji padnav, keyhints, main_integration) nadal przechodzą; luac -p przechodzi; README/CLAUDE.md: krótka wzmianka o śladzie i fladze
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Nowy modul kopad_trace.lua (nazwa unika kolizji z "trace" w package.loaded / KOReader): flaga-plik kopad-trace w settings dir, cache 2 s, rate-limit 20 l/s ze zwinieciem, zwijanie powtorek osi (<0.3 s), obciecie >256 KB do ostatnich 64 KB, wszystko pod pcall.
2. main.lua: pcall(require,"kopad_trace") z no-op stubem; logi: start (mtime padnav/main/keyhints), enabled, wynik ladowania sub-modulow, ui.rolling, toggle enabled, relay onGamepad*.
3. padnav.lua: ten sam loader; PadNav:_why_disabled() (ta sama kolejnosc co _is_enabled) wywolywany tylko gdy Trace.active(); logi powodu zwrotu, nazwy handlera i jego zwrotu, result=<bool> w onGamepadButtonDown/AxisMotion. Bez zmian semantyki.
4. Test test_trace.lua (bare Lua, mock datastorage przez package.preload) + regresja istniejacych testow + luac -p.
5. README (Diagnostics) i 1 linia w CLAUDE.md.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta: luac -p OK; testy: padnav 148/0, keyhints OK, main_integration OK, trace 57/0. Moduł nazwany kopad_trace (unik kolizji w package.loaded). Niezweryfikowane na LuaJIT/KOReaderze.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
kopad_trace.lua: ślad diagnostyczny kopad-trace.log włączany plikiem-flagą kopad-trace w katalogu ustawień
<!-- SECTION:FINAL_SUMMARY:END -->
