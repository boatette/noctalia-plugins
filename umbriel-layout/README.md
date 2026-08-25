# Umbriel Layout

A noctalia bar widget that shows which layout Umbriel is tiling with and switches between them on click.

## Plugin

Manifest id `boatette/umbriel-layout`. One entry:

| Entry | Kind       | Notes                                                  |
| ----- | ---------- | ------------------------------------------------------ |
| `bar` | bar widget | Icon, letter, or word. Left click switches the layout. |

Add it to a bar as `boatette/umbriel-layout:bar`.

## Display

`display_mode` picks what is drawn: `icon`, `letter` (`S`/`D`), `word` (`Scrolling`/`Dwindle`), `icon_letter`, or `icon_word`.

The default icons are the Tabler glyphs `carousel-horizontal` (a pane with partial panes either side, the scrolling strip) and `chart-treemap` (one large pane with a recursively subdivided remainder, which is what dwindle does).

A glyph setting holding a non-ASCII character is drawn as text in the bar's own font instead, so a Nerd Font codepoint such as `󱒎` (`md-view_quilt_outline`, U+F148E) works too, as long as the bar font has it. Anything else is taken as a Tabler name and drawn from noctalia's own icon font.

Words and letters are settings as well: an empty word uses the translated name, an empty letter is the first character of the word.

## Switching

Left click switches the focused workspace to the other layout, via `umbriel msg workspace-set-layout:<mode>`. The widget sends an explicit mode rather than umbriel's `toggle` so that it always knows what the result was, for the reason below.

## How the layout is determined

Umbriel's IPC cannot answer either question this widget needs. Its commands are `windows`, `layers`, `keyboard-layouts`, and `msg`: none report a workspace's layout, none report which workspace is focused, there is no layout-changed event, and no event at all fires on a workspace switch. Windows carry only an opaque per-output workspace serial (`eDP-1:50`), so an empty workspace is invisible to it.

So the layout shown is resolved, in order:

1. A layout this widget applied to that workspace during the session.
2. A matching `[[workspace]]` rule in umbriel's config, honouring its documented precedence: base `[layout]`, then a rule with no `output`, then a rule for that output.
3. The base `[layout] mode`.

Which workspace is active on each output comes from `umbriel-workspace-watch`, a small ext-workspace-v1 client whose source sits in this plugin's own `watch/` folder and which this repo's flake builds as `.#umbriel-workspace-watch`. That protocol carries the workspace's human-readable name and its active bit, and is the same source noctalia's own workspace widget reads, so the widget follows every switch regardless of what caused it: keybind, wheel, overview, or clicking the bar. The helper is run through `noctalia.runStream` inside a restart loop, so it recovers if it starts before the compositor or the compositor restarts under it.

A bar draws the workspace active on the monitor it sits on, so on several monitors each bar answers for its own. A switch is a different question: umbriel applies `workspace-set-layout` to the workspace it has focused, so that is the one a click or an ipc event reads and records against, and only the bar on that monitor changes.

`barWidget.outputName()` and `noctalia.focusedOutputName()` answer only while the host is calling into the widget; from an async callback both return `nil`. Both are therefore read in the entry points — script load, `onClick`, `onIpc`, `onConfigChanged` — and cached for the callbacks that follow. `apply` likewise captures its target workspace before spawning umbriel rather than in the callback, since focus can move while umbriel answers.

The helper is looked up on `PATH`; set `watch_command` to point at a different binary, or at any command of your own that prints `<output> <workspace>` per change. It takes effect on reload.

## Keeping the keybind in sync

Point umbriel's layout keybind at the widget rather than at the compositor, so a keyboard switch is recorded rather than happening behind its back:

```toml
"Mod+Shift+T" = "spawn:noctalia msg plugin boatette/umbriel-layout:bar all toggle"
```

Three events are accepted:

| Event    | Payload               | Effect                                                     |
| -------- | --------------------- | ---------------------------------------------------------- |
| `toggle` |                       | Switch the focused workspace to the other layout.          |
| `set`    | `scrolling`/`dwindle` | Switch the focused workspace to that layout.               |
| `sync`   | `scrolling`/`dwindle` | Record that layout for the focused workspace, without calling umbriel. |

`sync` is the escape hatch for anything that changes the layout on its own: have it tell the widget afterwards.

Recorded layouts are shared through `noctalia.state`, so bars on several monitors always agree.

## Working on the helper

`watch/main.c` includes `<wayland-client.h>`, which lives in the store, and `<ext-workspace-v1-client-protocol.h>`, which wayland-scanner generates at build time and so does not exist in the tree. clangd resolves neither on its own, and reports the whole file as broken. Write both, and the flags that find them, with:

```
cd umbriel-layout/watch
nix run .#watch-dev
```

That leaves `ext-workspace-v1-client-protocol.h`, `ext-workspace-v1-protocol.c`, and `compile_flags.txt` in the directory, all gitignored. Restart the language server afterwards. The flake build generates its own copies and only ever reads `main.c`, so these are for the editor alone and can be deleted at any time.

`.clang-tidy` turns off one check: it asks for the C11 Annex K `_s` functions, which are optional and which glibc does not implement, so every hit is unactionable.

## Known limits

- **Layouts changed behind the widget's back are not seen.** Anything that calls `workspace-set-layout` without going through the widget (a keybind still pointed at umbriel, a script) leaves the icon showing what the config says. Route it through `toggle`/`set`, or tell the widget with `sync`.
- **Recorded layouts last for the session.** `noctalia.state` is in-memory, so after a noctalia restart every workspace falls back to what the config says. Umbriel keeps its actual layouts across that restart, so a workspace you had switched shows the config's answer until you switch it again.
