---
id: TASK-2
title: 'Wyłączyć etykiety literowe (q, w, e, r, t, y…) na okładkach plików'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-11 06:04'
updated_date: '2026-10-11 06:13'
labels: []
dependencies: []
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Gdy kopad jest włączony, w przeglądarce plików (okładki/mozaika oraz listy) KOReader pokazuje na pozycjach etykiety literowe skrótów klawiaturowych (q, w, e, r, t, y…). Przy sterowaniu padem są zbędne i zasłaniają okładki. Kopad ma je wyłączać na czas działania (i przywracać po wyłączeniu wtyczki).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Przy włączonym kopadzie okładki plików w przeglądarce nie mają nałożonych etykiet literowych (q, w, e, r, t, y…)
- [x] #2 Po wyłączeniu kopada etykiety wracają do poprzedniego stanu (ustawienie użytkownika nie jest trwale nadpisane)
- [ ] #3 Działa na Steam Decku w trybie mozaiki i listy; luac -p przechodzi
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Mechanizm ustalony ze źródeł KOReadera 2026.07.1: etykiety rysuje MenuItem/MosaicMenuItem/ListMenuItem (ItemShortCutIcon) gdy item.shortcut != nil; shortcut ustawia Menu:updateItems / MosaicMenu/ListMenu:_updateItemsBuildUI tylko gdy self.is_enable_shortcut (pole klasy Menu = Device:hasKeyboard(), na Decku true). Brak ustawienia użytkownika (nic w G_reader_settings).
2. Nowy moduł keyhints.lua: apply() robi rawset(BookList, "is_enable_shortcut", false) (klasa bazowa FileChooser/History/Collections; zapamiętuje rawget oryginału), restore() przywraca dokładnie (wartość własna albo nil => dziedziczenie z Menu); idempotentne (flaga applied), wszystko pod pcall; po zmianie odświeża żywą FileManager.instance.file_chooser przez updateItems(select_number) i synchronizuje key_events.SelectByShortCut.
3. main.lua (chirurgicznie): safe_require("keyhints") w _load_subs, kopad:_sync_key_hints() wołane z init (FM tworzy plugin PRZED file_chooserem) i z callbacku toggle (enable=>apply, disable=>restore).
4. Test bare-Lua z mockami (apply/restore/idempotencja/odświeżanie), luac -p, wzmianka w README.md i CLAUDE.md (jedna linia).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta: mechanizm potwierdzony w źródłach KOReadera 2026.07.1 na Decku (Menu.is_enable_shortcut -> class field; FileChooser extends BookList; mosaicmenu.lua:893, listmenu.lua:925). keyhints.lua: rawset(BookList,...) z pełnym restore; testy 35 asercji + integracyjny OK; luac -p OK. AC3 (efekt na ekranie Decka w mozaice i liście) niezweryfikowany — czeka na test na urządzeniu.
<!-- SECTION:NOTES:END -->
