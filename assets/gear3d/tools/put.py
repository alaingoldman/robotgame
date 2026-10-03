"""PUT crop PNGs to Higgsfield presigned URLs via curl. stdin/file lines: '<crop name> <url>'."""
import sys, subprocess
from concurrent.futures import ThreadPoolExecutor
D = 'C:/Users/ICEMAN/Desktop/robotgame/assets/gear3d/work/crops/'
lines = [l.strip().split(' ', 1) for l in open(sys.argv[1]) if l.strip()]
def put(nu):
    n, u = nu
    r = subprocess.run(['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', '-X', 'PUT', '-H', 'Content-Type: image/png',
                        '-H', 'If-None-Match: *', '--data-binary', '@' + D + n, u], capture_output=True, text=True)
    return n, r.stdout
with ThreadPoolExecutor(8) as ex:
    for n, c in ex.map(put, lines): print(n, c)
