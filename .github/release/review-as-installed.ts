// Run inside an OLD release's product checkout (copied to its kernel/src by upgrade.sh; its config compiled for the instance as
// that release's setup wrote it): the release updater's pin commit, filed and reviewed as that release's kernel files and
// reviews it. Its own code end to end: writes.fileKernel plans the kernel.apply with the host planner (codehost-local's read of
// the commit, the product's git, the compiled config) and tiers it; the review loop builds the reviewer's request; that
// release's own AI reviewer (modules/ai-reviewer, its policy) judges it on the model, as its service does.
// One stand-in: the planner's check that the move is the updater's own verified release (updates.ts verify) needs the release
// published, which this test precedes; it answers the commit's own instance.yaml (which the old updater's pinText wrote) only
// for exactly the release being cut, <release> at <distro sha>, as the workflow names it.
//   OPENROUTER_API_KEY=… node kernel/src/review-as-installed.ts <instance bare repo> <instance repo> <branch> <sha> <from release> <release> <distro sha> <records db>
// Exits 0 only when the record was approved; 1 for anything else (rejected, waiting on the owner, refused at filing).
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import YAML from "yaml";
import { configDir, repo } from "./env.ts";
import { watched } from "./gateway/lib.ts";
import { openRecords, UPDATER } from "./records.ts";
import { createWrites } from "./writes.ts";
import { createReviewLoop } from "./review-loop.ts";
import { hostPlanner } from "./apply-tier.ts";
import { KERNEL_KINDS } from "./kinds.ts";
import { inventoryOf } from "./paths.ts";
import { checksFile } from "./checks.ts";
import { KERNEL } from "./updates.ts";
import { openRouterAsk, review } from "../../modules/ai-reviewer/service/src/review.ts";
import { LOCAL_KINDS } from "../../modules/codehost-local/src/host.ts";
import { localApply } from "../../modules/codehost-local/src/apply.ts";

const [bare, instanceRepo, branch, sha, from, release, relsha, db] = process.argv.slice(2) as [string, string, string, string, string, string, string, string];
const key = process.env.OPENROUTER_API_KEY?.trim();
if (!key) throw new Error("OPENROUTER_API_KEY is not set: the release's own AI reviewer needs a model key");
const log = (msg: string, f: Record<string, unknown> = {}) => console.log(`  kernel: ${msg} ${JSON.stringify(f).slice(0, 400)}`);
const git = (...args: string[]) => execFileSync("git", ["--git-dir", bare, ...args], { encoding: "utf8" });
const pinned = git("show", `${sha}:instance.yaml`);
const head = YAML.parse(pinned) as { product?: unknown; release?: { name?: unknown; sha?: unknown } };
if (String(head.release?.name) !== release || String(head.release?.sha) !== relsha) throw new Error(`the pin commit doesn't pin ${release} at ${relsha}`);
const kernel = String(head.product ?? "");
const product = execFileSync("git", ["-C", repo, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();

// The task the kernel files for a prepared release (main.ts, createUpdates' `file`), from this release's own templates.
const main = readFileSync(join(repo, "kernel/src/main.ts"), "utf8");
const tpl = /moduleTasks\.file\("kernel", \{ title: (`[^`]*`), role: [^,]+, source: [^,]+, description: (`[^`]*`) \}\)/.exec(main);
if (!tpl) throw new Error("this release's kernel/src/main.ts files its update task differently: update review-as-installed.ts");
const r = { release, from, compare: `https://github.com/${KERNEL}/compare/${product.slice(0, 12)}...${kernel.slice(0, 12)}` };
const [title, description] = [tpl[1]!, tpl[2]!].map((t) => t.slice(1, -1).replaceAll("\\n", "\n").replace(/\$\{r\.(\w+)\}/g, (_, k: keyof typeof r) => r[k]));
const TASK = "release-update";

// The kernel's wiring (main.ts), over the compiled config; the instance repo is codehost-local's, as a default install's.
const records = openRecords(db);
// The grants table's autonomy as paperclip-setup writes it (from the compiled paperclip.yaml); its agents are Paperclip's ids,
// which only an agent's own files read: none here.
const autonomy = String(YAML.parse(readFileSync(join(configDir, "paperclip.yaml"), "utf8"))?.autonomy ?? "off");
const moduleKinds = watched(join(configDir, "kernel", "writes.json"), (j) => j as never, {});
const writes = createWrites({
  records, log, secret: () => "", resolver: {} as never, connections: watched(join(configDir, "kernel", "connections.json"), (j) => j as never, {}),
  registry: () => ({ ...moduleKinds(), ...LOCAL_KINDS, ...KERNEL_KINDS }),
  repos: () => ({ product: process.env.AIDENHQ_PRODUCT_REPO, instance: instanceRepo, agentsOrgs: [instanceRepo.split("/")[0]!] }) as never,
  paths: watched(join(configDir, "kernel", "paths.json"), inventoryOf, undefined),
  checks: checksFile(join(configDir, "kernel", "checks.json")),
  autonomy: () => (["off", "tier0", "full"].includes(autonomy) ? autonomy : "off") as never,
  onTask: { open: async () => true, notify: async () => {} },
  replay: async () => ({ ok: false, text: "no proxy here" }),
  // An approved apply isn't run here: approving it is what this test checks.
  native: { "kernel.apply": async () => ({ ok: true, text: "approved; not applied (the release test)" }) },
  // The reviewer module's service (server.mjs reviewWith): review() on the model, here straight to OpenRouter.
  reviews: { request: (req: Record<string, unknown>) => review({ ...req, ask: openRouterAsk(key) }) } as never,
  planners: {
    "kernel.apply": hostPlanner({
      repo, configDir, instanceRepo: () => instanceRepo, read: localApply({ bare, instanceRepo }).read, grants: () => ({}),
      connections: watched(join(configDir, "kernel", "connections.json"), (j) => j as never, {}),
      verifyRelease: async (_base, name, s) => (name === release && s === relsha ? pinned : null),
    }),
  },
});
const loop = createReviewLoop({
  records, writes, log, decisions: async () => undefined, product: () => (process.env.AIDENHQ_PRODUCT_REPO ? [process.env.AIDENHQ_PRODUCT_REPO] : []),
  task: { issue: async () => ({ id: TASK, title, description }) as never, comments: async () => [], me: async () => "", notify: async () => {} },
});

let rec;
try {
  rec = await writes.fileKernel("kernel.apply", { args: { repo: instanceRepo, branch, sha }, task: TASK, requester: UPDATER });
} catch (e) {
  console.log(`not filed: ${(e as Error).message}`);
  process.exit(1);
}
console.log(`filed ${rec.id}: tier ${rec.tier}${rec.panel ? " (panel)" : ""}, rule ${rec.rule}, ${rec.state}`);
console.log(`task: ${title}\n${description}`);
// Sweeps until the record leaves review: a panel's second reviewer is the next sweep; a failed review waits out its backoff
// (REVIEW_TRIES, about half an hour, then the kernel's own failed verdict).
for (const until = Date.now() + 45 * 60_000; records.get(rec.id)!.state === "review" && Date.now() < until; ) {
  const at = writes.retryAt(rec.id);
  if (at && at > Date.now()) await new Promise((ok) => setTimeout(ok, at - Date.now()));
  await loop.tick();
}
const end = records.get(rec.id)!;
console.log(`record ${end.id}: ${end.state}${end.rule ? ` (rule ${end.rule})` : ""}${end.review_code ? `, code ${end.review_code}` : ""}, decided by ${end.decided_by ?? "-"}\nreview: ${end.review ?? "-"}`);
// Only an approval passes: an install on auto-update lands only what its reviewer approves. A reject, an escalation to the
// owner (a panel split, an unsure reviewer, Tier 2 on its merits) or a review that never completed all leave the install
// where it was.
if (["approved", "claimed", "done"].includes(end.state)) process.exit(0);
const lines = (end.args as { authority?: string[] }).authority ?? [];
const failed = ["reviewer_failed", "reviewer_refused"].includes(end.review_code ?? "") || /the reviewer failed|couldn't read it/.test(end.review ?? "");
const why = failed ? "the AI reviewer couldn't judge it (a failed or refused model call), so an install wouldn't land it"
  : end.state === "rejected" ? "the AI reviewer rejected the update"
  : end.state === "owner" ? "the AI reviewer didn't approve it: it waits on the owner's tap, so auto-update stops there"
  : `the record didn't reach a verdict (${end.state})`;
console.log(`${why}. The authority lines it judged (${lines.length}):\n${lines.map((l) => `  ${l}`).join("\n") || "  (none)"}`);
process.exit(1);
