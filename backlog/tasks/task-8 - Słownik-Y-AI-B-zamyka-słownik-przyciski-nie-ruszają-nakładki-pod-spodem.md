---
id: TASK-8
title: 'Słownik: Y = AI, B zamyka słownik, przyciski nie ruszają nakładki pod spodem'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 17:14'
updated_date: '2026-11-03 17:25'
labels:
  - gamepad
  - bug
dependencies:
  - TASK-7
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Przy okienku słownika otwartym z selektora nakładka zostaje pod spodem. Na ścieżce Gamepad* (KOReader >= 2026.07) onKPMenu zjada Y i robi Vortuyo pod spodem, więc hook Y->AI z _hook_dict_widget (klawisz ContextMenu) nigdy nie dochodzi; B zamyka nakładkę zamiast słownika; A otwiera menu akcji nad słownikiem; gałki ruszają kursorem pod spodem.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Kontekst dict: LB/RB = poprzedni/następny słownik, Y = wyjaśnienie AI, B i A oraz D-pad/L-gałka trafiają do słownika (stock), R-gałka i pozostałe nie ruszają nakładki
- [x] #2 Test w tests/ dla kontekstu dict
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Kontekst dict poza PAD_CONTEXTS: stockowe klawisze idą do okienka (LB/RB = RPgBack/RPgFwd = ReadPrev/NextResult, B zamyka, A/D-pad/gałki), spusty zjadane, nadpisania PC-014 nie działają. PadNav:_dict_button: Y = AI dla zaznaczenia z nakładki kopada (zamyka okienko, overlay:_do_ai), bez zaznaczenia przepuszcza. Usunięte martwe _find_dict_widget i gałęzie słownika w onKPPgFwd/onKPPgBk/_turn_page/onKPSelect/onKPStart/_override_action (DictQuickLookup nie ma pola name, więc nigdy nie działały). selector._hook_dict_widget szuka okienka przez DictQuickLookup.window_list (ścieżka legacy). Testy w sekcji 11. Niezweryfikowane na urządzeniu.
<!-- SECTION:NOTES:END -->
