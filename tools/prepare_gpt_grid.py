from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage


FRAME_WIDTH = 192
FRAME_HEIGHT = 208


def proportional_bounds(length: int, parts: int) -> list[int]:
    """Split a generated image without assuming its dimensions are divisible."""
    return [round(index * length / parts) for index in range(parts + 1)]


def remove_checkerboard(frame: Image.Image) -> Image.Image:
    """Recover a useful transparent sprite from GPT's baked light checkerboard."""
    rgb = np.asarray(frame.convert("RGB"), dtype=np.uint8)
    rgb16 = rgb.astype(np.int16)
    channel_range = rgb16.max(axis=2) - rgb16.min(axis=2)
    channel_min = rgb16.min(axis=2)

    # GPT's fake transparency is a nearly neutral 240-255 checkerboard.  The
    # frog, question marks and gas all have enough chroma or darkness to seed
    # a foreground mask.
    background = (channel_range <= 12) & (channel_min >= 220)
    foreground = (~background).astype(np.uint8)

    # Close tiny antialias gaps, discard isolated generation noise, and fill
    # neutral highlights that lie inside a real foreground component.
    kernel = np.ones((3, 3), dtype=np.uint8)
    foreground = cv2.morphologyEx(foreground, cv2.MORPH_CLOSE, kernel)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(foreground, 8)
    kept = np.zeros_like(foreground, dtype=bool)
    minimum_area = max(18, round(frame.width * frame.height * 0.00008))
    for label in range(1, count):
        if stats[label, cv2.CC_STAT_AREA] >= minimum_area:
            kept |= labels == label
    kept = ndimage.binary_fill_holes(kept)

    # Replace checker-contaminated boundary colours with the nearest interior
    # colour, then feather the recovered alpha by about one source pixel.
    inner = cv2.erode(kept.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    if inner.any():
        _, nearest = ndimage.distance_transform_edt(~inner, return_indices=True)
        boundary = kept & ~inner
        cleaned = rgb.copy()
        cleaned[boundary] = rgb[nearest[0][boundary], nearest[1][boundary]]
    else:
        cleaned = rgb.copy()

    alpha = cv2.GaussianBlur(kept.astype(np.float32), (0, 0), 0.8)
    alpha = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)
    rgba = np.dstack((cleaned, alpha))
    return Image.fromarray(rgba)


def prepare_grid(source: Path, output: Path, columns: int, rows: int) -> None:
    image = Image.open(source).convert("RGB")
    x_bounds = proportional_bounds(image.width, columns)
    y_bounds = proportional_bounds(image.height, rows)
    destination = Image.new(
        "RGBA", (columns * FRAME_WIDTH, rows * FRAME_HEIGHT), (0, 0, 0, 0)
    )

    for row in range(rows):
        for column in range(columns):
            box = (
                x_bounds[column],
                y_bounds[row],
                x_bounds[column + 1],
                y_bounds[row + 1],
            )
            recovered = remove_checkerboard(image.crop(box))
            recovered = recovered.resize(
                (FRAME_WIDTH, FRAME_HEIGHT), Image.Resampling.LANCZOS
            )
            destination.alpha_composite(
                recovered, (column * FRAME_WIDTH, row * FRAME_HEIGHT)
            )

    output.parent.mkdir(parents=True, exist_ok=True)
    destination.save(output, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Remove GPT's baked checkerboard and normalize a sprite grid."
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--columns", type=int, required=True)
    parser.add_argument("--rows", type=int, default=2)
    args = parser.parse_args()
    if args.columns < 1 or args.rows < 1:
        parser.error("columns and rows must be positive")
    prepare_grid(args.source, args.output, args.columns, args.rows)
    result = Image.open(args.output)
    print(f"PREPARED={args.output.resolve()}")
    print(f"SIZE={result.width}x{result.height}")
    print(f"ALPHA_RANGE={result.getchannel('A').getextrema()}")


if __name__ == "__main__":
    main()
