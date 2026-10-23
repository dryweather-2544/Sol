"""Engine nozzle detection from hull geometry (ship space: nose -z, tail +z).

A nozzle is a round, tail-facing, flat face: a connected patch of triangles whose normal points at the tail (+z), all at nearly the same z, whose outline is a ring
of at least six vertices roughly equidistant from its centre. Returns [(x, y, z, radius)] sorted by radius, largest first."""
import numpy as np


def detect_nozzles(ship_tris, length, min_radius=0.012, max_radius=0.2, min_verts=6, flat=0.9, cv_max=0.16, gap_max=1.6):
    a, b, c = ship_tris[:, 0], ship_tris[:, 1], ship_tris[:, 2]
    n = np.cross(b - a, c - a)
    ln = np.linalg.norm(n, axis=1)
    ok = ln > 1e-12
    n = n / np.maximum(ln, 1e-12)[:, None]
    centroid = ship_tris.mean(1)
    # winding is not trusted: orient away from the hull's middle
    outward = np.einsum("ij,ij->i", n, centroid - centroid.mean(0)) >= 0
    n = np.where(outward[:, None], n, -n)
    rear = ok & (n[:, 2] > flat)
    idx = np.nonzero(rear)[0]
    if len(idx) == 0:
        return []
    # union-find over triangles sharing a vertex (rounded) and lying in nearly the same z plane
    key = np.round(ship_tris[idx].reshape(-1, 3), 3)
    verts, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1, 3)
    parent = list(range(len(idx)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    owner = {}
    for t in range(len(idx)):
        for v in inv[t]:
            if v in owner:
                o = owner[v]
                if abs(centroid[idx[o], 2] - centroid[idx[t], 2]) < 0.06 * length / 10:
                    ra, rb = find(o), find(t)
                    if ra != rb:
                        parent[rb] = ra
            else:
                owner[v] = t
    groups = {}
    for t in range(len(idx)):
        groups.setdefault(find(t), []).append(t)
    found = []
    for g in groups.values():
        vid = np.unique(inv[g].reshape(-1))
        pts = verts[vid]
        if len(pts) < min_verts:
            continue
        cx, cy = pts[:, 0].mean(), pts[:, 1].mean()
        r = np.hypot(pts[:, 0] - cx, pts[:, 1] - cy)
        rmax = r.max()
        if rmax < min_radius * length or rmax > max_radius * length:
            continue
        outer = r > 0.75 * rmax
        if outer.sum() < min_verts:
            continue
        cv = r[outer].std() / r[outer].mean()
        if cv > cv_max:
            continue
        # outline roughly round: the outer vertices are spread right around the centre
        ang = np.sort(np.arctan2(pts[outer, 1] - cy, pts[outer, 0] - cx))
        gaps = np.diff(np.concatenate([ang, [ang[0] + 2 * np.pi]]))
        if gaps.max() > gap_max:
            continue
        found.append((float(cx), float(cy), float(pts[:, 2].mean()), float(rmax)))
    found.sort(key=lambda e: -e[3])
    return found


def dedupe(found, length):
    """Concentric or stacked rings at one nozzle count once: keep the one furthest back (largest radius on a tie)."""
    keep = []
    for e in sorted(found, key=lambda e: (-e[2], -e[3])):
        if all(np.hypot(e[0] - k[0], e[1] - k[1]) > 0.7 * max(e[3], k[3]) for k in keep):
            keep.append(e)
    return keep


def nozzles(ship_tris, length):
    found = dedupe(detect_nozzles(ship_tris, length), length)
    if not found:  # boxy engines: allow four-cornered, flatter outlines
        found = dedupe(detect_nozzles(ship_tris, length, min_verts=4, cv_max=0.4, gap_max=3.3, min_radius=0.02), length)
    return found


def select(found, length, limit=4, back_zone=0.09):
    """The engines that really push the ship: only the furthest-back nozzles, largest first, kept in mirrored pairs, at most `limit`."""
    if not found:
        return []
    zr = max(e[2] for e in found)
    cand = [e for e in found if e[2] > zr - back_zone * length]
    cand.sort(key=lambda e: -e[3])
    chosen = []
    for e in cand:
        if len(chosen) >= limit:
            break
        if abs(e[0]) < 0.05 * length:
            chosen.append(e)
            continue
        mirror = [m for m in cand if abs(m[0] + e[0]) < 0.06 * length and abs(m[1] - e[1]) < 0.06 * length and m is not e]
        if mirror and len(chosen) + 2 <= limit and not any(c is e or c is mirror[0] for c in chosen):
            chosen += [e, mirror[0]]
    chosen.sort(key=lambda e: e[0])
    return chosen
