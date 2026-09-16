# chicago/events — Event Viewer

Event Viewer for the Chicago desktop in the terminal
([chicago/shell](https://github.com/chicago-desktop/shell)): Start →
Settings → **Event Viewer**. It shows the platform's logs — the threads of
kickside/core, grouped by thread class — and the events of the chosen log,
newest first, in the manner of the classic Event Viewer. It writes nothing.

- **The log tree** on the left: a folder per thread class, a log per thread
  under it, named by its component's title. It lists only the threads whose
  component the logged-on person may read, the same ones the web UI shows
  them.
- **The events table**: the local time, the source (the module that wrote
  the event), the type and a one-line message. The log is read a page of 100
  at a time; the next page loads when the wheel or the keys push past the
  last loaded row.
- **Type** asks the platform for one type of event; **Find** filters the
  loaded events by text in any column; **Clear filter** drops both.
- **The event's properties** (double-click or Enter) open in a window of
  their own, **Event Properties** — one window per event: a second
  double-click on the same event raises the window already open. It shows
  the date, source, type, role, log, sequence and id, the trace, run, cause
  and correlation when the event carries them, and the payload as JSON with
  sorted keys; F5 reads the event again, Esc or Close closes it. The window
  is told only which event (`{thread_id, seq, log}`) and reads it itself, so
  a payload of any size never travels through a window argument.
- **Refresh** or F5 reads the logs again. A refusal is named in the status
  bar by its kind ("permission denied", "not found"), never shown as an empty
  log.

## What it needs from the application

- **No requirements.** The module declares no `ns.requirement`; the
  dependency entry takes no `parameters`:

  ```yaml
  - version: '>=0.2.0'
    name: events
    kind: ns.dependency
    meta: {}
    component: github.com/chicago-desktop/events
  ```

- **The platform.** `kickside/core` from v0.1.98, from the Hub — the
  windows import its `kickside.core.threads:contract` and call `list` and
  `list_events` (the event window bounds it to one sequence number with
  `from_seq` and `to_seq`). An application of the platform has it already and binds its
  requirements as usual.
- **The logged-on person's group.** The shell spawns the window under the
  actor of the person who logged on ("Log On to Windows"), and the contract
  checks that actor: the person's group must carry what the web UI uses to
  read threads (in the Chicago application, `app.security:user` does). The
  window's own policy, `chicago.events:window_scope`, only talks to the
  compositor (`process.context`, `process.registry`, `process.send`). Under
  the shell's service actor (a shell without logon) the window names the
  refusal in its status bar.

Its picture is the module's own pixel art, `chicago.events:images/event_viewer`
— a log sheet with an error, a warning and an information mark, an image pack
of the shell under `assets/images` (32 and 16 px), drawn by
`tools/event_icons.py` (see `assets/images/SOURCE.md`).

## Inside

- `chicago.events:window` — the window, an application on the shell's SDK
  (`chicago.shell.sdk:app`): the tree, the table, the select, the input and
  the status bar are the SDK's components, the same in cells and in pixels.
  The IO lives here, and so does opening an event's window (it asks the
  compositor what is open first, through the base's window API).
- `chicago.events:event` — the Event Properties window, one per event, not in
  the Start menu.
- `chicago.events:model` — the pure translation between the contract's
  thread and event rows and the window (the log tree, the table rows, the
  message line, the page request, the properties, the payload); times and
  refusals are worded by `chicago.shell.sdk:format`.
- `chicago.events:window_scope` — the window's policy, for the compositor.
- `chicago.events:images` — the image pack.

### Moving from the application's `src/app/events`

Event Viewer lived in the Chicago application's `src/app/events` (namespace
`app.events`) before this module. The entries kept their names in the new
namespace (`app.events:window` → `chicago.events:window`, the same for
`model` and `window_scope`), and the application's `app.common:format` gave
way to the shell's `chicago.shell.sdk:format` (chicago/shell v0.2.4) — the
same functions. There is no data to move: the window reads the platform's
tables and keeps nothing of its own.

## Developing

```bash
make setup     # resolve the dependencies (once, and after changing them)
make check     # the repository's invariants
make lint      # late locals, then wippy lint of this namespace and the harness
make test      # the harness in test/
```

The suites: `model_test` (log labels and the class tree, the type split and
the message line, paging newest first, the text and type filters, the
payload and the properties) and `window_test` (the entry, the picture, the
policy, and the window's definition over the stand-in contract — the first
page, paging on `end`, the type filter, an event opened in its own window
or raised when it is already open, the event window reading one event by
its sequence and saying why when there is none, and a refused log in the
status bar).

`make test` does not boot the platform: `test/stubs/core` stands in for
kickside/core with only the library Event Viewer imports — three threads in
two classes, 130 events in the first, a thread whose events are refused —
written from the contract's behaviour, not copied from its sources. It is
bound through `workspace.replacements` in `test/.wippy.yaml`, and `make
setup` records it in `test/wippy.lock` at the module's lower bound, without a
hash. `make lint` checks from the harness, so the boundary with the platform
is typed against the stand-in.

**A build of the runtime fork from its releases is required**
([chicago-desktop/runtime](https://github.com/chicago-desktop/runtime),
`v0.3.40a-chicago.2` or newer): it resolves the shell and the base from
GitHub by tag, and the shell declares the `gfx` module, which the release
runtime does not have — `wippy` from PATH does not load the shell at all.
The Makefile's `WIPPY` names the build; override it with `make test WIPPY=…`.

The window SDK is documented in [docs/sdk.md](docs/sdk.md), a copy of the
shell's guide, and the skill for agents in
[skills/wippy-window-app/SKILL.md](skills/wippy-window-app/SKILL.md); the
rules of this repository are in [AGENTS.md](AGENTS.md).

Made from [the Chicago module template](https://github.com/chicago-desktop/module-template) for
modules of the Chicago shell. Repository:
https://github.com/chicago-desktop/events.

## Licence

MIT.
