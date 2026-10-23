import numpy as np
from PIL import Image, ImageDraw
def render(P,T,mat=None,views=(('front',0),('side',90),('back',180)),H=700,out='views.png',joints=None,cols=None):
    """P Nx3 (y up, feet y=0), T tris. yaw views: camera rotates around y. joints: dict name->(xyz)."""
    ims=[]
    for name,yaw in views:
        a=np.radians(yaw); c,s=np.cos(a),np.sin(a)
        R=np.array([[c,0,s],[0,1,0],[-s,0,c]])
        Q=P@R.T            # camera looks down -z? use x right, z toward viewer
        ext=max(P[:,1].max()-P[:,1].min(),1e-6); sc=(H-40)/ext; W=int(H*0.8)
        im=Image.new('RGB',(W,H),(200,205,215)); d=ImageDraw.Draw(im)
        tri=Q[T]; n=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]); nn=np.linalg.norm(n,axis=1,keepdims=True)+1e-9; n/=nn
        depth=tri[:,:,2].mean(1); order=np.argsort(depth)
        L=np.array([0.4,0.6,0.7]); L/=np.linalg.norm(L)
        for i in order:
            if n[i,2]<0: continue
            sh=0.35+0.65*max(0,n[i]@L)
            base=np.array(cols[i] if cols is not None else (170,175,185),float)
            col=tuple(int(v) for v in base*sh)
            pts=[(W/2+tri[i,k,0]*sc, H-20-(tri[i,k,1]-P[:,1].min())*sc) for k in range(3)]
            d.polygon(pts,fill=col,outline=tuple(int(v*0.7) for v in col))
        if joints:
            for k,v in joints.items():
                q=np.array(v)@R.T; d.ellipse((W/2+q[0]*sc-4,H-20-(q[1]-P[:,1].min())*sc-4,W/2+q[0]*sc+4,H-20-(q[1]-P[:,1].min())*sc+4),fill=(255,0,0))
        ims.append(im)
    W=sum(i.width for i in ims); o=Image.new('RGB',(W,H)); x=0
    for i in ims: o.paste(i,(x,0)); x+=i.width
    o.save(out)
