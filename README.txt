CALC.R4X
========

CALC.R4X ist die gehostete Desktop-Rechner-App.

Projektstruktur seit 0.51.20:
- `build.zig` ruft seit 0.58.29 nur noch den generischen SDK-R4MF-Treiber.
- `build.zig.zon` bindet `r4os_sdk` als Paket.
- `module.R4MF` v2 beschreibt Sprache, Quelle, Klasse, Ziel, Scope und Imports.

Build:

    DevTools\Scripts\Build.bat -app CALC

Ergebnis:

    Code\zig-out\CALC.R4X

Contract:
- fachlicher Einstieg: `r4_app_main`; das SDK exportiert `R4XStart`
- App-Klasse: `gui`
- R4L-Imports: `R4SYS`, `R4DESK`, `R4DRAW`
- Zielpfad im Image: `C:\R4OS\SOFTWARE\DESKTOP\CALC.R4X`
- Window-/Message-/PaintContext-Fassade mit `desktopActivityWait` statt
  Drei-Tick-Polling
