#!/usr/bin/env python3
"""
parse_grok.py — Hardened Pure Views Version
Minimal, stable, low-maintenance.
"""
import sys, json, re, datetime
import curation

def load_previous_stories():
    """Safely load previous stories for velocity hold"""
    try:
        with open('stories.json', 'r') as f:
            data = json.load(f)
            all_stories = []
            for tab_data in data.get('stories', {}).values():
                all_stories.extend(tab_data.get('stories', []))
            return all_stories
    except:
        return []

raw = sys.stdin.read().strip()

# Clean Grok output
if raw.startswith('```'):
    raw = re.sub(r'^```json?\s*|\s*```$', '', raw, flags=re.MULTILINE)

try:
    start = raw.find('{')
    data = json.loads(raw[start:] if start != -1 else raw)
except Exception as e:
    print(f"JSON parse failed: {e}", file=sys.stderr)
    sys.exit(1)

output = {}
previous = load_previous_stories()

tabs = ['world', 'usa', 'business', 'top', 'msm', 'sports', 'elon', 'pods', 
        'pg6', 'recipe', 'science', 'local', 'conspiracy', 'comedy']

for tab in tabs:
    items = data.get(tab, [])
    if not isinstance(items, list):
        items = [items] if items else []

    cleaned = []
    for item in items:
        if isinstance(item, dict):
            if item.get('handle') and item.get('url'):
                cleaned.append(item)

    # Core curation call - this is the only decision logic
    chosen = curation.curate(tab, previous, cleaned, top_n=3)
    output[tab] = {'stories': chosen}

final = {
    'stories': output,
    'last_updated': datetime.datetime.now().isoformat()
}

with open('stories.json', 'w') as f:
    json.dump(final, f, indent=2)

print("✅ stories.json successfully updated", file=sys.stderr)