#!/usr/bin/env python3
"""Converts one of the downloaded Open-Galaxy cockpit FBX files (ASCII or binary, 7.x) to a single .glb in metres.

  python3 tools/fbx_to_glb.py <input.fbx> <textures_dir> <output.glb> [--hide name,name,...]

World transforms are baked into the vertices (FBX units are centimetres), polygons are triangulated, one glTF primitive per material.
Diffuse textures are found by file name (extension ignored: the FBX says .jpg, the zips carry .jpeg), shrunk to 1024 px and embedded.
The emission texture (EmissiveColor) is carried over so lamps and screens glow. Nodes whose names contain a --hide word are left out.
"""
import io, json, os, struct, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fbx_probe as fp

MAX_TEXTURE = 1024
DEFAULT_HIDE = ["hull", "window", "glass", "laser"]


def find_texture(textures_dir, wanted):
    base = os.path.splitext(os.path.basename(wanted.replace("\\", "/")))[0].lower()
    for root, _dirs, files in os.walk(textures_dir):
        for name in files:
            if os.path.splitext(name)[0].lower() == base and name.lower().endswith((".png", ".jpg", ".jpeg")):
                return os.path.join(root, name)
    return None


def prop70(node, key):
    p70 = node.first("Properties70")
    if p70:
        for p in p70.kids:
            if p.props and p.props[0] == key:
                return [float(v) for v in p.props[4:]]
    return None


def encode_texture(path):
    im = Image.open(path)
    has_alpha = im.mode in ("RGBA", "LA", "P")
    if max(im.size) > MAX_TEXTURE:
        scale = MAX_TEXTURE / max(im.size)
        im = im.resize((max(1, int(im.size[0] * scale)), max(1, int(im.size[1] * scale))), Image.LANCZOS)
    buf = io.BytesIO()
    if has_alpha:
        im.convert("RGBA").save(buf, "PNG", optimize=True)
        return buf.getvalue(), "image/png"
    im.convert("RGB").save(buf, "JPEG", quality=88)
    return buf.getvalue(), "image/jpeg"


def convert(src, textures_dir, dst, hide):
    root = fp.load(src)
    objs, conns = root.first("Objects"), root.first("Connections")
    models, geos, mats, texs = {}, {}, {}, {}
    for o in objs.kids:
        if o.name == "Model":
            models[o.props[0]] = (str(o.props[1]).split("\x00")[0].split("::")[-1], o)
        elif o.name == "Geometry":
            geos[o.props[0]] = o
        elif o.name == "Material":
            mats[o.props[0]] = (str(o.props[1]).split("\x00")[0].split("::")[-1], o)
        elif o.name == "Texture":
            texs[o.props[0]] = o
    parent, geo_of, mat_of, tex_of = {}, {}, {}, {}
    for c in conns.kids:
        if c.name != "C":
            continue
        kind, child, par = c.props[0], c.props[1], c.props[2]
        if kind == "OO":
            if child in models:
                parent[child] = par
            elif child in geos and par in models:
                geo_of.setdefault(par, []).append(child)
            elif child in mats and par in models:
                mat_of.setdefault(par, []).append(child)
        elif kind == "OP" and child in texs and par in mats:
            tex_of.setdefault(par, {})[str(c.props[3])] = child
    world = {}

    def wm(mid):
        if mid in world:
            return world[mid]
        m = fp.local_matrix(models[mid][1])
        p = parent.get(mid)
        if p in models:
            m = wm(p) @ m
        world[mid] = m
        return m

    images, image_index = [], {}  # list of (bytes, mime); path -> index
    textures_json, materials_json, material_slot = [], [], {}

    def image_for(tex_id):
        node = texs[tex_id]
        names = []
        for key in ("RelativeFilename", "FileName"):
            k = node.first(key)
            if k and k.props:
                names.append(str(k.props[0]))
        for name in names:
            found = find_texture(textures_dir, name)
            if found:
                if found not in image_index:
                    data, mime = encode_texture(found)
                    image_index[found] = len(images)
                    images.append((data, mime))
                return image_index[found]
        return None

    def material_for(mat_id):
        if mat_id in material_slot:
            return material_slot[mat_id]
        name, node = mats[mat_id]
        diffuse = prop70(node, "DiffuseColor") or [0.6, 0.6, 0.6]
        m = {"name": name, "pbrMetallicRoughness": {"baseColorFactor": [diffuse[0], diffuse[1], diffuse[2], 1.0], "metallicFactor": 0.35, "roughnessFactor": 0.65}, "doubleSided": True}
        tex = tex_of.get(mat_id, {})
        for key, target in (("DiffuseColor", "base"), ("EmissiveColor", "emit")):
            if key in tex:
                idx = image_for(tex[key])
                if idx is not None:
                    textures_json.append({"source": idx})
                    ref = {"index": len(textures_json) - 1}
                    if target == "base":
                        m["pbrMetallicRoughness"]["baseColorTexture"] = ref
                        m["pbrMetallicRoughness"]["baseColorFactor"] = [1, 1, 1, 1]
                    else:
                        m["emissiveTexture"] = ref
                        m["emissiveFactor"] = [1, 1, 1]
        materials_json.append(m)
        material_slot[mat_id] = len(materials_json) - 1
        return material_slot[mat_id]

    prims = {}  # glb material index -> lists of pos, nrm, uv
    kept, skipped = 0, 0
    for mid, (name, node) in models.items():
        lname = name.lower()
        if any(h in lname for h in hide):
            skipped += 1
            continue
        for g in geo_of.get(mid, []):
            geo = geos[g]
            v = geo.first("Vertices"); pvi = geo.first("PolygonVertexIndex")
            if v is None or pvi is None:
                continue
            pts = np.asarray(v.props[0], float).reshape(-1, 3)
            M = wm(mid)
            wpts = ((M[:3, :3] @ pts.T).T + M[:3, 3]) / 100.0
            nrm_m = np.linalg.inv(M[:3, :3]).T
            idx = np.asarray(pvi.props[0], dtype=np.int64)
            # polygons
            polys, cur = [], []
            for k, i in enumerate(idx):
                if i < 0:
                    cur.append((k, int(~i))); polys.append(cur); cur = []
                else:
                    cur.append((k, int(i)))
            normals = uvs = uvidx = None
            nel = geo.first("LayerElementNormal")
            if nel and nel.first("Normals"):
                normals = np.asarray(nel.first("Normals").props[0], float).reshape(-1, 3)
                nmap = str(nel.first("MappingInformationType").props[0]) if nel.first("MappingInformationType") else "ByPolygonVertex"
                nidx = np.asarray(nel.first("NormalsIndex").props[0], dtype=np.int64) if nel.first("NormalsIndex") else None
            uel = geo.first("LayerElementUV")
            if uel and uel.first("UV"):
                uvs = np.asarray(uel.first("UV").props[0], float).reshape(-1, 2)
                uidx = np.asarray(uel.first("UVIndex").props[0], dtype=np.int64) if uel.first("UVIndex") else None
            mel = geo.first("LayerElementMaterial")
            matlist = None; mall = True
            if mel and mel.first("Materials"):
                matlist = np.asarray(mel.first("Materials").props[0], dtype=np.int64)
                mmap = str(mel.first("MappingInformationType").props[0]) if mel.first("MappingInformationType") else "AllSame"
                mall = mmap == "AllSame"
            local_mats = mat_of.get(mid, [])
            for pi, poly in enumerate(polys):
                if len(poly) < 3:
                    continue
                slot = 0 if (matlist is None or mall) else int(matlist[pi])
                if matlist is not None and mall:
                    slot = int(matlist[0])
                if slot >= len(local_mats):
                    slot = max(0, len(local_mats) - 1)
                if not local_mats:
                    continue
                gm = material_for(local_mats[slot])
                if "baseColorTexture" not in materials_json[gm]["pbrMetallicRoughness"] and any(w in lname for w in ("canopy", "glass", "window")):
                    continue  # an untextured pane: it was glass in the game it came from, and here it would be an opaque white wall
                P = prims.setdefault(gm, ([], [], []))
                for t in range(1, len(poly) - 1):
                    for (k, vi) in (poly[0], poly[t], poly[t + 1]):
                        P[0].append(wpts[vi])
                        if normals is not None:
                            if nmap == "ByPolygonVertex":
                                ni = nidx[k] if nidx is not None else k
                            else:
                                ni = vi
                            P[1].append(nrm_m @ normals[ni])
                        else:
                            P[1].append(np.zeros(3))
                        if uvs is not None:
                            ui = uidx[k] if uidx is not None else k
                            P[2].append(uvs[ui] * [1.0, -1.0] + [0.0, 1.0])
                        else:
                            P[2].append(np.zeros(2))
            kept += 1
    # assemble
    blob = bytearray()
    views, accessors, mesh_prims = [], [], []

    def add_view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), **({"target": target} if target else {})})
        blob.extend(data)
        return len(views) - 1

    for gm, (pp, nn, uu) in prims.items():
        pos = np.asarray(pp, np.float32); nor = np.asarray(nn, np.float32); uv = np.asarray(uu, np.float32)
        lens = np.linalg.norm(nor, axis=1); lens[lens == 0] = 1
        nor = nor / lens[:, None]
        # flat-shaded fallback where the file had no normals
        bad = np.linalg.norm(nor, axis=1) < 0.5
        if bad.any():
            tri = pos.reshape(-1, 3, 3)
            fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
            fn = fn / np.maximum(np.linalg.norm(fn, axis=1), 1e-9)[:, None]
            nor = np.where(bad[:, None], np.repeat(fn, 3, axis=0), nor)
        attrs = {}
        for key, arr, typ in (("POSITION", pos, "VEC3"), ("NORMAL", nor, "VEC3"), ("TEXCOORD_0", uv, "VEC2")):
            bv = add_view(arr.tobytes(), 34962)
            acc = {"bufferView": bv, "componentType": 5126, "count": len(arr), "type": typ}
            if key == "POSITION":
                acc["min"] = pos.min(0).tolist(); acc["max"] = pos.max(0).tolist()
            accessors.append(acc)
            attrs[key] = len(accessors) - 1
        mesh_prims.append({"attributes": attrs, "material": gm, "mode": 4})
    image_views = []
    for data, mime in images:
        image_views.append({"bufferView": add_view(data), "mimeType": mime})
    doc = {"asset": {"version": "2.0", "generator": "Sol tools/fbx_to_glb.py"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": os.path.splitext(os.path.basename(dst))[0], "mesh": 0}],
           "meshes": [{"primitives": mesh_prims}], "materials": materials_json, "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors}
    if images:
        doc["images"] = image_views; doc["textures"] = textures_json
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    while len(blob) % 4:
        blob.append(0)
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)) + struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\x00") + bytes(blob)
    open(dst, "wb").write(out)
    print("%s: kept %d meshes, skipped %d, %d primitives, %d textures, %.1f MB" % (os.path.basename(dst), kept, skipped, len(mesh_prims), len(images), len(out) / 1e6))


if __name__ == "__main__":
    a = sys.argv
    hide = DEFAULT_HIDE
    if "--hide" in a:
        hide = a[a.index("--hide") + 1].split(",")
    convert(a[1], a[2], a[3], [h.lower() for h in hide])
