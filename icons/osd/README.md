# OSD master artwork

Hand-polished 800×800 English masters. When `Base_Dark.png` or
`Base_Light.png` is present here, the installer generates **every** size
variant (160×160 base and @125…@500) from that master by high-quality
downscaling instead of the programmatic label redraw. Families without a
master keep the redraw, so masters can be added incrementally.

Photoshop working files for these masters live in `icons/sources/`.
To produce a new master: take the largest pristine variant from
`state\<version>\original\res\Image\` (e.g. `KeyboardLight5_Dark@500.png`,
800×800), replace only the Chinese label in the bottom band (Dark variants
use white text, Light variants dark text; keep canvas size, transparency,
label band and glyph), and save as `Base_Dark.png` / `Base_Light.png` here.

Suggested labels: `Brightness 0–10`, `Auto`, `Mic on`, `Mic off`, `48–240Hz`,
`Quiet`, `Speed`, `Smart`, `Endurance`, `Beast`, `Balance`, `Silent`.

## Licensing note

These masters are derivative works of Xiaomi's artwork and remain Xiaomi's
property. The default redraw pipeline exists so the repository can work
without shipping Xiaomi-derived files; this folder opts into distributing
them.
