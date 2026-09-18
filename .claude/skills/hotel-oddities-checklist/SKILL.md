---
name: hotel-oddities-checklist
description: Pick one unclaimed item off the Hotel Oddities to-do list in Google Docs, propose it to Ethan, claim it, do it, and mark it done. The Google Doc is the only source of truth and its highlight colours are the state machine. Use when asked to work the checklist, pick the next task, or take something off the to-do list.
---

# Hotel Oddities Checklist

The to-do list lives in one Google Doc and nowhere else. Never copy it into the
repo as a second list — the doc's highlight colours are the shared state that
stops two agents doing the same item.

**Doc:** https://docs.google.com/document/d/1XSYE9NFfXukeNxNSQZDPpDswfJOydW8BkIC3arc0ljQ/edit?tab=t.0

## What the colours mean

| Highlight | Hex | Meaning |
| --- | --- | --- |
| none | — | open, nobody has claimed it |
| yellow | `#ffff00` | an agent is working it right now — hands off |
| green | `#00ff00` | done, untested |
| purple | `#9900ff` | Ethan said no LLM does this one — never pick it |

## The run

1. Read the doc (below). If nothing is unhighlighted, say so and stop.
2. Pick one **unhighlighted** item at random. Never pick yellow, green or purple.
3. Work out what it means against this repo — read `README.md` and
   `Documentation\` before guessing. Tell Ethan in **one sentence** what the item
   is, then two or three sentences on how you would fix it and which files you
   would touch. Then ask: yes, no, or skip.
4. **No** → highlight it purple, say it is parked, stop.
   **Skip** → leave it alone, pick another.
   **Yes** → highlight it yellow first, before writing any code. That is the claim,
   and it is what keeps another agent off it.
5. Do the work under the repo's rules in `CLAUDE.md` (docs updated, no code
   comments, commit only what you touched).
6. Highlight it green when the code is written. Green means done-but-untested —
   Ethan tests it, you never play test.
7. If you abandon the item, put it back to no highlight. Never leave it yellow.

## Reading the doc

Open the doc in a tab with the Claude in Chrome tools, then parse the HTML export
from the page's own context — it carries the exact highlight hex per line, which
nothing in the rendered page gives you cheaply.

`DOMParser` is blocked on this page by Trusted Types, so parse with regex:

```js
const id = "1XSYE9NFfXukeNxNSQZDPpDswfJOydW8BkIC3arc0ljQ";
const html = await fetch(`https://docs.google.com/feeds/download/documents/export/Export?id=${id}&exportFormat=html`, {credentials:"include"}).then(r=>r.text());
const styles = {};
for (const m of html.matchAll(/\.([a-zA-Z0-9_-]+)\{([^}]*)\}/g)) {
  const bg = m[2].match(/background-color:\s*([^;]+)/);
  if (bg) styles[m[1]] = bg[1].trim();
}
const strip = s => s.replace(/<[^>]+>/g,"").replace(/&amp;/g,"&").replace(/&#39;/g,"'").replace(/ /g," ").trim();
const items = [];
let docLine = 0;
for (const p of html.matchAll(/<(p|li)\b[^>]*>([\s\S]*?)<\/\1>/g)) {
  docLine++;
  const text = strip(p[2]);
  if (!text) continue;
  const colors = new Set();
  for (const s of p[2].matchAll(/<span class="([^"]*)"[^>]*>([\s\S]*?)<\/span>/g)) {
    if (!strip(s[2])) continue;
    for (const c of s[1].split(/\s+/)) if (styles[c] && styles[c] !== "#ffffff" && styles[c] !== "transparent") colors.add(styles[c]);
  }
  items.push({docLine, text, color: [...colors][0] || ""});
}
JSON.stringify(items);
```

`docLine` counts **every** paragraph including blank ones — that is the number the
cursor navigation below needs. Keep the output small; the result truncates, so
filter to what you need (open items only, or a slice) rather than dumping all 58.

## Writing a highlight

Two things that will waste your time if you do not know them:

- **Mouse clicks do not land in the Docs canvas.** Coordinates are off and a
  click lands on a different line, or nowhere. Move the cursor with the keyboard.
- **Toolbar clicks only work through element refs.** Use `find` to get a ref and
  click the ref; clicking toolbar coordinates silently does nothing.

The sequence, for an item at `docLine` N:

1. `computer` key `ctrl+Home`, then key `Down` with `repeat: N-1`, then `Home`,
   then `shift+End`. Screenshot or zoom to confirm the right line is selected in
   blue before going further — if the item's paragraph wraps onto two visual
   lines, `Down` counts visual lines and you will be off; in that case count the
   wraps and adjust.
2. `find` for "Highlight color toolbar button", click that ref.
3. `find` for the swatch ("yellow color swatch in highlight palette", or green,
   or purple), click that ref.
4. Re-run the read above and confirm the line's `color` is the hex you wanted.
   That is the only proof the write landed.

To clear a highlight, pick "None" at the top of the same palette.

## Rules

- One item per run. Do not batch several, and do not claim an item you are not
  about to start.
- Never touch an item's text. Colour is the only thing this skill writes.
- If two items are obviously the same job, still do only the one you claimed.
- If the doc will not load or the highlight will not stick, stop and tell Ethan
  rather than doing the work unclaimed — an unclaimed item is how two agents
  collide.
