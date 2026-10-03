"""List uploaded pieces that are ready to submit (all views present) and not yet submitted.
usage: python ready.py            -> list
       python ready.py add <piece> <job_id> [model]   -> record a submitted job
       python ready.py done <piece> <url>             -> record a result url"""
import json, glob, sys, os
W = r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d\work'
L = os.path.join(W, 'ledger.json')
led = json.load(open(L))
led.setdefault('results', {})
media = dict(led['media'])
for f in glob.glob(os.path.join(W, 'media_*.json')):
    try:
        media.update(json.load(open(f)))
    except Exception:
        pass
if len(sys.argv) > 2 and sys.argv[1] == 'add':
    led['jobs'][sys.argv[2]] = sys.argv[3]; json.dump(led, open(L, 'w'), indent=1); sys.exit()
if len(sys.argv) > 2 and sys.argv[1] == 'done':
    led['results'][sys.argv[2]] = sys.argv[3]; json.dump(led, open(L, 'w'), indent=1); sys.exit()
pieces = sorted({k.rsplit('_', 1)[0] for k in media})
sub = {k.split(':')[0] for k in led['jobs'] if not k.endswith(':sam')}
for p in pieces:
    if p in sub:
        continue
    if p.endswith(('melee', 'ranged')):
        if p + '_side' in media:
            print(p, 'single', media[p + '_side'])
    elif all(p + '_' + v in media for v in ('front', 'side', 'back')):
        print(p, 'mv', ' '.join(media[p + '_' + v] for v in ('front', 'side', 'back')))
print('submitted', len(sub), 'media', len(media))
