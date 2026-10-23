import json,struct,numpy as np
def load_glb(path):
    f=open(path,'rb').read()
    jl,=struct.unpack('<I',f[12:16]); j=json.loads(f[20:20+jl]); bo=20+jl+8
    return j,f[bo:]
def acc(j,b,i):
    a=j['accessors'][i]; bv=j['bufferViews'][a['bufferView']]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    dt={5126:'<f4',5123:'<u2',5125:'<u4',5121:'u1'}[a['componentType']]
    o=bv.get('byteOffset',0)+a.get('byteOffset',0)
    arr=np.frombuffer(b,dt,a['count']*n,o).reshape(a['count'],n)
    return arr
def qmat(q):
    x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
def mat4(t,r,s=None):
    m=np.eye(4); m[:3,:3]=qmat(r) if r is not None else np.eye(3)
    if s is not None: m[:3,:3]=m[:3,:3]*np.array(s)
    m[:3,3]=t; return m
