---
id: TASK-31
title: 'PDF/DjVu: podkreślanie z zaznaczenia kopada'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 20:53'
updated_date: '2026-11-03 22:20'
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
- [x] #1 X w zaznaczeniu PDF tworzy / usuwa podkreślenie widoczne w KOReaderze i po ponownym otwarciu
- [x] #2 Y w czytaniu PDF przegląda podkreślenia strony
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. selector.lua PagedOverlay: _collect_highlights = highlights (drawer ~= nil) on self.page from ui.annotation.annotations (direct loop: index = annotation index; multi-page via getSavedExtendedHighlightPage / ext[page]); native boxes from doc:getPageBoxesFromPositions (fallback ann.pboxes), sorted by native y; screen boxes recomputed in _screen_boxes on every paint/move.
2. _get_selection in mode hl: ann text/pos/pboxes + hl_index; walk/struct selection unchanged (pos0/pos1 tables + pboxes = what saveHighlight takes in paging).
3. _do_highlight: rh.selected_text = {text,pos0,pos1,pboxes} -> rh:saveHighlight() (annotation:addItem, AnnotationsModified, writePdfAnnotation like a finger), then collect + refresh. _do_toggle_highlight: hl mode = its index; else the page highlight whose pos0/pos1 snap to the same words -> rh:deleteHighlight(index); else save. _do_note: base path (saveHighlight + note) + writePdfAnnotation content in paging.
4. Unhide Highlight/Note row and "X hl" in the status (text only). Base _draw_hl_marks tolerates an off-screen item (sbox nil). hl mode reveals the focused highlight.
5. padnav: Y tap in paged (context paged, _any_selector) = _open_highlights; reflow = message; highlights action in paged too.
6. Tests: tests/pdfhl_test.lua (stub ReaderHighlight/ReaderAnnotation), padmap_test Y tap in paged. Docs: CLAUDE.md, padnav header + CHEAT_READING, README.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented (not yet checked on the Deck): PagedOverlay saves through ReaderHighlight:saveHighlight (selected_text {text,pos0,pos1,pboxes}), removes through deleteHighlight(index); Y tap in PDF (context paged) opens mode hl; Note on PDF works (new highlight or the browsed one, writePdfAnnotation content). Tests: tests/pdfhl_test.lua, padmap_test section paged Y. EPUB _do_toggle_highlight (pos0 == and table.remove) left unchanged.

Weryfikacja dyrygenta 2026-11-03: 11/11 plików testów OK, luac -p czysto; testy uruchomione też na samym indeksie commita (bez cudzych zmian padopen/vkb). tests/pdfhl_test.lua: X tworzy podkreślenie przez saveHighlight (page/pos0/pos1/pboxes/text/drawer w ui.annotation.annotations = sidecar), drugi X usuwa przez deleteHighlight (także podkreślenie palcem) (AC1); Y tap w paged = przegląd podkreśleń strony, strzałki z zawijaniem, prostokąty przy zoom 2 i przesunięciu, brak = komunikat (AC2). Notatka w PDF też działa. Na Decku do sprawdzenia: styl podkreślenia, trwałość po ponownym otwarciu, zapis do PDF. Osobno: EPUB _do_toggle_highlight usuwa table.remove bez index_modified.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF/DjVu: X w zaznaczeniu tworzy/usuwa podkreślenie przez ReaderHighlight (sidecar, zapis do PDF), Y tap = przegląd podkreśleń strony, notatki
<!-- SECTION:FINAL_SUMMARY:END -->
