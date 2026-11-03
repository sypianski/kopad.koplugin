---
id: TASK-34
title: 'Automatyczne wyłączanie kopada, gdy nie ma podłączonego pada'
status: To Do
assignee: []
created_date: '2026-11-03 21:08'
labels: []
dependencies: []
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Gdy do urządzenia nie jest podłączony żaden pad, kopad ma się sam dezaktywować, żeby nie bruździł w zwykłej obsłudze KOReadera (klawiatura, dotyk, czytnik bez pada): przechwytywanie klawiszy (_suppress_reader_keys), konteksty, owijanie ButtonDialog w koło (wheel.lua), etykiety itd. Po podłączeniu pada — włącza się z powrotem bez restartu.

Steam Deck: wbudowany kontroler jest zawsze podłączony, więc tam kopad zostaje aktywny.

Do ustalenia: skąd brać listę padów w KOReaderze >= 2026.07 (SDL, frontend/device/sdl/gamepad.lua / device.lua — zdarzenia podłączenia/odłączenia padu?), co ze starszymi buildami (ścieżka key_events), czy to osobny stan od ręcznego „Enable kopad” (ręczny wyłącznik ma pierwszeństwo).

Zgłoszone przy dyktowaniu przez diktonoti (pad przejmuje X/A/B/RT w polach tekstowych).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Bez podłączonego pada kopad nie zmienia żadnych klawiszy ani okien KOReadera
- [ ] #2 Podłączenie/odłączenie pada przełącza kopad bez restartu
- [ ] #3 Na Steam Decku (wbudowany kontroler) kopad jest aktywny
- [ ] #4 Ręczne wyłączenie w menu dalej działa i ma pierwszeństwo
<!-- AC:END -->
