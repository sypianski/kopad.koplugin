---
id: TASK-31
title: 'PDF/DjVu: podkreślanie z zaznaczenia kopada'
status: To Do
assignee: []
created_date: '2026-11-03 20:53'
updated_date: '2026-11-03 20:53'
labels:
  - gamepad
  - pdf
dependencies:
  - TASK-30
priority: medium
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Po tikecie zaznaczania w PDF. Podkreślenie w dokumencie stronicowanym zapisuje się inaczej niż w EPUB: pos0/pos1 to pozycje na stronie {x, y, page}, a nie xpointery; ścieżka przez ReaderHighlight (jak przy zaznaczaniu palcem). Do tego przeglądanie i usuwanie podkreśleń pod Y w PDF.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 X w zaznaczeniu PDF tworzy / usuwa podkreślenie widoczne w KOReaderze i po ponownym otwarciu
- [ ] #2 Y w czytaniu PDF przegląda podkreślenia strony
<!-- AC:END -->
