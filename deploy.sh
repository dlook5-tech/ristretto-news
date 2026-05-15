#!/bin/bash
# deploy.sh — digest-based deploy to Netlify (uploads only files Netlify doesn't have).
# Minimal version of the eXpressO deploy script.
set -euo pipefail

MAIN="$(cd "$(dirname "$0")" && pwd)"
SITE_ID="${NETLIFY_SITE_ID:-6df63a2b-f50c-4eba-9223-057d041a4234}"

[ -f "$MAIN/.env" ] && source "$MAIN/.env"
: "${NETLIFY_AUTH_TOKEN:?NETLIFY_AUTH_TOKEN required}"

cd "$MAIN"
BUILD=$(date +%Y%m%d%H%M%S)
echo "[deploy] Build version: $BUILD"
echo "$BUILD" > "$MAIN/version.txt"

# Stamp sw.js so browsers see a new service worker every deploy
if grep -q "BUILD = '" "$MAIN/sw.js" 2>/dev/null; then
    sed -i.bak -E "s|BUILD = '[^']*'|BUILD = '$BUILD'|" "$MAIN/sw.js"
    rm -f "$MAIN/sw.js.bak"
fi

# Make sure stories.json exists (empty placeholder on first deploy)
if [ ! -s "$MAIN/stories.json" ]; then
    echo '{"stories":{},"last_updated":"never"}' > "$MAIN/stories.json"
fi

# Build manifest: path -> sha1
FILES_JSON=$(MAIN="$MAIN" python3 <<'PYEOF'
import hashlib, json, os
MAIN = os.environ['MAIN']
files = ["index.html", "stories.json", "sw.js", "version.txt"]
manifest, paths_by_hash = {}, {}
for rel in files:
    full = os.path.join(MAIN, rel)
    if not os.path.isfile(full): continue
    h = hashlib.sha1(open(full,"rb").read()).hexdigest()
    manifest["/" + rel] = h
    paths_by_hash[h] = full
with open("/tmp/ristretto_paths.json","w") as o: json.dump(paths_by_hash,o)
print(json.dumps({"files": manifest}))
PYEOF
)

echo "[deploy] Creating digest deploy on $SITE_ID..."
DEPLOY_RESP=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $NETLIFY_AUTH_TOKEN" \
  -d "$FILES_JSON" \
  "https://api.netlify.com/api/v1/sites/$SITE_ID/deploys")

DEPLOY_ID=$(echo "$DEPLOY_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
[ -z "$DEPLOY_ID" ] && { echo "[deploy] ERROR no deploy_id"; echo "$DEPLOY_RESP" | head -c 500; exit 1; }

REQUIRED_COUNT=$(echo "$DEPLOY_RESP" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('required',[])))")
TOTAL_COUNT=$(echo "$FILES_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['files']))")
echo "[deploy] deploy_id=$DEPLOY_ID  uploading $REQUIRED_COUNT of $TOTAL_COUNT files"

if [ "$REQUIRED_COUNT" -gt 0 ]; then
  NETLIFY_AUTH_TOKEN="$NETLIFY_AUTH_TOKEN" DEPLOY_RESP="$DEPLOY_RESP" python3 <<'PYEOF'
import json, subprocess, os, sys
resp = json.loads(os.environ['DEPLOY_RESP'])
paths = json.load(open('/tmp/ristretto_paths.json'))
token = os.environ['NETLIFY_AUTH_TOKEN']
for sha in resp.get('required', []):
    p = paths.get(sha)
    if not p: continue
    r = subprocess.run(['curl','-s','-X','PUT',
        '-H','Content-Type: application/octet-stream',
        '-H', f'Authorization: Bearer {token}',
        '--data-binary', f'@{p}',
        f"https://api.netlify.com/api/v1/deploys/{resp['id']}/files/{sha}"], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"[deploy] upload failed: {p}: {r.stderr}", file=sys.stderr); sys.exit(1)
    print(f"  uploaded {p}")
PYEOF
fi

sleep 2
FINAL=$(curl -s -H "Authorization: Bearer $NETLIFY_AUTH_TOKEN" "https://api.netlify.com/api/v1/deploys/$DEPLOY_ID")
echo "$FINAL" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'[deploy] state={d.get(\"state\")} url={d.get(\"ssl_url\")}')"
echo "[deploy] Done at $(date)"
