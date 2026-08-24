# omarchy-import

Browse the [omarchy](https://omarchythemes.com) theme catalog from a panel, and import a theme as a noctalia palette, a wallpaper folder and a Neovim colorscheme, all under one name.

A bar button opens the browser. The list is every repository the GitHub search turns up that actually carries a palette; an imported theme is ticked, an official one starred. Selecting a theme shows its mode, its surface and primary colours, its sixteen ANSI colours, the three palettes already installed that it sits closest to, one of its wallpapers, and a sentence saying whether importing it would join one of those palettes or register a new one.

Install opens the same three questions the import itself asks — which palette, what Neovim should follow, and whether to take the wallpapers — and then reports each step as it runs. Remove shows the exact list of files, folders and pinned plugins that would go, and asks before taking them.

## The helper

The panel is a view. Everything it knows comes from `omarchy-import`, a Python program packaged by this repo's flake, which speaks one JSON object per line and never asks a question:

```
omarchy-import catalog [--refresh]
omarchy-import previews
omarchy-import preview <source> [--refresh]
omarchy-import import <source> --new|--reuse <palette> [--nvim auto|palette|plugin] [--apply]
omarchy-import remove <name> --dry-run|--yes
omarchy-import list | match <source> | sync
```

```
nix build .#omarchy-import
nix run   .#omarchy-import -- catalog
```

The plugin looks for it on `PATH`; the `helper_command` setting overrides that.

An import takes anywhere from five seconds to a minute — a fetch, then ImageMagick, then a poll of noctalia's own scheme — so it streams which of its six steps it is on rather than going silent, and the panel draws that. Commands with only one thing to say emit a single line, which is still valid NDJSON.

Judgements that both sides would otherwise have to make are made once, in the helper. Whether an import should join an existing palette or register a new one is decided next to the ranking that informs it and arrives as `would`; the panel starts its install form there rather than reimplementing the threshold. `normalise()` is likewise never rewritten in Luau — a catalog row already carries its `slug` and whether it is `imported`.

## Why the panel does not need a dwell timer

The terminal browser this replaces fetched a theme's palette when the cursor arrived on it, which meant leaning on `j` downloaded every theme it swept past; it held fetches behind a quarter-second of stillness to stop that.

Here `previews` hands over every preview already on disk in one call at open, so only a theme nobody has ever looked at costs a round trip, and a click selects exactly one theme. A single in-flight guard is the whole of what remains.

## What an import writes

|                                                       |                                            |
| ----------------------------------------------------- | ------------------------------------------ |
| `~/Pictures/Wallpapers/<Mode>/<Name>/`                | the theme's backgrounds                    |
| `~/.local/share/omarchy-import/palettes/`             | the palette, kept here                     |
| `~/.config/noctalia/palettes/`                        | a copy, the only place noctalia reads      |
| `~/nix/modules/programs/nvim/omarchy/`                | the Neovim registry and any plugin it pins |

The palette and the wallpapers take effect immediately. Only Neovim needs a rebuild, and only when the theme brings its own colorscheme plugin, because nixvim cannot reach one that was not built in — the panel says so, and hands over the command.

The last two paths are the `nix_repo` and `wallpaper_root` settings. They are passed to the helper explicitly rather than inherited, because the helper runs in noctalia's process environment rather than a login shell and would otherwise quietly use its own defaults.

## Applying a theme

Importing with wallpapers applies the theme by setting the first of them, and **Set wallpaper** does the same afterwards. That is how a theme is applied here: [`auto-theme`](../auto-theme) reads the palette back out of the wallpaper's folder, so whichever palette it settles on is the one that sticks.
