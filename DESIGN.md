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
  Node delays are the one place theme green and yellow appear (through
  `SystemTheme`): fast and slow. The milliseconds or `timeout` are always
  printed beside the colour, so the value never rides on the colour alone.
- **Colour alone never carries state.** The selected subscription is a filled
  dot *and* a selected fill; some themes put the accent close to the foreground.

## Labels

- Suffix a button or menu label with `...` when activating it opens a dialog, an
  editor, a page, a browser, or a terminal workflow instead of completing the
  action there and then. "Add..." opens the editor; "Update" fetches.
- Prefer the shorter label when both are honest, and never buy brevity with
  accuracy.
- `Cancel` is always an outline button, so the way out remains visible without
  competing with the action it cancels.
- An icon-only action carries its label in `tooltipText`, and that label follows
  the same `...` rule.

## The panel's shape

Five pages in one popup: the status page, subscriptions, installation, local
subscription rules, and a route test.
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
- **Collapsing is not navigation.** A page is always reached by name; a section
  inside one may still fold behind an icon. PROXY NODES ships folded into the
  icon beside the mode chips: a subscription's groups run three lines each and
  would push the connection stats off the bottom of the panel for everyone who
  never changes a node. A folded section leaves nothing on screen, header
  included. What a fold hides is a detour, never state the page is accountable
  for — the node actually carrying traffic stays on the connection row either
  way.
- **A state change does not sit inside a read-only block.** The connection stats
  are there to be read, so TUN reports its state there and is switched from the
  panel menu, where the other actions are. A toggle in that column put a change
  to the running core one stray click from a block nobody expects to be
  clickable.
- **A node switch is staged until `Apply`,** like a local rule and like the mode
  row's own proxy. A picker that switched on selection would fire a PUT at
  whatever its search filter happened to land on while the user was still
  typing.
- **A refused or failed action reports on the page it happened on.** A notice
  that only renders on page one turns a rejected subscription switch into the
  panel appearing to ignore the click. That was a real bug.
- **The route test reports the running core's actual outbound.** Opening it
  makes short requests to Google, X, GitHub, Claude, ChatGPT, xAI, Douyin,
  Wechat, and Taobao, then
  reads each request's first mihomo connection chain entry. That is the node
  (or `DIRECT`) which carried the traffic; selector group names are not shown
  as if they were an outbound. Overseas and mainland sites are separated so
  the routing policy is scannable at a glance.
- **Local rules enhance a subscription; they do not replace it.** Each saved
  subscription owns an ordered list of structured DOMAIN, DOMAIN-SUFFIX,
  DOMAIN-KEYWORD, and GEOSITE rules. The list order is the match priority and
  its routes are built-ins or proxy groups from the active config, never a
  node name that an update can remove. Editing is staged until `Apply`.
- **An enhanced update has no unruled window.** The plugin downloads into a
  candidate, preserves mihoro's current local overrides, prepends the active
  subscription's rules, asks the installed mihomo core to validate it, and
  only then atomically replaces `config.yaml` and restarts once. Enabling local
  rules moves config updates from mihoro's cron entry to the plugin's user
  timer; unrelated cron entries are retained. Failure leaves the running file
  untouched.

## Rows, the cursor, and the keyboard

- **The bar icon has one mouse action.** Left-click opens the panel; middle- and
  right-click do nothing. Service state changes belong inside the panel, where
  their consequence is visible and an incidental bar click cannot trigger one.

- A navigable row is a `CursorSurface`. It must not read `containsMouse` for its
  own colour: mouse hover updates the panel's cursor state at the root, and the
  visuals derive from `hasCursor` / `current`. That is what keeps exactly one
  highlight on screen whichever input is driving.
- The panel keeps one flat list of targets rebuilt from service state, in screen
  order. A panel this shallow does not need per-section cursors. Node groups are
  `node:<group>` targets in that list, so the cursor walks power, modes, nodes,
  and the subscription in the order they are drawn.
- A folded section contributes no targets at all — not the rows it hides, which
  would walk the cursor through things nobody can see, and not its own
  disclosure, which is a right-edge icon and therefore never a target. `n` opens
  the proxy nodes and lands the cursor on the first group.
- Right-edge action buttons are not cursor targets; the row they sit in is.
- Every action the mouse can reach has a key: the letter for the page's own
  actions, digits for a list.
- An open node picker owns the keys — its search filter accepts every letter the
  panel binds — so the key catcher yields to it as it does to the URL editor.
- `d` tests the delays of the group under the cursor, and `u` toggles TUN, whose
  mouse path is the menu row rather than a control on the page. A pick made while
  a switch is in flight is queued (latest wins), never dropped.
  Enter on a group confirms a drafted pick, or opens the picker when there is
  none, so the keyboard reaches Apply without a key of its own.
- The poll watchdog reaps polls only. Its fuse is tied to the refresh that armed
  it, so reaping an action from it could kill a healthy delay test mid-flight;
  actions bound themselves with curl's `--max-time` instead.

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
- It lives in mihoro's own directory, hardcoded beside the config file mihoro
  itself hardcodes. The two describe one thing between them — the file mihoro
  reads names the subscription in effect, this one names the rest — and a path
  that can be configured is a path that can disagree.
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
- The connection facts name the selectable node on its own `Proxy` label/value
  row. In Rule mode that means the live `PROXY` selector; in Global mode it
  means `GLOBAL`; Direct has no selector and says `DIRECT`. Editing expands the
  row into a searchable picker, but choosing only stages a value: `Apply`
  changes the running core and `Cancel` leaves it alone. Success returns to the
  label/value row; failure leaves the editor open so the choice can be retried.

## Verification

Run `make validate` after any QML or behaviour change. `tests/test_panel_source.sh`
pins the decisions above at the source level, because Quickshell's `Process`,
`Panel` and the `qs.Ui` kit only exist inside a running shell. When a decision
here changes, change the test in the same commit — a rule with nothing holding
it is a rule that has already drifted.
