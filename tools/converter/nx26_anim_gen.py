import math, json, os
PI=math.pi
def Rx(a):
    c,s=math.cos(a),math.sin(a); return [[1,0,0],[0,c,-s],[0,s,c]]
def Ry(a):
    c,s=math.cos(a),math.sin(a); return [[c,0,s],[0,1,0],[-s,0,c]]
def Rz(a):
    c,s=math.cos(a),math.sin(a); return [[c,-s,0],[s,c,0],[0,0,1]]
def mm(A,B): return [[sum(A[i][k]*B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def angles(rx,ry,rz): return mm(mm(Rx(rx),Ry(ry)),Rz(rz))
I=[[1,0,0],[0,1,0],[0,0,1]]
def ca(rx,ry,rz): return {"p":[0,0,0],"r":angles(rx,ry,rz)}
def cn(x,y,z): return {"p":[x,y,z],"r":I}
def cmul(A,B):
    r=mm(A["r"],B["r"]); p=[A["p"][i]+sum(A["r"][i][k]*B["p"][k] for k in range(3)) for i in range(3)]
    return {"p":p,"r":r}
def comp(cf):
    p=cf["p"]; r=cf["r"]; return [p[0],p[1],p[2],r[0][0],r[0][1],r[0][2],r[1][0],r[1][1],r[1][2],r[2][0],r[2][1],r[2][2]]
def runSampler(u):
    ph=u*2*PI; s=math.sin(ph); c=math.cos(ph)
    return {"LeftHip":ca(s*0.85,0,0.03),"RightHip":ca(-s*0.85,0,-0.03),"LeftKnee":ca(max(0,-s)*1.3+0.2,0,0),"RightKnee":ca(max(0,s)*1.3+0.2,0,0),"LeftAnkle":ca(-s*0.4+0.1,0,0),"RightAnkle":ca(s*0.4+0.1,0,0),"LeftShoulder":ca(-s*0.7,0,0.12),"RightShoulder":ca(s*0.7,0,-0.12),"LeftElbow":ca(-0.9,0,0),"RightElbow":ca(-0.9,0,0),"Waist":ca(0.18,s*0.06,0),"Root":cn(0,abs(c)*0.06,0),"Neck":ca(-0.1,0,0)}
def sprintSampler(u):
    ph=u*2*PI; s=math.sin(ph); c=math.cos(ph)
    return {"LeftHip":ca(s*1.05,0,0.04),"RightHip":ca(-s*1.05,0,-0.04),"LeftKnee":ca(max(0,-s)*1.6+0.25,0,0),"RightKnee":ca(max(0,s)*1.6+0.25,0,0),"LeftAnkle":ca(-s*0.5+0.15,0,0),"RightAnkle":ca(s*0.5+0.15,0,0),"LeftShoulder":ca(-s*0.9,0,0.15),"RightShoulder":ca(s*0.9,0,-0.15),"LeftElbow":ca(-1.1,0,0),"RightElbow":ca(-1.1,0,0),"Waist":ca(0.28,s*0.08,0),"Root":cn(0,abs(c)*0.08,0),"Neck":ca(-0.15,0,0)}
def idleSampler(u):
    b=math.sin(u*2*PI)
    return {"Waist":ca(0.02+b*0.02,0,0),"LeftShoulder":ca(0,0,0.05+b*0.02),"RightShoulder":ca(0,0,-0.05-b*0.02),"LeftElbow":ca(-0.15,0,0),"RightElbow":ca(-0.15,0,0),"Root":cn(0,b*0.02,0)}
def kickSampler(u):
    if u<0.3: k=-(u/0.3)*1.1
    elif u<0.5: k=-1.1+((u-0.3)/0.2)*2.2
    else: k=1.1*(1-(u-0.5)/0.5)
    return {"RightHip":ca(k,0,0),"RightKnee":ca(max(0,-k)*1.0+0.15,0,0),"RightAnkle":ca(max(0,k)*0.3,0,0),"LeftHip":ca(-0.2,0,0),"LeftKnee":ca(0.35,0,0),"Waist":ca(0.2,-k*0.1,0),"LeftShoulder":ca(0.5,0,0.4),"RightShoulder":ca(-0.5,0,-0.4),"LeftElbow":ca(-0.8,0,0),"RightElbow":ca(-0.8,0,0)}
def passSampler(u):
    k=math.sin(min(u/0.6,1)*PI)*0.7
    return {"RightHip":ca(k,0,0),"RightKnee":ca(0.2,0,0),"LeftHip":ca(-0.12,0,0),"Waist":ca(0.12,0,0),"LeftShoulder":ca(0.3,0,0.2),"RightShoulder":ca(-0.3,0,-0.2)}
def tackleSampler(u):
    l=math.sin(min(u/0.7,1)*PI)
    return {"Root":cmul(cn(0,-l*0.4,0),ca(l*0.5,0,0)),"Waist":ca(l*0.4,0,0),"LeftHip":ca(-l*0.9,0,0),"RightHip":ca(l*0.5,0,0),"LeftKnee":ca(l*0.9,0,0),"RightKnee":ca(l*0.4,0,0),"LeftShoulder":ca(-l*0.8,0,0.3),"RightShoulder":ca(-l*0.8,0,-0.3)}
def stepover(u,side,p):
    ph=u*p.get("reps",1)*2*PI; sw=math.sin(ph); lf=max(0,math.sin(ph))
    return {"RightHip":ca(-0.3*lf,0,side*(0.5*sw+0.3)),"RightKnee":ca(0.6*lf+0.2,0,0),"LeftHip":ca(-0.1,0,0),"LeftKnee":ca(0.2,0,0),"Waist":ca(0.1,side*0.15*sw,side*0.08),"LeftShoulder":ca(0,0,side*0.2),"RightShoulder":ca(0,0,-side*0.2)}
def spinfeint(u,side,p):
    tw=math.sin(u*PI); sw=math.sin(u*2*PI)
    return {"Waist":ca(0.1,side*tw*math.radians(p.get("deg",360))*0.3,0),"RightHip":ca(-0.4*tw,0,side*0.4*sw),"RightKnee":ca(0.5*tw+0.2,0,0),"LeftHip":ca(0.2*tw,0,0),"LeftShoulder":ca(0,0,side*0.3*tw),"RightShoulder":ca(0,0,-side*0.3*tw),"Root":cn(0,-0.1*tw,0)}
def flick(u,side,p):
    h=p.get("high",False)
    if u<0.4: k=-(u/0.4)*0.5
    elif u<0.6: k=-0.5+((u-0.4)/0.2)*(2.0 if h else 1.4)
    else: k=(1.5 if h else 0.9)*(1-(u-0.6)/0.4)
    return {"RightHip":ca(k,0,0),"RightKnee":ca(max(0,-k)*0.8+0.2,0,0),"LeftHip":ca(-0.15,0,0),"Waist":ca(-0.15 if h else 0.1,0,0),"LeftShoulder":ca(0.3,0,0.2),"RightShoulder":ca(-0.3,0,-0.2)}
def elastico(u,side,p):
    o=math.sin(u*2*PI)*(-1 if p.get("reverse") else 1)
    return {"RightHip":ca(-0.2,0,side*o*0.5),"RightKnee":ca(0.3,0,0),"LeftHip":ca(-0.1,0,0),"Waist":ca(0.1,side*o*0.15,side*o*0.08),"LeftShoulder":ca(0,0,side*0.15),"RightShoulder":ca(0,0,-side*0.15)}
def bodyfeint(u,side,p):
    a=0.25 if p.get("advanced") else 0.15; d=math.sin(u*2*PI)
    return {"Waist":ca(0.08,0,side*d*a),"Root":cn(0,-abs(d)*0.1,0),"LeftShoulder":ca(0,0,side*(0.2+d*0.15)),"RightShoulder":ca(0,0,-side*(0.2-d*0.15)),"LeftHip":ca(-0.1,0,side*d*0.1),"RightHip":ca(-0.1,0,-side*d*0.1),"LeftKnee":ca(0.25,0,0),"RightKnee":ca(0.25,0,0)}
def cut(u,side,p):
    s=math.sin(u*PI)
    return {"RightHip":ca(-0.3*s,0,side*0.5*s),"RightKnee":ca(0.5*s+0.2,0,0),"LeftHip":ca(-0.1,0,0),"Waist":ca(0.12,side*0.2*s,side*0.1*s),"LeftShoulder":ca(0,0,side*0.2),"RightShoulder":ca(0,0,-side*0.2)}
def dragback(u,side,p):
    q=math.sin(u*PI)
    return {"RightHip":ca(q*0.6,0,0),"RightKnee":ca(0.3,0,0),"LeftHip":ca(-0.15,0,0),"Waist":ca(0.15,0,0),"Root":cn(0,-0.08*q,0),"LeftShoulder":ca(0.3,0,0.2),"RightShoulder":ca(-0.3,0,-0.2)}
def roll(u,side,p):
    a=math.sin(u*2*PI)
    return {"RightHip":ca(-0.25,0,side*a*0.4),"RightKnee":ca(0.35,0,0),"LeftHip":ca(-0.1,0,0),"Waist":ca(0.1,side*a*0.1,side*a*0.06),"LeftShoulder":ca(0,0,side*0.15),"RightShoulder":ca(0,0,-side*0.15)}
def stopgo(u,side,p):
    st=math.sin((u/0.4)*PI) if u<0.4 else 0; go=math.sin(((u-0.4)/0.6)*PI) if u>=0.4 else 0
    return {"RightHip":ca(-st*0.3+go*0.7,0,0),"RightKnee":ca(st*0.4+0.2,0,0),"LeftHip":ca(-st*0.2-go*0.4,0,0),"LeftKnee":ca(st*0.3+go*0.5+0.2,0,0),"Waist":ca(st*0.1+go*0.2,0,0),"Root":cn(0,-st*0.1,0),"LeftShoulder":ca(-go*0.5,0,0.2),"RightShoulder":ca(go*0.5,0,-0.2)}
def nutmeg(u,side,p):
    q=math.sin(u*PI)
    return {"RightHip":ca(-q*0.5,0,0),"RightKnee":ca(0.3,0,0),"LeftHip":ca(-0.1,0,0),"Waist":ca(0.15,0,0),"LeftShoulder":ca(0.3,0,0.2),"RightShoulder":ca(-0.3,0,-0.2)}
def fakeshot(u,side,p):
    w=(u/0.4) if u<0.4 else 1; q=math.sin(((u-0.4)/0.6)*PI) if u>=0.4 else 0
    return {"RightHip":ca(-w*0.9+q*0.6,0,0),"RightKnee":ca(w*0.8+0.2,0,0),"LeftHip":ca(-0.15,0,0),"Waist":ca(0.15,0,0),"LeftShoulder":ca(0.4,0,0.3),"RightShoulder":ca(-0.4,0,-0.3)}
HIER={"HumanoidRootPart":["Root"],"Root":["Waist","LeftHip","RightHip"],"Waist":["Neck","LeftShoulder","RightShoulder"],"Neck":[],"LeftShoulder":["LeftElbow"],"LeftElbow":["LeftWrist"],"LeftWrist":[],"RightShoulder":["RightElbow"],"RightElbow":["RightWrist"],"RightWrist":[],"LeftHip":["LeftKnee"],"LeftKnee":["LeftAnkle"],"LeftAnkle":[],"RightHip":["RightKnee"],"RightKnee":["RightAnkle"],"RightAnkle":[]}
ALLJ=list(HIER.keys())
def poses(anim): return {j:comp(anim.get(j,{"p":[0,0,0],"r":I})) for j in ALLJ}
def mk(name,group,key,side,loop,dur,sampler,steps,fps=30,prio="Action"):
    kf=[{"time":round((i/steps)*dur,6),"poses":poses(sampler(i/steps))} for i in range(steps+1)]
    return {"name":name,"group":group,"key":key,"side":side,"loop":loop,"duration":dur,"fps":fps,"priority":prio,"rig":"R15","hierarchy":HIER,"keyframes":kf}
FEINTS={"StepOver":(stepover,{"reps":1},0.55),"DoubleStepOver":(stepover,{"reps":2},0.85),"Roulette":(spinfeint,{"deg":360},0.7),"RainbowFlick":(flick,{"high":True},0.9),"HeelFlick":(flick,{"high":False},0.55),"Elastico":(elastico,{"reverse":False},0.6),"ReverseElastico":(elastico,{"reverse":True},0.7),"BodyFeint":(bodyfeint,{"advanced":False},0.35),"BallRoll":(roll,{},0.5),"FakeShot":(fakeshot,{},0.55),"Nutmeg":(nutmeg,{},0.6),"DragBack":(dragback,{},0.65),"LaCroqueta":(cut,{},0.4),"McGeadySpin":(spinfeint,{"deg":360},0.75),"HeelToHeel":(roll,{},0.65),"BodyFeintCut":(bodyfeint,{"advanced":True},0.5),"TwoTouchQuick":(roll,{},0.38),"Chop":(cut,{},0.5),"RouletteBurst":(spinfeint,{"deg":360},0.5),"DoubleTouch":(roll,{},0.4),"StepoverExit":(stepover,{"reps":1},0.45),"LateralHeelToHeel":(roll,{},0.5),"SombreroFlick":(flick,{"high":True},0.8),"StopAndGo":(stopgo,{},0.65),"ScoopTurn":(spinfeint,{"deg":180},0.6),"VCut":(cut,{},0.5),"BerbaSpin":(spinfeint,{"deg":90},0.55),"AdvancedBodyFeint":(bodyfeint,{"advanced":True},0.5)}
LOCO={"Idle":(idleSampler,True,2.4,12),"RunNoBall":(runSampler,True,0.62,12),"RunBall":(runSampler,True,0.66,12),"Sprint":(sprintSampler,True,0.5,12)}
ACTS={"Shoot":(kickSampler,False,0.55,14),"Pass":(passSampler,False,0.45,12),"Long":(kickSampler,False,0.6,14),"TackleFast":(tackleSampler,False,0.6,12),"TackleSlide":(tackleSampler,False,0.8,12)}
def export_all(outdir="anim_json"):
    os.makedirs(outdir,exist_ok=True); n=0
    def sv(s):
        nonlocal n
        json.dump(s,open(os.path.join(outdir,"%s_%s%s.json"%(s["group"],s["key"],"_Left" if s["side"]==-1 else "")),"w")); n+=1
    for k,(f,l,d,st) in LOCO.items(): sv(mk("NX_"+k,"Locomotion",k,1,l,d,f,st,prio="Movement"))
    for k,(f,l,d,st) in ACTS.items(): sv(mk("NX_"+k,"Actions",k,1,l,d,f,st))
    for k,(f,p,d) in FEINTS.items():
        for side in (1,-1): sv(mk("NX_"+k,"Feints",k,side,False,d,(lambda u,f=f,side=side,p=p:f(u,side,p)),12))
    return n
if __name__=="__main__":
    print("exported", export_all(), "animations")
