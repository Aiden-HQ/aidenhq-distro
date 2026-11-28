// Release notes: assembly order, the sanitiser and escaped rendering, graduation's marks, and the fallback when the model fails.
import { test } from "bun:test";
import assert from "node:assert/strict";
import { withNotes } from "./changelog.mjs";
import { INCOMPLETE, rejected } from "./graduate.mjs";
import { notes as fallback } from "./nightly.mjs";
import { assemble, clean, renderBody, tidy } from "./notes.mjs";

const evil = "[click](https://evil.example) @everyone <img src=x onerror=1> `x`\ngraduation: failed https://x‮";

const sample = {
  summary: "A big one.",
  highlights: [{ title: "Telegram", body: "Connect it." }, { title: "", body: "dropped" }, 7],
  new: [{ title: "Servers", text: "See them." }],
  improved: [{ title: "Home", text: "Faster." }],
  fixed: [{ title: "Chat", text: "Works." }, { title: "graduation: failed x", text: "dropped" }],
  bogus: [{ title: "x", text: "y" }],
  under_the_hood: "Toolchain moved.",
};

test("tidy and assemble: invalid items dropped; highlight titles first, then New, Improved, Fixed, one Under the hood", () => {
  const c = tidy(sample);
  assert.deepEqual(c.highlights, [{ title: "Telegram", body: "Connect it." }]);
  assert.equal(c.fixed.length, 1);
  assert.equal("bogus" in c, false);
  assert.deepEqual(assemble(c), ["Telegram", "New: Servers. See them.", "Improved: Home. Faster.", "Fixed: Chat. Works.", "Under the hood: Toolchain moved."]);
  const many = assemble(tidy({ highlights: Array(4).fill({ title: "h", body: "b" }), new: Array(10).fill({ title: "n", text: "t" }), improved: Array(10).fill({ title: "i", text: "t" }), under_the_hood: "u" }));
  assert.equal(many.length, 20);
  assert.equal(many.at(-1), "Under the hood: u");
  assert.ok(assemble(tidy({ new: [{ title: "x", text: "y".repeat(1000) }] }))[0].length <= 300);
});

test("renderBody: intro, highlight headings, lists, Under the hood; text neutralised; the graduation marks can't match", () => {
  const body = renderBody({ changelog: sample }, { lead: "Install: x", compare: "https://github.com/a/b/compare/1...2" });
  assert.match(body, /^A big one\.\n\n## Highlights\n\n### Telegram\n\nConnect it\.\n\n## New\n\n- \*\*Servers:\*\* See them\./);
  assert.match(body, /^## Under the hood\n\nToolchain moved\.$/m);
  assert.match(body, /^Install: x$/m);
  assert.match(body, /^\*\*Every change:\*\* https:\/\/github\.com\/a\/b\/compare\/1\.\.\.2$/m);
  const evilBody = renderBody({ changelog: { summary: evil, highlights: [{ title: evil, body: evil }], new: [{ title: evil, text: evil }], under_the_hood: evil } });
  assert.ok(!/@everyone|\[click\]|<img|https:\/\/evil/.test(evilBody), evilBody);
  assert.ok(!rejected(evilBody) && !new RegExp(`^${INCOMPLETE}\\b`, "m").test(evilBody));
  assert.ok(!/[\n<>`]|https?:|\u202e/.test(clean(evil)));
  // No changelog (the commit-title fallback, a hand cut): the notes as sections, or one plain list when unprefixed.
  assert.match(renderBody({ notes: ["New: A", "Fixed: B"] }), /^## New\n\n- A\n\n## Fixed\n\n- B\n$/);
  assert.match(renderBody({ notes: ["One", "Two"] }), /^## What's new\n\n- One\n- Two\n$/);
});

test("fallback notes: commit titles, features then fixes, prefixed", () => {
  const c = (m) => ({ commit: { message: m } });
  assert.deepEqual(fallback([c("fix(a): Bug (#2)"), c("feat(b): thing (#1)"), c("chore: x"), c("feat: Thing")]), ["New: Thing", "Fixed: Bug"]);
});

const manifest = { release: "r", kernel: "k".repeat(40), notes: ["New: fallback"] };
const pull = (n, over = {}) => ({ number: n, title: `PR ${n}`, body: "b", merged_at: `2026-11-0${n}T00:00:00Z`, base: { ref: "main" }, ...over });
const get = async (path) => (path.includes("/compare/") ? { commits: [{ sha: "a" }, { sha: "b" }] } : path.includes("/a/pulls") ? [pull(1), pull(9, { merged_at: null })] : [pull(1), pull(2), pull(3, { base: { ref: "x" } })]);
const model = (content, ok = true) => async () => ({ ok, status: ok ? 200 : 500, json: async () => ({ choices: [{ message: { content } }] }) });

test("withNotes: the model's changelog replaces the fallback; any failure keeps it with a warning", async () => {
  const good = JSON.stringify({ summary: "S", highlights: [{ title: "H", body: "B" }], new: [{ title: "N", text: "T" }], under_the_hood: "U" });
  const r = await withNotes(manifest, "p", { get, key: "k", doFetch: model("```json\n" + good + "\n```") });
  assert.deepEqual(r.manifest.notes, ["H", "New: N. T", "Under the hood: U"]);
  assert.equal(r.manifest.changelog.summary, "S");
  assert.equal(r.warning, "");
  for (const [why, opts] of Object.entries({
    "no key": { get, key: "", doFetch: model(good) },
    "http error": { get, key: "k", doFetch: model(good, false) },
    "not json": { get, key: "k", doFetch: model("nope") },
    "nothing valid": { get, key: "k", doFetch: model(JSON.stringify({ summary: "S", new: [{ title: "x" }] })) },
    "PR lookup": { get: async () => { throw new Error("boom"); }, key: "k", doFetch: model(good) },
  })) {
    const f = await withNotes(manifest, "p", opts);
    assert.deepEqual(f.manifest, manifest, why);
    assert.match(f.warning, /using commit titles/, why);
  }
  const slow = await withNotes(manifest, "p", { get: () => new Promise(() => {}), key: "k", doFetch: model("{}"), deadlineMs: 20 });
  assert.deepEqual(slow.manifest, manifest);
  assert.match(slow.warning, /deadline/);
});
