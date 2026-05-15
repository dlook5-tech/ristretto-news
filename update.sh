#!/bin/bash
# Ristretto News — minimal Grok pipeline (parallel call per tab, Pure Views curation)
set -e
cd "$(dirname "$0")"

[ -f .env ] && source .env
: "${XAI_API_KEY:?XAI_API_KEY required (set via .env locally, GitHub Secrets in CI)}"

echo "=== Ristretto News Update $(date) ==="

TABS=(world usa business top msm sports elon pods pg6 recipe science local conspiracy comedy)

# Per-tab prompts kept short — single Grok call per tab, returns JSON array.
prompt_for() {
    local tab=$1
    case "$tab" in
        world)    echo "Top 5 highest-view X posts (past 24h) about WORLD news — international events outside the US." ;;
        usa)      echo "Top 5 highest-view X posts (past 24h) about US national news — politics, federal events." ;;
        business) echo "Top 5 highest-view X posts (past 24h) about business / markets / finance / economy." ;;
        top)      echo "Top 5 highest-view X posts (past 24h) — the absolute most-viewed across the platform." ;;
        msm)      echo "Top 5 highest-view X posts (past 24h) from mainstream-media accounts (NYT, WaPo, CNN, BBC, Reuters, AP, etc.)." ;;
        sports)   echo "Top 5 highest-view X posts (past 24h) about sports — major leagues, big games, athlete news." ;;
        elon)     echo "Top 5 highest-view X posts (past 24h) by or about Elon Musk." ;;
        pods)     echo "Top 5 highest-view X posts (past 24h) about or from major podcasters (Rogan, Lex, Theo Von, etc.)." ;;
        pg6)      echo "Top 5 highest-view X posts (past 24h) about celebrity / entertainment / pop-culture news." ;;
        recipe)   echo "Top 5 highest-view X posts (past 24h) about recipes / cooking / food." ;;
        science)  echo "Top 5 highest-view X posts (past 24h) about science / tech / research breakthroughs." ;;
        local)    echo "Top 5 highest-view X posts (past 24h) about Southern California / Orange County / Newport Beach local news." ;;
        conspiracy) echo "Top 5 highest-view X posts (past 24h) about conspiracies / under-reported stories / fringe theories." ;;
        comedy)   echo "Top 5 highest-view X posts (past 24h) that are funny — jokes, memes, comedy clips going viral." ;;
    esac
}

call_grok() {
    local tab=$1
    local user_prompt="$(prompt_for "$tab")
Return ONLY a JSON array, no markdown, no prose. Each item:
{\"handle\":\"username\",\"url\":\"https://x.com/user/status/<id>\",\"headline\":\"neutral one-line summary\",\"body\":\"actual post text\",\"engagement\":\"500K views\",\"views\":500000}
URLs MUST be real X status URLs. Views must be the actual view count number."

    local payload
    payload=$(python3 -c '
import json, sys
prompt = sys.argv[1]
print(json.dumps({
    "model": "grok-4-fast",
    "input": [{"role": "user", "content": prompt}],
    "tools": [{"type": "x_search"}],
    "max_output_tokens": 4000
}))
' "$user_prompt")

    curl -s --max-time 240 https://api.x.ai/v1/responses \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $XAI_API_KEY" \
        -d "$payload" > "/tmp/ristretto_raw_${tab}.json" \
      || echo '{"error":"curl failed"}' > "/tmp/ristretto_raw_${tab}.json"
    echo "  [done] $tab"
}

export -f call_grok prompt_for
export XAI_API_KEY

echo "Calling Grok for ${#TABS[@]} tabs in parallel..."
for tab in "${TABS[@]}"; do
    call_grok "$tab" &
done
wait
echo "All Grok calls complete."

# Merge per-tab responses into single JSON keyed by tab.
python3 << 'PY' > /tmp/grok_raw.json
import json, re

TABS = ['world','usa','business','top','msm','sports','elon','pods',
        'pg6','recipe','science','local','conspiracy','comedy']

def extract_text(resp):
    """Pull text content from xAI /v1/responses shape."""
    if isinstance(resp.get('output'), list):
        chunks = []
        for o in resp['output']:
            for c in o.get('content', []) or []:
                t = c.get('text') if isinstance(c, dict) else None
                if t: chunks.append(t)
        if chunks: return '\n'.join(chunks)
    if isinstance(resp.get('choices'), list) and resp['choices']:
        msg = resp['choices'][0].get('message', {})
        if isinstance(msg, dict): return msg.get('content', '') or ''
    return ''

out = {}
for tab in TABS:
    try:
        with open(f'/tmp/ristretto_raw_{tab}.json') as f:
            resp = json.load(f)
        if resp.get('error'):
            out[tab] = []
            continue
        text = extract_text(resp)
        # strip fences
        text = re.sub(r'^```[a-zA-Z]*\s*', '', text.strip())
        text = re.sub(r'\s*```\s*$', '', text)
        # find first JSON array
        m = re.search(r'\[.*\]', text, re.DOTALL)
        out[tab] = json.loads(m.group(0)) if m else []
    except Exception as e:
        print(f"  [merge-warn] {tab}: {e}")
        out[tab] = []

print(json.dumps(out))
PY

echo "Running Grok's curator..."
python3 parse_grok.py < /tmp/grok_raw.json

echo "=== Update Complete $(date) ==="
