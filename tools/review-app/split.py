"""Split a design doc into reviewable entries.

The shape it understands (the shape of plans/language-cheat-sheet.md):

  ## Section heading
  **Entry title.** Prose ... *(status tag)*
  ```
  code
  ```
  - **OH Comment**: an earlier review note (kept apart, shown in yellow)

An entry starts at a paragraph that opens with **bold text**; it runs to the
next such paragraph or `## ` heading. Text before a section's first entry
becomes an entry named after the section. Each entry keeps the line range it
came from, so comments can be written back into the file (apply_comments.py).
"""
import re

OH = re.compile(r'^- \*\*OH Comment\*\*:\s*(.*)$')


def slug(s):
    s = re.sub(r'[^a-z0-9]+', '-', s.replace('`', '').lower()).strip('-')
    return s[:40].strip('-') or 'x'


def split(text):
    src = text.split('\n')
    sections = []
    sec = {'title': 'About this page', 'id': 'about', 'entries': []}
    cur = None
    used = set()
    in_code = False

    def flush(end):
        nonlocal cur
        if cur is None:
            return
        lines = src[cur['start']:end]
        # trim blank / rule lines at the end, remembering where the entry really ends
        last = len(lines)
        while last and lines[last - 1].strip() in ('', '---'):
            last -= 1
        first = 0
        while first < last and lines[first].strip() in ('', '---'):
            first += 1
        body_lines = lines[first:last]
        if not body_lines:
            cur = None
            return
        oh, body = [], []
        for l in body_lines:
            m = OH.match(l)
            (oh.append(m.group(1)) if m else body.append(l))
        md = re.sub(r'\n{3,}', '\n\n', '\n'.join(body)).strip()
        tags = [re.sub(r'\s+', ' ', x) for x in re.findall(r'\*\(([^)]+)\)\*', md)]
        base = sec['id'] + '--' + slug(cur['title'])
        eid, i = base, 1
        while eid in used:
            i += 1
            eid = f'{base}-{i}'
        used.add(eid)
        sec['entries'].append({
            'id': eid, 'title': cur['title'], 'md': md,
            'status': tags[0] if tags and sec['id'] != 'about' else '',
            'oh': oh,
            # 0-based, end-exclusive line range of the entry's content
            'lines': [cur['start'] + first, cur['start'] + last],
        })
        cur = None

    for n, l in enumerate(src):
        if l.startswith('```'):
            in_code = not in_code
            if cur is None:
                cur = {'title': sec['title'], 'start': n}
            continue
        if in_code:
            continue
        if l.startswith('# '):
            continue
        if l.startswith('## '):
            flush(n)
            if sec['entries']:
                sections.append(sec)
            t = l[3:].strip()
            sec = {'title': t, 'id': slug(t), 'entries': []}
            continue
        m = re.match(r'^\*\*(.+?)\*\*', l)
        if m and (n == 0 or src[n - 1].strip() == ''):
            flush(n)
            cur = {'title': m.group(1).strip().rstrip('.'), 'start': n}
        if cur is None:
            cur = {'title': sec['title'], 'start': n}
    flush(len(src))
    sections.append(sec)
    return sections
