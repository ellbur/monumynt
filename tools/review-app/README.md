# Phone review app for design docs

A way to review a long design doc on a phone. The doc is split into one
card per entry, each card gets a comment box, and the comments are saved
where Claude Code can read them back and write them into the doc.

First used on `plans/language-cheat-sheet.md` (2026-11-14). That review's
page: https://claude.ai/artifact/E69TtmCwffmd4omW3fLMkz (built from
`language-cheat-sheet` at `657d93f`).

## Files

- `split.py` — splits the doc into sections and entries. An entry starts at a
  paragraph that opens with `**bold text**` and runs to the next one or the
  next `## ` heading. Existing `- **OH Comment**:` bullets are pulled out and
  shown separately. Each entry remembers its line range in the file.
- `build.py` — runs the split and fills `template.html`, giving one
  self-contained HTML page.
- `template.html` — the page: cards, comment boxes, a "Looks fine" mark, a
  progress bar, a section picker, a To do / Noted filter, and a
  "Copy all comments" button that copies Markdown.
- `apply_comments.py` — writes the saved comments back into the doc as
  `- **OH Comment**:` bullets under their entries.

## Steps for Claude Code

1. **Build.** Use the exact version of the doc being reviewed:

   ```
   git show <branch>:<doc> > /tmp/doc.md
   python3 tools/review-app/build.py /tmp/doc.md <scratchpad>/review.html \
     --title "Cheat Sheet Review" \
     --source "<doc> @ <branch> <short sha>" \
     --entries-json <scratchpad>/entries.json
   ```

   Check `entries.json` to make sure the split makes sense for this doc.

2. **Publish** `review.html` with the Artifact tool, passing
   `capabilities: {"db": {}}` and an `icon`. Comments are saved in the
   artifact's database, in the `comments` collection, one document per card:
   `{entry, section, title, text, ok, updatedAt}`. `entry` is the card id,
   `ok` is the "Looks fine" mark, and the doc id `general` holds the
   whole-doc comment. Write down the URL and the source commit, as at the
   top of this file.

   The page loads `marked` from cdnjs. Testing locally, the container's proxy
   may block cdnjs; `npm pack marked@12.0.2` gets the same file.

3. **Read the comments back** when the user says the review is done:
   ArtifactData `list` on the artifact URL, collection `comments`, with
   `out_dir` set to a scratch directory.

4. **Apply** them to the same version of the doc the page was built from.
   Card ids come from section and entry titles, so if the doc changed since,
   the script falls back to matching by title and reports anything it can't
   place:

   ```
   python3 tools/review-app/apply_comments.py <doc> <out_dir> --dry-run   # check first
   python3 tools/review-app/apply_comments.py <doc> <out_dir>
   ```

   The general comment is printed, not written into the doc. Entries marked
   "Looks fine" with no text are skipped.

If the user pastes the Markdown from "Copy all comments" instead, each
comment there carries its card id in an `<!-- id: … -->` line, so it can be
placed the same way by hand.
