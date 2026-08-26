# OSD master artwork (optional)

Drop edited 800×800 master PNGs here to override the programmatic label
redraw with hand-polished artwork. When `Base_Dark.png` or `Base_Light.png`
is present in this folder, the installer generates **every** size variant
(160×160 base and @125…@500) from that master by high-quality downscaling —
the same way the original scale set was produced.

## How to create masters

1. On a patched installation, dump the pristine themed originals:
   `state\<version>\original\res\Image\` holds the untouched Chinese files.
2. Take the **largest** variant of a family (e.g. `KeyboardLight5_Dark@500.png`,
   800×800) into Photoshop.
3. Replace only the Chinese label in the bottom band with the English label
   (keep the canvas size, transparency, label band and glyph untouched;
   Dark variants use white text, Light variants dark text).
4. Save as `Base_Dark.png` / `Base_Light.png` (e.g. `KeyboardLight5_Dark.png`)
   into this folder and re-run `INSTALL-ENGLISH.bat`.

Suggested labels: `Brightness 0–10`, `Auto`, `Mic on`, `Mic off`, `48–240Hz`,
`Quiet`, `Speed`, `Smart`, `Endurance`, `Beast`, `Balance`, `Silent`.

## Licensing note

These masters are derivative works of Xiaomi's artwork and remain Xiaomi's
property. Distributing edited masters in a public fork replicates Xiaomi
content — the default redraw pipeline exists precisely so the repository
ships no Xiaomi-derived files. Add masters here at your own discretion.
