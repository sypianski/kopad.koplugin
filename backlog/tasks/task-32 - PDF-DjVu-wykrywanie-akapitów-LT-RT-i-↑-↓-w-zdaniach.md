---
id: TASK-32
title: 'PDF/DjVu: wykrywanie akapitów (LT/RT i ↑/↓ w zdaniach)'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 20:53'
updated_date: '2026-11-03 22:23'
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
- [x] #1 Akapity rozpoznane na typowych PDF-ach (jedna i dwie kolumny)
- [x] #2 LT/RT i ↑/↓ w zdaniach używają ich w PDF
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Wpiąć pdfpara.lua w pdfwords.lua: words_from_boxes zwraca słowa w kolejności czytania (info.order) z polem para; sentences().para = akapit pierwszego słowa; PagedOverlay cache info per strona + rtl. Nawigacja _para_target/_ww_para bez zmian. Testy w pdfwords_test (1 i 2 kolumny), docs CLAUDE.md/README.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-03: testy OK na samym indeksie commita (bez cudzych zmian padopen/vkb). tests/pdfpara_test.lua (heurystyka: wcięcie, odstęp, krótka ostatnia linia, dwie kolumny, nagłówki) + tests/pdfwords_test.lua sekcja 3: jedna kolumna = 2 akapity, dwie kolumny = poprawna kolejność czytania i akapit przechodzący między kolumnami (AC1); ↑/↓ i LT/RT w zdaniach oraz LT/RT w słowach skaczą o akapit, także przez granicę kolumn (AC2). Słowa w PDF idą teraz w kolejności czytania pdfpara (↑/↓ w słowach przy dwóch kolumnach: lewa, potem prawa). Na Decku: książki bez wcięć z ciasną interlinią, artykuły dwukolumnowe, przypisy, listy, RTL.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF/DjVu: akapity z geometrii linii (pdfpara.lua: odstęp, wcięcie, krótka ostatnia linia, dwie kolumny) napędzają ↑/↓ i LT/RT
<!-- SECTION:FINAL_SUMMARY:END -->
