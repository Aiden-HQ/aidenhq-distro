// Release graduation (.github/workflows/graduate.yml; README "Release graduation"): which cut to test, whether a test's result
// is the one asked for, and moving the release to graduated (or marking it rejected). GitHub's REST API with GITHUB_TOKEN.
//   node .github/release/graduate.mjs select        the candidate and its baseline (a dry run without $GITHUB_OUTPUT)
//   node .github/release/graduate.mjs env [candidate] [baseline]   the test job's env as shell exports (a manual VM run)
//   node .github/release/graduate.mjs promote <result.json>   (IDENTITY, RUN_ID) graduate it: not a pre-release, latest
//   node .github/release/graduate.mjs reject        (IDENTITY, RUN_URL, BASELINE, TEST_RESULT, REACHED, VERDICT,
//                                                   PROMOTE_RESULT) mark it rejected and open one issue when its own checks
//                                                   failed, or after its 3rd run that reached it without a verdict; anything
//                                                   else (the baseline, the runner, a rate limit before the candidate ran,
//                                                   a cancel, promotion) only an issue: it stays pending (onFailure)
//   (select also opens one "Graduation stalled" issue once the candidate has waited over STALL_HOURS; promote closes it)
//   node .github/release/graduate.mjs rejected      the rejected releases' names, space-separated (release.yml's upgrade test)
// A cut is published as a pre-release (release.yml). The baseline is GitHub's latest release: the newest graduated one, what
// get.aidenhq.ai serves. The candidate is the OLDEST pre-release newer than the baseline that isn't marked rejected (a line
// `graduation: failed <run url>` in its body), so cuts graduate in order and each is tested from the release before it.
// Nothing here runs a release's code.
import { createHash } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";

export const DISTRO = process.env.GITHUB_REPOSITORY || "Aiden-HQ/aidenhq-distro";
const KERNEL = "Aiden-HQ/AidenHQ";
export const NAME = /^\d{4}\.\d{1,2}(\.\d+){0,2}$/;
const SHA = /^[0-9a-f]{40}$/;
const DIGEST = /^sha256:[0-9a-f]{64}$/;
/** The rejected mark: one line in the release's body. Delete the line to have the release tested again. */
export const MARK = "graduation: failed";
/** A run that reached the candidate but ended without a verdict: one line each; at INCOMPLETE_LIMIT of them it is rejected. */
export const INCOMPLETE = "graduation: incomplete";
export const INCOMPLETE_LIMIT = 3;
export const rejected = (body) => new RegExp(`^${MARK}\\b`, "m").test(String(body ?? ""));
/** The variable the baseline's updater must know (kernel/src/updates.ts) to prepare a named pre-release. */
export const CANDIDATE_ENV = "AIDENHQ_UPDATE_CANDIDATE";

export const compare = (a, b) => {
  const [x, y] = [a, b].map((s) => s.split(".").map(Number));
  for (let i = 0; i < 4; i++) { const d = (x[i] ?? 0) - (y[i] ?? 0); if (d) return Math.sign(d); }
  return 0;
};

/** The candidate among `releases` (the API's rows) above `latest` (a tag name): the oldest pending pre-release, or null. */
export function pick(releases, latest) {
  if (!NAME.test(String(latest ?? ""))) throw new Error("there is no graduated release (GitHub's latest) to test from");
  const pending = releases.filter((r) => !r.draft && r.prerelease === true && NAME.test(r.tag_name) && compare(r.tag_name, latest) > 0 && !rejected(r.body));
  return pending.sort((a, b) => compare(a.tag_name, b.tag_name))[0] ?? null;
}

/** A release's two assets, name -> GitHub's sha256 digest; throws unless both are there with a digest. */
export function assetsOf(release) {
  const want = ["install.sh", `${release.tag_name}.json`];
  const out = {};
  for (const n of want) {
    const a = (release.assets ?? []).find((x) => x.name === n);
    if (!a || !DIGEST.test(String(a.digest ?? ""))) throw new Error(`${release.tag_name} has no ${n} asset with a sha256 digest`);
    out[n] = a.digest;
  }
  return out;
}

/** What select names and every later job must match: the release, its tag's commit, its kernel and its assets. */
export const identityOf = (release, tagSha, kernel) => ({ tag: release.tag_name, release_id: release.id, tag_sha: tagSha, kernel, assets: assetsOf(release) });

export function checkIdentity(id) {
  const ok = id && NAME.test(id.tag) && Number.isSafeInteger(id.release_id) && id.release_id > 0 && SHA.test(id.tag_sha) && SHA.test(id.kernel)
    && id.assets && isDeepStrictEqual(Object.keys(id.assets).sort(), ["install.sh", `${id.tag}.json`].sort()) && Object.values(id.assets).every((d) => DIGEST.test(d));
  if (!ok) throw new Error("the select step's identity is malformed");
  return id;
}

/** The checks the test job runs (graduate-instance.sh, graduate-scenario.mjs): each must be in the result, and true. */
export const CHECKS = ["baseline_installed", "upgraded", "running_release", "generation_good", "chat_reply"];

/**
 * The test job's result.json, read as untrusted (it was written next to the candidate's code): exactly these fields, bounded,
 * naming the selected release and baseline, every check true. Returns it; throws on anything else.
 */
export function validateResult(r, id, baseline) {
  const keys = ["release", "release_id", "tag_sha", "kernel", "baseline", "passed", "checks", "notes", "timings"];
  if (!r || typeof r !== "object" || Array.isArray(r) || !isDeepStrictEqual(Object.keys(r).sort(), [...keys].sort())) throw new Error(`the result must have exactly ${keys.join(", ")}`);
  if (r.release !== id.tag || r.release_id !== id.release_id || r.tag_sha !== id.tag_sha || r.kernel !== id.kernel) throw new Error("the result names another release than the one selected");
  if (r.baseline !== baseline) throw new Error("the result names another baseline than the one selected");
  if (!r.checks || typeof r.checks !== "object" || Array.isArray(r.checks) || !isDeepStrictEqual(Object.keys(r.checks).sort(), [...CHECKS].sort())) throw new Error(`the result's checks must be exactly ${CHECKS.join(", ")}`);
  const failed = CHECKS.filter((c) => r.checks[c] !== true);
  if (r.passed !== true || failed.length) throw new Error(`the test didn't pass${failed.length ? `: ${failed.join(", ")}` : ""}`);
  if (!Array.isArray(r.notes) || r.notes.length > 20 || !r.notes.every((n) => typeof n === "string" && n.length <= 300)) throw new Error("the result's notes must be up to 20 short strings");
  const t = r.timings;
  if (!t || typeof t !== "object" || Array.isArray(t) || Object.keys(t).length > 30 || !Object.entries(t).every(([k, v]) => /^[a-z][a-z0-9_]{0,39}$/.test(k) && Number.isSafeInteger(v) && v >= 0)) throw new Error("the result's timings must be up to 30 phases' whole seconds");
  return r;
}

/**
 * Whether to graduate, from what the API says now: "promote", "done" (already graduated and latest: a re-run) or a throw.
 * The release must still be the selected one (id, tag, the tag's commit, both assets' digests), not rejected, and not older
 * than the current latest.
 */
export function decide({ release, tagSha, latest, id }) {
  if (release.id !== id.release_id || release.tag_name !== id.tag || release.draft) throw new Error(`release ${id.release_id} isn't the published ${id.tag} any more`);
  if (tagSha !== id.tag_sha) throw new Error(`${id.tag}'s tag moved: ${String(tagSha).slice(0, 12)}, tested ${id.tag_sha.slice(0, 12)}`);
  if (!isDeepStrictEqual(assetsOf(release), id.assets)) throw new Error(`${id.tag}'s assets changed since it was selected`);
  if (rejected(release.body)) throw new Error(`${id.tag} is marked rejected`);
  if (!release.prerelease && latest === id.tag) return "done";
  if (NAME.test(String(latest ?? "")) && compare(latest, id.tag) > 0) throw new Error(`${id.tag} is older than the current latest ${latest}: refused`);
  return "promote";
}

/**
 * What a run that didn't graduate its candidate does to it. "mark" (rejected) only when the candidate's own checks failed: the
 * test failed after the upgrade started and its result's verdict is "failed" (a check ran and said no). Anything else is an
 * "issue" and the candidate stays pending for the next run: a failure before the upgrade (the baseline, the runner), a
 * verdict that is "incomplete" or missing (a rate limit, a step or job cut short by its timeout, a cancel), or promotion
 * failing after a passing test. "none" when nothing failed.
 */
export function onFailure({ test, reached, verdict, promote }) {
  if (test === "success") return promote === "success" || promote === "skipped" ? "none" : "issue";
  if (test === "failure" && reached === "candidate" && verdict === "failed") return "mark";
  // The test hit its own limit (verdict "harness": e.g. the update waits on an owner's tap it doesn't make): not the candidate's.
  if (verdict === "harness") return "issue";
  // Reached the candidate and failed without a verdict (it hung, a step timed out, its checks never wrote): counted, so a
  // candidate that never completes can't hold every later cut back (noteIncomplete).
  if (test === "failure" && reached === "candidate") return "incomplete";
  return test === "skipped" ? "none" : "issue";
}

/**
 * The body with this run's `graduation: incomplete <run>` line (once per run), and whether that makes INCOMPLETE_LIMIT of
 * them: then it also carries the rejected mark (never completed), so select moves on to the next cut.
 */
export function noteIncomplete(body, run) {
  let b = String(body ?? "");
  if (!b.split("\n").includes(`${INCOMPLETE} ${run}`)) b = `${b.trimEnd()}\n\n${INCOMPLETE} ${run}\n`;
  const n = b.split("\n").filter((l) => l.startsWith(`${INCOMPLETE} `)).length;
  const reject = n >= INCOMPLETE_LIMIT;
  return { body: reject ? markRejected(b, `${run} (never completed in ${n} runs)`) : b, count: n, rejected: reject };
}

/** Release tags in order (YYYY.MM.DD.N): negative when `a` is older. */
const tagOrder = (a, b) => { const x = a.split(".").map(Number), y = b.split(".").map(Number); for (let k = 0; k < Math.max(x.length, y.length); k++) if ((x[k] ?? 0) !== (y[k] ?? 0)) return (x[k] ?? 0) - (y[k] ?? 0); return 0; };
/**
 * The open issues graduation itself opened, closed once `tag` graduates: every cut it couldn't judge (infrastructure failure,
 * incomplete), each older cut it rejected (a later cut graduated past it, so whatever failed it no longer stops releases), and the stall
 * issue of this cut or an older one.
 */
export const closable = (issues, tag) => issues.filter((i) => !i.pull_request && /^github-actions(\[bot\])?$/.test(i.user?.login ?? "") &&
  (/^Graduation of \S+ didn't finish$/.test(i.title) || (/^Release (\S+) failed graduation$/.test(i.title) && tagOrder(i.title.split(" ")[1], tag) < 0) ||
    (/^Graduation stalled: \S+ waiting since /.test(i.title) && tagOrder(i.title.split(" ")[2], tag) <= 0)));

/** How long an eligible candidate may wait before select reports the stall. */
export const STALL_HOURS = 24;
export const STALL_PREFIX = (tag) => `Graduation stalled: ${tag} waiting since `;
/** Hours the candidate has waited (since it was published) when that is over STALL_HOURS, else null. */
export const stalledHours = (publishedAt, now = Date.now()) => {
  const h = (now - Date.parse(publishedAt)) / 3_600_000;
  return h > STALL_HOURS ? Math.floor(h) : null;
};
/**
 * Where a graduate run's test job failed, from its steps: "baseline" (steps a-c: before the candidate was touched), "candidate"
 * (d, e: the upgrade and its checks; the upgrade step can still fail before the updater prepared the candidate), or null when
 * no lettered step failed (passed, or cut short elsewhere).
 */
export const stageOf = (job) => {
  const f = (job?.steps ?? []).find((s) => /^[a-e]\. /.test(s.name) && s.conclusion && !["success", "skipped"].includes(s.conclusion));
  return f ? { stage: /^[a-c]\./.test(f.name) ? "baseline" : "candidate", step: f.name } : null;
};
/** The stall issue's body: candidate, baseline, and each recent run (newest first) with the stage it failed in. */
export const stallBody = ({ tag, baseline, hours, runs }) => [
  `${tag} is an eligible pre-release that has waited ${hours} hours without graduating (limit ${STALL_HOURS}). Baseline: ${baseline}, the current latest.`,
  "", "Recent graduation runs since it was published (newest first):",
  ...(runs.length ? runs.map((r) => `- ${r.url}: ${r.conclusion}${r.fail ? `, failed in the ${r.fail.stage} stage (step "${r.fail.step}")${r.fail.stage === "baseline" ? ": before the candidate was touched" : ""}` : ""}`) : ["- none finished"]),
  "", "Nothing graduates until this is settled: fix the baseline or the candidate, or graduate it by hand (README \"Release graduation\"). This issue closes when the candidate (or a newer cut) graduates through the workflow; after a manual graduation, close it by hand.",
].join("\n");

/** The body with the rejected mark (unchanged when it has one). */
export const markRejected = (body, run) => (rejected(body) ? String(body) : `${String(body ?? "").trimEnd()}\n\n${MARK} ${run}\n`);

// ------------------------------------------------------------------------------------------------ the API (the CLI below)

const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN || "";
/** How long a rate-limited answer asks to wait (retry-after, or the limit's reset), in ms; null when it isn't a rate limit. */
export function rateLimitWait(status, h, now = Date.now()) {
  if (status !== 403 && status !== 429) return null;
  const after = Number(h.get("retry-after")), reset = Number(h.get("x-ratelimit-reset"));
  if (after > 0) return after * 1000;
  if (h.get("x-ratelimit-remaining") === "0" && reset > 0) return Math.max(0, reset * 1000 - now) + 1000;
  return status === 429 ? 60_000 : null; // a 403 without the limit's headers is a refusal, not a limit
}

async function api(path, { method = "GET", body, allow404 = false } = {}) {
  for (let i = 0, limited = 0; ; ) {
    const r = await fetch(`https://api.github.com/${path}`, {
      method, headers: { accept: "application/vnd.github+json", "user-agent": "aidenhq-graduate", ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(30_000),
    }).catch((e) => ({ ok: false, status: 0, headers: new Headers(), text: async () => String(e) }));
    if (allow404 && r.status === 404) return null;
    if (r.ok) return r.status === 204 ? null : r.json();
    // A rate limit: wait as GitHub asks, up to 15 minutes a time, 4 times; 5xx and network errors: 3 retries, backing off.
    const wait = rateLimitWait(r.status, r.headers);
    if (wait != null && limited++ < 4 && wait <= 15 * 60_000) { console.log(`rate-limited (${r.status}): waiting ${Math.ceil(wait / 1000)} s`); await new Promise((ok) => setTimeout(ok, wait)); continue; }
    if (i < 3 && (r.status === 0 || r.status >= 500)) { await new Promise((ok) => setTimeout(ok, 5000 * ++i)); continue; }
    throw new Error(`${method} ${path}: ${r.status} ${(await r.text()).slice(0, 200)}`);
  }
}
async function allReleases() {
  const out = [];
  for (let page = 1; ; page++) {
    const rows = await api(`repos/${DISTRO}/releases?per_page=100&page=${page}`);
    out.push(...rows);
    if (rows.length < 100) return out;
  }
}
/** The commit a tag names (an annotated tag is followed to its commit). */
async function tagCommit(tag) {
  let o = (await api(`repos/${DISTRO}/git/ref/tags/${tag}`)).object;
  while (o.type === "tag") o = (await api(`repos/${DISTRO}/git/tags/${o.sha}`)).object;
  return o.sha;
}
/** The release's own <tag>.json asset, checked against its digest. */
async function releaseFile(release) {
  const a = release.assets.find((x) => x.name === `${release.tag_name}.json`);
  const r = await fetch(a.browser_download_url, { signal: AbortSignal.timeout(30_000) });
  if (!r.ok) throw new Error(`${a.browser_download_url}: ${r.status}`);
  const bytes = Buffer.from(await r.arrayBuffer());
  if (`sha256:${createHash("sha256").update(bytes).digest("hex")}` !== a.digest) throw new Error(`${a.name} doesn't match its digest`);
  return JSON.parse(bytes.toString("utf8"));
}
const output = (o) => { if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(o).map(([k, v]) => `${k}=${v}\n`).join("")); };
const summary = (s) => { console.log(s); if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${s}\n`); };

/**
 * The candidate and its baseline, as the test job's env (select's outputs), or null when there is nothing to graduate. By
 * default the oldest pending pre-release above latest, from latest; `want` names them instead (a manual run: `env`).
 */
async function selection(want = {}) {
  const tagged = (t) => api(`repos/${DISTRO}/releases/tags/${encodeURIComponent(t)}`);
  const [releases, latest] = await Promise.all([want.candidate ? [] : allReleases(), want.baseline ? tagged(want.baseline) : api(`repos/${DISTRO}/releases/latest`, { allow404: true })]);
  const base = latest?.tag_name;
  // Published, not pre-releases, newer than latest: what updaters with the graduated filter treat as graduated, though they
  // were never tested here (cuts from before graduation). Said, so they can be turned back into pre-releases by hand.
  const odd = releases.filter((r) => !r.draft && !r.prerelease && NAME.test(r.tag_name) && base && compare(r.tag_name, base) > 0).map((r) => r.tag_name);
  if (odd.length) (want.env ? console.error : summary)(`::warning::published, not pre-releases and newer than latest ${base}: ${odd.join(", ")}. Updaters treat them as graduated; mark them pre-releases to have them graduate in order.`);
  const c = want.candidate ? await tagged(want.candidate) : pick(releases, base);
  if (!c) return null;
  const [file, tagSha, baseFile] = await Promise.all([releaseFile(c), tagCommit(c.tag_name), releaseFile(latest)]);
  if (!SHA.test(String(file.kernel)) || file.release !== c.tag_name) throw new Error(`${c.tag_name}.json is malformed`);
  const id = checkIdentity(identityOf(c, tagSha, file.kernel));
  // The bootstrap: the baseline's own updater must be able to prepare a named pre-release, or the test can't upgrade it.
  const u = await api(`repos/${KERNEL}/contents/kernel/src/updates.ts?ref=${baseFile.kernel}`, { allow404: true });
  if (!u || !Buffer.from(u.content, "base64").toString("utf8").includes(CANDIDATE_ENV)) {
    throw new Error(`baseline ${base} predates graduation (its updater has no ${CANDIDATE_ENV}); graduate one release by hand (README "Release graduation")`);
  }
  const baseAssets = assetsOf(latest);
  return { tag: c.tag_name, published_at: c.published_at ?? c.created_at, release_id: c.id, tag_sha: tagSha, kernel: file.kernel, baseline: base, baseline_install_digest: baseAssets["install.sh"], candidate_file_digest: id.assets[`${c.tag_name}.json`], identity: JSON.stringify(id) };
}

/** Opens an issue unless an open one's title starts with `prefix` (the whole title by default): graduation's one failure-issue path. */
async function openIssue(title, body, prefix = title) {
  const open = await api(`repos/${DISTRO}/issues?state=open&per_page=100`);
  if (!open.some((i) => !i.pull_request && i.title.startsWith(prefix))) await api(`repos/${DISTRO}/issues`, { method: "POST", body: { title, body } });
}

/** Once the candidate has waited over STALL_HOURS, opens (or keeps open) the one stall issue naming the recent runs' failing stage. */
async function reportStall(s) {
  const hours = stalledHours(s.published_at);
  if (hours == null) return;
  const prefix = STALL_PREFIX(s.tag);
  const open = await api(`repos/${DISTRO}/issues?state=open&per_page=100`);
  if (open.some((i) => !i.pull_request && i.title.startsWith(prefix))) return;
  const since = Date.parse(s.published_at);
  const rows = (await api(`repos/${DISTRO}/actions/workflows/graduate.yml/runs?status=completed&per_page=10`)).workflow_runs.filter((r) => Date.parse(r.created_at) >= since).slice(0, 5);
  const runs = [];
  for (const r of rows) {
    const job = (await api(`repos/${DISTRO}/actions/runs/${r.id}/jobs?per_page=100`)).jobs.find((j) => j.name === "test");
    runs.push({ url: r.html_url, conclusion: r.conclusion, fail: stageOf(job) });
  }
  await openIssue(`${prefix}${s.published_at}`, stallBody({ tag: s.tag, baseline: s.baseline, hours, runs }), prefix);
  summary(`**${s.tag} stalled**: waiting ${hours} hours; issue opened.`);
}

async function select() {
  const s = await selection();
  if (!s) { summary("**Nothing to graduate**: no pending pre-release newer than latest."); output({ found: "false" }); return; }
  summary(`**Graduating ${s.tag}** (distro ${s.tag_sha.slice(0, 12)}, kernel ${s.kernel.slice(0, 12)}) from ${s.baseline}.`);
  output({ found: "true", ...s });
  // Reporting writes an issue: only in the workflow (the dry run stays read-only), and never stops the graduation itself.
  if (process.env.GITHUB_OUTPUT) await reportStall(s).catch((e) => console.log(`::warning::stall report failed: ${e.message}`));
}

/** A manual run's env (README "Release graduation"): `eval "$(node graduate.mjs env [candidate] [baseline])"`. */
async function env(candidate, baseline) {
  const s = await selection({ candidate, baseline, env: true });
  if (!s) throw new Error("nothing to graduate: no pending pre-release newer than latest (name one)");
  const q = (v) => `'${String(v).replace(/'/g, "'\\''")}'`;
  console.log(Object.entries(s).filter(([k]) => k !== "release_id").map(([k, v]) => `export ${k.toUpperCase()}=${q(v)}`).join("\n"));
}

async function promote(file) {
  const id = checkIdentity(JSON.parse(process.env.IDENTITY ?? ""));
  const result = validateResult(JSON.parse(readFileSync(file, "utf8")), id, process.env.BASELINE);
  // The test job itself, from the API (not the artifact): this run's job named "test" succeeded.
  const jobs = (await api(`repos/${DISTRO}/actions/runs/${process.env.RUN_ID}/jobs?per_page=100`)).jobs;
  const test = jobs.filter((j) => j.name === "test");
  if (test.length !== 1 || test[0].conclusion !== "success") throw new Error(`this run's test job didn't succeed (${test.map((j) => j.conclusion).join(", ") || "none"})`);
  const [release, tagSha, latest] = await Promise.all([api(`repos/${DISTRO}/releases/${id.release_id}`), tagCommit(id.tag), api(`repos/${DISTRO}/releases/latest`, { allow404: true })]);
  const d = decide({ release, tagSha, latest: latest?.tag_name, id });
  if (d === "done") { summary(`**${id.tag} is already graduated** (latest).`); return; }
  await api(`repos/${DISTRO}/releases/${id.release_id}`, { method: "PATCH", body: { prerelease: false, make_latest: "true" } });
  const now = await api(`repos/${DISTRO}/releases/latest`);
  if (now.tag_name !== id.tag) throw new Error(`after promotion GitHub's latest is ${now.tag_name}, not ${id.tag}`);
  for (const i of closable(await api(`repos/${DISTRO}/issues?state=open&creator=github-actions%5Bbot%5D&per_page=100`), id.tag)) {
    await api(`repos/${DISTRO}/issues/${i.number}/comments`, { method: "POST", body: { body: `${id.tag} graduated: ${process.env.RUN_URL}` } });
    await api(`repos/${DISTRO}/issues/${i.number}`, { method: "PATCH", body: { state: "closed", state_reason: "completed" } });
  }
  summary(`**Graduated ${id.tag}** from ${result.baseline}: it is the latest release; installs and get.aidenhq.ai take it.`);
}

async function reject() {
  const id = checkIdentity(JSON.parse(process.env.IDENTITY ?? ""));
  const run = String(process.env.RUN_URL ?? "");
  if (!/^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/actions\/runs\/\d+$/.test(run)) throw new Error("RUN_URL isn't a run link");
  const issue = openIssue;
  const e = process.env;
  const evidence = e.FAILURES?.trim() ? `\n\nFailing checks (from the test's verdict):\n\`\`\`\n${e.FAILURES.trim().replace(/`/g, "'")}\n\`\`\`` : "";
  const what = onFailure({ test: e.TEST_RESULT, reached: e.REACHED, verdict: e.VERDICT, promote: e.PROMOTE_RESULT });
  if (what === "none") { summary("nothing failed that rejects or reports"); return; }
  if (what === "issue") {
    const base = String(e.BASELINE ?? "").slice(0, 40);
    const why = e.TEST_RESULT === "success" ? "its test passed, but promotion failed (the API, or the release changed since it was selected)"
      : e.VERDICT === "harness" ? "the test hit a limit of its own (the job log says which, e.g. the update waiting on an owner's tap the test doesn't make)"
      : e.REACHED !== "candidate" ? `the baseline ${base} or the runner failed before the upgrade started`
      : "the test didn't finish judging it (a rate limit, a step or the job cut short by its timeout, or a cancel)";
    await issue(`Graduation of ${id.tag} didn't finish`, `${id.tag} wasn't graduated or rejected: ${why}. It stays a pending pre-release and is tested again at the next run (every 6 hours, or run graduate by hand). If it keeps failing this way, reject it by hand (README "Release graduation").${evidence}\n\nRun: ${run}`);
    summary(`**${id.tag} not judged**: ${why}; ${run}`);
    return;
  }
  const release = await api(`repos/${DISTRO}/releases/${id.release_id}`);
  if (release.tag_name !== id.tag) throw new Error(`release ${id.release_id} isn't ${id.tag}`);
  if (!release.prerelease) { summary(`${id.tag} is graduated already: not marked`); return; }
  let marked = rejected(release.body);
  if (what === "incomplete" && !marked) {
    const n = noteIncomplete(release.body, run);
    await api(`repos/${DISTRO}/releases/${id.release_id}`, { method: "PATCH", body: { body: n.body } });
    if (!n.rejected) {
      await issue(`Graduation of ${id.tag} didn't finish`, `${id.tag}'s upgrade began but the run ended without a verdict (it hung, a step timed out, or its checks never wrote): ${n.count} of ${INCOMPLETE_LIMIT} such runs. It stays pending and is tested again at the next run; at ${INCOMPLETE_LIMIT} it is rejected.${evidence}\n\nRun: ${run}`);
      summary(`**${id.tag} incomplete** (${n.count}/${INCOMPLETE_LIMIT}); ${run}`);
      return;
    }
    marked = true; // its body above carries the rejected mark already
  }
  if (!marked) await api(`repos/${DISTRO}/releases/${id.release_id}`, { method: "PATCH", body: { body: markRejected(release.body, run) } });
  await issue(`Release ${id.tag} failed graduation`, `${id.tag} didn't pass graduation, so it stays a pre-release: no install updates to it and get.aidenhq.ai keeps serving the latest graduated release. The next cut is tested from the same baseline.${evidence}\n\nRun: ${run}\n\nTo test it again (an infrastructure failure), delete the \`${MARK}\` line from the release's notes; the next graduate run picks it up.`);
  summary(`**${id.tag} rejected**: marked in its notes; ${run}`);
}

if (import.meta.main) {
  const [cmd, arg] = process.argv.slice(2);
  try {
    if (cmd === "select") await select();
    else if (cmd === "env") await env(arg, process.argv[4]);
    else if (cmd === "promote" && arg) await promote(arg);
    else if (cmd === "reject") await reject();
    else if (cmd === "rejected") console.log((await allReleases()).filter((r) => r.prerelease && NAME.test(r.tag_name) && rejected(r.body)).map((r) => r.tag_name).join(" "));
    else { console.error("usage: graduate.mjs select | env [candidate] [baseline] | promote <result.json> | reject | rejected"); process.exitCode = 2; }
  } catch (e) {
    (cmd === "env" ? console.error : console.log)(`::error::${e.message}`); // env's stdout is eval'd
    process.exitCode = 1;
  }
}
