#!/usr/bin/env python3
"""Reads ASCII or binary FBX (7.x): per-model world-space bounds of its geometry. Usage: fbxprobe.py file.fbx [--meshes]"""
import re, struct, sys, zlib
import numpy as np


class Node:
    def __init__(self, name):
        self.name = name
        self.props = []
        self.kids = []

    def find(self, name):
        return [k for k in self.kids if k.name == name]

    def first(self, name):
        f = self.find(name)
        return f[0] if f else None


def parse_binary(data):
    ver = struct.unpack_from('<I', data, 23)[0]
    wide = ver >= 7500
    pos = 27
    root = Node('root')

    def read_node(pos):
        if wide:
            end, nprops, plen = struct.unpack_from('<QQQ', data, pos); pos += 24
        else:
            end, nprops, plen = struct.unpack_from('<III', data, pos); pos += 12
        nlen = data[pos]; pos += 1
        if end == 0:
            return None, pos
        name = data[pos:pos + nlen].decode('latin1'); pos += nlen
        node = Node(name)
        for _ in range(nprops):
            t = chr(data[pos]); pos += 1
            if t in 'YCIFDL':
                fmt = {'Y': '<h', 'C': '<?', 'I': '<i', 'F': '<f', 'D': '<d', 'L': '<q'}[t]
                node.props.append(struct.unpack_from(fmt, data, pos)[0]); pos += struct.calcsize(fmt)
            elif t in 'fdlib':
                n, enc, clen = struct.unpack_from('<III', data, pos); pos += 12
                dt = {'f': '<f4', 'd': '<f8', 'l': '<i8', 'i': '<i4', 'b': 'u1'}[t]
                raw = data[pos:pos + clen]; pos += clen
                if enc:
                    raw = zlib.decompress(raw)
                node.props.append(np.frombuffer(raw, dtype=dt, count=n))
            elif t in 'SR':
                n = struct.unpack_from('<I', data, pos)[0]; pos += 4
                raw = data[pos:pos + n]; pos += n
                node.props.append(raw.decode('latin1') if t == 'S' else raw)
        header = 24 if wide else 12
        while pos < end:
            kid, pos = read_node(pos)
            if kid is None:
                break
            node.kids.append(kid)
        return node, end

    while pos < len(data) - 200:
        n, pos = read_node(pos)
        if n is None:
            break
        root.kids.append(n)
    return root


def parse_ascii(text):
    root = Node('root')
    stack = [root]
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip(); i += 1
        if not line or line.startswith(';'):
            continue
        if line == '}':
            stack.pop(); continue
        m = re.match(r'^([A-Za-z0-9_]+):\s*(.*)$', line)
        if not m:
            continue
        name, rest = m.group(1), m.group(2)
        node = Node(name)
        opens = rest.endswith('{')
        if opens:
            rest = rest[:-1].strip()
        if rest.startswith('*') and opens:  # array: *N { a: ... }
            # gather until closing brace
            body = []
            while i < len(lines):
                l = lines[i].strip(); i += 1
                if l == '}':
                    break
                body.append(l[2:] if l.startswith('a:') else l)
            txt = ''.join(body).replace(' ', '')
            node.props = [np.array([float(x) for x in txt.split(',') if x != ''])]
            stack[-1].kids.append(node)
            continue
        props = []
        for tok in re.findall(r'"[^"]*"|[^,\s][^,]*', rest):
            tok = tok.strip()
            if tok.startswith('"'):
                props.append(tok.strip('"'))
            else:
                try:
                    props.append(int(tok))
                except ValueError:
                    try:
                        props.append(float(tok))
                    except ValueError:
                        props.append(tok)
        node.props = props
        stack[-1].kids.append(node)
        if opens:
            stack.append(node)
    return root


def load(path):
    data = open(path, 'rb').read()
    if data.startswith(b'Kaydara FBX Binary'):
        return parse_binary(data)
    return parse_ascii(data.decode('latin1'))


def euler(rx, ry, rz):
    rx, ry, rz = np.radians([rx, ry, rz])
    cx, sx, cy, sy, cz, sz = np.cos(rx), np.sin(rx), np.cos(ry), np.sin(ry), np.cos(rz), np.sin(rz)
    X = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Z = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Z @ Y @ X


def local_matrix(model):
    props = {}
    p70 = model.first('Properties70')
    if p70:
        for p in p70.kids:
            if p.props and len(p.props) >= 5:
                props[p.props[0]] = [float(v) for v in p.props[4:]]
    t = props.get('Lcl Translation', [0, 0, 0])
    r = props.get('Lcl Rotation', [0, 0, 0])
    s = props.get('Lcl Scaling', [1, 1, 1])
    pre = props.get('PreRotation', [0, 0, 0])
    post = props.get('PostRotation', [0, 0, 0])
    M = np.eye(4)
    R = euler(*pre) @ euler(*r) @ np.linalg.inv(euler(*post))
    M[:3, :3] = R @ np.diag(s)
    M[:3, 3] = t
    return M


def analyse(path):
    root = load(path)
    objs = root.first('Objects')
    conns = root.first('Connections')
    models, geos = {}, {}
    for o in objs.kids:
        if o.name == 'Model':
            models[o.props[0]] = (str(o.props[1]).split('\x00')[0], o)
        elif o.name == 'Geometry':
            geos[o.props[0]] = o
    parent = {}
    geo_of = {}
    for c in conns.kids:
        if c.name != 'C' or c.props[0] != 'OO':
            continue
        child, par = c.props[1], c.props[2]
        if child in models:
            parent[child] = par
        elif child in geos and par in models:
            geo_of.setdefault(par, []).append(child)
    world = {}

    def wm(mid):
        if mid in world:
            return world[mid]
        m = local_matrix(models[mid][1])
        p = parent.get(mid)
        if p in models:
            m = wm(p) @ m
        world[mid] = m
        return m

    out = []
    for mid, (name, node) in models.items():
        for g in geo_of.get(mid, []):
            v = geos[g].first('Vertices')
            if v is None:
                continue
            pts = np.asarray(v.props[0], dtype=float).reshape(-1, 3)
            M = wm(mid)
            w = (M[:3, :3] @ pts.T).T + M[:3, 3]
            out.append((name.split('::')[-1], w.min(0), w.max(0), len(pts)))
    unit = 1.0
    gs = root.first('GlobalSettings')
    if gs and gs.first('Properties70'):
        for p in gs.first('Properties70').kids:
            if p.props and p.props[0] == 'UnitScaleFactor':
                unit = float(p.props[4])
    return out, unit


def mesh_points(path):
    """name -> (N,3) world-space vertices in metres (FBX units are cm)."""
    root = load(path)
    objs = root.first('Objects')
    conns = root.first('Connections')
    models, geos = {}, {}
    for o in objs.kids:
        if o.name == 'Model':
            models[o.props[0]] = (str(o.props[1]).split('\x00')[0], o)
        elif o.name == 'Geometry':
            geos[o.props[0]] = o
    parent, geo_of = {}, {}
    for c in conns.kids:
        if c.name != 'C' or c.props[0] != 'OO':
            continue
        child, par = c.props[1], c.props[2]
        if child in models:
            parent[child] = par
        elif child in geos and par in models:
            geo_of.setdefault(par, []).append(child)
    world = {}

    def wm(mid):
        if mid in world:
            return world[mid]
        m = local_matrix(models[mid][1])
        p = parent.get(mid)
        if p in models:
            m = wm(p) @ m
        world[mid] = m
        return m

    out = {}
    for mid, (name, node) in models.items():
        for g in geo_of.get(mid, []):
            v = geos[g].first('Vertices')
            if v is None:
                continue
            pts = np.asarray(v.props[0], dtype=float).reshape(-1, 3)
            M = wm(mid)
            w = ((M[:3, :3] @ pts.T).T + M[:3, 3]) / 100.0
            out[name.split('::')[-1]] = w
    return out


if __name__ == '__main__':
    path = sys.argv[1]
    meshes, unit = analyse(path)
    print('unit scale factor', unit, 'meshes', len(meshes))
    lo = np.min([m[1] for m in meshes], axis=0)
    hi = np.max([m[2] for m in meshes], axis=0)
    print('ALL  min', np.round(lo * unit / 100, 3), 'max', np.round(hi * unit / 100, 3), '(metres)')
    if '--meshes' in sys.argv:
        for name, a, b, n in sorted(meshes, key=lambda m: -np.prod(m[2] - m[1])):
            print('%-22s n=%6d min %s max %s' % (name, n, np.round(a * unit / 100, 3), np.round(b * unit / 100, 3)))
