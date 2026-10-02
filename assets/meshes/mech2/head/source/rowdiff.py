import sys, numpy as np, refs, geom, verify
parts=geom.all_parts()
for view in sys.argv[1:]:
    d,img,lab,mask=verify.render_sheet(view,parts)
    r=d['roi']; m=mask&r; s=d['sil']; c=refs.VIEWS[view]
    print('==',view,'missing',int((s&~m).sum()),'extra',int((m&~s).sum()))
    for y in range(0,d['h'],3):
        miss=int((s[y]&~m[y]).sum()); ext=int((m[y]&~s[y]).sum())
        if miss+ext<3: continue
        Y=refs.Y0-(y-c['yG'])/refs.SY
        line=''.join('#' if (s[y,x] and m[y,x]) else ('-' if s[y,x] else ('+' if m[y,x] else '.')) for x in range(0,d['w'],1))
        print(f"{y:3d} {Y:5.2f} m{miss:3d} e{ext:3d} {line}")
