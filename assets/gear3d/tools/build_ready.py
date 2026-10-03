"""Build every tier whose three raw GLBs are downloaded and whose Gear_T##.glb is missing (or all listed tiers)."""
import os, sys, subprocess
from concurrent.futures import ThreadPoolExecutor
ROOT = r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d'
force = [int(x) for x in sys.argv[1:]]
todo = []
for T in range(1, 21):
    raws = [os.path.join(ROOT, 'work', 'raw', '%d%s.glb' % (T, s)) for s in ('01_arm', '02_leg', '03_chest')]
    if all(os.path.exists(r) for r in raws) and (T in force or not os.path.exists(os.path.join(ROOT, 'Gear_T%02d.glb' % T))):
        todo.append(T)
print('building', todo, flush=True)


def run(T):
    r = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'build_tier.py'), str(T)], capture_output=True, text=True)
    return T, (r.stdout.strip().splitlines() or [''])[-1], r.stderr.strip()[-600:]


with ThreadPoolExecutor(4) as ex:
    for T, out, err in ex.map(run, todo):
        print(T, out, ('ERR ' + err) if err and 'Error' in err else '', flush=True)
