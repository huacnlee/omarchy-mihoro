# Project working agreements

## The surface

`DESIGN.md` is the design standard — icons, colour, labels, the panel's shape,
and what may show a credential. Read it before touching a component, and change
it in the same commit as the behaviour it describes. It exists because those
rules were being re-derived per component, and a row ended up carrying two icons
drawn on two different grids.

The two that come up most:

- Colours come from `qs.Commons.Color` and the shared `Style` helpers. No
  hard-coded hex, RGB, or named display colours. Derive shades with `Qt.darker`,
  `Qt.lighter`, or `Qt.rgba` over a theme colour, and let reusable controls
  accept or inherit the relevant foreground/accent colours so they stay correct
  across themes.
- Suffix button and menu labels with `...` when activating them opens a dialog,
  editor, terminal workflow, or secondary page instead of completing the action
  immediately.

## Verification

- Run `make validate` after QML or behavior changes.
