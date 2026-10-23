#!/usr/bin/env python3
"""Furnishing for rooms made with shipkit.Plan: everything is tried at a spot and kept only if it fits, stays clear of the doors and
leaves every door and seat of the room reachable (Plan.piece checks). Pieces are boxes in the materials the game draws."""
import math

import shipkit
from shipkit import facing


def bx(side, name, cx, cz, along, depth, h, mat, solid=False, lift=0.0, da=0.0, dd=0.0):
    """A box against the wall `side`. (cx, cz) is the centre of the slot; along runs with the wall, depth away from it (into the room);
    da / dd shift it along / away from the wall."""
    if side == "left":
        return (name, cx + dd, cz + da, depth, h, along, mat, solid, lift)
    if side == "right":
        return (name, cx - dd, cz + da, depth, h, along, mat, solid, lift)
    if side == "nose":
        return (name, cx + da, cz + dd, along, h, depth, mat, solid, lift)
    return (name, cx + da, cz - dd, along, h, depth, mat, solid, lift)


def place_along(p, room, side, along, depth, builder, count=99, start=0.0, gap=0.25, margin=0.12, step=0.25, stop=None):
    x, z, w, d = p.rooms[room]
    length = d if side in ("left", "right") else w
    stop = length if stop is None else stop
    cursor, n = start, 0
    while n < count:
        spot, placed = cursor, False
        while spot + along <= stop - 0.05:
            mid = spot + along / 2
            if side == "left":
                cx, cz = x + margin + depth / 2, z + mid
            elif side == "right":
                cx, cz = x + w - margin - depth / 2, z + mid
            elif side == "nose":
                cx, cz = x + mid, z + margin + depth / 2
            else:
                cx, cz = x + mid, z + d - margin - depth / 2
            if p.group(room, builder(cx, cz, side)):
                placed = True
                cursor = spot + along + gap
                n += 1
                break
            spot += step
        if not placed:
            break
    return n


# ------------------------------------------------------------------------------------------------ single items (builders)
def b_bunk(mat="fabric"):
    def build(cx, cz, side):
        return [bx(side, "bunk_low", cx, cz, 2.0, 0.95, 0.25, mat, True, 0.3),
                bx(side, "bunk_high", cx, cz, 2.0, 0.95, 0.2, mat, False, 1.15),
                bx(side, "bunk_post_a", cx, cz, 0.06, 0.06, 1.7, "steel", False, 0.0, da=-1.0, dd=-0.45),
                bx(side, "bunk_post_b", cx, cz, 0.06, 0.06, 1.7, "steel", False, 0.0, da=1.0, dd=-0.45),
                bx(side, "bunk_post_c", cx, cz, 0.06, 0.06, 1.7, "steel", False, 0.0, da=-1.0, dd=0.45),
                bx(side, "bunk_post_d", cx, cz, 0.06, 0.06, 1.7, "steel", False, 0.0, da=1.0, dd=0.45),
                bx(side, "pillow", cx, cz, 0.4, 0.6, 0.1, "white", False, 0.55, da=-0.7),
                bx(side, "pillow_high", cx, cz, 0.4, 0.6, 0.1, "white", False, 1.35, da=-0.7)]
    return build


def b_bed(mat="linen", frame="wood"):
    def build(cx, cz, side):
        return [bx(side, "bed_frame", cx, cz, 2.1, 1.2, 0.4, frame, True),
                bx(side, "bed_mattress", cx, cz, 2.0, 1.1, 0.14, mat, False, 0.4),
                bx(side, "bed_pillow", cx, cz, 0.4, 0.8, 0.12, "white", False, 0.54, da=-0.75)]
    return build


def b_locker(mat="console", w=0.7, h=1.9):
    def build(cx, cz, side):
        return [bx(side, "locker", cx, cz, w, 0.55, h, mat, True),
                bx(side, "locker_light", cx, cz, w * 0.5, 0.03, 0.1, "glow_teal", False, h - 0.3, dd=-0.0 + 0.29)]
    return build


def b_counter(mat="steel", top="steel", h=0.9, depth=0.62):
    def build(cx, cz, side):
        return [bx(side, "counter", cx, cz, 1.2, depth, h, mat, True), bx(side, "counter_top", cx, cz, 1.24, depth + 0.03, 0.04, top, False, h)]
    return build


def b_stove():
    def build(cx, cz, side):
        return [bx(side, "stove", cx, cz, 1.0, 0.65, 0.9, "steel", True), bx(side, "stove_plate", cx, cz, 0.8, 0.5, 0.03, "glow_amber", False, 0.9),
                bx(side, "hood", cx, cz, 1.0, 0.5, 0.4, "steel", False, 1.9, dd=-0.05)]
    return build


def b_fridge():
    def build(cx, cz, side):
        return [bx(side, "fridge", cx, cz, 0.8, 0.7, 1.9, "white", True), bx(side, "fridge_strip", cx, cz, 0.05, 0.03, 0.8, "glow_green", False, 0.9, dd=0.35)]
    return build


def b_console_wall(screen_w=1.0):
    def build(cx, cz, side):
        return [bx(side, "wall_console", cx, cz, screen_w + 0.4, 0.55, 1.05, "console", True),
                bx(side, "wall_screen", cx, cz, screen_w, 0.04, 0.45, "screen", False, 1.15, dd=0.05)]
    return build


def b_shelf(mat="steel", h=2.0, depth=0.5, along=1.4):
    def build(cx, cz, side):
        out = [bx(side, "shelf_unit", cx, cz, along, depth, h, mat, True)]
        for i, lift in enumerate((0.5, 1.0, 1.5)):
            out.append(bx(side, "shelf_load_%d" % i, cx, cz, along * 0.8, depth * 0.7, 0.25, "crate", False, lift + 0.05, dd=depth * 0.12))
        return out
    return build


def b_rack():
    def build(cx, cz, side):
        return [bx(side, "gun_rack", cx, cz, 1.3, 0.4, 1.8, "dark", True), bx(side, "rack_strip", cx, cz, 1.1, 0.03, 0.06, "glow_red", False, 1.6, dd=0.2)]
    return build


def b_sofa(mat="red_fabric", along=2.0):
    def build(cx, cz, side):
        return [bx(side, "sofa_seat", cx, cz, along, 0.85, 0.42, mat, True), bx(side, "sofa_back", cx, cz, along, 0.18, 0.5, mat, False, 0.42, dd=-0.33)]
    return build


def b_planter(h=0.7, along=1.2):
    def build(cx, cz, side):
        return [bx(side, "planter_box", cx, cz, along, 0.6, 0.45, "planter", True), bx(side, "planter_leaves", cx, cz, along * 0.8, 0.45, h, "glow_green", False, 0.45)]
    return build


def b_medbed():
    def build(cx, cz, side):
        return [bx(side, "medbed", cx, cz, 2.0, 0.95, 0.5, "white", True), bx(side, "medbed_pad", cx, cz, 1.9, 0.85, 0.08, "glow_green", False, 0.5),
                bx(side, "medbed_monitor", cx, cz, 0.5, 0.05, 0.4, "screen", False, 1.3, da=-0.5, dd=-0.5)]
    return build


def b_bench(mat="steel", h=0.9, depth=0.8, along=1.6, top="wood"):
    def build(cx, cz, side):
        return [bx(side, "bench", cx, cz, along, depth, h, mat, True), bx(side, "bench_top", cx, cz, along + 0.04, depth + 0.04, 0.05, top, False, h)]
    return build


def b_pipe_run(along=1.6):
    def build(cx, cz, side):
        return [bx(side, "pipe_a", cx, cz, along, 0.12, 0.12, "pipe", False, 0.4, dd=0.1), bx(side, "pipe_b", cx, cz, along, 0.12, 0.12, "pipe", False, 1.6, dd=0.1),
                bx(side, "pipe_post", cx, cz, 0.1, 0.1, 2.4, "pipe", False, 0.0, dd=0.1)]
    return build


# ------------------------------------------------------------------------------------------------ free-standing items
def table(p, room, x, z, sx=1.6, sz=0.9, stools=True, mat="wood"):
    parts = [("table_top", x, z, sx, 0.06, sz, mat, True, 0.72),
             ("table_leg", x, z, 0.1, 0.72, 0.1, "steel", False, 0.0)]
    if stools:
        for (dx, dz) in ((-sx * 0.28, -sz * 0.5 - 0.3), (sx * 0.28, -sz * 0.5 - 0.3), (-sx * 0.28, sz * 0.5 + 0.3), (sx * 0.28, sz * 0.5 + 0.3)):
            parts.append(("stool", x + dx, z + dz, 0.38, 0.45, 0.38, "grey_fabric", False, 0.0))
    return p.group(room, parts)


def crate(p, room, x, z, s=1.0, tall=0.9, stack=False):
    parts = [("crate", x, z, s, tall, s, "crate", True, 0.0)]
    if stack:
        parts.append(("crate_top", x, z, s * 0.7, tall * 0.6, s * 0.7, "crate", False, tall))
    return p.group(room, parts)


def rug(p, room, x, z, sx, sz, mat="carpet"):
    return p.piece(room, "rug", x, z, sx, 0.02, sz, mat, False, 0.0)


def holo_table(p, room, x, z, sx=2.4, sz=1.4):
    return p.group(room, [("holo_base", x, z, sx, 0.8, sz, "console", True, 0.0), ("holo_glass", x, z, sx * 0.85, 0.04, sz * 0.85, "glow_teal", False, 0.8),
                          ("holo_glow", x, z, sx * 0.5, 0.45, sz * 0.5, "glass", False, 0.84)])


def reactor(p, room, x, z, r=1.0, h=2.6):
    return p.group(room, [("reactor_base", x, z, r * 2.0, 0.35, r * 2.0, "steel", True, 0.0), ("reactor_core", x, z, r * 1.2, h, r * 1.2, "glow_amber", False, 0.35),
                          ("reactor_cap", x, z, r * 1.7, 0.2, r * 1.7, "steel", False, h + 0.35)])


# ------------------------------------------------------------------------------------------------ rooms by kind
def furnish(p, room):
    kind = p.kinds[room]
    fn = globals().get("_f_" + kind)
    if fn:
        fn(p, room)


def _long_axis_side(p, room):
    x, z, w, d = p.rooms[room]
    return ("left", "right") if d >= w else ("nose", "tail")


def _f_corridor(p, room):
    x, z, w, d = p.rooms[room]
    # floor guide lights along both edges, a plant and a first-aid box at the dead ends (only where they fit)
    sides = _long_axis_side(p, room)
    long_len = max(w, d)
    for s in sides:
        if s in ("left", "right"):
            px = x + 0.18 if s == "left" else x + w - 0.18
            p.piece(room, "floor_strip", px, z + d / 2, 0.06, 0.02, d - 0.6, "glow_teal", False, 0.0)
        else:
            pz = z + 0.18 if s == "nose" else z + d - 0.18
            p.piece(room, "floor_strip", x + w / 2, pz, w - 0.6, 0.02, 0.06, "glow_teal", False, 0.0)
    if long_len > 12:
        place_along(p, room, sides[0], 0.9, 0.5, b_planter(0.9, 0.9), count=2, start=1.2, gap=long_len / 3)
        place_along(p, room, sides[1], 0.8, 0.4, b_locker("white", 0.8, 1.6), count=2, start=long_len * 0.35, gap=long_len * 0.3)


def _f_quarters(p, room, bunks=2):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    mat = p.rng.choice(["fabric", "grey_fabric", "red_fabric"])
    place_along(p, room, sides[0], 2.0, 1.0, b_bunk(mat), count=bunks, start=0.3, gap=0.4)
    place_along(p, room, sides[1], 0.75, 0.55, b_locker(), count=2, start=0.3, gap=0.2)
    place_along(p, room, sides[1], 1.4, 0.7, b_bench("steel", 0.75, 0.7, 1.4), count=1, start=2.0)
    rug(p, room, x + w / 2, z + d / 2, min(2.4, w - 2.2), min(1.6, d - 2.2))


def _f_captain(p, room):
    x, z, w, d = p.rooms[room]
    long_side = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, long_side[0], 2.1, 1.2, b_bed("linen", "wood"), count=1, start=0.4)
    place_along(p, room, long_side[1], 0.9, 0.6, b_locker("wood", 0.9, 2.1), count=2, start=0.3, gap=0.2)
    place_along(p, room, long_side[1], 1.6, 0.7, b_bench("wood", 0.75, 0.7, 1.6, "wood"), count=1, start=2.4)
    rug(p, room, x + w / 2, z + d / 2, min(3.0, w - 2.0), min(2.0, d - 2.0), "red_fabric")
    # a chart screen on the wall opposite the bed
    place_along(p, room, long_side[1], 1.4, 0.4, b_console_wall(1.2), count=1, start=max(0.5, (d if d >= w else w) - 2.2))


def _f_galley(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.2, 0.65, b_stove(), count=1, start=0.3)
    place_along(p, room, sides[0], 1.2, 0.62, b_counter(), count=3, start=1.6, gap=0.0)
    place_along(p, room, sides[0], 0.8, 0.7, b_fridge(), count=1, start=5.2 if max(w, d) > 7 else 4.0)
    place_along(p, room, sides[1], 1.2, 0.62, b_counter("white", "wood"), count=2, start=0.4, gap=0.0)
    table(p, room, x + w / 2, z + d / 2, 1.8, 0.9)


def _f_mess(p, room):
    x, z, w, d = p.rooms[room]
    if d >= w:
        for k in range(int(max(1, (d - 1.5) // 2.4))):
            for sx in (-1.4, 1.4):
                if w >= 5.0 or sx < 0:
                    table(p, room, x + w / 2 + (sx if w >= 5.0 else 0), z + 1.4 + k * 2.4, 0.9, 1.6, stools=True)
    else:
        for k in range(int(max(1, (w - 1.5) // 2.8))):
            table(p, room, x + 1.6 + k * 2.8, z + d / 2, 1.8, 0.9, stools=True)
    place_along(p, room, "left" if d >= w else "nose", 1.2, 0.62, b_counter("white", "wood"), count=2, start=0.4, gap=0.0)


def _f_medical(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 2.0, 0.95, b_medbed(), count=3, start=0.5, gap=0.9)
    place_along(p, room, sides[1], 1.0, 0.6, b_locker("white", 1.0, 1.8), count=2, start=0.4, gap=0.2)
    place_along(p, room, sides[1], 1.4, 0.7, b_bench("white", 0.8, 0.7, 1.4, "white"), count=1, start=2.8)
    p.group(room, [("scanner_post_a", x + w / 2 - 0.8, z + d / 2, 0.08, 1.7, 0.08, "steel", False, 0.0), ("scanner_post_b", x + w / 2 + 0.8, z + d / 2, 0.08, 1.7, 0.08, "steel", False, 0.0),
                   ("scanner_bar", x + w / 2, z + d / 2, 1.7, 0.08, 0.14, "glow_teal", False, 1.7)])


def _f_cargo(p, room):
    x, z, w, d = p.rooms[room]
    rng = p.rng
    attempts = int(w * d / 6)
    for _ in range(attempts):
        s = rng.choice([0.9, 1.0, 1.2, 1.5])
        cx = x + 0.6 + rng.random() * (w - 1.2)
        cz = z + 0.6 + rng.random() * (d - 1.2)
        crate(p, room, round(cx * 4) / 4, round(cz * 4) / 4, s, rng.choice([0.8, 1.0, 1.4]), stack=rng.random() < 0.4)
    place_along(p, room, "left" if d >= w else "nose", 1.4, 0.5, b_shelf(), count=3, start=0.5, gap=0.3)


def _f_engineering(p, room):
    x, z, w, d = p.rooms[room]
    reactor(p, room, x + w / 2, z + d / 2, min(1.3, min(w, d) * 0.16), min(2.4, p.ceiling_y - 0.35))
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.4, 0.55, b_console_wall(1.0), count=3, start=0.6, gap=0.3)
    place_along(p, room, sides[1], 1.6, 0.4, b_pipe_run(), count=4, start=0.4, gap=0.6)
    place_along(p, room, sides[1], 0.8, 0.6, b_locker("steel", 0.8, 1.7), count=2, start=0.4, gap=0.3)


def _f_lab(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.6, 0.7, b_bench("white", 0.9, 0.7, 1.6, "white"), count=3, start=0.4, gap=0.1)
    place_along(p, room, sides[1], 1.4, 0.55, b_console_wall(1.0), count=2, start=0.4, gap=0.2)
    p.group(room, [("island", x + w / 2, z + d / 2, 1.8, 0.9, 0.9, "white", True, 0.0), ("island_dome", x + w / 2, z + d / 2, 0.5, 0.4, 0.5, "glass", False, 0.9),
                   ("island_glow", x + w / 2, z + d / 2, 0.2, 0.2, 0.2, "glow_teal", False, 0.95)])


def _f_armoury(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.3, 0.4, b_rack(), count=4, start=0.4, gap=0.1)
    place_along(p, room, sides[1], 1.3, 0.4, b_rack(), count=3, start=0.4, gap=0.1)
    p.group(room, [("armoury_bench", x + w / 2, z + d / 2, 1.8, 0.9, 0.8, "dark", True, 0.0), ("bench_light", x + w / 2, z + d / 2, 1.2, 0.03, 0.1, "glow_red", False, 0.92)])


def _f_lounge(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    mat = p.rng.choice(["red_fabric", "grey_fabric", "fabric"])
    place_along(p, room, sides[0], 2.0, 0.9, b_sofa(mat), count=3, start=0.5, gap=0.4)
    place_along(p, room, sides[1], 1.2, 0.6, b_planter(1.1, 1.2), count=2, start=0.5, gap=1.0)
    table(p, room, x + w / 2, z + d / 2, 1.2, 0.8, stools=False, mat="glass" if False else "wood")
    rug(p, room, x + w / 2, z + d / 2, min(3.4, w - 2.0), min(2.4, d - 2.0), "carpet")


def _f_observation(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[1], 2.0, 0.9, b_sofa("grey_fabric"), count=2, start=0.6, gap=0.5)
    place_along(p, room, sides[0], 1.2, 0.6, b_planter(1.0, 1.2), count=2, start=0.6, gap=1.2)
    rug(p, room, x + w / 2, z + d / 2, min(3.0, w - 2.0), min(2.0, d - 2.0), "carpet")


def _f_greenhouse(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.4, 0.8, b_planter(1.3, 1.4), count=8, start=0.3, gap=0.2)
    place_along(p, room, sides[1], 1.4, 0.8, b_planter(1.3, 1.4), count=8, start=0.3, gap=0.2)
    p.group(room, [("grow_bed", x + w / 2, z + d / 2, 1.0, 0.5, 2.2 if d >= w else 1.0, "planter", True, 0.0), ("grow_leaves", x + w / 2, z + d / 2, 0.8, 0.9, 2.0 if d >= w else 0.8, "glow_green", False, 0.5)])


def _f_workshop(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.8, 0.8, b_bench("steel", 0.95, 0.8, 1.8, "wood"), count=3, start=0.4, gap=0.1)
    place_along(p, room, sides[1], 1.4, 0.6, b_shelf(), count=3, start=0.4, gap=0.2)
    p.group(room, [("machine", x + w / 2, z + d / 2, 1.2, 1.3, 1.0, "console", True, 0.0), ("machine_light", x + w / 2, z + d / 2, 0.8, 0.06, 0.06, "glow_amber", False, 1.2)])


def _f_ops(p, room):
    x, z, w, d = p.rooms[room]
    holo_table(p, room, x + w / 2, z + d / 2, 2.6, 1.5)
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.4, 0.55, b_console_wall(1.0), count=3, start=0.5, gap=0.2)
    place_along(p, room, sides[1], 1.4, 0.55, b_console_wall(1.0), count=3, start=0.5, gap=0.2)


def _f_comms(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.4, 0.55, b_console_wall(1.0), count=4, start=0.4, gap=0.2)
    place_along(p, room, sides[1], 1.4, 0.55, b_console_wall(1.0), count=4, start=0.4, gap=0.2)
    p.group(room, [("comms_mast", x + w / 2, z + d / 2, 0.8, 1.5, 0.8, "console", True, 0.0), ("comms_dish", x + w / 2, z + d / 2, 0.9, 0.08, 0.9, "glow_teal", False, 1.5)])


def _f_atrium(p, room):
    x, z, w, d = p.rooms[room]
    p.group(room, [("fountain_basin", x + w / 2, z + d / 2, 3.0, 0.5, 3.0, "white", True, 0.0), ("fountain_water", x + w / 2, z + d / 2, 2.6, 0.06, 2.6, "glow_teal", False, 0.5),
                   ("fountain_spire", x + w / 2, z + d / 2, 0.4, 1.4, 0.4, "glass", False, 0.5)])
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 2.0, 0.8, b_sofa("grey_fabric"), count=3, start=0.8, gap=0.8)
    place_along(p, room, sides[1], 2.0, 0.8, b_sofa("fabric"), count=3, start=0.8, gap=0.8)
    for dx in (-1, 1):
        p.group(room, [("atrium_planter", x + w / 2 + dx * (w / 2 - 1.6), z + d / 2, 1.0, 0.5, 1.0, "planter", True, 0.0), ("atrium_tree", x + w / 2 + dx * (w / 2 - 1.6), z + d / 2, 0.8, 1.8, 0.8, "glow_green", False, 0.5)])


def _f_storage(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.4, 0.5, b_shelf(), count=6, start=0.3, gap=0.0)
    place_along(p, room, sides[1], 1.4, 0.5, b_shelf(), count=6, start=0.3, gap=0.0)
    crate(p, room, x + w / 2, z + d / 2, 1.0, 0.9, True)


def _f_brig(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 2.0, 0.6, b_bench("steel", 0.45, 0.6, 2.0, "grey_fabric"), count=2, start=0.4, gap=0.9)
    place_along(p, room, sides[1], 0.6, 0.5, b_locker("steel", 0.6, 1.4), count=2, start=0.4, gap=0.5)
    p.group(room, [("cell_bars", x + w / 2, z + d / 2, 0.06, 2.2, d * 0.4 if d >= w else 0.06, "glow_red", False, 0.0)] if d >= w else [])


def _f_hangar(p, room):
    x, z, w, d = p.rooms[room]
    # a shuttle on the floor (a solid wedge of boxes) with tool carts at the sides
    sw, sd = min(5.0, w * 0.45), min(7.0, d * 0.55)
    p.group(room, [("shuttle_hull", x + w / 2, z + d / 2, sw, 1.5, sd, "steel", True, 0.5), ("shuttle_nose", x + w / 2, z + d / 2 - sd * 0.5 - 0.0, sw * 0.5, 0.9, sd * 0.1, "grey_fabric", False, 0.6),
                   ("shuttle_glow", x + w / 2, z + d / 2, sw * 0.7, 0.05, sd * 0.4, "glow_teal", False, 2.0)])
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.6, 0.8, b_bench("steel", 0.95, 0.8, 1.6, "steel"), count=2, start=0.5, gap=0.5)
    place_along(p, room, sides[1], 1.4, 0.5, b_shelf(), count=3, start=0.5, gap=0.4)


def _f_core(p, room):
    x, z, w, d = p.rooms[room]
    reactor(p, room, x + w / 2, z + d / 2, min(2.0, min(w, d) * 0.18), min(2.4, p.ceiling_y - 0.35))
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 1.4, 0.55, b_console_wall(1.0), count=3, start=0.8, gap=0.4)
    place_along(p, room, sides[1], 1.4, 0.55, b_console_wall(1.0), count=3, start=0.8, gap=0.4)


def _f_airlock(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    place_along(p, room, sides[0], 0.7, 0.5, b_locker("white", 0.7, 1.9), count=2, start=0.3, gap=0.1)
    place_along(p, room, sides[1], 1.0, 0.4, b_console_wall(0.7), count=1, start=0.4)


def _f_bridge(p, room):
    pass


def _f_troop(p, room):
    x, z, w, d = p.rooms[room]
    sides = ("left", "right") if d >= w else ("nose", "tail")
    bench = b_bench("steel", 0.5, 0.7, 2.2, "grey_fabric")
    place_along(p, room, sides[0], 2.2, 0.7, bench, count=5, start=0.3, gap=0.3)
    place_along(p, room, sides[1], 2.2, 0.7, bench, count=5, start=0.3, gap=0.3)
    crate(p, room, x + w / 2, z + d - 2.0, 1.2, 0.9, True)
    place_along(p, room, "tail" if d >= w else "right", 1.4, 0.5, b_shelf(), count=2, start=0.4, gap=0.4)
