---
id: TASK-32
title: 'PDF/DjVu: wykrywanie akapitów (LT/RT i ↑/↓ w zdaniach)'
status: To Do
assignee: []
created_date: '2026-11-03 20:53'
updated_date: '2026-11-03 20:53'
labels:
  - gamepad
  - pdf
dependencies:
  - TASK-30
priority: low
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Odłożone przez usera 2026-11-03. PDF nie zna akapitów; heurystyka z prostokątów linii: większy odstęp międzywierszowy, wcięcie pierwszej linii, krótka ostatnia linia, kolumny. Do tego czasu w PDF akapit = do ustalenia (np. zdanie albo blok z getTextBoxes).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Akapity rozpoznane na typowych PDF-ach (jedna i dwie kolumny)
- [ ] #2 LT/RT i ↑/↓ w zdaniach używają ich w PDF
<!-- AC:END -->
