#!/usr/bin/env python3
"""Write catalog.toml from every plugin.toml in this repo.

A path source does not need this: noctalia scans */plugin.toml when there is no
catalog, and a scan cannot go stale the way a checked-in catalog can. Generate
one only to publish this repo as a git source, which does require it.

added_at / updated_at are preserved from an existing catalog.toml so that
regenerating does not reshuffle the plugin browser; new plugins get the current
time for both.
"""

from __future__ import annotations

import sys
import time
import tomllib
from pathlib import Path

FIELDS = ("id", "name", "version", "author", "license", "icon", "description", "plugin_api")


def toml_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(v) for v in value) + "]"
    text = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{text}"'


def existing_timestamps(catalog: Path) -> dict[str, dict[str, int]]:
    if not catalog.is_file():
        return {}
    with catalog.open("rb") as handle:
        data = tomllib.load(handle)
    out = {}
    for row in data.get("plugin", []):
        if "id" in row:
            out[row["id"]] = {
                "added_at": row.get("added_at", 0),
                "updated_at": row.get("updated_at", 0),
            }
    return out


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    catalog = root / "catalog.toml"
    kept = existing_timestamps(catalog)
    now = int(time.time())

    manifests = sorted(root.glob("*/plugin.toml"))
    if not manifests:
        print(f"generate-catalog: no */plugin.toml under {root}", file=sys.stderr)
        return 1

    blocks = []
    for path in manifests:
        with path.open("rb") as handle:
            manifest = tomllib.load(handle)

        missing = [f for f in FIELDS if f not in manifest]
        if missing:
            print(f"generate-catalog: {path} is missing {', '.join(missing)}", file=sys.stderr)
            return 1

        stamps = kept.get(manifest["id"], {"added_at": now, "updated_at": now})

        lines = ["[[plugin]]"]
        lines += [f"{field} = {toml_value(manifest[field])}" for field in FIELDS]
        lines.append(f"tags = {toml_value(manifest.get('tags', []))}")
        lines.append(f"added_at = {stamps['added_at']}")
        lines.append(f"updated_at = {stamps['updated_at']}")
        blocks.append("\n".join(lines))

    catalog.write_text("\n\n".join(blocks) + "\n", encoding="utf-8")
    print(f"wrote {catalog} ({len(blocks)} plugins)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
