"""Generate the scalable Kasata lockup from bundled Inter outlines (fonttools)."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

ROOT = Path(__file__).resolve().parent.parent


def outline(text, weight, size, x, baseline, tracking=0):
    font = TTFont(ROOT / f"assets/fonts/Inter-{weight}.ttf")
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    pen = SVGPathPen(glyphs)
    for char in text:
        name = cmap[ord(char)]
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
        x += font["hmtx"][name][0] * scale + tracking
    return pen.getCommands(), x


name, end = outline("Kasata", "Bold", 146, 350, 179, -4)
descriptor, descriptor_end = outline("Kasir & Operasional F&B", "Medium", 28, 354, 235)
width = round(max(end, descriptor_end) + 24)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="320" viewBox="0 0 {width} 320" fill="none">
  <title>Kasata — Kasir dan Operasional F&amp;B</title>
  <g transform="translate(16 16) scale(4.5)">
    <rect width="64" height="64" rx="16" fill="#176B55"/>
    <rect x="14" y="17" width="9" height="30" rx="2" fill="#fff"/>
    <path d="M28 32L41 17H52L39 32L52 47H41Z" fill="#fff"/>
  </g>
  <path d="{name}" fill="#191C1B"/>
  <path d="{descriptor}" fill="#626966"/>
</svg>
'''
(ROOT / "assets/images/sajia_logo_lockup.svg").write_text(svg, encoding="utf-8")
print(f"Kasata lockup: {width} x 320, text converted to vector outlines.")
