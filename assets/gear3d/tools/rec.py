"""Record result URLs (job id is inside the URL) -> ledger results. args: url url ..."""
import json, sys, re
L = r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d\work\ledger.json'
led = json.load(open(L)); led.setdefault('results', {})
inv = {v: k for k, v in led['jobs'].items()}
for u in sys.argv[1:]:
    j = re.search(r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.glb', u).group(1)
    led['results'][inv[j]] = u; print(inv[j])
json.dump(led, open(L, 'w'), indent=1)
