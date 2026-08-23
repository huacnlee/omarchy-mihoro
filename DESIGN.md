# Design

What the panel looks like and why. `AGENTS.md` holds the working agreements
about the code; this holds the ones about the surface. Where a rule has a
reason, the reason is the rule — it is what tells you whether a new case is
covered.

## Icons

**One set, one grid, one weight.** `components/ActionIcon.qml` is the whole set:
Canvas paths on a 16-unit grid, `strokeScale: 1.4`, drawn by name. A new glyph
is a branch in it, never a new component. Two drawn-icon components are two
grids, and two grids in one row is exactly what a reader notices without being
able to say why.

- **Drawn, not rasterised.** These render at 12–16px, where Qt's SVG renderer
  smears strokes. The shell's own bar icons are Canvas paths for the same
  reason, and so is omamail's `ActionIcon`, which this follows — the shared
  glyphs are the same coordinates.
- **Drawn, not a text glyph.** A character covers whatever fraction of its em
  box the family chose. `×` is a multiplication sign: set at 12px it draws about
  6px of ink and reads as broken punctuation beside anything else. `✏` and 🗑
  are worse — they pick up a colour emoji presentation on most font stacks.
- **One size within a row.** The grid guarantees two glyphs at the same
  `iconSize` are optically equal; nothing guarantees it across sizes. Row
  actions are `Style.font.icon`. The size is a property of the context, not of
  the glyph.
- Sizes come from `Style.font.*` and box sizes from `Style.space()`, so a user
  who scales their font scales the icons with it.

`components/MihoroIcon.qml` is deliberately outside the set. It is the brand
mark — its own proportions, its own crossed/warning/ringed states — and putting
it on the action grid would claim it belongs to the same family as remove and
edit.

## Colour

- Every colour comes from the active Omarchy theme through `qs.Commons.Color`
  or a `Style.*FillFor` helper. No hex, no named display colours; a literal
  fallback grey is still a literal. `tests/test_panel_source.sh` enforces this.
- Derive muted, hover and selected variants from an inherited colour with
  `Qt.rgba`/`Qt.darker`/`Qt.lighter`, or from the kit's fill helpers.
- Reusable controls take the foreground and accent they should use as
  properties, so one theme change reaches every view.
- The semantics are fixed: `Color.accent` is download, connected, and the
  current selection; `Color.urgent` is upload, failure, and destruction.
- **Colour alone never carries state.** The selected subscription is a filled
  dot *and* a selected fill; some themes put the accent close to the foreground.

## Labels

- Suffix a button or menu label with `...` when activating it opens a dialog, an
  editor, a page, a browser, or a terminal workflow instead of completing the
  action there and then. "Add..." opens the editor; "Update" fetches.
- Prefer the shorter label when both are honest, and never buy brevity with
  accuracy.
- An icon-only action carries its label in `tooltipText`, and that label follows
  the same `...` rule.

## The panel's shape

Three pages in one popup: the status page, subscriptions, and installation.
Navigation between them is explicit — a named menu item or a back arrow, never a
collapsible section, and never an accidental click on something that shows a
credential.

- Every fresh open returns to page one with the editor closed. A popup that
  reopens where it was left is a popup that shows the wrong thing after the
  panel has been shut for a day.
- Page one is the whole state at a glance: what it is doing, what went wrong, or
  why the proxy is not connected, in **one** notice line. A failure may take up
  to three, and no more — past that the panel is more error than panel. The
  clamp is `maximumLineCount`, not a character count: it has to hold against the
  reader's font size and the panel's real width.
- **A message from outside is shortened before it is shown, never by the clamp.**
  mihoro quotes back the URL it was given and the body it could not parse, so
  the notice would otherwise render a bearer token and several kilobytes on one
  line. `Model.noticeMessage` redacts URLs to their host and collapses quoted
  payloads first; eliding first could stop halfway through a token and leave the
  front of it on screen.
- **What will not fit goes to an agent, on a button.** Three lines cannot hold
  why `mihoro update` failed, and the panel can neither read a journal nor fetch
  a URL to find out. `Diagnose...` writes the whole output to a `0600` file and
  points the user's default agent at it. It is offered only for a failed mihoro
  command — a rejected URL is the user's to fix — and only once
  `omarchy-default-agent` names one, because a button that opens nothing
  explains nothing. It never opens on its own: a failed update must not spawn a
  terminal nobody asked for. It carries the plain foreground, not `urgent`: the
  failure is the notice line above it, and the button is an offer.
- **A refused or failed action reports on the page it happened on.** A notice
  that only renders on page one turns a rejected subscription switch into the
  panel appearing to ignore the click. That was a real bug.

## Rows, the cursor, and the keyboard

- A navigable row is a `CursorSurface`. It must not read `containsMouse` for its
  own colour: mouse hover updates the panel's cursor state at the root, and the
  visuals derive from `hasCursor` / `current`. That is what keeps exactly one
  highlight on screen whichever input is driving.
- The panel keeps one flat list of targets rebuilt from service state, in screen
  order. A panel this shallow does not need per-section cursors.
- Right-edge action buttons are not cursor targets; the row they sit in is.
- Every action the mouse can reach has a key: the letter for the page's own
  actions, digits for a list.

## Credentials

A subscription URL is a bearer token — the whole of the authentication.

- It is never rendered outside the editor. Rows carry the name the user gave the
  subscription, which defaults to the URL's host.
- It never reaches a command line; it goes over stdin. Arguments are visible in
  the process list. This is why the diagnosis prompt carries paths rather than
  the failure output: `omarchy-agent --prompt` becomes argv.
- The store is written `0600` through a temporary file in the same directory and
  renamed into place. `mihoro.toml` is not ours, so that write keeps the
  permissions it finds.
- It does not go in `shell.json`: that file is world-readable, it is what people
  paste when they ask for help with their bar, and its writer rebuilds plugin
  entries from the manifest schema.

## Optimism and truth

- A control moves the instant it is clicked; the refresh that confirms it stops
  overriding once it lands. Waiting for systemd makes the panel feel broken.
- Optimism has a deadline. Every optimistic overlay is dropped after a timeout
  whether or not the truth arrived.
- Where the panel and the CLI could disagree, the file on disk wins and the
  running core wins over both — the panel never shows a state nothing has
  confirmed.

## Verification

Run `make validate` after any QML or behaviour change. `tests/test_panel_source.sh`
pins the decisions above at the source level, because Quickshell's `Process`,
`Panel` and the `qs.Ui` kit only exist inside a running shell. When a decision
here changes, change the test in the same commit — a rule with nothing holding
it is a rule that has already drifted.
