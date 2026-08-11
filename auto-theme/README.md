# Auto Theme

Sets the global noctalia color scheme and light/dark mode from the directory the
wallpaper lives in. Pick a wallpaper, and the theme follows.

Replaces the directory-mapping half of the old `.local/bin/theme-switcher` from the
Hyprland/Quickshell setup.

## Install

```sh
noctalia msg plugins source add local path ~/dotfiles/.config/noctalia/plugins
noctalia msg plugins enable boatette/auto-theme
```

Then add the hooks below and `noctalia msg config-reload`.

## Hooks (required)

The plugin is purely event-driven — without these it never runs. Add to
`~/.local/state/noctalia/settings.toml`:

```toml
[hooks]
wallpaper_changed  = ["noctalia msg plugin boatette/auto-theme:auto-theme all wallpaper-changed \"$NOCTALIA_WALLPAPER_PATH\""]
colors_changed     = ["noctalia msg plugin boatette/auto-theme:auto-theme all colors-changed"]
theme_mode_changed = ["noctalia msg plugin boatette/auto-theme:auto-theme all theme-mode-changed"]
```

Hook commands run through `/bin/sh`, so `$NOCTALIA_WALLPAPER_PATH` expands.
The target is `all` — a headless service entry has no output surface, so `focused`
is rejected.

`colors_changed` and `theme_mode_changed` are only needed for the per-wallpaper
scheme memory described below; drop them if you don't want it.

## Layout rules

Paths are read relative to **Wallpaper Root**. Anything outside it is ignored.

The **mode folder** (`Dark` / `Light`) is looked for anywhere in the path, and the
**theme folder** is the segment just below it — falling back to the segment just
above. Both of these work, so an existing tree never has to be reorganised:

```
<root>/Dark/Catppuccin/x.png        <root>/Catppuccin/Dark/x.png
```

| Path | Mode | Palette |
|---|---|---|
| `Dark/Catppuccin/x.png` | dark | `builtin Catppuccin` |
| `Light/Nord/x.png` | light | `builtin Nord` |
| `Dark/Rose-Pine/x.png` | dark | `builtin Rosé Pine` |
| `Dark/Everforest/x.png` | dark | `community Everforest` |
| `Dark/Dynamic/x.png` | dark | `wallpaper <scheme>` |
| `Light/Dynamic/x.png` | light | `wallpaper <scheme>` |
| `Dynamic/x.png` | from image luma | `wallpaper <scheme>` |
| `Dark/x.png` | dark | unchanged (no theme folder named) |

### Name matching

Folder names are folded before comparison: lowercased, diacritics stripped,
punctuation removed. So `Rose-Pine` matches the builtin `Rosé Pine`, and
`Tokyo-Night` matches `Tokyo-Night`, with no configuration.

Resolution order is **alias → builtin → community → custom**. Builtins are
`Ayu, Catppuccin, Dracula, Gruvbox, Rosé Pine, Tokyo-Night, Eldritch, Kanagawa, Nord`;
community palettes are whatever is in `~/.local/state/noctalia/community-palettes/`.

A folder that matches nothing produces a notification and leaves the color scheme
untouched — the mode is still applied. `Dark/Rose-Pine-Moon` behaves this way until
that community palette is downloaded.

Use the **Folder Aliases** setting to override:

```
Rose-Pine-Moon = community:Rosé Pine Moon
Mono           = builtin:Nord
Screenshots    = skip:
```

Valid prefixes: `builtin:`, `community:`, `custom:`, `wallpaper:`, `skip:`.
A value with no prefix is re-resolved in the normal order.

## Dynamic wallpapers

Wallpapers under a `Dynamic` folder generate their palette from the image
(`color-scheme-set wallpaper <scheme>`) rather than using a named one.

**Scheme** — the remembered scheme for that exact wallpaper, else *Default Dynamic
Scheme*. When *Remember Scheme Per Wallpaper* is on, changing the generator in
noctalia's settings while a dynamic wallpaper is active records it against that
wallpaper, and returning to it later restores it. Stored in `dynamic.json` in the
plugin's data directory.

**Mode**, in precedence order:

1. the path's mode folder — `Dark/Dynamic/…`, `Light/Dynamic/…`
2. a remembered mode for that wallpaper
3. perceptual lightness vs *Luma Threshold* (default 45), via
   `magick <img> -colorspace LAB -channel R -separate -resize 1x1! -format '%[fx:mean]' info:`

Step 3 only matters for a `Dynamic` folder with no `Dark`/`Light` parent, such as
the Wallhaven download directory. Without ImageMagick the mode is left unchanged.

Use **CIELAB L\***, not `-colorspace Gray`. IM7's Gray is linear-light, which does
not just shift the scale — it reorders images. A dark space photo measured `0.557`
under Gray while its true L\* was `0.114`, so it was classified light. The 45
default was calibrated against the `Dark/` and `Light/` trees: darks measured
0.21–0.51, lights 0.46–0.92, and 45 misfiles 1 of 16 where 55 misfiles 3.

## Notes

- Applies are idempotent: if the target theme is already active, no `noctalia msg`
  command is issued at all.
- `wallpaper_changed` fires **once per output**, so a multi-monitor setup delivers
  the same path several times a few ms apart. Repeats within 1.5s are collapsed —
  without that, each copy reads `settings.toml` before the first write lands and
  redoes the work (including re-running `magick`).
- `colors_changed` is delivered roughly **2.6s after** the palette actually changes.
  The plugin ignores colors/mode events for 4s after its own writes so it never
  records the intermediate state of its own two-step apply as a user choice, and
  it re-reads `[wallpaper.last]` at learn time rather than trusting an in-memory
  "current wallpaper" that a racing switch could have already replaced.
- Leave `[wallpaper].directory_dark` / `directory_light` unset. Scoping the
  browsable pool by mode prevents reaching the other tree, which defeats the point.

## Foot live reload

`../scripts/foot-live-theme` is wired into the same `colors_changed` hook:

```toml
colors_changed = [
  "noctalia msg plugin boatette/auto-theme:auto-theme all colors-changed",
  "/home/boatette/dotfiles/.config/noctalia/scripts/foot-live-theme",
]
```

foot **never re-reads its config**. Its only signals are SIGUSR1/SIGUSR2, which
switch between the `[colors-dark]` and `[colors-light]` sections parsed at
startup — verified with `strace`: neither signal produces an `openat` on
`foot.ini` or the theme file. noctalia's builtin foot template regenerates
`~/.config/foot/themes/noctalia` and its `apply.sh` only ensures the `include=`
line exists, so without this script a palette change reaches new windows only.

The script re-reads the generated theme and pushes it to every running foot as
OSC escapes (`4;0`–`4;15`, `10`/`11`/`12` for fg/bg/cursor, `17`/`19` for
selection), writing to the pty of each foot's child — the direction foot renders.
Verified: the hook fires after the template is written, and both palette changes
and mode-only toggles reach all live terminals.

Note the generated file always uses the `[colors-dark]` header, whichever mode is
active, because foot's `initial-color-theme` defaults to `dark`. That is
noctalia's design, not a bug — and `alpha`/`blur` from your own `[colors-dark]`
block still merge with it.

## Development

The `path` source is read in place — noctalia watches the `.luau` file in this repo
and hot-reloads on save, so there is no copy step. Check syntax and settings wiring
with:

```sh
cd ~/dotfiles/.config/noctalia/plugins && noctalia plugins lint auto-theme
```

Runtime output goes to `~/.cache/noctalia/noctalia.log`:

```sh
grep auto-theme ~/.cache/noctalia/noctalia.log | tail
```

Trigger the engine by hand without changing the wallpaper (the file need not exist
for named-theme folders):

```sh
noctalia msg plugin boatette/auto-theme:auto-theme all wallpaper-changed \
  ~/Pictures/Wallpapers/Dark/Everforest/whatever.png
```
