# Binary Clock

A BCD binary clock for noctalia, as both a bar widget and a desktop widget. One column of LEDs per decimal digit of the time, rows weighted 8 / 4 / 2 / 1 from the top — the same face as the classic LED desk clocks.

## Plugin

Manifest id `boatette/binary-clock`. Two entries, each with its own settings:

| Entry     | Kind           | Notes                                                               |
| --------- | -------------- | ------------------------------------------------------------------- |
| `bar`     | bar widget     | LEDs or braille; full time in the tooltip. Left click opens the calendar. |
| `desktop` | desktop widget | Column headers, row legend, and the decimal readout.                |

Add the bar widget as `boatette/binary-clock:bar`, and the desktop widget from the desktop-widgets editor.

## Usage

### Reading it

Each decimal digit gets its own column, top to bottom weighted 8, 4, 2, 1. Add up the lit rows in a column to get that digit.

```
        Hours    Minutes   Seconds
  8       ·  ·     ·  ·      ·  ·
  4       ·  ●     ·  ·      ●  ·
  2       ·  ●     ·  ·      ·  ●
  1       ·  ●     ·  ●      ·  ●
          0  7  :  0  5   :  5  3
```

That is BCD, not plain binary: `7` is `4+2+1` in the hours-units column rather than a seven encoded across a single six-bit hours column. It is what the physical clocks do, and it makes the decimal readout a straight column-by-column translation.

Columns are drawn four cells tall even when the digit cannot use all four bits — hours-tens only reaches 2, minutes- and seconds-tens only reach 5. The unused top cells are left empty so the row legend lines up across all six columns.

### Bar widget

The bar capsule clips to the bar thickness, so the bar face is LEDs only. Four LEDs plus three gaps have to fit: the defaults (size 5, gap 2) come to 26px, which clears a stock 32px bar. Raise **LED Size** on a thicker bar.

On a side bar the LED grid is transposed rather than rotated — digits run down the bar, each digit's four bits run across it with 8 on the left — so the weights keep a fixed reading order whichever edge the bar is docked to.

Hover for the full date and time; see **Tooltip Format** below.

### Braille face

**Face Style** switches the bar widget from drawn LEDs to text. A braille cell is a 2×4 dot grid, which is exactly one BCD group — left column the tens digit, right column the units, rows carrying 8 / 4 / 2 / 1 from the top — so the whole clock is three characters, one per group, and the face becomes three `ui.label`s instead of twenty-four boxes.

```
01:23:45  ->  ⢀⢤⢒
09:58:07  ->  ⢈⡊⢰
12:34:56  ->  ⡠⡔⡲
23:59:59  ->  ⢤⣊⣊
```

Braille only draws lit dots, so there are no unlit ones: `00:00:00` renders as three blanks, and you lose the positional reference the LED face gives you. It cannot be fixed from the plugin — a glyph is one text run in one color, and the ui tree has no way to stack an unlit layer behind it. The LED face is the more readable of the two; braille is the compact one.

**Lit Color** colors the text; **Unlit Color**, **LED Size**, **LED Spacing** and **Glow** do nothing in this mode. **Group Spacing** still separates the three characters, and wants a smaller value here than the LED default of 6, since the glyphs carry their own side bearings.

The bar font may not cover U+2800–U+28FF. Set **Braille Font** to one that does, and check first:

```sh
fc-list ':charset=2800' family | sort -u
```

DejaVu Sans and the JetBrainsMono Nerd Font family both cover the block. The prettier alternatives — sextants (U+1FB00) and octants (U+1CE00), same 2×4 grid but solid blocks instead of dots — are only in GNU Unifont in practice, so braille is the portable choice.

The desktop widget stays LEDs-only: its face is built around the headers, row legend and decimal readout, which braille has no room for.

### Clicking

Left click is declared in the manifest as `panel-toggle control-center calendar`, the same panel the built-in `clock` widget opens. It is a widget default, not script behaviour, so it shows up in the bar widget's settings editor and can be rebound like any other gesture:

```toml
[widget.binary-clock.actions]
left = "panel-toggle control-center weather"
forward = "exec gnome-calendar"
```

Middle click keeps the shell-wide default of opening the widget's settings.

### Desktop widget

Position, size, and rotation are owned by the desktop-widgets editor. The plugin's settings control what the face contains: headers, the 8/4/2/1 legend down the right, the decimal readout underneath, and the rules between groups can each be turned off for a barer face.

## Settings

Both entries carry their own copies, so the bar can stay minimal while the desktop face stays verbose.

| Setting               | Entries | Default                   | Notes                                                    |
| --------------------- | ------- | ------------------------- | -------------------------------------------------------- |
| Show Seconds          | both    | on                        | Off drops the seconds columns and redraws once a minute. |
| Hour Format           | both    | 24-hour                   | 12-hour counts 1–12, with no AM/PM indicator.            |
| Face Style            | bar     | LEDs                      | Braille draws the grid as three characters instead.      |
| Braille Size          | bar     | 13                        | Font size of the braille characters. Braille face only.  |
| Braille Font          | bar     | *(bar font)*              | Family to draw the braille with. Braille face only.      |
| LED Size              | both    | 5 (bar) / 16 (desktop)    | Diameter of one LED.                                     |
| LED Spacing           | both    | 2 (bar) / 8 (desktop)     | Gap between LEDs.                                        |
| Group Spacing         | both    | 6 (bar) / 14 (desktop)    | Gap between hours, minutes and seconds.                  |
| Lit Color             | both    | `primary`                 | Palette role, `role/alpha`, or a hex value.              |
| Unlit Color           | both    | `outline`                 | Also colors the group separators.                        |
| Glow                  | both    | 0                         | Blur radius on lit LEDs only.                            |
| Tooltip Format        | bar     | `%A, %d %B %Y — %H:%M:%S` | strftime pattern; empty hides the tooltip.               |
| Show Column Headers   | desktop | on                        | Hours / Minutes / Seconds above each group.              |
| Show Row Legend       | desktop | on                        | The 8 / 4 / 2 / 1 weights down the right.                |
| Show Decimal Readout  | desktop | on                        | Decimal time under the grid.                             |
| Show Group Separators | desktop | on                        | Rules between groups, with the `:` of the readout.       |
| Text Size             | desktop | 13                        | Headers, legend and readout.                             |
| Text Color            | desktop | `on_surface`              | Headers, legend and readout.                             |

## Notes

- Both entries redraw only when the displayed time actually changes, so a minutes-only face costs one render a minute rather than sixty.
- The bar widget re-arms its tick against the wall clock on every update rather than free-running on a fixed 1000ms interval. An interval timer drifts, and a binary clock that flips its seconds column a third of a second late is visibly wrong next to any other clock on screen. With seconds off it sleeps to the next minute boundary instead.
- The desktop widget uses `desktopWidget.setWantsSecondTicks(true)`, which the host already aligns to second boundaries.

## Development

```sh
noctalia plugins lint /path/to/noctalia-plugins/binary-clock
grep binary-clock ~/.cache/noctalia/noctalia.log | tail
```

The `path` plugin source is read in place, so noctalia hot-reloads the `.luau` files on save.
