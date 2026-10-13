---
id: TASK-6
title: Więcej akcji ról w czytaniu (14 → 48)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-13 08:25'
updated_date: '2026-10-13 08:26'
labels: []
dependencies: []
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rozszerzenie zamkniętego słownika akcji ról (PC-014) z 14 do 48 pozycji: nawigacja, książka, biblioteka, wygląd, zrzut ekranu, ściągawka, słownik. Większość to zdarzenia KOReadera wysyłane do ReaderUI (te same, których używa Dispatcher). Kontrakt z koligilo (TASK-28 tam).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 padmap.lua ACTION_ORDER ma 48 id; każde ma runner (ACTION_RUNNERS) i etykietę ściągawki (ACTION_LABELS) — pilnuje test
- [x] #2 lua tests/padmap_test.lua zielone
- [x] #3 README i CLAUDE.md opisują nową listę
- [ ] #4 Wgrane na Decka (/opt/koreader-shared/plugins/kopad.koplugin) i przeklikane na urządzeniu
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Kod i testy gotowe (commit f395d14), kopia w ~/modi/koreader/koplugins/kopad.koplugin zaktualizowana. Otwarte AC4: Deck był offline 2026-10-13 (tailscale: last seen 2h) — wgrać: rsync -a --exclude=.git --exclude=llm_config.lua --exclude=CLAUDE.md ~/modi/koreader/koplugins/kopad.koplugin/ deck:/opt/koreader-shared/plugins/kopad.koplugin/ ; potem restart KOReadera ze Steama i przeklikanie nowych akcji (nazwy zdarzeń KOReadera wpisane z pamięci, niezweryfikowane na urządzeniu).
<!-- SECTION:NOTES:END -->
