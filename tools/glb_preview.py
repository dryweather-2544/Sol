#!/usr/bin/env python3
"""Tiny software renderer for looking inside a cockpit .glb without Godot (nose = +z in the file's own space).

  python3 tools/glb_preview.py cockpit.glb out.png  eye_x,eye_y,eye_z  [yaw_deg] [pitch_deg] [fov_deg] [plates 'x,y,z,size;...']

Draws the glb's textured triangles into a 640x400 image seen from the eye, looking down +z (yaw turns left, pitch up), with an optional list of
readout plates (centre x,y,z and edge length in metres, drawn as flat magenta squares facing the eye). For eyeballing eye and plate placement.
"""
import io, json, struct, sys
import numpy as np
from PIL import Image


def read_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack_from("<I", d, 12)[0]
    j = json.loads(d[20:20 + jl]); b = d[20 + jl + 8:]
    return j, b


def accessor(j, b, i):
    a = j["accessors"][i]; bv = j["bufferViews"][a["bufferView"]]
    n = {"VEC3": 3, "VEC2": 2, "SCALAR": 1}[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return np.frombuffer(b, "<f4", a["count"] * n, off).reshape(-1, n)


def render(path, out, eye, yaw=0.0, pitch=0.0, fov=80.0, plates=(), size=(640, 400)):
    j, b = read_glb(path)
    textures = {}
    for i, t in enumerate(j.get("textures", [])):
        im = j["images"][t["source"]]; bv = j["bufferViews"][im["bufferView"]]
        textures[i] = np.asarray(Image.open(io.BytesIO(b[bv["byteOffset"]:bv["byteOffset"] + bv["byteLength"]])).convert("RGB"))
    W, H = size
    f = (H / 2) / np.tan(np.radians(fov) / 2)
    yw, pt = np.radians(yaw), np.radians(pitch)
    Ry = np.array([[np.cos(yw), 0, -np.sin(yw)], [0, 1, 0], [np.sin(yw), 0, np.cos(yw)]])
    Rx = np.array([[1, 0, 0], [0, np.cos(pt), -np.sin(pt)], [0, np.sin(pt), np.cos(pt)]])
    R = (Ry @ Rx)  # camera looks along +z in the file's space
    img = np.zeros((H, W, 3), np.float32); img[:] = (12, 14, 22)
    zbuf = np.full((H, W), 1e9, np.float32)

    def project(p):
        c = (p - np.asarray(eye)) @ R  # camera space, +z forward
        return c

    def raster(tri_c, shader):
        z = tri_c[:, 2]
        if (z < 0.05).any():
            return
        sx = W / 2 + f * tri_c[:, 0] / z
        sy = H / 2 - f * tri_c[:, 1] / z
        x0, x1 = int(max(0, np.floor(sx.min()))), int(min(W - 1, np.ceil(sx.max())))
        y0, y1 = int(max(0, np.floor(sy.min()))), int(min(H - 1, np.ceil(sy.max())))
        if x0 > x1 or y0 > y1 or (x1 - x0) * (y1 - y0) > 200000:
            return
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (sy[1] - sy[2]) * (sx[0] - sx[2]) + (sx[2] - sx[1]) * (sy[0] - sy[2])
        if abs(d) < 1e-9:
            return
        l0 = ((sy[1] - sy[2]) * (xs - sx[2]) + (sx[2] - sx[1]) * (ys - sy[2])) / d
        l1 = ((sy[2] - sy[0]) * (xs - sx[2]) + (sx[0] - sx[2]) * (ys - sy[2])) / d
        l2 = 1 - l0 - l1
        inside = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
        if not inside.any():
            return
        # perspective-correct
        iz = l0 / z[0] + l1 / z[1] + l2 / z[2]
        depth = 1.0 / np.maximum(iz, 1e-9)
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        ok = inside & (depth < sub)
        if not ok.any():
            return
        w0, w1, w2 = l0 / z[0] * depth, l1 / z[1] * depth, l2 / z[2] * depth
        sub[ok] = depth[ok]
        img[y0:y1 + 1, x0:x1 + 1][ok] = shader(w0[ok], w1[ok], w2[ok])

    mats = j.get("materials", [])
    for mesh in j["meshes"]:
        for prim in mesh["primitives"]:
            pos = accessor(j, b, prim["attributes"]["POSITION"]).astype(float)
            uv = accessor(j, b, prim["attributes"]["TEXCOORD_0"]).astype(float) if "TEXCOORD_0" in prim["attributes"] else np.zeros((len(pos), 2))
            m = mats[prim["material"]]; pbr = m["pbrMetallicRoughness"]
            tex = textures.get(pbr["baseColorTexture"]["index"]) if "baseColorTexture" in pbr else None
            col = np.array(pbr["baseColorFactor"][:3]) * 255
            if "indices" in prim:
                ia = j["accessors"][prim["indices"]]; ibv = j["bufferViews"][ia["bufferView"]]
                dt = {5121: "u1", 5123: "<u2", 5125: "<u4"}[ia["componentType"]]
                ids = np.frombuffer(b, dt, ia["count"], ibv.get("byteOffset", 0) + ia.get("byteOffset", 0))
                pos, uv = pos[ids], uv[ids]
            cam = project(pos)
            for t in range(0, len(pos), 3):
                tc, tu = cam[t:t + 3], uv[t:t + 3]
                if tex is not None:
                    h, w = tex.shape[:2]
                    def shader(w0, w1, w2, tu=tu, tex=tex, h=h, w=w):
                        u = (w0 * tu[0, 0] + w1 * tu[1, 0] + w2 * tu[2, 0]) % 1.0
                        v = (w0 * tu[0, 1] + w1 * tu[1, 1] + w2 * tu[2, 1]) % 1.0
                        return tex[(v * (h - 1)).astype(int), (u * (w - 1)).astype(int)].astype(np.float32)
                else:
                    def shader(w0, w1, w2, col=col):
                        return np.broadcast_to(col, (len(w0), 3))
                raster(tc, shader)
    for plate in plates:
        cx, cy, cz, s = plate
        c = np.array([cx, cy, cz]); n = (np.asarray(eye) - c); n /= np.linalg.norm(n)
        up = np.array([0, 1, 0.0]); up = up - n * up.dot(n); up /= np.linalg.norm(up)
        right = np.cross(up, n)
        h = s / 2
        quad = [c - right * h - up * h, c + right * h - up * h, c + right * h + up * h, c - right * h + up * h]
        for tri in ([0, 1, 2], [0, 2, 3]):
            raster(project(np.array([quad[i] for i in tri])), lambda a, b2, c2: np.broadcast_to(np.array([230, 40, 200.0]), (len(a), 3)))
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(out)


if __name__ == "__main__":
    a = sys.argv
    eye = [float(v) for v in a[3].split(",")]
    yaw = float(a[4]) if len(a) > 4 else 0.0
    pitch = float(a[5]) if len(a) > 5 else 0.0
    fov = float(a[6]) if len(a) > 6 else 80.0
    plates = [tuple(float(v) for v in p.split(",")) for p in a[7].split(";")] if len(a) > 7 and a[7] else []
    render(a[1], a[2], eye, yaw, pitch, fov, plates)
