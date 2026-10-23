#!/usr/bin/env python3
"""Design kit for Sol's big-ship interiors. Ships are authored in tools/gen_big_ships.py with this kit, which checks them (rooms do not
overlap, every door joins two rooms, every seat, door and crew spot can be walked to from the spawn point, furniture stays in its room,
nothing blocks a doorway), draws a floor plan of each, and writes src/bigship/big_ship_data.gd for the game to load.

Conventions match InteriorLayout: ship-local metres, x to starboard, z to the tail (nose at -z), rooms are (x, z, w, d) rectangles on one
deck, two rooms that share a wall stand GAP apart and the door is the GAP-thick strip between them. yaw 0 faces the nose (-z), positive
turns to port (-x).
"""
import math
import random
from collections import deque

import numpy as np

GAP = 0.2
RADIUS = 0.42         # a person for the checks: InteriorBody.RADIUS (0.3) plus a margin, so every lane we accept is comfortably wider than one
RES = 0.1             # raster cell, metres
DOOR_W = 1.4
CLEAR_DEPTH = 1.6     # how far in front of a door nothing solid may stand
MATERIALS = ["console", "steel", "white", "wood", "linen", "screen", "crate", "glow_teal", "glow_green", "glow_amber", "glow_red",
             "glass", "fabric", "carpet", "planter", "pipe", "dark", "grey_fabric", "red_fabric"]
KINDS = ["bridge", "captain", "corridor", "quarters", "galley", "mess", "medical", "cargo", "engineering", "lab", "armoury", "lounge",
         "greenhouse", "workshop", "ops", "airlock", "hangar", "core", "atrium", "storage", "brig", "comms", "observation", "troop"]


def _overlap(a, b, grow=0.0):
    return a[0] - grow < b[0] + b[2] and b[0] - grow < a[0] + a[2] and a[1] - grow < b[1] + b[3] and b[1] - grow < a[1] + a[3]


def _inside(inner, outer, eps=1e-6):
    return inner[0] >= outer[0] - eps and inner[1] >= outer[1] - eps and inner[0] + inner[2] <= outer[0] + outer[2] + eps and inner[1] + inner[3] <= outer[1] + outer[3] + eps


def facing(yaw):
    """Unit (x, z) a person faces at this yaw."""
    return (-math.sin(yaw), -math.cos(yaw))


class Plan:
    def __init__(self, ship_id, display_name, floor_y=0.0, ceiling_y=2.8, seed=1):
        self.id = ship_id
        self.name = display_name
        self.floor_y = floor_y
        self.ceiling_y = ceiling_y
        self.rng = random.Random(seed)
        self.rooms = {}
        self.kinds = {}
        self.names = {}
        self.portals = []
        self.seats = {}
        self.furniture = []
        self.windows = []
        self.npcs = []
        self.zones = {}      # room -> keep-clear rects in front of doors
        self.anchors = {}    # room -> [(x, z, label)] points that must stay reachable from each other
        self.spawn = None
        self.warnings = []

    # ---------------------------------------------------------------- rooms and doors
    def room(self, rid, x, z, w, d, kind, name=None):
        assert rid not in self.rooms, "room %s twice" % rid
        assert kind in KINDS, kind
        rect = (round(x, 3), round(z, 3), round(w, 3), round(d, 3))
        for other_id, other in self.rooms.items():
            assert not _overlap(rect, other, GAP - 0.01), "%s is too close to or overlaps %s" % (rid, other_id)
        self.rooms[rid] = rect
        self.kinds[rid] = kind
        self.names[rid] = name or rid.replace("_", " ").title()
        self.zones[rid] = []
        self.anchors[rid] = []
        return rect

    def below(self, rid):
        """z at which the next room may start below (toward the tail of) this one."""
        r = self.rooms[rid]
        return round(r[1] + r[3] + GAP, 3)

    def right_of(self, rid):
        r = self.rooms[rid]
        return round(r[0] + r[2] + GAP, 3)

    def link(self, a, b, at=None, width=DOOR_W, kind="door"):
        """A door between two rooms that stand GAP apart. `at` is where along the shared wall (x for a wall that runs along x)."""
        ra, rb = self.rooms[a], self.rooms[b]
        near = lambda u, v: abs(u - v) < 0.011
        if near(ra[1] + ra[3] + GAP, rb[1]) or near(rb[1] + rb[3] + GAP, ra[1]):
            upper, lower = (a, b) if near(ra[1] + ra[3] + GAP, rb[1]) else (b, a)
            ru, rl = self.rooms[upper], self.rooms[lower]
            lo, hi = max(ru[0], rl[0]), min(ru[0] + ru[2], rl[0] + rl[2])
            c = (lo + hi) / 2 if at is None else at
            assert hi - lo >= width + 0.4 and c - width / 2 - 0.2 >= lo - 1e-6 and c + width / 2 + 0.2 <= hi + 1e-6, "door %s-%s does not fit (%s..%s at %s)" % (a, b, lo, hi, c)
            wall_z = ru[1] + ru[3]
            opening = (round(c - width / 2, 3), round(wall_z, 3), width, GAP)
            self._add_zone(upper, (c - width / 2 - 0.3, wall_z - CLEAR_DEPTH, width + 0.6, CLEAR_DEPTH), (c, wall_z - 0.5))
            self._add_zone(lower, (c - width / 2 - 0.3, rl[1], width + 0.6, CLEAR_DEPTH), (c, rl[1] + 0.5))
        elif near(ra[0] + ra[2] + GAP, rb[0]) or near(rb[0] + rb[2] + GAP, ra[0]):
            left, right = (a, b) if near(ra[0] + ra[2] + GAP, rb[0]) else (b, a)
            rl_, rr = self.rooms[left], self.rooms[right]
            lo, hi = max(rl_[1], rr[1]), min(rl_[1] + rl_[3], rr[1] + rr[3])
            c = (lo + hi) / 2 if at is None else at
            assert hi - lo >= width + 0.4 and c - width / 2 - 0.2 >= lo - 1e-6 and c + width / 2 + 0.2 <= hi + 1e-6, "door %s-%s does not fit (%s..%s at %s)" % (a, b, lo, hi, c)
            wall_x = rl_[0] + rl_[2]
            opening = (round(wall_x, 3), round(c - width / 2, 3), GAP, width)
            self._add_zone(left, (wall_x - CLEAR_DEPTH, c - width / 2 - 0.3, CLEAR_DEPTH, width + 0.6), (wall_x - 0.5, c))
            self._add_zone(right, (rr[0], c - width / 2 - 0.3, CLEAR_DEPTH, width + 0.6), (rr[0] + 0.5, c))
        else:
            raise AssertionError("%s and %s do not share a wall" % (a, b))
        pid = "%s_%s_%s" % ("lock" if kind == "airlock_inner" else "door", a, b)
        self.portals.append({"id": pid, "kind": kind, "rect": tuple(round(v, 3) for v in opening), "rooms": (a, b)})
        return pid

    def outer_door(self, room, side, at=None, width=DOOR_W):
        """The airlock's outside door, in a room's wall on `side` (nose/tail/left/right)."""
        r = self.rooms[room]
        if side in ("nose", "tail"):
            c = r[0] + r[2] / 2 if at is None else at
            wall_z = r[1] - GAP if side == "nose" else r[1] + r[3]
            opening = (c - width / 2, wall_z, width, GAP)
            inner = r[1] if side == "nose" else r[1] + r[3] - CLEAR_DEPTH
            self._add_zone(room, (c - width / 2 - 0.3, inner, width + 0.6, CLEAR_DEPTH), (c, r[1] + 0.5 if side == "nose" else r[1] + r[3] - 0.5))
        else:
            c = r[1] + r[3] / 2 if at is None else at
            wall_x = r[0] - GAP if side == "left" else r[0] + r[2]
            opening = (wall_x, c - width / 2, GAP, width)
            inner = r[0] if side == "left" else r[0] + r[2] - CLEAR_DEPTH
            self._add_zone(room, (inner, c - width / 2 - 0.3, CLEAR_DEPTH, width + 0.6), (r[0] + 0.5 if side == "left" else r[0] + r[2] - 0.5, c))
        pid = "outer_%s" % room
        self.portals.append({"id": pid, "kind": "airlock_outer", "rect": tuple(round(v, 3) for v in opening), "rooms": (room,)})
        return pid

    def _add_zone(self, room, rect, anchor):
        r = self.rooms[room]
        x0, z0 = max(rect[0], r[0]), max(rect[1], r[1])
        x1, z1 = min(rect[0] + rect[2], r[0] + r[2]), min(rect[1] + rect[3], r[1] + r[3])
        self.zones[room].append((x0, z0, x1 - x0, z1 - z0))
        self.anchors[room].append((round(anchor[0], 3), round(anchor[1], 3), "door"))

    def window(self, room, side, center, width, sill=0.9, height=1.2):
        r = self.rooms[room]
        lo, hi = (r[0], r[0] + r[2]) if side in ("nose", "tail") else (r[1], r[1] + r[3])
        assert lo + 0.3 <= center - width / 2 and center + width / 2 <= hi - 0.3, "window of %s off its wall" % room
        for old in self.windows:
            if old["room"] == room and old["side"] == side:
                assert abs(old["center"] - center) >= (old["width"] + width) / 2 + 0.2, "windows of %s overlap" % room
        self.windows.append({"room": room, "side": side, "center": round(center, 3), "width": round(width, 3), "sill": sill, "height": height})

    # ---------------------------------------------------------------- furniture
    def _snapshot(self):
        return len(self.furniture), len(self.seats), {k: len(v) for k, v in self.anchors.items()}

    def _restore(self, snap):
        del self.furniture[snap[0]:]
        for k, n in snap[2].items():
            del self.anchors[k][n:]

    def piece(self, room, name, x, z, sx, sy, sz, mat, solid=False, lift=0.0, must=False, check=True):
        """One axis-aligned box on the floor of `room` (x, z its centre; sx/sy/sz its size). True if it was placed."""
        assert mat in MATERIALS, mat
        rect = (x - sx / 2, z - sz / 2, sx, sz)
        ok = _inside(rect, self.rooms[room], 1e-4)
        if ok and solid:
            ok = not any(_overlap(rect, zone) for zone in self.zones[room])
            ok = ok and not any(f["solid"] and f["room"] == room and _overlap(rect, f["rect"]) for f in self.furniture)
        if ok:
            self.furniture.append({"room": room, "name": name, "rect": rect, "x": round(x, 3), "z": round(z, 3), "size": (round(sx, 3), round(sy, 3), round(sz, 3)),
                                   "lift": round(lift, 3), "mat": mat, "solid": solid})
            if solid and check and not self._room_connected(room):
                self.furniture.pop()
                ok = False
        if not ok and must:
            raise AssertionError("could not place %s in %s at (%.2f, %.2f)" % (name, room, x, z))
        return ok

    def group(self, room, pieces, must=False):
        """All of these pieces, or none. Each is a tuple (name, x, z, sx, sy, sz, mat, solid, lift)."""
        snap = self._snapshot()
        for (name, x, z, sx, sy, sz, mat, solid, lift) in pieces:
            if not self.piece(room, name, x, z, sx, sy, sz, mat, solid, lift):
                self._restore(snap)
                if must:
                    raise AssertionError("could not place group %s in %s" % (pieces[0][0], room))
                return False
        return True

    def seat(self, room, sid, role, x, z, yaw, mat="fabric", console=True, console_w=1.3, exit_side="back", must=True):
        """A seat with a chair (solid) and, in front of it, a console with a lit screen. The exit spot is where the sitter stands up."""
        fx, fz = facing(yaw)
        rx, rz = -fz, fx   # the sitter's right
        ex = {"back": (-fx, -fz), "left": (-rx, -rz), "right": (rx, rz)}[exit_side]
        exit_at = (round(x + ex[0] * 0.95, 3), round(z + ex[1] * 0.95, 3))
        alongx = abs(fx) > 0.5
        chair = [("chair_base", x, z, 0.55, 0.42, 0.55, "steel", True, 0.0),
                 ("chair_seat", x, z, 0.52, 0.1, 0.52, mat, False, 0.42),
                 ("chair_back", x - fx * 0.24, z - fz * 0.24, 0.1 if alongx else 0.5, 0.6, 0.5 if alongx else 0.1, mat, False, 0.5)]
        if not self.group(room, chair):
            if must:
                raise AssertionError("no room for seat %s" % sid)
            return False
        self.anchors[room].append((exit_at[0], exit_at[1], "exit:" + sid))
        if not self._room_connected(room):
            raise AssertionError("seat %s exit is shut in" % sid)
        self.seats[sid] = {"id": sid, "role": role, "room": room, "x": round(x, 3), "z": round(z, 3), "yaw": round(yaw, 4), "exit": exit_at}
        if console:
            cx, cz = x + fx * 0.97, z + fz * 0.97
            across = console_w
            sx_, sz_ = (0.5, across) if alongx else (across, 0.5)
            parts = [("console", cx, cz, sx_, 1.0, sz_, "console", True, 0.0),
                     ("screen", cx - fx * 0.2, cz - fz * 0.2, 0.05 if alongx else across * 0.8, 0.34, across * 0.8 if alongx else 0.05, "screen", False, 1.0)]
            if not self.group(room, parts):
                self.warnings.append("seat %s has no console" % sid)
        return True

    def row(self, room, side, items, start=0.0, margin=0.12, step=0.25, stop=None):
        """Furniture standing against one wall of `room` ("left"/"right"/"nose"/"tail"). items: (name, along, depth, height, mat, solid, lift, gap_after).
        Each item takes the first free spot at or after the cursor. Returns the number placed."""
        x, z, w, d = self.rooms[room]
        placed = 0
        cursor = start
        length = d if side in ("left", "right") else w
        stop = length if stop is None else stop
        for (name, along, depth, height, mat, solid, lift, gap_after) in items:
            spot = cursor
            done = False
            while spot + along <= stop + 1e-6:
                mid = spot + along / 2
                if side == "left":
                    ok = self.piece(room, name, x + margin + depth / 2, z + mid, depth, height, along, mat, solid, lift)
                elif side == "right":
                    ok = self.piece(room, name, x + w - margin - depth / 2, z + mid, depth, height, along, mat, solid, lift)
                elif side == "nose":
                    ok = self.piece(room, name, x + mid, z + margin + depth / 2, along, height, depth, mat, solid, lift)
                else:
                    ok = self.piece(room, name, x + mid, z + d - margin - depth / 2, along, height, depth, mat, solid, lift)
                if ok:
                    cursor = spot + along + gap_after
                    placed += 1
                    done = True
                    break
                spot += step
            if not done:
                continue
        return placed

    def npc(self, room, role, x, z, yaw):
        self.npcs.append({"room": room, "role": role, "x": round(x, 3), "z": round(z, 3), "yaw": round(yaw, 4)})

    # ---------------------------------------------------------------- walkability (same rules as InteriorLayout.is_position_walkable)
    def _local_mask(self, room):
        """Where a person (radius RADIUS) can stand in one room, as a grid [z][x] with the cell-centre coordinates."""
        x, z, w, d = self.rooms[room]
        nx, nz = int(round(w / RES)), int(round(d / RES))
        xs = x + (np.arange(nx) + 0.5) * RES
        zs = z + (np.arange(nz) + 0.5) * RES
        okx = (xs >= x + RADIUS - 1e-9) & (xs <= x + w - RADIUS + 1e-9)
        okz = (zs >= z + RADIUS - 1e-9) & (zs <= z + d - RADIUS + 1e-9)
        mask = okz[:, None] & okx[None, :]
        for f in self.furniture:
            if f["room"] == room and f["solid"]:
                rx, rz, rw, rd = f["rect"]
                blocked = ((xs > rx - RADIUS) & (xs < rx + rw + RADIUS))[None, :] & ((zs > rz - RADIUS) & (zs < rz + rd + RADIUS))[:, None]
                mask = mask & ~blocked
        return mask, xs, zs

    def free_spot(self, room, near, keep_door=1.1, keep_seat=1.0, keep_npc=1.4, keep_solid=0.35):
        """The walkable spot in `room` closest to `near` that is clear of doors, seat exits, other crew and furniture."""
        mask, xs, zs = self._local_mask(room)
        grid_x, grid_z = np.meshgrid(xs, zs)
        ok = mask.copy()
        for (ax, az, label) in self.anchors[room]:
            ok &= (np.hypot(grid_x - ax, grid_z - az) >= (keep_door if label == "door" else keep_seat))
        for n in self.npcs:
            if n["room"] == room:
                ok &= (np.hypot(grid_x - n["x"], grid_z - n["z"]) >= keep_npc)
        for f in self.furniture:
            if f["room"] == room and f["solid"]:
                rx, rz, rw, rd = f["rect"]
                blocked = ((grid_x > rx - RADIUS - keep_solid) & (grid_x < rx + rw + RADIUS + keep_solid) & (grid_z > rz - RADIUS - keep_solid) & (grid_z < rz + rd + RADIUS + keep_solid))
                ok &= ~blocked
        if not ok.any():
            return None
        dist = np.hypot(grid_x - near[0], grid_z - near[1])
        dist[~ok] = 1e9
        i, j = np.unravel_index(int(np.argmin(dist)), dist.shape)
        return (round(float(xs[j]), 2), round(float(zs[i]), 2))

    def npc_auto(self, room, role, near=None, yaw=None):
        r = self.rooms[room]
        centre = (r[0] + r[2] / 2, r[1] + r[3] / 2)
        spot = self.free_spot(room, near or centre)
        if spot is None:
            self.warnings.append("no free spot for %s in %s" % (role, room))
            return False
        if yaw is None:
            yaw = math.atan2(-(centre[0] - spot[0]), -(centre[1] - spot[1])) if (abs(centre[0] - spot[0]) + abs(centre[1] - spot[1])) > 0.5 else 0.0
        self.npc(room, role, spot[0], spot[1], yaw)
        return True

    def _room_connected(self, room):
        mask, xs, zs = self._local_mask(room)
        x, z, w, d = self.rooms[room]
        nx, nz = len(xs), len(zs)
        points = self.anchors[room]
        if len(points) < 2:
            return True
        cells = []
        for (ax, az, label) in points:
            i, j = int((az - z) / RES), int((ax - x) / RES)
            if not (0 <= i < nz and 0 <= j < nx) or not mask[i, j]:
                return False
            cells.append((i, j))
        reach = np.zeros_like(mask)
        reach[cells[0]] = True
        while True:
            grown = reach.copy()
            grown[1:, :] |= reach[:-1, :]
            grown[:-1, :] |= reach[1:, :]
            grown[:, 1:] |= reach[:, :-1]
            grown[:, :-1] |= reach[:, 1:]
            grown &= mask
            if (grown == reach).all():
                break
            reach = grown
        return all(reach[c] for c in cells)

    def raster(self):
        xs0 = min(r[0] for r in self.rooms.values()) - 2.0
        zs0 = min(r[1] for r in self.rooms.values()) - 2.0
        xs1 = max(r[0] + r[2] for r in self.rooms.values()) + 2.0
        zs1 = max(r[1] + r[3] for r in self.rooms.values()) + 2.0
        nx, nz = int(math.ceil((xs1 - xs0) / RES)), int(math.ceil((zs1 - zs0) / RES))
        xs = xs0 + (np.arange(nx) + 0.5) * RES
        zs = zs0 + (np.arange(nz) + 0.5) * RES
        point_ok = np.zeros((nz, nx), bool)

        def fill(rect, grid):
            rx, rz, rw, rd = rect
            inx = (xs >= rx) & (xs < rx + rw)
            inz = (zs >= rz) & (zs < rz + rd)
            grid[np.ix_(inz, inx)] = True

        for rect in self.rooms.values():
            fill(rect, point_ok)
        for portal in self.portals:
            if portal["kind"] != "airlock_outer":
                fill(portal["rect"], point_ok)
        k = int(round(RADIUS / RES))
        padded = np.pad(point_ok, k)
        walk = point_ok.copy()
        for dz in (-k, k):
            for dx in (-k, k):
                walk &= padded[k + dz:k + dz + nz, k + dx:k + dx + nx]
        for f in self.furniture:
            if f["solid"]:
                rx, rz, rw, rd = f["rect"]
                inx = (xs > rx - RADIUS) & (xs < rx + rw + RADIUS)
                inz = (zs > rz - RADIUS) & (zs < rz + rd + RADIUS)
                walk[np.ix_(inz, inx)] = False
        return walk, xs0, zs0

    def reachable(self):
        walk, x0, z0 = self.raster()
        sx, sz = self.spawn[0], self.spawn[1]
        start = (int((sz - z0) / RES), int((sx - x0) / RES))
        assert walk[start], "spawn is not walkable"
        seen = np.zeros_like(walk)
        seen[start] = True
        queue = deque([start])
        nz, nx = walk.shape
        while queue:
            i, j = queue.popleft()
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                a, b = i + di, j + dj
                if 0 <= a < nz and 0 <= b < nx and walk[a, b] and not seen[a, b]:
                    seen[a, b] = True
                    queue.append((a, b))
        return seen, walk, x0, z0

    def validate(self):
        problems = []
        ids = list(self.rooms)
        for i, a in enumerate(ids):
            for b in ids[i + 1:]:
                if _overlap(self.rooms[a], self.rooms[b], GAP - 0.01):
                    problems.append("%s and %s overlap or are closer than a wall" % (a, b))
        for portal in self.portals:
            if portal["kind"] == "airlock_outer":
                continue
            grown = (portal["rect"][0] - 0.05, portal["rect"][1] - 0.05, portal["rect"][2] + 0.1, portal["rect"][3] + 0.1)
            touching = [rid for rid, r in self.rooms.items() if _overlap(r, grown)]
            if sorted(touching) != sorted(portal["rooms"]):
                problems.append("door %s touches %s, wanted %s" % (portal["id"], touching, portal["rooms"]))
        for rid in ids:
            if not any(rid in p["rooms"] for p in self.portals):
                problems.append("room %s has no door" % rid)
        for f in self.furniture:
            if not _inside(f["rect"], self.rooms[f["room"]], 1e-4):
                problems.append("%s sticks out of %s" % (f["name"], f["room"]))
        for w in self.windows:
            r = self.rooms[w["room"]]
            t = GAP
            skin = {"nose": (r[0] - t, r[1] - t, r[2] + 2 * t, t), "tail": (r[0] - t, r[1] + r[3], r[2] + 2 * t, t),
                    "left": (r[0] - t, r[1], t, r[3]), "right": (r[0] + r[2], r[1], t, r[3])}[w["side"]]
            for p in self.portals:
                if _overlap(skin, p["rect"]):
                    lo, hi = (p["rect"][0], p["rect"][0] + p["rect"][2]) if w["side"] in ("nose", "tail") else (p["rect"][1], p["rect"][1] + p["rect"][3])
                    if lo < w["center"] + w["width"] / 2 + 0.1 and hi > w["center"] - w["width"] / 2 - 0.1:
                        problems.append("a window of %s runs into door %s" % (w["room"], p["id"]))
        if self.spawn is None:
            problems.append("no spawn")
            return problems
        seen, walk, x0, z0 = self.reachable()

        def reached(x, z):
            i, j = int((z - z0) / RES), int((x - x0) / RES)
            return bool(seen[i, j])

        for sid, s in self.seats.items():
            if not reached(*s["exit"]):
                problems.append("seat %s: exit not reachable from the spawn" % sid)
            sx_, sz_ = s["exit"]
            r = self.rooms[s["room"]]
            if not (r[0] + RADIUS <= sx_ <= r[0] + r[2] - RADIUS and r[1] + RADIUS <= sz_ <= r[1] + r[3] - RADIUS):
                problems.append("seat %s: exit outside its room" % sid)
        for rid, pts in self.anchors.items():
            for (ax, az, label) in pts:
                if not reached(ax, az):
                    problems.append("%s: %s at (%.1f, %.1f) not reachable from the spawn" % (rid, label, ax, az))
        for n in self.npcs:
            if not reached(n["x"], n["z"]):
                problems.append("crew %s in %s stands where nobody can walk" % (n["role"], n["room"]))
        return problems

    # ---------------------------------------------------------------- output
    def to_gd_dict(self):
        def num(v):
            return round(float(v), 3)

        seats = []
        for s in self.seats.values():
            seats.append([s["id"], s["role"], s["room"], num(s["x"]), num(s["z"]), s["yaw"], num(s["exit"][0]), num(s["exit"][1])])
        return {
            "name": self.name, "floor_y": self.floor_y, "ceiling_y": self.ceiling_y, "spawn": [num(v) for v in self.spawn],
            "rooms": {k: [num(v) for v in r] for k, r in self.rooms.items()},
            "kinds": dict(self.kinds), "names": dict(self.names),
            "portals": [[p["id"], p["kind"]] + [num(v) for v in p["rect"]] for p in self.portals],
            "seats": seats,
            "furniture": [[f["name"], f["x"], f["z"], f["size"][0], f["size"][1], f["size"][2], f["lift"], f["mat"], f["solid"]] for f in self.furniture],
            "windows": [[w["room"], w["side"], w["center"], w["width"], w["sill"], w["height"]] for w in self.windows],
            "npcs": [[n["role"], n["room"], n["x"], n["z"], n["yaw"]] for n in self.npcs],
        }


def gd_literal(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        text = repr(round(value, 4))
        return "0.0" if text in ("-0.0",) else text
    if isinstance(value, str):
        return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"')
    if isinstance(value, (list, tuple)):
        if all(not isinstance(v, (list, tuple, dict)) for v in value):
            return "[" + ", ".join(gd_literal(v) for v in value) + "]"
        inner = ",\n".join(pad + "\t" + gd_literal(v, indent + 1) for v in value)
        return "[\n" + inner + "\n" + pad + "]"
    if isinstance(value, dict):
        inner = ",\n".join(pad + "\t" + gd_literal(str(k)) + ": " + gd_literal(v, indent + 1) for k, v in value.items())
        return "{\n" + inner + "\n" + pad + "}"
    raise TypeError(type(value))


# -------------------------------------------------------------------- floor plans
KIND_COLOURS = {"bridge": "#b9d3f2", "captain": "#f2d9b9", "corridor": "#e4e4e4", "quarters": "#f3e6c4", "galley": "#f2c9c9", "mess": "#f4d9d0",
                "medical": "#cdf0dc", "cargo": "#d8d2c2", "engineering": "#f5d594", "lab": "#c6ecef", "armoury": "#d7c6c6", "lounge": "#e6cdf0",
                "greenhouse": "#c9e8b4", "workshop": "#e8dcb0", "ops": "#c9d0f5", "airlock": "#f0b8b8", "hangar": "#cfcfdc", "core": "#f5c9a0",
                "atrium": "#e0f0c9", "storage": "#d0d0c0", "brig": "#d9d9d9", "comms": "#cfe3f5", "observation": "#d6e4f7", "troop": "#d5d9c0"}


def draw_plan(plan, path, scale=1.0):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Rectangle, FancyArrow

    xs0 = min(r[0] for r in plan.rooms.values()) - 3
    xs1 = max(r[0] + r[2] for r in plan.rooms.values()) + 3
    zs0 = min(r[1] for r in plan.rooms.values()) - 3
    zs1 = max(r[1] + r[3] for r in plan.rooms.values()) + 3
    width_in = max(6.0, (xs1 - xs0) * 0.22 * scale)
    height_in = max(6.0, (zs1 - zs0) * 0.22 * scale)
    fig, ax = plt.subplots(figsize=(width_in, height_in))
    ax.set_xlim(xs0, xs1)
    ax.set_ylim(zs1, zs0)   # nose (-z) at the top
    ax.set_aspect("equal")
    ax.set_title("%s - nose at the top" % plan.name)
    for rid, r in plan.rooms.items():
        ax.add_patch(Rectangle((r[0], r[1]), r[2], r[3], fc=KIND_COLOURS.get(plan.kinds[rid], "#dddddd"), ec="#222", lw=1.2))
        ax.text(r[0] + r[2] / 2, r[1] + 0.4, plan.names[rid], ha="center", va="top", fontsize=6, color="#222")
    for f in plan.furniture:
        rx, rz, rw, rd = f["rect"]
        face = {"screen": "#2a6", "glow_teal": "#3bd", "glow_amber": "#fb3", "glow_green": "#6c6", "glow_red": "#e44", "glass": "#9cf", "carpet": "#c99", "planter": "#7b5"}.get(f["mat"], "#555" if f["solid"] else "#aaa")
        ax.add_patch(Rectangle((rx, rz), rw, rd, fc=face, ec="none", alpha=0.9 if f["solid"] else 0.55))
    for p in plan.portals:
        rx, rz, rw, rd = p["rect"]
        ax.add_patch(Rectangle((rx, rz), rw, rd, fc="#e07000" if p["kind"] != "airlock_outer" else "#c00", ec="none"))
    for w in plan.windows:
        r = plan.rooms[w["room"]]
        c, h = w["center"], w["width"] / 2
        if w["side"] == "nose":
            ax.plot([c - h, c + h], [r[1] - 0.1, r[1] - 0.1], color="#09f", lw=3)
        elif w["side"] == "tail":
            ax.plot([c - h, c + h], [r[1] + r[3] + 0.1, r[1] + r[3] + 0.1], color="#09f", lw=3)
        elif w["side"] == "left":
            ax.plot([r[0] - 0.1, r[0] - 0.1], [c - h, c + h], color="#09f", lw=3)
        else:
            ax.plot([r[0] + r[2] + 0.1, r[0] + r[2] + 0.1], [c - h, c + h], color="#09f", lw=3)
    for sid, s in plan.seats.items():
        fx, fz = facing(s["yaw"])
        ax.add_patch(FancyArrow(s["x"] - fx * 0.2, s["z"] - fz * 0.2, fx * 0.5, fz * 0.5, width=0.28, head_width=0.5, head_length=0.3, fc="#c00" if s["role"] == "captain" else "#036", ec="none"))
    for n in plan.npcs:
        ax.plot([n["x"]], [n["z"]], "o", color="#a0a", ms=4)
    ax.plot([plan.spawn[0]], [plan.spawn[1]], "*", color="k", ms=10)
    ax.grid(True, lw=0.2)
    fig.tight_layout()
    fig.savefig(path, dpi=80)
    plt.close(fig)
