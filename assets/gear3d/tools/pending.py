import json
led = json.load(open(r'C:\Users\ICEMAN\Desktop\robotgame\assets\gear3d\work\ledger.json'))
pend = [(k, v) for k, v in led['jobs'].items() if k not in led['results'] and not k.endswith(':sam')]
print(json.dumps([{'index': i, 'job_id': v} for i, (k, v) in enumerate(pend[:12])]))
print(' '.join(k for k, v in pend[:12]), '| pending', len(pend))
