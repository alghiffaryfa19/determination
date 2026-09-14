#!/usr/bin/env python3
"""Generate Android vectors from the canonical Aurora ribbon mark."""
from pathlib import Path
import argparse
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

HERE = Path(__file__).resolve().parent
RES = HERE.parent / "app/src/main/res/drawable"
SVG = "{http://www.w3.org/2000/svg}"


def vector(source, *, launcher=False, monochrome=False):
    size, viewport = (108, 54) if launcher else (26, 32)
    lines = ['<vector xmlns:android="http://schemas.android.com/apk/res/android"',
             '    xmlns:aapt="http://schemas.android.com/aapt"',
             f'    android:width="{size}dp" android:height="{size}dp"',
             f'    android:viewportWidth="{viewport}" android:viewportHeight="{viewport}">']
    if launcher:
        lines.append('    <group android:translateX="11" android:translateY="11">')
    gradients = {g.attrib["id"]: g for g in source.findall(f"{SVG}defs/{SVG}linearGradient")}
    for path in source.findall(f"{SVG}path"):
        attrs = path.attrib
        if monochrome and "opacity" in attrs:
            continue
        fill = "#FFFFFF" if monochrome else attrs["fill"]
        lines.append(f'        <path android:pathData={quoteattr(attrs["d"])}')
        if attrs.get("fill-rule") == "evenodd":
            lines.append('            android:fillType="evenOdd"')
        for svg, android in (("opacity", "fillAlpha"), ("stroke", "strokeColor"),
                             ("stroke-width", "strokeWidth"), ("stroke-linejoin", "strokeLineJoin")):
            if svg in attrs and not monochrome:
                lines.append(f'            android:{android}={quoteattr(attrs[svg])}')
        if "stroke" in attrs and "opacity" in attrs:
            lines.append(f'            android:strokeAlpha={quoteattr(attrs["opacity"])}')
        if not fill.startswith("url("):
            lines.append(f'            android:fillColor={quoteattr(fill)} />')
            continue
        g = gradients[fill[5:-1]]
        lines += ['            >', '            <aapt:attr name="android:fillColor">',
                  '                <gradient android:type="linear"']
        for svg, android in (("x1", "startX"), ("y1", "startY"), ("x2", "endX"), ("y2", "endY")):
            lines.append(f'                    android:{android}={quoteattr(g.attrib[svg])}')
        lines.append('                    >')
        for stop in g:
            color = stop.attrib["stop-color"]
            if "stop-opacity" in stop.attrib:
                alpha = round(float(stop.attrib["stop-opacity"]) * 255)
                color = f"#{alpha:02X}{color[1:]}"
            lines.append(f'                    <item android:offset={quoteattr(stop.attrib["offset"])} android:color={quoteattr(color)} />')
        lines += ['                </gradient>', '            </aapt:attr>', '        </path>']
    if launcher:
        lines.append('    </group>')
    return "\n".join([*lines, '</vector>', ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source = ET.parse(HERE / 'aurora.svg').getroot()
    outputs = {
        'ic_aurora.xml': vector(source),
        'ic_aurora_fg.xml': vector(source, launcher=True),
        'ic_aurora_mono.xml': vector(source, launcher=True, monochrome=True),
    }
    for name, text in outputs.items():
        path = RES / name
        if args.check:
            if not path.exists() or path.read_text() != text:
                raise SystemExit(f'Stale vector: {path}; run {__file__}')
        else:
            path.write_text(text)
    print('Aurora icon vectors: OK')


if __name__ == '__main__':
    main()
