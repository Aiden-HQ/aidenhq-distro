// get.aidenhq.ai's installer: GitHub's latest published install.sh, cached, with the last good copy when GitHub fails.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { installer, isCut } from "./worker.js";

const repo = readFileSync(new URL("../install.sh", import.meta.url), "utf8");
const cut = (rel) => repo.replace(/^DEFAULT_RELEASE=.*$/m, `DEFAULT_RELEASE=${rel}`).replace(/^RELEASE_SHA256=""$/m, `RELEASE_SHA256="${"a".repeat(64)}"`)
  .replace(/^RELEASE_COMMIT=""$/m, `RELEASE_COMMIT="${"b".repeat(40)}"`);
// The Cache API, as the worker uses it: match and put by URL; `expire` drops the fresh copy as its max-age would.
function cache() {
  const m = new Map();
  return { m, match: async (k) => (m.has(k) ? new Response(m.get(k)) : undefined), put: async (k, r) => void m.set(k, await r.text()), expire: () => m.delete("https://get.aidenhq.ai/.installer/fresh") };
}
const github = (answers) => {
  const calls = [];
  const get = async (u) => { calls.push(u); const a = answers.shift(); if (a instanceof Error) throw a; return a; };
  return { calls, get };
};

test("only a cut installer counts: the repo's own copy doesn't", () => {
  assert.equal(isCut(repo), false);
  assert.equal(isCut(cut("2026.11.18.1")), true);
});

test("the latest release's installer is served and cached; GitHub failing serves the last good copy", async () => {
  const c = cache();
  const g = github([new Response(cut("2026.11.18")), new Response("nope", { status: 503 }), new Error("network"), new Response(repo)]);
  assert.equal(await installer(c, g.get), cut("2026.11.18"));
  assert.match(g.calls[0], /\/releases\/latest\/download\/install\.sh$/);
  assert.equal(await installer(c, g.get), cut("2026.11.18"));
  assert.equal(g.calls.length, 1, "a fresh copy is served from the cache");
  for (let i = 0; i < 3; i++) { c.expire(); assert.equal(await installer(c, g.get), cut("2026.11.18")); }
  assert.equal(g.calls.length, 4);
});

test("nothing good yet and GitHub failing: no installer", async () => {
  assert.equal(await installer(cache(), github([new Error("network")]).get), null);
  assert.equal(await installer(cache(), github([new Response(repo)]).get), null);
});
