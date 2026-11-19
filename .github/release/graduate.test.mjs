// graduate.mjs on fixture release lists: which cut is tested, what result is accepted, when promotion goes ahead.
import { test } from "node:test";
import assert from "node:assert/strict";
import { CHECKS, checkIdentity, decide, identityOf, markRejected, onFailure, pick, rateLimitWait, rejected, validateResult } from "./graduate.mjs";

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
  assert.equal(c("failure", "candidate", "incomplete"), "issue", "a rate limit or a step cut short: a check never said no");
  assert.equal(c("failure", "candidate", ""), "issue", "the job timed out before the verdict");
  assert.equal(c("cancelled", "candidate", ""), "issue");
  assert.equal(c("success", "candidate", "passed", "failure"), "issue", "promotion failing never rejects");
  assert.equal(c("success", "candidate", "passed", "success"), "none");
  assert.equal(c("skipped", "", "", "skipped"), "none");
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
  const good = { release: "2026.11.19", release_id: 7, tag_sha: SHA, kernel: K, baseline: "2026.11.18.1", passed: true, checks: Object.fromEntries(CHECKS.map((c) => [c, true])), notes: ["hello app: grad-hello"] };
  assert.equal(validateResult(good, id, "2026.11.18.1"), good);
  assert.throws(() => validateResult({ ...good, release: "2026.11.20" }, id, "2026.11.18.1"), /another release/);
  assert.throws(() => validateResult({ ...good, kernel: "3".repeat(40) }, id, "2026.11.18.1"), /another release/);
  assert.throws(() => validateResult(good, id, "2026.11.18"), /another baseline/);
  assert.throws(() => validateResult({ ...good, checks: { ...good.checks, chat_reply: false } }, id, "2026.11.18.1"), /didn't pass: chat_reply/);
  assert.throws(() => validateResult({ ...good, checks: { ...good.checks, extra: true } }, id, "2026.11.18.1"), /exactly/);
  assert.throws(() => validateResult({ ...good, passed: "true" }, id, "2026.11.18.1"), /didn't pass/);
  assert.throws(() => validateResult({ ...good, injected: 1 }, id, "2026.11.18.1"), /exactly/);
  assert.throws(() => validateResult({ ...good, notes: ["x".repeat(301)] }, id, "2026.11.18.1"), /notes/);
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
