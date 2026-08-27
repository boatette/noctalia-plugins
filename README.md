# noctalia-plugins

Noctalia plugins, read straight from this directory by noctalia rather than
built into a system configuration.

| Plugin           | What it is                                                                 |
| ---------------- | -------------------------------------------------------------------------- |
| `auto-theme`     | Sets the global color scheme and light/dark mode from the wallpaper's directory. |

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
