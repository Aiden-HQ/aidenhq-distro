// The nightly's decision (.github/workflows/nightly.yml; README "Nightly releases"): is there a release to cut tonight, under
// which name, with which shas and notes. Read-only: GitHub's REST API, with GITHUB_TOKEN when set (public repos otherwise).
//   node .github/release/nightly.mjs            print the decision and the release file it would cut (a dry run)
//   node .github/release/nightly.mjs <file>     also write the release file there and the decision to $GITHUB_OUTPUT
// Cut when product main (its kernel sha or its modules-pin.json) moved since the newest published release and its
// `ci-required` check passed on that commit. The release file has no `images` (the build adds them) and no `tested` (publish).
import { appendFileSync, writeFileSync } from "node:fs";

const DISTRO = "Aiden-HQ/aidenhq-distro", KERNEL = "Aiden-HQ/AidenHQ", MODULES = "Aiden-HQ/aidenhq-modules";
const CHECK = "ci-required";
/** Release names: 2026.11, 2026.11.2, 2026.11.18 (a nightly), 2026.11.18.1 (the same day's second cut). */
export const NAME = /^\d{4}\.\d{1,2}(\.\d+){0,2}$/;
export const compare = (a, b) => {
  const [x, y] = [a, b].map((s) => s.split(".").map(Number));
  for (let i = 0; i < 4; i++) { const d = (x[i] ?? 0) - (y[i] ?? 0); if (d) return Math.sign(d); }
  return 0;
};

const headers = { accept: "application/vnd.github+json", "user-agent": "aidenhq-nightly", ...(process.env.GITHUB_TOKEN ? { authorization: `Bearer ${process.env.GITHUB_TOKEN}` } : {}) };
async function api(path, { allow404 = false } = {}) {
  const r = await fetch(`https://api.github.com/${path}`, { headers, signal: AbortSignal.timeout(30_000) });
  if (allow404 && r.status === 404) return null;
  if (!r.ok) throw new Error(`GET ${path}: ${r.status} ${(await r.text()).slice(0, 200)}`);
  return r.json();
}
const file = async (repo, path, ref) => {
  const r = await api(`repos/${repo}/contents/${path}?ref=${ref}`, { allow404: true });
  return r && JSON.parse(Buffer.from(r.content, "base64").toString("utf8"));
};

/** A commit subject as a user-facing note: feat, fix and perf only, without the type, scope and PR number. */
export function note(subject) {
  const m = /^(feat|fix|perf)(\([^)]*\))?!?:\s*(.+)$/i.exec(subject.trim());
  if (!m) return null;
  const s = m[3].replace(/\s*\(#\d+\)\s*$/, "").trim();
  return s && s[0].toUpperCase() + s.slice(1);
}

/** Up to 20 notes (the updater shows 20, the owner's message the first 5): authority, features, fixes, then host setup. */
export function notes(commits, { authority = [], host = [] } = {}) {
  const seen = new Set(), feats = [], fixes = [];
  for (const c of commits) {
    const n = note(c.commit.message.split("\n")[0]);
    if (!n || seen.has(n.toLowerCase())) continue;
    seen.add(n.toLowerCase());
    (/^feat/i.test(c.commit.message) ? feats : fixes).push(n);
  }
  return [...[...authority, ...feats, ...fixes].slice(0, 20 - host.length), ...host];
}

/** Cheap, approximate flags from the changed files (the kernel's authority diff is the real check, at apply). */
export function flagsOf(productFiles, moduleFiles) {
  const out = { authority: [], host: [] };
  const authority = /^\+\s*(writes|privileged|default_grants|roles|isolation|secrets|connections)\s*:|^\+.*:\s*write\s*$/m;
  const mods = [...new Set(moduleFiles.filter((f) => /^[^/]+\/module\.yaml$/.test(f.filename) && (!f.patch || authority.test(f.patch))).map((f) => f.filename.split("/")[0]))];
  if (mods.length) out.authority.push(`May add authority (grants, writes, roles or secrets) in: ${mods.join(", ")}. Auto-updates accept it; turn them off to review first.`);
  if (productFiles.some((f) => /^ops\/(setup\.sh|vm\/)/.test(f.filename))) out.host.push("Host setup changed (ops/setup.sh or ops/vm): an update runs apply only, so running the installer again may be needed (curl -fsSL https://get.aidenhq.ai | sh).");
  return out;
}

/** The release name for `day`: Y.M.D, then Y.M.D.1, .2 … while a tag or a release file already has it. */
export async function nameFor(day, tags, exists) {
  const base = `${day.getUTCFullYear()}.${day.getUTCMonth() + 1}.${day.getUTCDate()}`;
  for (let n = 0; ; n++) {
    const name = n ? `${base}.${n}` : base;
    if (!tags.includes(name) && !(await exists(name))) return name;
  }
}

/** ci-required on `sha`: "success", "pending" or the failing conclusion. Waits up to `waitMin` minutes while it is pending. */
async function ci(sha, waitMin) {
  const until = Date.now() + waitMin * 60_000;
  for (;;) {
    const runs = (await api(`repos/${KERNEL}/commits/${sha}/check-runs?check_name=${CHECK}&per_page=20`)).check_runs;
    const latest = runs.sort((a, b) => String(b.started_at).localeCompare(String(a.started_at)))[0];
    const state = !latest || latest.status !== "completed" ? "pending" : latest.conclusion;
    if (state !== "pending" || Date.now() >= until) return state;
    await new Promise((r) => setTimeout(r, 60_000));
  }
}

export async function decide({ now = new Date(), waitMin = 0 } = {}) {
  const head = (await api(`repos/${KERNEL}/commits/main`)).sha;
  const pin = await file(KERNEL, "modules-pin.json", head);
  if (pin?.repo !== MODULES || !/^[0-9a-f]{40}$/.test(pin.sha ?? "")) throw new Error(`${KERNEL}@${head}: modules-pin.json doesn't name ${MODULES} at a sha`);
  // The newest published release (a tag whose run failed is deleted; a draft isn't one).
  const published = (await api(`repos/${DISTRO}/releases?per_page=100`)).filter((r) => !r.draft && NAME.test(r.tag_name)).map((r) => r.tag_name);
  const last = published.sort(compare).at(-1);
  if (!last) throw new Error(`${DISTRO} has no published release to compare with`);
  const prev = await file(DISTRO, `releases/${last}.json`, last);
  const base = { head, modules: pin.sha, last };
  if (prev.kernel === head && prev.marketplace.sha === pin.sha) return { go: false, why: `nothing changed since ${last}`, ...base };
  const state = await ci(head, waitMin);
  if (state !== "success") return { go: false, why: `${CHECK} on ${KERNEL}@${head.slice(0, 12)} is ${state}`, ...base };
  // Product main always descends from the last release's kernel, but a hand-pinned modules sha might not: refuse a downgrade.
  const [pc, mc] = await Promise.all([api(`repos/${KERNEL}/compare/${prev.kernel}...${head}`), api(`repos/${MODULES}/compare/${prev.marketplace.sha}...${pin.sha}`)]);
  if (pc.behind_by || mc.behind_by) return { go: false, why: `main doesn't descend from ${last} (kernel behind ${pc.behind_by}, modules behind ${mc.behind_by})`, ...base };
  const tags = (await api(`repos/${DISTRO}/tags?per_page=100`)).map((t) => t.name);
  const name = await nameFor(now, tags, async (n) => !!(await api(`repos/${DISTRO}/contents/releases/${n}.json?ref=main`, { allow404: true })));
  // A day's second cut (four parts) needs a kernel that accepts it: an older one's ops/setup.sh refuses the name on a fresh install.
  if (name.split(".").length === 4) {
    const src = await api(`repos/${KERNEL}/contents/kernel/src/loader/release.ts?ref=${head}`);
    const re = /const NAME = \/(.+)\/;/.exec(Buffer.from(src.content, "base64").toString("utf8"))?.[1];
    if (!re || !new RegExp(re).test(name)) return { go: false, why: `${name} is a day's second cut, and the kernel at ${head.slice(0, 12)} doesn't accept four-part names yet`, ...base };
  }
  const bundle = (await file(MODULES, "marketplace.json", pin.sha))?.bundle;
  if (!Array.isArray(bundle) || !bundle.length) throw new Error(`${MODULES}@${pin.sha}: marketplace.json has no bundle`);
  const release = {
    name: "AidenHQ", release: name, kernel: head, kernel_repo: KERNEL,
    marketplace: { name: "aidenhq", source: { source: "github", repo: MODULES }, sha: pin.sha },
    modules: Object.fromEntries([...bundle].sort().map((m) => [m, pin.sha])),
    notes: notes([...pc.commits, ...mc.commits].reverse(), flagsOf(pc.files ?? [], mc.files ?? [])),
  };
  return { go: true, why: `${KERNEL} ${prev.kernel.slice(0, 12)}..${head.slice(0, 12)} (${pc.ahead_by} commits), modules ${prev.marketplace.sha.slice(0, 12)}..${pin.sha.slice(0, 12)} (${mc.ahead_by})`, name, release, ...base };
}

if (import.meta.main) {
  const out = process.argv[2];
  const d = await decide({ waitMin: Number(process.env.NIGHTLY_CI_WAIT_MIN ?? 0) });
  console.log(`${d.go ? `cut ${d.name}` : "skip"}: ${d.why} (since ${d.last}; main ${d.head}, modules ${d.modules})`);
  if (d.go) console.log(JSON.stringify(d.release, null, 2));
  if (out && d.go) writeFileSync(out, `${JSON.stringify(d.release, null, 2)}\n`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `go=${d.go}\nname=${d.name ?? ""}\nwhy=${d.why.replace(/\n/g, " ")}\nmanifest=${d.go ? JSON.stringify(d.release) : ""}\n`);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${d.go ? `**Cutting ${d.name}**` : "**No release tonight**"}: ${d.why}\n${d.go ? `\n${d.release.notes.map((n) => `- ${n}`).join("\n")}\n` : ""}`);
}
