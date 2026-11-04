---
id: TASK-44
title: 'Wskaż od-do: D-pad ↑↓ = linia, zdania tylko zaraz po etykiecie (PC-025)'
status: Done
assignee: []
created_date: '2026-11-04 09:18'
updated_date: '2026-11-04 09:27'
labels: []
dependencies: []
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Zmienia TASK-42/TASK-43 (PC-025 zastępuje PC-024). W trybie słów: D-pad ←→ słowo, ↑↓ linia (przywrócony w TASK-43 _ww_line), lewa gałka znów tak samo jak D-pad; RT trzymany (i A trzymany) = zaznaczanie o słowo / linię. Bez skoków o zdanie w trybie słów. Faza po etykiecie: dopóki kursor stoi na początku zdania z etykiety i nie było innego ruchu, RT+↓ = całe zdanie (kotwica = początek), kolejne RT+↓ = do końca następnego, RT+↑ = zdejmuje zdanie (ostatnie -> brak zakresu, faza trwa). Pierwszy inny ruch (D-pad bez RT, RT+←/→, gałka) kończy fazę; od tej chwili RT+↑↓ = o linię. Zmiana zdania = B (bez zakresu -> etykiety) i nowa etykieta.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tryb słów: D-pad i lewa gałka ←→ słowo, ↑↓ linia (EPUB, PDF, przez krawędź strony bez zakresu); RT/A trzymany + ↑↓ = zakres o linię; brak skoków o zdanie
- [x] #2 Faza po etykiecie: RT+↓ całe zdanie, kolejne RT+↓ następne, RT+↑ zdejmuje; pierwszy inny ruch kończy fazę; zakres zdaniowy można dalej korygować RT+←/→
- [x] #3 Testy zielone; CLAUDE.md, README, nagłówek padnav.lua, main.lua, linia statusu (faza widoczna) zaktualizowane
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Weryfikacja dyrygenta 2026-11-04: 12 testów zielonych, luac czysto; przejrzane line()/step()/_ww_phase_range. Wybory: w fazie nagłówek statusu START także przy zakresie; B kasujące zakres kończy fazę; RT↑ bez zakresu nic nie robi; trzymane RT+↓ powtarza (zdanie na powtórzenie).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
D-pad i gałka ↑↓ = linia; zdania RT+↓/↑ tylko zaraz po etykiecie (PC-025)
<!-- SECTION:FINAL_SUMMARY:END -->
