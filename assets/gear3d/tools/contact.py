"""Stack the per-tier turnarounds into contact sheets (renders/contact_1-10.png, contact_11-20.png)."""
import os, glob
from PIL import Image
D = r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d\renders'
for a, b in ((1, 10), (11, 20)):
    ims = [Image.open(os.path.join(D, 'T%02d_turnaround.png' % t)) for t in range(a, b + 1) if os.path.exists(os.path.join(D, 'T%02d_turnaround.png' % t))]
    if not ims:
        continue
    ims = [im.resize((im.width // 2, im.height // 2)) for im in ims]
    out = Image.new('RGB', (ims[0].width, sum(i.height for i in ims)), 'white')
    y = 0
    for im in ims:
        out.paste(im, (0, y)); y += im.height
    out.save(os.path.join(D, 'contact_%d-%d.png' % (a, b)))
