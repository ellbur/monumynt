#!/usr/bin/env python3
"""Write review comments back into the doc as `- **OH Comment**:` bullets.

  python3 tools/review-app/apply_comments.py plans/language-cheat-sheet.md <comments> [--dry-run]

<comments> is either a directory of per-document JSON files (what ArtifactData
`list` with `out_dir` saves: <out_dir>/comments/<id>.json) or one JSON file
holding a list of documents. Each document carries `entry` (the card id),
`title` and `text`. Comments go after the entry's last line, below any
earlier OH Comment bullets. Entries are matched by id, then by title; any
comment that matches nothing is reported and left out. The general comment
(id "general") is printed, not written into the doc.
"""
import argparse, glob, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from split import split

ap = argparse.ArgumentParser()
ap.add_argument('doc')
ap.add_argument('comments')
ap.add_argument('--dry-run', action='store_true')
ap.add_argument('--label', default='OH Comment')
a = ap.parse_args()

def load(path):
    if os.path.isdir(path):
        files = glob.glob(os.path.join(path, '**', '*.json'), recursive=True)
        docs = [json.load(open(f)) for f in sorted(files)]
    else:
        docs = json.load(open(path))
        if isinstance(docs, dict):
            docs = docs.get('documents') or list(docs.values())
    out = []
    for d in docs:
        body = d.get('data', d) if isinstance(d.get('data'), dict) else d
        out.append(body)
    return out

text = open(a.doc, encoding='utf-8').read()
lines = text.split('\n')
entries = [e for s in split(text) for e in s['entries']]
by_id = {e['id']: e for e in entries}
by_title = {}
for e in entries:
    by_title.setdefault(e['title'], []).append(e)

inserts = {}  # line index -> [bullet lines]
unmatched, general = [], None
for c in load(a.comments):
    body = (c.get('text') or '').strip()
    if not body:
        continue
    if c.get('entry') == 'general':
        general = body
        continue
    e = by_id.get(c.get('entry'))
    if e is None and len(by_title.get(c.get('title'), [])) == 1:
        e = by_title[c['title']][0]
    if e is None:
        unmatched.append(c)
        continue
    paras = body.split('\n')
    bullet = [f'- **{a.label}**: {paras[0]}'] + [('  ' + p) if p.strip() else '' for p in paras[1:]]
    inserts.setdefault(e['lines'][1], []).append((e, bullet))

for at in sorted(inserts, reverse=True):
    e, _ = inserts[at][0]
    block = [l for _, b in inserts[at] for l in b]
    prev_is_oh = lines[at - 1].startswith('- **')
    lines[at:at] = ([] if prev_is_oh else ['']) + block

n = sum(len(v) for v in inserts.values())
print(f'{n} comments placed', file=sys.stderr)
if general:
    print(f'\nGeneral comment (not written into the doc):\n{general}\n', file=sys.stderr)
for c in unmatched:
    print(f'UNMATCHED: {c.get("entry")} / {c.get("title")}: {c.get("text")!r}', file=sys.stderr)
result = '\n'.join(lines)
if a.dry_run:
    sys.stdout.write(result)
else:
    open(a.doc, 'w', encoding='utf-8').write(result)
