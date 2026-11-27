import { afterAll, test } from "bun:test";
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { isoWeek, withKeys } from "./image-key.mjs";

const NOW = new Date("2026-11-25T03:00:00Z");
const kernel = mkdtempSync(join(tmpdir(), "image-key-"));
const put = (f, body) => { mkdirSync(join(kernel, f, ".."), { recursive: true }); writeFileSync(join(kernel, f), body); };
put("a/Dockerfile", "FROM scratch\n");
put("b/Dockerfile", "FROM ${BASE}\n");
put("c/Dockerfile", "FROM scratch\n");
const chains = [[{ name: "a", context: "a" }, { name: "b", context: "b", base: "a" }], [{ name: "c", context: "c" }]];
const keys = (c = chains, now = NOW) => Object.fromEntries(withKeys(c, kernel, now).flat().map((i) => [i.name, i.key]));

test("a key is stable and depends on content, parent, week and version", () => {
  const k = keys();
  assert.deepEqual(keys(), k);
  assert.equal(k.a, k.c, "identical content, no parent: the same key (the registry repo tells them apart)");
  put("a/app.js", "1");
  const k2 = keys();
  assert.notEqual(k2.a, k.a);
  assert.notEqual(k2.b, k.b, "a child's key follows its parent's");
  assert.equal(k2.c, k.c, "an unrelated image keeps its key");
  chmodSync(join(kernel, "a/app.js"), 0o755);
  assert.notEqual(keys().a, k2.a, "the executable bit counts");
  symlinkSync("app.js", join(kernel, "c/link"));
  assert.notEqual(keys().c, k.c, "a symlink counts");
  assert.notEqual(keys(chains, new Date("2026-12-02T03:00:00Z")).a, k2.a, "a new week rebuilds");
});

test("git and node_modules are not part of the context", () => {
  const before = keys();
  put("c/.git/HEAD", "x"); put("c/node_modules/x/index.js", "x");
  assert.deepEqual(keys(), before);
});

test("a base that is not earlier in the chain is an error", () => {
  assert.throws(() => withKeys([[{ name: "b", context: "b", base: "a" }]], kernel, NOW));
});

test("isoWeek", () => {
  assert.equal(isoWeek(new Date("2026-11-25T00:00:00Z")), "2026-W48");
  assert.equal(isoWeek(new Date("2027-01-01T00:00:00Z")), "2026-W53");
  assert.equal(isoWeek(new Date("2024-12-30T00:00:00Z")), "2025-W01");
});

afterAll(() => rmSync(kernel, { recursive: true }));
