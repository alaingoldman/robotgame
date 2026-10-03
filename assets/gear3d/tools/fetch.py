"""Download every result GLB recorded in ledger.json['results'] that is not on disk yet -> work/raw/<piece>.glb"""
import json, os, subprocess
from concurrent.futures import ThreadPoolExecutor
W = r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d\work'
led = json.load(open(os.path.join(W, 'ledger.json')))
todo = [(p, u) for p, u in led.get('results', {}).items() if not os.path.exists(os.path.join(W, 'raw', p + '.glb'))]


def get(pu):
    p, u = pu
    tmp = os.path.join(W, 'raw', p + '.part')
    r = subprocess.run(['curl', '-s', '-f', '-o', tmp, u])
    if r.returncode == 0:
        os.replace(tmp, os.path.join(W, 'raw', p + '.glb'))
    return p, r.returncode


with ThreadPoolExecutor(6) as ex:
    for p, c in ex.map(get, todo):
        print(p, 'ok' if c == 0 else 'ERR %d' % c)
