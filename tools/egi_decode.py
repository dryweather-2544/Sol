#!/usr/bin/env python3
"""Decode Rodina's binary interior map (Data/Interiors/DefaultMap.egi) into JSON plus a top-down ASCII map per level.

Format (worked out from the file; the loader is native code, so it is not in the Lua):
  u32 N                      byte offset where the name table ends
  repeat until N: u32 id, NUL-terminated name
  then a typed stream:   0x04 bool(1 byte)  0x05 float64  0x06 uint32  0x07 3 x float32  0x08 3 x float64
                         0x0b u32 name id (a field name, or a name used as a value)
                         0x0c begin container ... 0x00 end container
  A container (and the top level) is a run of key,value pairs: keys are name ids for structs, float64 indices for lists.

Grid facts, checked against Airlock.egi: cells are 2 m wide and 3 m high, OriginCoord is the airlock-out door cell (13, 9, 2),
and an object at Position (px, py, pz) sits in cell (OriginX + px/2, OriginY + py/2) at level OriginZ + pz/3.

Usage: tools/egi_decode.py DefaultMap.egi OUT_DIR [Airlock.egi]
"""
import json
import math
import struct
import sys
from pathlib import Path

OBJECT_MARKS = {"Bed": "B", "Toilet": "T", "ShipStatus": "S", "LimnalDrive": "L", "PilotStation": "P", "Generator": "G",
                "BatteryArray": "A", "FTL_Radio": "R", "Scanners": "C", "Airlock": "X", "Stairs2": "^", "StairsWide": "^",
                "Sink": "k", "Desk": "d", "Crate": "c", "StorageCloset": "s", "Archives": "r", "Holoscreen": "h"}


def read_names(data):
    end = struct.unpack_from("<I", data, 0)[0]
    pos, names = 4, {}
    while pos < end:
        name_id = struct.unpack_from("<I", data, pos)[0]
        stop = data.index(b"\0", pos + 4)
        names[name_id] = data[pos + 4:stop].decode()
        pos = stop + 1
    return names, pos


class Reader:
    def __init__(self, data, names, pos):
        self.d, self.names, self.p = data, names, pos

    def value(self):
        d, t = self.d, self.d[self.p]
        self.p += 1
        if t == 4:
            self.p += 1
            return bool(d[self.p - 1])
        if t == 5:
            self.p += 8
            return struct.unpack_from("<d", d, self.p - 8)[0]
        if t == 6:
            self.p += 4
            return struct.unpack_from("<I", d, self.p - 4)[0]
        if t == 7:
            self.p += 12
            return list(struct.unpack_from("<3f", d, self.p - 12))
        if t == 8:
            self.p += 24
            return list(struct.unpack_from("<3d", d, self.p - 24))
        if t == 0x0b:
            self.p += 4
            return self.names[struct.unpack_from("<I", d, self.p - 4)[0]]
        if t == 0x0c:
            out = {}
            while d[self.p] != 0:
                key = self.value()
                out[str(key)] = self.value()
            self.p += 1
            return out
        raise ValueError("unknown type 0x%02x at offset %d" % (t, self.p - 1))

    def top(self):
        out = {}
        while self.p < len(self.d) and any(self.d[self.p:]):  # the stream ends with padding zeros
            key = self.value()
            out[str(key)] = self.value()
        return out


def decode(path):
    data = Path(path).read_bytes()
    names, pos = read_names(data)
    return Reader(data, names, pos).top(), len(names)


def interpret(tree):
    ox, oy, oz = tree["OriginCoord"]
    rooms, cell_room = [], {}
    for key, room in tree["Rooms"].items():
        if not isinstance(room, dict):
            continue
        cells = [(int(c["CoordX"]), int(c["CoordY"]), int(c["CoordZ"])) for c in room["Coords"].values() if isinstance(c, dict)]
        for cell in cells:
            cell_room[cell] = int(float(key))
        rooms.append({"id": int(float(key)), "kind": room["DefaultTileset"], "entrance": room["IsEntrance"], "cells": [list(c) for c in sorted(cells)],
                      "levels": sorted({c[2] for c in cells}), "min": [min(c[i] for c in cells) for i in range(3)], "max": [max(c[i] for c in cells) for i in range(3)],
                      "doors_to": [{"room": int(v["OtherRoomID"]), "door": int(v["DoorLocalID"])} for v in room["RoomDoors"].values() if isinstance(v, dict)]})
    doors = [{"index": int(float(k)), "type": v["Type"], "id": v["LocalID"], "cell": [int(v["CoordX"]), int(v["CoordY"]), int(v["CoordZ"])],
              "direction": int(v["Direction"]), "entrance": v["IsEntrance"]} for k, v in tree["Doors"].items() if isinstance(v, dict)]
    objects = []
    for k, v in tree["InteriorObject"].items():
        if not isinstance(v, dict):
            continue
        px, py, pz = v["Position"]
        cell = [math.floor(ox + px / 2.0), math.floor(oy + py / 2.0), round(oz + pz / 3.0)]
        objects.append({"index": int(float(k)), "type": v["Type"], "position": v["Position"], "yaw_pitch_roll": v["Rotation"], "cell": cell,
                        "room": cell_room.get(tuple(cell), cell_room.get((cell[0], cell[1], 2), cell_room.get((cell[0], cell[1], 3), -1))), "entrance": v["IsEntrance"]})
    return {"grid": {"width": int(tree["GridWidth"]), "depth": int(tree["GridDepth"]), "height": int(tree["GridHeight"]),
                     "cell_width_m": tree["GridCellWidth"], "cell_height_m": tree["GridCellHeight"], "origin_cell": [int(ox), int(oy), int(oz)],
                     "bounds_mesh": tree["BoundsPath"]},
            "rooms": sorted(rooms, key=lambda r: r["id"]), "doors": sorted(doors, key=lambda d: d["index"]), "objects": sorted(objects, key=lambda o: o["index"])}


def ascii_levels(layout):
    grid = layout["grid"]
    room_cells = {}
    for room in layout["rooms"]:
        for c in room["cells"]:
            room_cells[tuple(c)] = room["id"]
    levels = sorted({c[2] for c in room_cells} | {d["cell"][2] for d in layout["doors"]})
    pages = {}
    for level in levels:
        canvas = [["." for _ in range(grid["width"])] for _ in range(grid["depth"])]
        for (x, y, z), room_id in room_cells.items():
            if z == level:
                canvas[y][x] = chr(ord("a") + room_id % 26)
        for door in layout["doors"]:
            x, y, z = door["cell"]
            if z == level:
                canvas[y][x] = "+"
        for obj in layout["objects"]:
            x, y, z = obj["cell"]
            if z == level and obj["type"] in OBJECT_MARKS and 0 <= y < grid["depth"] and 0 <= x < grid["width"]:
                canvas[y][x] = OBJECT_MARKS[obj["type"]]
        rows = ["".join(row).rstrip(".") for row in canvas]
        while rows and rows[-1] == "":
            rows.pop()
        pages[level] = "\n".join("%2d %s" % (i, row) for i, row in enumerate(rows))
    return pages


def check_against_airlock(layout, airlock_path):
    """Airlock.egi is the text version of the entrance room; the same room and doors must be in the binary map."""
    lines = Path(airlock_path).read_text().replace("\r", "").split("\n")
    airlock_cells = set()
    for i, line in enumerate(lines):
        if line == "BEGIN ROOM COORDS":
            count = int(lines[i + 1])
            for n in range(count):
                x, y, z = (int(lines[i + 2 + n * 7 + k]) for k in range(3))
                airlock_cells.add((x, y, z))
    entrance = [r for r in layout["rooms"] if r["entrance"]]
    problems = []
    if not entrance or {tuple(c) for c in entrance[0]["cells"]} != airlock_cells:
        problems.append("entrance room cells differ from Airlock.egi: %s vs %s" % ([r["cells"] for r in entrance], sorted(airlock_cells)))
    door_types = {d["type"] for d in layout["doors"] if d["entrance"]}
    if not {"DoorAirlockIn", "DoorAirlockOut"} <= door_types:
        problems.append("airlock doors missing from the binary map: %s" % door_types)
    if layout["grid"]["origin_cell"] != [13, 9, 2]:
        problems.append("origin cell is not Airlock.egi's header triple 13 9 2")
    return problems


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    tree, name_count = decode(sys.argv[1])
    layout = interpret(tree)
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "default_map.json").write_text(json.dumps(layout, indent=1))
    pages = ascii_levels(layout)
    for level, page in pages.items():
        (out / ("level_%d.txt" % level)).write_text(page + "\n")
    print("%d names, %d rooms, %d doors, %d objects, levels %s" % (name_count, len(layout["rooms"]), len(layout["doors"]), len(layout["objects"]), sorted(pages)))
    if len(sys.argv) > 3:
        problems = check_against_airlock(layout, sys.argv[3])
        print("Airlock.egi cross-check:", "OK" if not problems else problems)
        sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
