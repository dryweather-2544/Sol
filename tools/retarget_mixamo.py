"""Retarget a Mixamo FBX animation (binary, skeleton + curves, no mesh) onto Sol's 13-bone astronaut rig.
Rotations are copied as world-space deltas from the Mixamo rest pose (both rigs rest in a T-pose facing +z), the hips' height bob is
scaled to our leg length, and any walking-forward travel is dropped (the game moves the body). Returns {(bone, 'rotation'|'translation'): (times, values)}."""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fbx_probe as fp

TICKS = 46186158000.0
# our bone -> Mixamo bone whose world rotation it follows
MAP = {'hips': 'Hips', 'spine': 'Spine1', 'head': 'Head', 'uarm_l': 'LeftArm', 'farm_l': 'LeftForeArm', 'uarm_r': 'RightArm', 'farm_r': 'RightForeArm',
       'thigh_l': 'LeftUpLeg', 'shin_l': 'LeftLeg', 'foot_l': 'LeftFoot', 'thigh_r': 'RightUpLeg', 'shin_r': 'RightLeg', 'foot_r': 'RightFoot'}
OUR_PARENT = {'hips': None, 'spine': 'hips', 'head': 'spine', 'uarm_l': 'spine', 'farm_l': 'uarm_l', 'uarm_r': 'spine', 'farm_r': 'uarm_r',
              'thigh_l': 'hips', 'shin_l': 'thigh_l', 'foot_l': 'shin_l', 'thigh_r': 'hips', 'shin_r': 'thigh_r', 'foot_r': 'shin_r'}
ORDER = ['hips', 'spine', 'head', 'uarm_l', 'farm_l', 'uarm_r', 'farm_r', 'thigh_l', 'shin_l', 'foot_l', 'thigh_r', 'shin_r', 'foot_r']

def rot_xyz(deg):
    x, y, z = np.radians(deg)
    cx, sx, cy, sy, cz, sz = np.cos(x), np.sin(x), np.cos(y), np.sin(y), np.cos(z), np.sin(z)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]]); Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]); Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx

def mat_to_quat(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1) * 2; q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, s / 4]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1 + m[0, 0] - m[1, 1] - m[2, 2]) * 2; q = [s / 4, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1 + m[1, 1] - m[0, 0] - m[2, 2]) * 2; q = [(m[0, 1] + m[1, 0]) / s, s / 4, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1 + m[2, 2] - m[0, 0] - m[1, 1]) * 2; q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, s / 4, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q); return q / np.linalg.norm(q)

def load_clip(path, fps=30.0):
    root = fp.load(path); obj = root.first('Objects')
    models = {}; curves = {}; nodes = {}
    for k in obj.kids:
        if k.name == 'Model':
            name = k.props[1].split('\x00')[0].replace('mixamorig:', ''); p = {}
            p70 = k.first('Properties70')
            for q in (p70.kids if p70 else []):
                if q.props: p[q.props[0]] = np.array(q.props[4:7], float) if len(q.props) >= 7 else q.props[4:]
            models[k.props[0]] = dict(name=name, props=p, parent=None)
        elif k.name == 'AnimationCurve':
            curves[k.props[0]] = (np.array(k.first('KeyTime').props[0], float) / TICKS, np.array(k.first('KeyValueFloat').props[0], float))
        elif k.name == 'AnimationCurveNode':
            nodes[k.props[0]] = dict(prop=None, model=None, ch={})
    for c in root.first('Connections').kids:
        if c.name != 'C': continue
        kind, child, parent = c.props[0], c.props[1], c.props[2]
        if kind == 'OO' and child in models and parent in models: models[child]['parent'] = parent
        elif kind == 'OP' and child in nodes and parent in models: nodes[child]['model'] = parent; nodes[child]['prop'] = c.props[3]
        elif kind == 'OP' and child in curves and parent in nodes: nodes[parent]['ch'][c.props[3].split('|')[-1]] = child
    by_name = {m['name']: i for i, m in models.items()}
    anim = {}
    for nid, n in nodes.items():
        if n['model'] is None: continue
        anim[(models[n['model']]['name'], n['prop'])] = {ax: curves[cid] for ax, cid in n['ch'].items()}
    end = max(t[-1] for cv in anim.values() for (t, _) in cv.values())
    times = np.arange(0, end + 1e-6, 1.0 / fps)
    def sample(name, prop, default):
        cv = anim.get((name, prop)); out = np.tile(np.array(default, float), (len(times), 1))
        if cv:
            for i, ax in enumerate('XYZ'):
                if ax in cv: out[:, i] = np.interp(times, cv[ax][0], cv[ax][1])
        return out
    def chain(name):
        res = []; i = by_name[name]
        while i is not None: res.append(models[i]['name']); i = models[i]['parent']
        return res[::-1]
    def static(name, prop):
        v = models[by_name[name]]['props'].get(prop); return np.zeros(3) if v is None else np.array(v[:3], float)
    def world_rots(name, frame=None):
        W = np.tile(np.eye(3), (len(times), 1, 1))
        for nm in chain(name):
            pre = rot_xyz(static(nm, 'PreRotation'))
            if frame == 'rest':
                R = np.tile(pre @ rot_xyz(static(nm, 'Lcl Rotation')), (len(times), 1, 1))
            else:
                e = sample(nm, 'Lcl Rotation', static(nm, 'Lcl Rotation'))
                R = np.array([pre @ rot_xyz(d) for d in e])
            W = W @ R
        return W
    deltas = {}
    for ours, mx in MAP.items():
        Wt = world_rots(mx); Wr = world_rots(mx, 'rest')
        deltas[ours] = np.array([Wt[i] @ Wr[i].T for i in range(len(times))])
    out = {}
    for b in ORDER:
        par = OUR_PARENT[b]
        loc = deltas[b] if par is None else np.array([deltas[par][i].T @ deltas[b][i] for i in range(len(times))])
        q = np.array([mat_to_quat(m) for m in loc])
        for i in range(1, len(q)):
            if q[i] @ q[i - 1] < 0: q[i] = -q[i]
        out[(b, 'rotation')] = (times.astype('f4'), q.astype('f4'))
    # hips: scale the bob to our legs (hips-to-ankle 0.88 in rig units), drop travel
    ankle_y = sum(static(n, 'Lcl Translation')[1] for n in ('LeftUpLeg', 'LeftLeg', 'LeftFoot'))
    scale = 0.88 / (static('Hips', 'Lcl Translation')[1] + ankle_y)
    t = sample('Hips', 'Lcl Translation', static('Hips', 'Lcl Translation'))
    pos = np.stack([(t[:, 0] - t[:, 0].mean()) * scale, 0.02 + (t[:, 1] - static('Hips', 'Lcl Translation')[1]) * scale, np.zeros(len(t))], 1)
    out[('hips', 'translation')] = (times.astype('f4'), pos.astype('f4'))
    out['_meta'] = dict(scale=scale, travel=(t[-1] - t[0]) * scale, frames=len(times), end=end)
    return out

if __name__ == '__main__':
    for f in sys.argv[1:]:
        o = load_clip(f); print(os.path.basename(f), o['_meta'])
        for k, v in o.items():
            if k != '_meta' and k[1] == 'translation': print(' hips pos range', v[1].min(0).round(3), v[1].max(0).round(3))
