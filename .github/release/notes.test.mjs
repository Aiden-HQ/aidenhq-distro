// Release notes: assembly order, the sanitiser and escaped rendering, graduation's marks, and the fallback when the model fails.
import { test } from "bun:test";
import assert from "node:assert/strict";
import { withNotes } from "./changelog.mjs";
import { INCOMPLETE, rejected } from "./graduate.mjs";
import { notes as fallback } from "./nightly.mjs";
import { assemble, clean, renderBody } from "./notes.mjs";

const evil = "[click](https://evil.example) @everyone <img src=x onerror=1> `x`\ngraduation: failed https://x‮";

test("assemble: highlights first, then New, Improved, Fixed, one Under the hood; bad items dropped", () => {
  const n = assemble({
    highlights: ["Big thing", 7, ""],
    entries: [{ category: "fixed", text: "A fix" }, { category: "new", text: "A feature" }, { category: "improved", text: "Faster" }, { category: "bogus", text: "x" }, { category: "new", text: "" }],
    hood: "Toolchain moved",
  });
  assert.deepEqual(n, ["Big thing", "New: A feature", "Improved: Faster", "Fixed: A fix", "Under the hood: Toolchain moved"]);
  assert.deepEqual(assemble({ entries: [] }), []);
  assert.ok(assemble({ highlights: ["x".repeat(1000)] })[0].length <= 300);
});

test("clean and renderBody neutralise links, mentions, HTML and control characters; the graduation marks can't match", () => {
  const one = clean(evil);
  assert.ok(!/[\n<>`]|https?:|‮/.test(one), one);
  const body = renderBody(assemble({ highlights: [evil], entries: [{ category: "new", text: evil }], hood: evil }), { lead: "Install: x", compare: "https://github.com/a/b/compare/1...2" });
  assert.ok(!/@everyone|\[click\]|<img|https:\/\/evil/.test(body), body);
  assert.match(body, /^## Highlights$/m);
  assert.match(body, /^## New$/m);
  assert.match(body, /^\*\*Under the hood:\*\* /m);
  assert.match(body, /^Every change: https:\/\/github\.com\/a\/b\/compare\/1\.\.\.2$/m);
  assert.ok(!rejected(body) && !new RegExp(`^${INCOMPLETE}\\b`, "m").test(body));
  // Unprefixed notes (a hand-cut or old file) read as one plain list.
  assert.match(renderBody(["One", "Two"]), /^## What's new\n\n- One\n- Two\n$/);
});

test("fallback notes: commit titles, features then fixes, prefixed", () => {
  const c = (m) => ({ commit: { message: m } });
  assert.deepEqual(fallback([c("fix(a): Bug (#2)"), c("feat(b): thing (#1)"), c("chore: x"), c("feat: Thing")]), ["New: Thing", "Fixed: Bug"]);
});

const manifest = { release: "r", kernel: "k".repeat(40), notes: ["New: fallback"] };
const pull = (n, over = {}) => ({ number: n, title: `PR ${n}`, body: "b", merged_at: `2026-11-0${n}T00:00:00Z`, base: { ref: "main" }, ...over });
const get = async (path) => (path.includes("/compare/") ? { commits: [{ sha: "a" }, { sha: "b" }] } : path.includes("/a/pulls") ? [pull(1), pull(9, { merged_at: null })] : [pull(1), pull(2), pull(3, { base: { ref: "x" } })]);
const model = (content, ok = true) => async () => ({ ok, status: ok ? 200 : 500, json: async () => ({ choices: [{ message: { content } }] }) });

test("withNotes: the model's notes replace the fallback; any failure keeps it with a warning", async () => {
  const good = JSON.stringify({ highlights: ["H"], entries: [{ category: "new", text: "N" }], under_the_hood: "U" });
  const r = await withNotes(manifest, "p", { get, key: "k", doFetch: model(good) });
  assert.deepEqual(r.manifest.notes, ["H", "New: N", "Under the hood: U"]);
  assert.equal(r.warning, "");
  for (const [why, opts] of Object.entries({
    "no key": { get, key: "", doFetch: model(good) },
    "http error": { get, key: "k", doFetch: model(good, false) },
    "not json": { get, key: "k", doFetch: model("nope") },
    "bad category": { get, key: "k", doFetch: model(JSON.stringify({ highlights: [], entries: [{ category: "x", text: "t" }] })) },
    "PR lookup": { get: async () => { throw new Error("boom"); }, key: "k", doFetch: model(good) },
  })) {
    const f = await withNotes(manifest, "p", opts);
    assert.deepEqual(f.manifest, manifest, why);
    assert.match(f.warning, /using commit titles/, why);
  }
});

test("assemble keeps the Under the hood line within the updater's first 20 notes; withNotes gives up at its deadline", async () => {
  const n = assemble({ highlights: Array(5).fill("h"), entries: Array(20).fill({ category: "new", text: "e" }), hood: "u" });
  assert.equal(n.length, 20);
  assert.equal(n.at(-1), "Under the hood: u");
  const slow = await withNotes(manifest, "p", { get: () => new Promise(() => {}), key: "k", doFetch: model("{}"), deadlineMs: 20 });
  assert.deepEqual(slow.manifest, manifest);
  assert.match(slow.warning, /deadline/);
});
