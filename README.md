# noctalia-plugins

Noctalia plugins, read straight from this directory by noctalia rather than
built into a system configuration.

| Plugin           | What it is                                                                 |
| ---------------- | -------------------------------------------------------------------------- |
| `auto-theme`     | Sets the global color scheme and light/dark mode from the wallpaper's directory. |
| `binary-clock`   | A BCD binary clock, as a bar widget and a desktop widget.                  |
| `umbriel-layout` | Shows the focused workspace's Umbriel layout, and switches it on click.    |

Each has its own README.

## Using them

Register this directory as a plugin source, and noctalia picks up every
`*/plugin.toml` under it:

```toml
[[plugins.source]]
name = "Personal"
kind = "path"
location = "~/Projects/noctalia-plugins"
enabled = true
```

Then enable the ones you want by id (`boatette/auto-theme`, and so on).

Because it is a path source, editing a `.luau` here takes effect on the next
plugin reload. There is nothing to rebuild and nothing to push.

## catalog.toml

There isn't one, deliberately. Noctalia prefers `catalog.toml` when a path
source has one and only scans `*/plugin.toml` when it does not, so a checked-in
catalog that falls behind silently hides a plugin. Scanning cannot.

Publishing this repo as a **git** source does require a catalog, since noctalia
cannot list a remote's directories. Generate one then:

```
nix run .#catalog
```

It keeps the `added_at` / `updated_at` of plugins already listed, so the ordering
in the plugin browser stays put.

## umbriel-workspace-watch

`umbriel-layout` needs to know which workspace is focused, and Umbriel's IPC
cannot say: it reports workspaces only as opaque per-output serials attached to
windows, and emits no event on a switch. `umbriel-layout/watch/main.c` reads it
from `ext-workspace-v1` instead, the same protocol noctalia's own workspace
widget uses.

```
nix build .#umbriel-workspace-watch
nix run   .#umbriel-workspace-watch     # prints "<output> <workspace>" per change
```

The plugin looks for it on `PATH`; its `watch_command` setting overrides that.

To work on it, `nix run .#watch-dev` from `umbriel-layout/watch` writes the
wayland-scanner output and a `compile_flags.txt` so clangd can resolve
`<wayland-client.h>` and the generated protocol header. See that plugin's README.
