"""Compare Sol renders with DeepSeek's measured Rodina frames (docs/rodina_reference/palette_report.csv).

Usage: python3 -I tools/palette_compare.py <csv> <scene>=<sol image> [<scene>=<sol image> ...]
Scenes: orbit, salmon_ground, interior, ship_space. Prints, per scene, the Sol image's mean colour (RGB 0-255 and HSV,
measured like the CSV: HSV of the mean RGB), its four dominant colours, and the Rodina reference rows it is checked
against, with the difference in brightness (HSV value) and hue. Whole-frame means depend on framing (how much sky or
space is in view), so they are a guide, not a pass/fail.
"""
import colorsys
import csv
import sys

from PIL import Image

# Rodina reference frames per scene (DeepSeek's selection, sources.csv gives each frame's URL and timestamp).
REFERENCES = {
    "orbit": ["frames/selected/space/steam06_orbit_ochre.jpg", "frames/selected/space/trailer003_planet_ship.jpg"],
    "salmon_ground": ["frames/selected/surface/steam01_salmon_sky_mountains.jpg"],
    "interior": ["frames/selected/interior/steam11_dark_interior.jpg", "frames/selected/interior/video20_corridor.jpg",
                 "frames/selected/interior/steam00_inventory_room.jpg", "frames/selected/interior/steam04_green_corridor.jpg"],
    "ship_space": ["frames/selected/space/videoT90_19_ship_silhouette.jpg", "frames/selected/space/steam12_sun_cyan_silhouette.jpg"],
}


def measure(path):
    image = Image.open(path).convert("RGB")
    image.thumbnail((320, 180))
    pixels = list(image.getdata())
    count = len(pixels)
    mean = tuple(sum(p[i] for p in pixels) / count for i in range(3))
    hue, sat, value = colorsys.rgb_to_hsv(*(c / 255.0 for c in mean))
    quantized = image.quantize(colors=4)
    palette = quantized.getpalette()[:12]
    order = sorted(quantized.getcolors(), reverse=True)
    dominant = ["#%02x%02x%02x" % tuple(palette[index * 3:index * 3 + 3]) for _, index in order]
    return mean, (hue * 360.0, sat, value), dominant


def hue_gap(a, b):
    gap = abs(a - b) % 360.0
    return min(gap, 360.0 - gap)


def main():
    rows = {}
    with open(sys.argv[1], newline="") as handle:
        for row in csv.DictReader(handle):
            rows[row["file"]] = row
    for argument in sys.argv[2:]:
        scene, path = argument.split("=", 1)
        mean, hsv, dominant = measure(path)
        print("== %s: %s" % (scene, path))
        print("   Sol    mean rgb (%3d,%3d,%3d)  hue %3d sat %.2f value %.2f  dominant %s" % (
            mean[0], mean[1], mean[2], hsv[0], hsv[1], hsv[2], " ".join(dominant)))
        for reference in REFERENCES.get(scene, []):
            row = rows.get(reference)
            if row is None:
                continue
            value_gap = hsv[2] - float(row["value"])
            print("   Rodina mean rgb (%3s,%3s,%3s)  hue %3s sat %s value %s  dominant %s   [value %+.2f, hue off %3d]  %s" % (
                row["mean_r"], row["mean_g"], row["mean_b"], row["hue"], row["sat"], row["value"], row["dominant"],
                value_gap, hue_gap(hsv[0], float(row["hue"])), reference.split("/")[-1]))


if __name__ == "__main__":
    main()
