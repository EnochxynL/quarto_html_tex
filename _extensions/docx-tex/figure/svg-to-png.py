# /// script
# requires-python = ">=3.11"
# dependencies = ["pymupdf==2.0"]
# ///
"""Rasterize SVG bytes for Word's fallback image without a browser."""
import sys
import pymupdf

with pymupdf.open(stream=sys.stdin.buffer.read(), filetype="svg") as document:
    page = document[0]
    # Preserve the renderer's physical page size through PNG's pHYs metadata.
    # Increasing pixel count must not enlarge an inline symbol in Word.
    scale = min(300 / 72, 2400 / max(page.rect.width, page.rect.height))
    pixmap = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=True)
    pixmap.set_dpi(max(1, round(72 * scale)), max(1, round(72 * scale)))
    sys.stdout.buffer.write(pixmap.tobytes("png"))
