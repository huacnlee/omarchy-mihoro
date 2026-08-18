# Project working agreements

## UI colors

- Use Omarchy system/theme colors from `qs.Commons.Color` and shared `Style` helpers.
- Do not hard-code hex, RGB, or named display colors in QML components.
- Derived shades may use `Qt.darker`, `Qt.lighter`, or `Qt.rgba` with a system color as their source.
- Reusable controls must accept or inherit the relevant foreground/accent colors so they remain correct across themes.

## UI labels

- Suffix button and menu labels with `...` when activating them opens a dialog,
  editor, terminal workflow, or secondary page instead of completing the action immediately.

## Verification

- Run `make validate` after QML or behavior changes.
