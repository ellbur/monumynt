#!/usr/bin/env python3
"""Build the phone review page for a design doc.

  python3 tools/review-app/build.py plans/language-cheat-sheet.md out.html \
      --title "Cheat Sheet Review" --source "plans/language-cheat-sheet.md @ language-cheat-sheet 657d93f"

Then publish out.html as an Artifact with capabilities {"db": {}}. See README.md.
"""
import argparse, html, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from split import split

ap = argparse.ArgumentParser()
ap.add_argument('doc')
ap.add_argument('out')
ap.add_argument('--title', required=True, help='page name, e.g. "Cheat Sheet Review"')
ap.add_argument('--source', help='where the doc came from (path @ branch commit); defaults to the doc path')
ap.add_argument('--entries-json', help='also write the parsed entries here, for checking the split')
a = ap.parse_args()

sections = split(open(a.doc, encoding='utf-8').read())
if a.entries_json:
    json.dump(sections, open(a.entries_json, 'w'), ensure_ascii=False, indent=1)
safe = lambda o: json.dumps(o, ensure_ascii=False).replace('</', '<\\/')
tpl = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'template.html'), encoding='utf-8').read()
title = html.escape(a.title).replace('`', '').replace('$', '')
out = (tpl.replace('__DATA__', safe(sections))
          .replace('__SOURCE__', safe(a.source or a.doc))
          .replace('__TITLE__', title))
open(a.out, 'w', encoding='utf-8').write(out)
n = sum(len(s['entries']) for s in sections)
print(f'{a.out}: {n} entries in {len(sections)} sections')
