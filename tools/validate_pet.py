from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


CELL_WIDTH = 192
CELL_HEIGHT = 208
GRID_COLUMNS = 8
MAX_GRID_ROWS = 12
LEGACY_GRID_ROWS = 11
EXPECTED_SIZES = {
    (CELL_WIDTH * GRID_COLUMNS, CELL_HEIGHT * LEGACY_GRID_ROWS),
    (CELL_WIDTH * GRID_COLUMNS, CELL_HEIGHT * MAX_GRID_ROWS),
}
EXPECTED_VERSION_BY_ROWS = {
    LEGACY_GRID_ROWS: 2,
    MAX_GRID_ROWS: 3,
}
BASELINE_ROWS = 11
EXPECTED_BASELINE_SIZE = (CELL_WIDTH * GRID_COLUMNS, CELL_HEIGHT * BASELINE_ROWS)
MAX_BYTES = 20 * 1024 * 1024

ACTION_ROWS = {
    0: "idle",
    1: "running-right",
    2: "running-left",
    3: "waving",
    4: "jumping",
    5: "failed",
    6: "waiting",
    7: "running",
    8: "review",
    9: "look-directions-1",
    10: "look-directions-2",
    11: "typing",
}


def parse_rows(value: str) -> set[int]:
    if not value.strip():
        return set()
    rows = {int(part.strip()) for part in value.split(",")}
    invalid = sorted(row for row in rows if row < 0 or row >= MAX_GRID_ROWS)
    if invalid:
        raise argparse.ArgumentTypeError(f"rows outside 0..{MAX_GRID_ROWS - 1}: {invalid}")
    return rows


def changed_pixels(left: Image.Image, right: Image.Image) -> int:
    diff = ImageChops.difference(left, right)
    return sum(1 for pixel in diff.getdata() if any(pixel))


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a Codex v2/v3 pet and protect unchanged sprite rows.")
    parser.add_argument("pet_dir", type=Path)
    parser.add_argument("--baseline", type=Path, help="Baseline spritesheet for row-level comparison.")
    parser.add_argument("--allowed-rows", type=parse_rows, default=set(), help="Comma-separated rows allowed to change.")
    parser.add_argument(
        "--require-changed-rows",
        type=parse_rows,
        default=set(),
        help="Comma-separated rows that must differ from the baseline.",
    )
    args = parser.parse_args()

    errors: list[str] = []
    pet_json = args.pet_dir / "pet.json"
    if not pet_json.is_file():
        print(f"FAIL: missing {pet_json}")
        return 1

    try:
        metadata = json.loads(pet_json.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"FAIL: invalid pet.json: {exc}")
        return 1

    for key in ("id", "displayName", "spriteVersionNumber", "spritesheetPath"):
        if key not in metadata:
            errors.append(f"pet.json missing {key}")
    if metadata.get("spriteVersionNumber") not in EXPECTED_VERSION_BY_ROWS.values():
        errors.append("spriteVersionNumber must be 2 or 3")

    sprite = args.pet_dir / str(metadata.get("spritesheetPath", ""))
    if not sprite.is_file():
        errors.append(f"missing spritesheet: {sprite}")
    else:
        if sprite.stat().st_size > MAX_BYTES:
            errors.append(f"spritesheet exceeds 20 MiB: {sprite.stat().st_size} bytes")
        try:
            image = Image.open(sprite).convert("RGBA")
        except Exception as exc:
            errors.append(f"cannot open spritesheet: {exc}")
            image = None
        if image is not None:
            if image.size not in EXPECTED_SIZES:
                errors.append(f"spritesheet size is {image.size}, expected one of {sorted(EXPECTED_SIZES)}")
            if image.getchannel("A").getextrema()[0] != 0:
                errors.append("spritesheet has no fully transparent pixels")

            grid_rows = image.height // CELL_HEIGHT
            expected_version = EXPECTED_VERSION_BY_ROWS.get(grid_rows)
            if expected_version is not None and metadata.get("spriteVersionNumber") != expected_version:
                errors.append(
                    f"spriteVersionNumber must be {expected_version} for a {grid_rows}-row spritesheet"
                )
            missing_required = sorted(row for row in args.require_changed_rows if row >= grid_rows)
            if missing_required:
                errors.append(f"required rows are missing from this spritesheet: {missing_required}")

            if args.baseline:
                baseline = Image.open(args.baseline).convert("RGBA")
                if baseline.size not in (image.size, EXPECTED_BASELINE_SIZE):
                    errors.append(
                        f"baseline size {baseline.size} is neither {image.size} nor {EXPECTED_BASELINE_SIZE}"
                    )
                else:
                    if baseline.size != image.size:
                        expanded = Image.new("RGBA", image.size, (0, 0, 0, 0))
                        expanded.paste(baseline, (0, 0))
                        baseline = expanded
                    print("ROW_DIFF_REPORT")
                    for row in range(grid_rows):
                        box = (0, row * CELL_HEIGHT, image.width, (row + 1) * CELL_HEIGHT)
                        count = changed_pixels(baseline.crop(box), image.crop(box))
                        print(f"row={row:02d} state={ACTION_ROWS[row]:18s} changed_pixels={count}")
                        if count and row not in args.allowed_rows:
                            errors.append(f"protected row {row} ({ACTION_ROWS[row]}) changed")
                        if row in args.require_changed_rows and count == 0:
                            errors.append(f"required row {row} ({ACTION_ROWS[row]}) did not change")

    if errors:
        print("VALIDATION=FAIL")
        for error in errors:
            print(f"- {error}")
        return 1

    print("VALIDATION=PASS")
    print(f"pet_id={metadata['id']}")
    print(f"spritesheet={sprite}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
