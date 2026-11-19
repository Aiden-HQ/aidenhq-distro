// Release graduation (.github/workflows/graduate.yml; README "Release graduation"): which cut to test, whether a test's result
// is the one asked for, and moving the release to graduated (or marking it rejected). GitHub's REST API with GITHUB_TOKEN.
//   node .github/release/graduate.mjs select        the candidate and its baseline (a dry run without $GITHUB_OUTPUT)
//   node .github/release/graduate.mjs promote <result.json>   (IDENTITY, RUN_ID) graduate it: not a pre-release, latest
//   node .github/release/graduate.mjs reject        (IDENTITY, RUN_URL, BASELINE, TEST_RESULT, REACHED, PROMOTE_RESULT)
//                                                   mark it rejected and open one issue; when the test failed before the
//                                                   upgrade, only the issue: the baseline or the runner failed (onFailure)
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
export const CHECKS = ["baseline_installed", "baseline_first_run", "baseline_chat", "upgraded", "running_release", "generation_good", "agents_ready", "chat_reply", "hello_app_serves", "second_app_deploys", "verify_security"];

/**
 * The test job's result.json, read as untrusted (it was written next to the candidate's code): exactly these fields, bounded,
 * naming the selected release and baseline, every check true. Returns it; throws on anything else.
 */
export function validateResult(r, id, baseline) {
  const keys = ["release", "release_id", "tag_sha", "kernel", "baseline", "passed", "checks", "notes"];
  if (!r || typeof r !== "object" || Array.isArray(r) || !isDeepStrictEqual(Object.keys(r).sort(), [...keys].sort())) throw new Error(`the result must have exactly ${keys.join(", ")}`);
  if (r.release !== id.tag || r.release_id !== id.release_id || r.tag_sha !== id.tag_sha || r.kernel !== id.kernel) throw new Error("the result names another release than the one selected");
  if (r.baseline !== baseline) throw new Error("the result names another baseline than the one selected");
  if (!r.checks || typeof r.checks !== "object" || Array.isArray(r.checks) || !isDeepStrictEqual(Object.keys(r.checks).sort(), [...CHECKS].sort())) throw new Error(`the result's checks must be exactly ${CHECKS.join(", ")}`);
  const failed = CHECKS.filter((c) => r.checks[c] !== true);
  if (r.passed !== true || failed.length) throw new Error(`the test didn't pass${failed.length ? `: ${failed.join(", ")}` : ""}`);
  if (!Array.isArray(r.notes) || r.notes.length > 20 || !r.notes.every((n) => typeof n === "string" && n.length <= 300)) throw new Error("the result's notes must be up to 20 short strings");
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
 * What a failed run does to its candidate: "mark" it rejected when its code ran (the upgrade started, or the test passed and
 * promotion failed), else only an "issue": a test that failed before the upgrade is the baseline's or the runner's failure.
 */
export const onFailure = ({ test, reached, promote }) => (test === "success" ? (promote === "failure" ? "mark" : "none") : test === "failure" && reached === "candidate" ? "mark" : test === "failure" ? "issue" : "none");

/** The body with the rejected mark (unchanged when it has one). */
export const markRejected = (body, run) => (rejected(body) ? String(body) : `${String(body ?? "").trimEnd()}\n\n${MARK} ${run}\n`);

// ------------------------------------------------------------------------------------------------ the API (the CLI below)

const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN || "";
async function api(path, { method = "GET", body, allow404 = false } = {}) {
  for (let i = 0; ; i++) {
    const r = await fetch(`https://api.github.com/${path}`, {
      method, headers: { accept: "application/vnd.github+json", "user-agent": "aidenhq-graduate", ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(30_000),
    }).catch((e) => ({ ok: false, status: 0, text: async () => String(e) }));
    if (allow404 && r.status === 404) return null;
    if (r.ok) return r.status === 204 ? null : r.json();
    if (i < 3 && (r.status === 0 || r.status >= 500)) { await new Promise((ok) => setTimeout(ok, 5000 * (i + 1))); continue; }
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

async function select() {
  const [releases, latest] = await Promise.all([allReleases(), api(`repos/${DISTRO}/releases/latest`, { allow404: true })]);
  const base = latest?.tag_name;
  // Published, not pre-releases, newer than latest: what updaters with the graduated filter treat as graduated, though they
  // were never tested here (cuts from before graduation). Said, so they can be turned back into pre-releases by hand.
  const odd = releases.filter((r) => !r.draft && !r.prerelease && NAME.test(r.tag_name) && base && compare(r.tag_name, base) > 0).map((r) => r.tag_name);
  if (odd.length) summary(`::warning::published, not pre-releases and newer than latest ${base}: ${odd.join(", ")}. Updaters treat them as graduated; mark them pre-releases to have them graduate in order.`);
  const c = pick(releases, base);
  if (!c) { summary(`**Nothing to graduate**: no pending pre-release newer than ${base}.`); output({ found: "false" }); return; }
  const [file, tagSha, baseFile] = await Promise.all([releaseFile(c), tagCommit(c.tag_name), releaseFile(latest)]);
  if (!SHA.test(String(file.kernel)) || file.release !== c.tag_name) throw new Error(`${c.tag_name}.json is malformed`);
  const id = checkIdentity(identityOf(c, tagSha, file.kernel));
  // The bootstrap: the baseline's own updater must be able to prepare a named pre-release, or the test can't upgrade it.
  const u = await api(`repos/${KERNEL}/contents/kernel/src/updates.ts?ref=${baseFile.kernel}`, { allow404: true });
  if (!u || !Buffer.from(u.content, "base64").toString("utf8").includes(CANDIDATE_ENV)) {
    throw new Error(`baseline ${base} predates graduation (its updater has no ${CANDIDATE_ENV}); graduate one release by hand (README "Release graduation")`);
  }
  const baseAssets = assetsOf(latest);
  summary(`**Graduating ${c.tag_name}** (distro ${tagSha.slice(0, 12)}, kernel ${file.kernel.slice(0, 12)}) from ${base}.`);
  output({ found: "true", tag: c.tag_name, release_id: c.id, tag_sha: tagSha, kernel: file.kernel, baseline: base, baseline_install_digest: baseAssets["install.sh"], candidate_file_digest: id.assets[`${c.tag_name}.json`], identity: JSON.stringify(id) });
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
  summary(`**Graduated ${id.tag}** from ${result.baseline}: it is the latest release; installs and get.aidenhq.ai take it.`);
}

async function reject() {
  const id = checkIdentity(JSON.parse(process.env.IDENTITY ?? ""));
  const run = String(process.env.RUN_URL ?? "");
  if (!/^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/actions\/runs\/\d+$/.test(run)) throw new Error("RUN_URL isn't a run link");
  const issue = async (title, body) => {
    const open = await api(`repos/${DISTRO}/issues?state=open&per_page=100`);
    if (!open.some((i) => i.title === title)) await api(`repos/${DISTRO}/issues`, { method: "POST", body: { title, body } });
  };
  const what = onFailure({ test: process.env.TEST_RESULT, reached: process.env.REACHED, promote: process.env.PROMOTE_RESULT });
  if (what === "none") { summary("nothing failed that rejects or reports"); return; }
  if (what === "issue") {
    const base = String(process.env.BASELINE ?? "").slice(0, 40);
    await issue(`Graduation can't test from ${base}`, `The test failed before the upgrade to ${id.tag} started: the baseline ${base} didn't install or pass its first run and chat, or the runner failed. ${id.tag} stays pending and is tested again at the next run.\n\nRun: ${run}`);
    summary(`**Couldn't test ${id.tag}**: the baseline or the runner failed before the upgrade; ${run}`);
    return;
  }
  const release = await api(`repos/${DISTRO}/releases/${id.release_id}`);
  if (release.tag_name !== id.tag) throw new Error(`release ${id.release_id} isn't ${id.tag}`);
  if (!release.prerelease) { summary(`${id.tag} is graduated already: not marked`); return; }
  if (!rejected(release.body)) await api(`repos/${DISTRO}/releases/${id.release_id}`, { method: "PATCH", body: { body: markRejected(release.body, run) } });
  await issue(`Release ${id.tag} failed graduation`, `${id.tag} didn't pass graduation, so it stays a pre-release: no install updates to it and get.aidenhq.ai keeps serving the latest graduated release. The next cut is tested from the same baseline.\n\nRun: ${run}\n\nTo test it again (an infrastructure failure), delete the \`${MARK}\` line from the release's notes; the next graduate run picks it up.`);
  summary(`**${id.tag} rejected**: marked in its notes; ${run}`);
}

if (import.meta.main) {
  const [cmd, arg] = process.argv.slice(2);
  try {
    if (cmd === "select") await select();
    else if (cmd === "promote" && arg) await promote(arg);
    else if (cmd === "reject") await reject();
    else if (cmd === "rejected") console.log((await allReleases()).filter((r) => r.prerelease && NAME.test(r.tag_name) && rejected(r.body)).map((r) => r.tag_name).join(" "));
    else { console.error("usage: graduate.mjs select | promote <result.json> | reject | rejected"); process.exitCode = 2; }
  } catch (e) {
    console.log(`::error::${e.message}`);
    process.exitCode = 1;
  }
}
