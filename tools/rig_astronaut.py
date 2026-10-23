"""Re-skin the new low-poly astronaut FBX onto Sol's existing 13-bone astronaut rig (idle/walk/run/sprint)
and write assets/characters/astronaut.glb.   usage: python3 rig_astronaut.py <astronout.fbx> <old.glb> <out.glb> [preview_dir]"""
import sys, os, heapq, json, struct, io
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fbx_probe as fp
from glb_lib import load_glb, acc, qmat, mat4
import mesh_views as mv

BONES = ['hips','spine','head','uarm_l','farm_l','uarm_r','farm_r','thigh_l','shin_l','foot_l','thigh_r','shin_r','foot_r']
TARGET_H = 1.9           # old mesh height in root-local units
FLOOR = -0.95

def load_fbx(path):
    root = fp.load(path)
    g = [k for k in root.first('Objects').kids if k.name == 'Geometry'][0]
    v = np.array(g.first('Vertices').props[0], float).reshape(-1, 3)
    pvi = np.array(g.first('PolygonVertexIndex').props[0])
    nrm = np.array(g.first('LayerElementNormal').first('Normals').props[0], float).reshape(-1, 3)
    uvs = np.array(g.first('LayerElementUV').first('UV').props[0], float).reshape(-1, 2)
    uvi = np.array(g.first('LayerElementUV').first('UVIndex').props[0])
    pm = np.array(g.first('LayerElementMaterial').first('Materials').props[0])
    # Body.000: Lcl Rotation -90 X (Z-up -> Y-up), scale 100 on cm units (already metres in file)
    R = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float)   # (x,y,z)->(x,z,-y)
    v = v @ R.T; nrm = nrm @ R.T
    corners = []; tri_mat = []; cur = []; pi = 0
    for ci, i in enumerate(pvi):
        cur.append(ci)
        if i < 0:
            for k in range(1, len(cur) - 1): corners.append((cur[0], cur[k], cur[k + 1])); tri_mat.append(pm[pi])
            cur = []; pi += 1
    vidx = np.where(pvi < 0, ~pvi, pvi)
    return v, vidx, nrm, np.array(corners), np.array(tri_mat)

def to_rig_space(v):
    """mesh (facing +x, feet y~0) -> rig root-local (facing +z, the way the walk/run clips move; feet y=-0.95)."""
    s = TARGET_H / (v[:, 1].max() - v[:, 1].min())
    shin = v[(v[:, 1] > 0.3) & (v[:, 1] < 0.8)]
    x0 = shin[:, 0].mean()
    out = np.stack([-v[:, 2] * s, (v[:, 1] - v[:, 1].min()) * s + FLOOR, (v[:, 0] - x0) * s], 1)
    return out, s, x0

def rot_to_rig(n):
    return np.stack([-n[:, 2], n[:, 1], n[:, 0]], 1)

def smooth(t): t = np.clip(t, 0, 1); return t * t * (3 - 2 * t)

def seg_dist(P, a, b):
    ab = b - a; t = np.clip(((P - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)

def label_weights(P, edges_w, adj, v_mesh_x, in_mat0):
    n = len(P); x = P[:, 0]; y = P[:, 1]; ax = np.abs(x); z = P[:, 2]
    seeds = {}
    def add(name, mask): seeds[name] = np.where(mask)[0]
    back = (v_mesh_x < -0.42) & (y > (1.25 * 0.734 + FLOOR)) & in_mat0
    add('head', (y > 0.70) & ~back)
    add('spine', ((ax < 0.10) & (y > 0.15) & (y < 0.5) & ~back) | back)
    add('hips', (ax < 0.09) & (y > -0.08) & (y < 0.08))
    for side, sg in (('l', 1), ('r', -1)):
        sx = sg * x
        add('uarm_' + side, (sx > 0.31) & (y > 0.25) & (y < 0.42) & ~back)
        add('farm_' + side, (sx > 0.31) & (y > -0.12) & (y < 0.12))
        add('thigh_' + side, (sx > 0.08) & (sx < 0.26) & (y > -0.45) & (y < -0.05))
        add('shin_' + side, (sx > 0.05) & (sx < 0.30) & (y > -0.72) & (y < -0.52))
        add('foot_' + side, (sx > 0.03) & (y < -0.80))
    names = list(seeds); dist = np.full(n, np.inf); lab = np.full(n, -1)
    pq = []
    for li, nm in enumerate(names):
        for i in seeds[nm]: dist[i] = 0; lab[i] = li; heapq.heappush(pq, (0.0, i, li))
    while pq:
        d, i, li = heapq.heappop(pq)
        if d > dist[i] or lab[i] != li: continue
        for j, w in adj[i]:
            nd = d + w
            if nd < dist[j]: dist[j] = nd; lab[j] = li; heapq.heappush(pq, (nd, j, li))
    W = np.zeros((n, len(BONES)))
    for i in range(n):
        nm = names[lab[i]]
        side = 'l' if x[i] >= 0 else 'r'
        if nm[:4] in ('uarm', 'farm'):            # arm vs forearm split at the elbow (blended analytically later)
            nm = ('uarm_' if y[i] > 0.215 else 'farm_') + nm[-1]
        elif y[i] < 0.12 and nm != 'head' and not back[i]:
            nm = 'hips'
        if back[i]: nm = 'spine'
        W[i, BONES.index(nm)] = 1
    arm = np.array([names[l][:4] in ('uarm', 'farm') for l in lab])
    leg = (~arm) & (~back) & (y < 0.06)
    return W, lab, names, back, arm, leg

def smooth_weights(W, adj, iters=5, alpha=0.5):
    for _ in range(iters):
        N = np.zeros_like(W)
        for i, nb in enumerate(adj):
            ws = np.array([1.0 / max(w, 1e-4) for _, w in nb]); idx = [j for j, _ in nb]
            N[i] = (W[idx] * ws[:, None]).sum(0) / ws.sum()
        W = (1 - alpha) * W + alpha * N
    # keep 4 strongest
    out = np.zeros_like(W)
    for i in range(len(W)):
        k = np.argsort(-W[i])[:4]; out[i, k] = W[i, k]
    return out / out.sum(1, keepdims=True)

def fk(nodes, par, loc):
    Wd = {}
    def w(i):
        if i in Wd: return Wd[i]
        m = mat4(loc[i][0], loc[i][1], loc[i][2] if len(loc[i]) > 2 else None)
        Wd[i] = w(par[i]) @ m if i in par else m
        return Wd[i]
    for i in range(len(nodes)): w(i)
    return Wd

def main(fbx, oldglb, outglb, prev=None):
    v, vidx, nrm, corners, tri_mat = load_fbx(fbx)
    P, s, x0 = to_rig_space(v)
    nrm = rot_to_rig(nrm)
    # adjacency on welded vertices
    adj = [dict() for _ in range(len(P))]
    for c in corners:
        vi = vidx[c]
        for a, b in ((0, 1), (1, 2), (2, 0)):
            i, j = vi[a], vi[b]; d = float(np.linalg.norm(P[i] - P[j])); adj[i][j] = d; adj[j][i] = d
    adj = [list(d.items()) for d in adj]
    # ---- rig: old glb, tweak bone offsets to fit this body
    j, b = load_glb(oldglb); nodes = j['nodes']
    byname = {n['name']: i for i, n in enumerate(nodes)}
    tweak = {'uarm_l': (0.26, 0.37, 0), 'uarm_r': (-0.26, 0.37, 0),
             'thigh_l': (0.16, -0.02, 0), 'thigh_r': (-0.16, -0.02, 0),
             'shin_l': (0.02, -0.49, 0), 'shin_r': (-0.02, -0.49, 0)}
    for nm, t in tweak.items(): nodes[byname[nm]]['translation'] = list(t)
    par = {}
    for i, n in enumerate(nodes):
        for c in n.get('children', []): par[c] = i
    # idle frame 0 pose = bind pose
    anims = {}
    for a in j['animations']:
        d = {}
        for ch in a['channels']:
            sm = a['samplers'][ch['sampler']]
            d[(ch['target']['node'], ch['target']['path'])] = (acc(j, b, sm['input'])[:, 0].copy(), acc(j, b, sm['output']).copy(), sm.get('interpolation', 'LINEAR'))
        anims[a['name']] = d
    # Mixamo clips downloaded by the owner replace "walk" and add the seated poses (retarget_mixamo.py)
    import retarget_mixamo as rm
    dl = os.path.expanduser('~/mnt/Downloads') if os.path.isdir(os.path.expanduser('~/mnt/Downloads')) else os.path.expanduser('~/Downloads')
    for clip, fname in (('walk', 'Walking.fbx'), ('sit', 'Sitting.fbx'), ('sit_idle', 'Sitting Idle.fbx')):
        fpth = os.path.join(dl, fname)
        if os.path.exists(fpth):
            got = rm.load_clip(fpth); d = {}
            for key, val in got.items():
                if key == '_meta': continue
                d[(byname[key[0]], key[1])] = (val[0], val[1], 'LINEAR')
            anims[clip] = d
    def local_at(anim, frame):
        loc = {i: [np.array(n.get('translation', [0, 0, 0]), float), np.array(n.get('rotation', [0, 0, 0, 1]), float), np.array(n.get('scale', [1, 1, 1]), float)] for i, n in enumerate(nodes)}
        for (ni, path), (t, vals, _) in anims[anim].items():
            loc[ni][0 if path == 'translation' else 1] = vals[frame]
        return loc
    bind = fk(nodes, par, local_at('idle', 0))
    # root-local frame (strip Astronaut node transform)
    root_inv = np.linalg.inv(bind[byname['Astronaut']])
    BW = {nm: root_inv @ bind[byname[nm]] for nm in BONES}
    # ---- weights
    in_mat0 = np.zeros(len(P), bool)
    for c, m in zip(corners, tri_mat):
        if m == 0: in_mat0[vidx[c]] = True
    W, lab, names, back, arm, leg = label_weights(P, None, adj, v[:, 0], in_mat0)
    W = smooth_weights(W, adj, iters=6)
    W[back] = 0; W[back, BONES.index('spine')] = 1
    head_only = (P[:, 1] > 0.66) & ~back
    W[head_only] = 0; W[head_only, BONES.index('head')] = 1
    B = BONES.index
    for i in np.where(arm)[0]:                    # elbow: analytic blend (arm weights keep their smoothed shoulder share)
        t = smooth((0.265 - P[i, 1]) / 0.10); a = sum(W[i, B(k + sd)] for k in ('uarm_', 'farm_') for sd in ('l', 'r'))
        sd = 'l' if P[i, 0] >= 0 else 'r'; W[i, :] *= 0
        W[i, B('uarm_' + sd)] = a * (1 - t); W[i, B('farm_' + sd)] = a * t
        W[i, B('spine')] = 1 - a
    for i in np.where(leg)[0]:                    # hip / knee / ankle: analytic blends by height, straight clean transitions
        y_ = P[i, 1]; sd = 'l' if P[i, 0] >= 0 else 'r'; W[i, :] = 0
        th = smooth((0.06 - y_) / 0.16); tk = smooth((-0.36 - y_) / 0.24); ta = smooth((-0.72 - y_) / 0.14)
        W[i, B('hips')] = 1 - th; r = th
        W[i, B('thigh_' + sd)] = r * (1 - tk); W[i, B('shin_' + sd)] = r * tk * (1 - ta); W[i, B('foot_' + sd)] = r * tk * ta
    if prev:
        os.makedirs(prev, exist_ok=True)
        pal = np.array([[230,60,60],[60,200,80],[70,100,240],[240,200,40],[200,60,220],[40,200,200],[250,130,40],[130,90,60],[255,255,255],[120,120,120],[160,200,20],[90,90,250],[250,90,160]])
        tri = np.array([vidx[c] for c in corners])
        cols = [tuple(int(k) for k in (pal[W[t].mean(0).argmax()])) for t in tri]
        joints = {nm: BW[nm][:3, 3] for nm in BONES}
        mv.render(P - np.array([0, FLOOR, 0]), tri, views=(('front', 0), ('side', 90), ('back', 180)), cols=cols, joints={k: v_ - np.array([0, FLOOR, 0]) for k, v_ in joints.items()}, out=os.path.join(prev, 'weights.png'))
    return dict(back=back, back_centre=P[back].mean(0), v=v, vidx=vidx, nrm=nrm, corners=corners, tri_mat=tri_mat, P=P, W=W, BW=BW, nodes=nodes, j=j, b=b, anims=anims, par=par, byname=byname, local_at=local_at)


SWATCH = [(222, 224, 230), (52, 54, 62), (20, 56, 78)]     # suit, dark gear (backpack/trim), visor + chest panel

def build_vertices(r):
    key = {}; pos = []; nor = []; uv = []; wts = []; idx = []
    mat_cell = {1: 0, 0: 1, 2: 2}
    for c, m in zip(r['corners'], r['tri_mat']):
        p3 = [r['P'][r['vidx'][ci]] for ci in c]
        face = np.cross(p3[1] - p3[0], p3[2] - p3[0]); want = sum(r['nrm'][ci] for ci in c)
        # The suit's polygons are wound inside-out in this file (its normals too), the backpack box's are right: wind the suit
        # reversed and the backpack so it faces away from its own centre.
        vs = r['vidx'][list(c)]
        if r['back'][vs].all():
            order = c if face @ (sum(p3) / 3 - r['back_centre']) >= 0 else (c[0], c[2], c[1])
        else:
            order = (c[0], c[2], c[1])
        for ci in order:
            vi = r['vidx'][ci]; n = r['nrm'][ci]; n = n / (np.linalg.norm(n) + 1e-9)
            k = (vi, tuple(np.round(n, 3)), m)
            if k not in key:
                key[k] = len(pos); pos.append(r['P'][vi]); nor.append(n); wts.append(r['W'][vi])
                uv.append(((mat_cell[int(m)] + 0.5) / len(SWATCH), 0.5))
            idx.append(key[k])
    return np.array(pos, '<f4'), np.array(nor, '<f4'), np.array(uv, '<f4'), np.array(wts), np.array(idx, '<u4').reshape(-1, 3)

def pack_weights(w):
    J = np.zeros((len(w), 4), '<u2'); Wt = np.zeros((len(w), 4), '<f4')
    for i, row in enumerate(w):
        k = np.argsort(-row)[:4]; J[i] = k; Wt[i] = row[k]
    Wt /= Wt.sum(1, keepdims=True); return J, Wt

def write_glb(r, path):
    from PIL import Image
    pos, nor, uv, w, idx = build_vertices(r)
    J, Wt = pack_weights(w)
    # flip winding: mesh was authored for +x facing; our basis change (x,z swap with sign) is a proper rotation so winding is kept
    nodes = json.loads(json.dumps(r['nodes'])); nodes[r['byname']['Body']].update(mesh=0, skin=0)
    nodes[r['byname']['Astronaut']]['rotation'] = [0, 1, 0, 0]   # 180 degree yaw: the model's front (+z) then faces the game's forward (-z); checked in game
    BW = r['BW']; ibm = np.array([np.linalg.inv(BW[nm]).T.astype('<f4') for nm in BONES])   # column-major
    img = Image.new('RGB', (len(SWATCH) * 8, 8))
    for i, c in enumerate(SWATCH):
        for x in range(8):
            for y in range(8): img.putpixel((i * 8 + x, y), c)
    pb = io.BytesIO(); img.save(pb, 'PNG'); png = pb.getvalue()
    chunks = []; views = []; accs = []
    def add(data, target=None):
        pad = (-sum(len(c) for c in chunks)) % 4
        if pad: chunks.append(b'\0' * pad)
        off = sum(len(c) for c in chunks); chunks.append(data)
        v = {'buffer': 0, 'byteOffset': off, 'byteLength': len(data)}
        if target: v['target'] = target
        views.append(v); return len(views) - 1
    def acc_(arr, ctype, typ, target=None, mm=False):
        bv = add(arr.tobytes(), target)
        a = {'bufferView': bv, 'componentType': ctype, 'count': len(arr), 'type': typ}
        if mm: a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
        accs.append(a); return len(accs) - 1
    FL, US, UI = 5126, 5123, 5125
    a_pos = acc_(pos, FL, 'VEC3', 34962, True); a_nor = acc_(nor, FL, 'VEC3', 34962); a_uv = acc_(uv, FL, 'VEC2', 34962)
    a_j = acc_(J, US, 'VEC4', 34962); a_w = acc_(Wt, FL, 'VEC4', 34962); a_i = acc_(idx.reshape(-1).astype('<u4'), UI, 'SCALAR', 34963)
    a_ibm = acc_(ibm.reshape(-1, 16), FL, 'MAT4')
    img_bv = add(png)
    anims = []
    for name, d in r['anims'].items():
        samplers = []; channels = []
        for (ni, chpath), (t, vals, interp) in d.items():
            ai = acc_(t.astype('<f4').reshape(-1, 1), FL, 'SCALAR', mm=True); ao = acc_(vals.astype('<f4'), FL, 'VEC4' if chpath == 'rotation' else 'VEC3')
            samplers.append({'input': ai, 'output': ao, 'interpolation': interp}); channels.append({'sampler': len(samplers) - 1, 'target': {'node': ni, 'path': chpath}})
        anims.append({'name': name, 'samplers': samplers, 'channels': channels})
    doc = {'asset': {'version': '2.0', 'generator': 'Sol tools/rig_astronaut.py'}, 'scene': 0, 'scenes': [{'nodes': [r['byname']['Astronaut']]}],
           'nodes': nodes, 'meshes': [{'name': 'Body', 'primitives': [{'attributes': {'POSITION': a_pos, 'NORMAL': a_nor, 'TEXCOORD_0': a_uv, 'JOINTS_0': a_j, 'WEIGHTS_0': a_w}, 'indices': a_i, 'material': 0}]}],
           'skins': [{'name': 'Skel', 'joints': [r['byname'][n] for n in BONES], 'inverseBindMatrices': a_ibm, 'skeleton': r['byname']['hips']}],
           'materials': [{'name': 'Suit', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 0.85}}],
           'textures': [{'source': 0, 'sampler': 0}], 'samplers': [{'magFilter': 9728, 'minFilter': 9728, 'wrapS': 33071, 'wrapT': 33071}],
           'images': [{'bufferView': img_bv, 'mimeType': 'image/png'}], 'animations': anims,
           'accessors': accs, 'bufferViews': views}
    blob = b''.join(chunks); blob += b'\0' * ((-len(blob)) % 4); doc['buffers'] = [{'byteLength': len(blob)}]
    js = json.dumps(doc).encode(); js += b' ' * ((-len(js)) % 4)
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + blob
    with open(path, 'wb') as fh: fh.write(out)
    return doc, len(pos)

def skin_pose(r, anim, frame):
    loc = r['local_at'](anim, frame); Wd = fk(r['nodes'], r['par'], loc)
    root_inv = np.linalg.inv(Wd[r['byname']['Astronaut']] if False else fk(r['nodes'], r['par'], r['local_at']('idle', 0))[r['byname']['Astronaut']])
    pos, nor, uv, w, idx = build_vertices(r)
    out = np.zeros_like(pos, dtype=float)
    M = np.array([root_inv @ Wd[r['byname'][nm]] @ np.linalg.inv(r['BW'][nm]) for nm in BONES])
    h = np.concatenate([pos, np.ones((len(pos), 1))], 1)
    for k in range(len(BONES)):
        out += w[:, k:k + 1] * (h @ M[k].T)[:, :3]
    return out, idx

def preview_poses(r, path):
    from PIL import Image
    shots = []
    for anim, frames in (('walk', [0, 8, 16, 24]), ('sit', [0, 60]), ('sit_idle', [0, 60]), ('run', [6])):
        for f in frames:
            P, idx = skin_pose(r, anim, f)
            P = P - np.array([0, FLOOR, 0]); tmp = path + '_t.png'
            mv.render(P, idx, views=(('side', 90), ('front', 0)), H=360, out=tmp, cols=None)
            shots.append(Image.open(tmp).copy())
    W = max(i.width for i in shots); cols = 3; rows = (len(shots) + cols - 1) // cols
    sheet = Image.new('RGB', (W * cols, 360 * rows), 'white')
    for k, im in enumerate(shots): sheet.paste(im, ((k % cols) * W, (k // cols) * 360))
    sheet.save(path); os.remove(path + '_t.png')

if __name__ == '__main__':
    fbx, old, out = sys.argv[1:4]; prev = sys.argv[4] if len(sys.argv) > 4 else None
    r = main(fbx, old, out, prev)
    doc, nv = write_glb(r, out); print('wrote', out, nv, 'verts', os.path.getsize(out), 'bytes')
    if prev: preview_poses(r, os.path.join(prev, 'poses.png'))
