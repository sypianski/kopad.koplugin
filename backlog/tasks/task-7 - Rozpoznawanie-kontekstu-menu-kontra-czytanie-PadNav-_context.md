---
id: TASK-7
title: 'Rozpoznawanie kontekstu: menu kontra czytanie (PadNav:_context)'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 17:14'
updated_date: '2026-11-03 17:24'
labels:
  - gamepad
  - bug
dependencies: []
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Przegląd 2026-11-03: Pluginaro.is_modal_active patrzy tylko na klasę okna na szczycie stosu, a menu górne (ReaderMenu/FileManagerMenu), spis treści i zakładki są owinięte w CenterContainer, ConfigDialog nie jest na liście. Skutek: przy otwartym menu kopad steruje książką pod spodem (EPUB: A/Y/gałki otwierają selektor, L-gałka przewraca stronę, Select otwiera drugie menu; PDF: D-pad/gałki przesuwają/zoomują stronę; TOC: LB/RT przewracają stronę książki; nadpisania PC-014 działają w menu). Naprawa: jedna pozytywna klasyfikacja wg najwyższego nie-tostowego okna: reading / paged / filemanager (okno == self.ui), selection (nakładka kopada), dict, top_menu (TouchMenu w oknie), window (cokolwiek innego). Sterowanie czytania tylko w reading/paged; nieznane okno = przepuszczenie.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Przy otwartym menu górnym (czytnik i FileManager) D-pad, L-gałka, A i B trafiają do menu (kopad zwraca false), LB/RB = kategorie, LT/RT = strony menu, Select zamyka menu, X/Y/Start/R-gałka nie ruszają dokumentu
- [x] #2 Przy otwartym spisie treści / zakładkach / ConfigDialog / innym oknie kopad nie steruje dokumentem; LT/RT przewijają stronę listy, gdy okno ma onNextPage/onPrevPage
- [x] #3 Nadpisania akcji ról (PC-014) i sterowanie PDF działają tylko w kontekście reading/paged
- [x] #4 Test w tests/ z układem CenterContainer{TouchMenu} i CenterContainer{Menu} dla EPUB i PDF; lua tests/*.lua przechodzi
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PadNav:_context() klasyfikuje najwyższe nie-tostowe okno (off/foreign/reading/paged/filemanager/selection/dict/top_menu/window). _is_enabled i _paged_idle korzystają z kontekstu; _button_down/_trigger_event oddają menu i inne okna KOReaderowi (_menu_button: LB/RB kategorie, Select zamyka, Start przepuszczony bo stockowe 'Menu' zamyka TouchMenu; _menu_trigger: LT/RT strona menu albo listy w oknie). Przy okazji: DictQuickLookup nie ma pola name w żadnej wersji KOReadera -> rozpoznanie przez DictQuickLookup.window_list (is_dict_window); _find_dict_widget i hook w selector.lua poprawia TASK-8. Test 11 w tests/padmap_test.lua (CenterContainer{TouchMenu}, CenterContainer{Menu}, EPUB/PDF/FM). Niezweryfikowane na urządzeniu.
<!-- SECTION:NOTES:END -->
