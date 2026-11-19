// graduate.mjs on fixture release lists: which cut is tested, what result is accepted, when promotion goes ahead.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildResult, child, readChecks, runParallel, verdictOf, writeCheck } from "./graduate-checks.mjs";
import { CHECKS, checkIdentity, decide, identityOf, markRejected, noteIncomplete, onFailure, pick, rateLimitWait, rejected, validateResult } from "./graduate.mjs";

const d = (c) => `sha256:${c.repeat(64)}`;
const rel = (tag, { pre = true, draft = false, body = "", id = 1 } = {}) => ({
  id, tag_name: tag, draft, prerelease: pre, body,
  assets: [{ name: "install.sh", digest: d("a") }, { name: `${tag}.json`, digest: d("b") }],
});
const SHA = "1".repeat(40), K = "2".repeat(40);

test("select: the oldest pending pre-release above latest; rejected, drafts, graduated and older ones skipped; none is null", () => {
  const list = [
    rel("2026.11.20"), rel("2026.11.19.1"), rel("2026.11.19", { body: "notes\n\ngraduation: failed https://github.com/x/y/actions/runs/1" }),
    rel("2026.11.18.2", { draft: true }), rel("2026.11.18.1", { pre: false }), rel("2026.11.18"), rel("not-a-release"),
  ];
  assert.equal(pick(list, "2026.11.18.1").tag_name, "2026.11.19.1");
  assert.equal(pick(list, "2026.11.19.1").tag_name, "2026.11.20");
  assert.equal(pick(list, "2026.11.20"), null);
  assert.equal(pick([rel("2026.11.19", { body: "graduation: failed https://x" })], "2026.11.18"), null);
  assert.throws(() => pick(list, undefined), /no graduated release/);
});

test("only the candidate's own failed checks reject it; the baseline, rate limits, timeouts, cancels and promotion only open an issue", () => {
  const c = (test, reached, verdict, promote = "skipped") => onFailure({ test, reached, verdict, promote });
  assert.equal(c("failure", "candidate", "failed"), "mark");
  assert.equal(c("failure", "", "failed"), "issue", "a baseline check failed before the upgrade");
  assert.equal(c("failure", "candidate", "incomplete"), "incomplete", "reached the candidate, a check never said no: counted");
  assert.equal(c("failure", "candidate", ""), "incomplete");
  assert.equal(c("failure", "", "incomplete"), "issue", "a rate limit before the candidate was prepared: not counted");
  assert.equal(c("cancelled", "candidate", ""), "issue");
  assert.equal(c("success", "candidate", "passed", "failure"), "issue", "promotion failing never rejects");
  assert.equal(c("success", "candidate", "passed", "success"), "none");
  assert.equal(c("skipped", "", "", "skipped"), "none");
});

test("a candidate that never completes is rejected at its third incomplete run, once per run", () => {
  const r = (n) => `https://github.com/a/b/actions/runs/${n}`;
  let n = noteIncomplete("Install: x", r(1));
  assert.deepEqual([n.count, n.rejected, rejected(n.body)], [1, false, false]);
  n = noteIncomplete(n.body, r(1));
  assert.equal(n.count, 1, "a re-run of the same run's reject job counts once");
  n = noteIncomplete(n.body, r(2));
  assert.deepEqual([n.count, n.rejected], [2, false]);
  n = noteIncomplete(n.body, r(3));
  assert.deepEqual([n.count, n.rejected, rejected(n.body)], [3, true, true]);
  assert.match(n.body, /graduation: failed .*runs\/3 \(never completed in 3 runs\)/);
  assert.equal(pick([{ id: 1, tag_name: "2026.11.20", draft: false, prerelease: true, body: n.body }, { id: 2, tag_name: "2026.11.21", draft: false, prerelease: true, body: "" }], "2026.11.19").tag_name, "2026.11.21", "select moves on");
});

test("a rate limit waits as GitHub asks; any other 403 is a refusal", () => {
  const h = (o) => new Headers(o);
  assert.equal(rateLimitWait(429, h({ "retry-after": "30" })), 30_000);
  assert.equal(rateLimitWait(403, h({ "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1000" }), 900_000), 101_000);
  assert.equal(rateLimitWait(403, h({})), null);
  assert.equal(rateLimitWait(500, h({ "retry-after": "5" })), null);
});

test("the rejected mark is one line, added once", () => {
  assert.ok(!rejected("Install: curl ... Tested: {}"));
  assert.ok(!rejected("we talk about graduation: failed runs"), "only at a line's start");
  const once = markRejected("Install: x", "https://github.com/a/b/actions/runs/9");
  assert.ok(rejected(once));
  assert.equal(markRejected(once, "https://github.com/a/b/actions/runs/10"), once);
});

test("the test's result is accepted only when it names the selected release and baseline, has exactly the checks, all true", () => {
  const id = checkIdentity(identityOf(rel("2026.11.19", { id: 7 }), SHA, K));
  const good = { release: "2026.11.19", release_id: 7, tag_sha: SHA, kernel: K, baseline: "2026.11.18.1", passed: true, checks: Object.fromEntries(CHECKS.map((c) => [c, true])), notes: ["hello app: grad-hello"], timings: { install: 540, upgrade: 300 } };
  assert.equal(validateResult(good, id, "2026.11.18.1"), good);
  assert.throws(() => validateResult({ ...good, release: "2026.11.20" }, id, "2026.11.18.1"), /another release/);
  assert.throws(() => validateResult({ ...good, kernel: "3".repeat(40) }, id, "2026.11.18.1"), /another release/);
  assert.throws(() => validateResult(good, id, "2026.11.18"), /another baseline/);
  assert.throws(() => validateResult({ ...good, checks: { ...good.checks, chat_reply: false } }, id, "2026.11.18.1"), /didn't pass: chat_reply/);
  assert.throws(() => validateResult({ ...good, checks: { ...good.checks, extra: true } }, id, "2026.11.18.1"), /exactly/);
  assert.throws(() => validateResult({ ...good, passed: "true" }, id, "2026.11.18.1"), /didn't pass/);
  assert.throws(() => validateResult({ ...good, injected: 1 }, id, "2026.11.18.1"), /exactly/);
  assert.throws(() => validateResult({ ...good, notes: ["x".repeat(301)] }, id, "2026.11.18.1"), /notes/);
  assert.throws(() => validateResult({ ...good, timings: { install: -1 } }, id, "2026.11.18.1"), /timings/);
  assert.throws(() => validateResult({ ...good, timings: { "x y": 1 } }, id, "2026.11.18.1"), /timings/);
  const { timings: _, ...untimed } = good;
  assert.throws(() => validateResult(untimed, id, "2026.11.18.1"), /exactly/);
  assert.throws(() => checkIdentity({ ...id, tag_sha: "short" }), /malformed/);
});

test("promote: only the selected, unchanged release, never behind latest; a re-run after promotion is done", () => {
  const r = rel("2026.11.19", { id: 7 });
  const id = identityOf(r, SHA, K);
  assert.equal(decide({ release: r, tagSha: SHA, latest: "2026.11.18.1", id }), "promote");
  assert.equal(decide({ release: { ...r, prerelease: false }, tagSha: SHA, latest: "2026.11.19", id }), "done");
  assert.throws(() => decide({ release: r, tagSha: "9".repeat(40), latest: "2026.11.18.1", id }), /tag moved/);
  assert.throws(() => decide({ release: { ...r, assets: [r.assets[0], { name: "2026.11.19.json", digest: d("c") }] }, tagSha: SHA, latest: "2026.11.18.1", id }), /assets changed/);
  assert.throws(() => decide({ release: r, tagSha: SHA, latest: "2026.11.20", id }), /older than the current latest 2026\.11\.20/);
  assert.throws(() => decide({ release: { ...r, body: "graduation: failed https://x" }, tagSha: SHA, latest: "2026.11.18.1", id }), /rejected/);
  assert.throws(() => decide({ release: { ...r, id: 8 }, tagSha: SHA, latest: "2026.11.18.1", id }), /isn't the published/);
});

test("checks side by side: each decides in its own file, a hang is incomplete (never failed), a throw is a no", async () => {
  const dir = mkdtempSync(join(tmpdir(), "grad-"));
  try {
    const hang = () => new Promise(() => {});
    await runParallel(dir, [
      { names: ["a"], ms: 1000, run: async () => [{ name: "a", ok: true, note: "fine" }] },
      { names: ["b", "c"], ms: 1000, run: async () => { writeCheck(dir, "b", true); } }, // a child writes its own; c never
      { names: ["d"], ms: 50, run: hang },
      { names: ["f"], ms: 100, run: child("sleep", ["30"]) }, // killed at its bound
    ]);
    const c = readChecks(dir);
    assert.deepEqual(c.checks, { a: true, b: true });
    assert.ok(c.notes.some((n) => /^c: ended without a result/.test(n)) && c.notes.some((n) => /^d: didn't finish within/.test(n)) && c.notes.some((n) => /^f: didn't finish/.test(n)));
    assert.equal(verdictOf(c.checks, ["a", "b", "c", "d"]), "incomplete", "nothing said no: the candidate stays pending");
    await runParallel(dir, [{ names: ["d", "e"], ms: 1000, run: async () => { throw new Error("refused"); } }]);
    assert.deepEqual(readChecks(dir).checks, { a: true, b: true, d: false, e: false });
    assert.equal(verdictOf(readChecks(dir).checks, ["a", "b", "c", "d", "e"]), "failed");
    writeCheck(dir, "a", null, "late note");
    assert.equal(readChecks(dir).checks.a, true, "a note never undoes a decided check");
    const all = Object.fromEntries(CHECKS.map((n) => [n, true]));
    assert.equal(verdictOf(all), "passed");
    const id = identityOf(rel("2026.11.19", { id: 7 }), SHA, K);
    const { result, verdict } = buildResult(dir, id, "2026.11.18.1");
    assert.equal(verdict, "failed");
    assert.throws(() => validateResult(result, checkIdentity(id), "2026.11.18.1"), /didn't pass/, "the shape promote reads; only its checks fail");
    assert.ok(Object.keys(result.timings).includes("check_a"));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
