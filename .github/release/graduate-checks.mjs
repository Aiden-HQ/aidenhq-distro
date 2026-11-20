// Graduation's test results (.github/workflows/graduate.yml, test job): each check's outcome in its own file, the checks
// that run side by side within their bounds, the phases' timings, and result.json with its verdict. Imported by
// graduate-scenario.mjs; graduate-instance.sh writes the same files (rec, timing) and runs `result` here.
//   node graduate-checks.mjs result    (GRAD_DIR, IDENTITY, BASELINE) result.json, the verdict, the timings table
// $GRAD_DIR/checks/<name>.json is {ok, note}: ok true or false once the check ran and decided, null when it didn't (timed out,
// crashed): a note only, so the check stays missing and the verdict is incomplete, never failed. One file per check, so
// checks running in parallel never overwrite each other. $GRAD_DIR/timings/<phase>.json is the phase's seconds.
import { spawn } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { CHECKS } from "./graduate.mjs";

const NAME = /^[a-z][a-z0-9_]{0,39}$/;
const log = (s) => console.log(`${new Date().toISOString().slice(11, 19)} ${s}`);
const one = (s) => String(s ?? "").replace(/[\r\n]+/g, " ").slice(0, 280);

/** One check's outcome: ok true/false (it decided) or null (a note only). A decided check is never downgraded to a note. */
export function writeCheck(dir, name, ok, note) {
  if (!NAME.test(name)) throw new Error(`bad check name ${name}`);
  mkdirSync(join(dir, "checks"), { recursive: true, mode: 0o700 });
  const f = join(dir, "checks", `${name}.json`);
  if (ok == null && existsSync(f) && typeof JSON.parse(readFileSync(f, "utf8")).ok === "boolean") return;
  writeFileSync(f, `${JSON.stringify({ ok: ok == null ? null : ok === true, note: one(note) })}\n`, { mode: 0o600 });
  log(`${ok == null ? "note" : ok === true ? "ok  " : "FAIL"} ${name}${note ? `: ${one(note)}` : ""}`);
}
const decided = (dir, name) => existsSync(join(dir, "checks", `${name}.json`)) && typeof JSON.parse(readFileSync(join(dir, "checks", `${name}.json`), "utf8")).ok === "boolean";

/** Every check's file merged: {checks: {name: bool} for the decided ones, notes: ["name: note"]}. */
export function readChecks(dir) {
  const d = join(dir, "checks");
  const out = { checks: {}, notes: [] };
  for (const f of existsSync(d) ? readdirSync(d).filter((x) => x.endsWith(".json")).sort() : []) {
    const name = f.slice(0, -5), c = JSON.parse(readFileSync(join(d, f), "utf8"));
    if (typeof c.ok === "boolean") out.checks[name] = c.ok;
    if (c.note) out.notes.push(`${name}: ${c.note}`);
  }
  return out;
}

export function writeTiming(dir, phase, seconds) {
  if (!NAME.test(phase)) throw new Error(`bad phase name ${phase}`);
  mkdirSync(join(dir, "timings"), { recursive: true, mode: 0o700 });
  writeFileSync(join(dir, "timings", `${phase}.json`), `${Math.max(0, Math.round(seconds))}\n`, { mode: 0o600 });
  console.log(`timing: ${phase} ${Math.round(seconds)}s`);
}
/** Each phase's seconds, in the order they were written. */
export function readTimings(dir) {
  const d = join(dir, "timings");
  if (!existsSync(d)) return {};
  const files = readdirSync(d).filter((x) => x.endsWith(".json")).sort((a, b) => statSync(join(d, a)).mtimeMs - statSync(join(d, b)).mtimeMs);
  return Object.fromEntries(files.map((f) => [f.slice(0, -5), Number(readFileSync(join(d, f), "utf8"))]).filter(([, s]) => Number.isFinite(s)));
}

/** passed (every check true), failed (one ran and said no: the candidate's own failure) or incomplete (some never decided). */
export function verdictOf(checks, names = CHECKS) {
  if (names.every((n) => checks[n] === true)) return "passed";
  return Object.values(checks).some((v) => v === false) ? "failed" : "incomplete";
}

/**
 * Checks side by side, each within its bound: item {names, ms, run(signal)}. run returns its outcomes ([{name, ok, note}])
 * or writes them itself (a child process) and returns nothing. A throw is a "no" (false) for its names not yet decided; a
 * bound reached leaves them undecided with a note (incomplete), and outcomes arriving after it are ignored. Waits for all.
 */
export async function runParallel(dir, items) {
  await Promise.all(items.map(async (it) => {
    const t0 = Date.now(), ac = new AbortController();
    let timer;
    const r = await Promise.race([
      Promise.resolve().then(() => it.run(ac.signal)).then((out) => ({ out }), (error) => ({ error })),
      new Promise((ok) => { timer = setTimeout(() => ok({ timedOut: true }), it.ms); }),
    ]);
    clearTimeout(timer);
    ac.abort();
    const secs = (Date.now() - t0) / 1000;
    for (const o of r.out ?? []) writeCheck(dir, o.name, o.ok === true, o.note);
    for (const n of it.names) {
      if (decided(dir, n)) continue;
      if (r.timedOut) writeCheck(dir, n, null, `didn't finish within ${Math.round(it.ms / 1000)}s`);
      else if (r.error) writeCheck(dir, n, false, r.error.message);
      else writeCheck(dir, n, null, "ended without a result");
    }
    writeTiming(dir, `check_${it.names[0]}`, secs);
  }));
}

/** A child process as a parallel check's run: it writes its own check files; aborted, its whole process group is killed. */
export const child = (cmd, args, env = {}) => (signal) => new Promise((ok) => {
  const p = spawn(cmd, args, { stdio: "inherit", detached: true, env: { ...process.env, ...env } });
  const kill = () => { try { process.kill(-p.pid, "SIGKILL"); } catch {} };
  signal.addEventListener("abort", kill, { once: true });
  p.on("exit", () => { signal.removeEventListener("abort", kill); ok(); });
  p.on("error", () => ok());
});

/** result.json: the identity select named, every CHECKS entry (false unless it ran and passed), the notes and the timings. */
export function buildResult(dir, id, baseline) {
  const c = readChecks(dir);
  const checks = Object.fromEntries(CHECKS.map((n) => [n, c.checks[n] === true]));
  return {
    result: { release: id.tag, release_id: id.release_id, tag_sha: id.tag_sha, kernel: id.kernel, baseline, passed: Object.values(checks).every(Boolean), checks, notes: c.notes.map((n) => n.slice(0, 300)).slice(-20), timings: Object.fromEntries(Object.entries(readTimings(dir)).slice(0, 30)) },
    verdict: verdictOf(c.checks),
  };
}

/** What a triager needs, without admin rights to the logs: each failed check with its note, then the last note naming the update
 * record, scrubbed of URLs, addresses and tokens and capped (it goes in a public issue). */
export function failureLines(result, cap = 12) {
  const scrub = (t) => t.replace(/https?:\/\/\S+/g, "<url>").replace(/\b\d{1,3}(\.\d{1,3}){3}\b/g, "<ip>").replace(/(token=)\S+/g, "$1<redacted>").replace(/sk-or-[\w-]{20,}/g, "<redacted>").replace(/`/g, "'").slice(0, 300);
  const lines = Object.entries(result.checks).filter(([, ok]) => !ok).map(([k]) => `FAIL ${k}: ${result.notes.findLast((n) => n.startsWith(`${k}: `))?.slice(k.length + 2) ?? "no note (it never ran or decided)"}`);
  const rec = result.notes.findLast((n) => n.includes("record:"));
  if (rec && !lines.some((l) => l.endsWith(rec.slice(rec.indexOf(": ") + 2)))) lines.push(`last record: ${rec}`);
  return lines.slice(0, cap).map(scrub).join("\n");
}

if (import.meta.main && process.argv[2] === "result") {
  const dir = process.env.GRAD_DIR;
  if (!dir) throw new Error("GRAD_DIR is not set");
  const { result, verdict } = buildResult(dir, JSON.parse(process.env.IDENTITY ?? ""), process.env.BASELINE);
  writeFileSync(join(dir, "result.json"), `${JSON.stringify(result, null, 2)}\n`);
  console.log(JSON.stringify(result, null, 2));
  // A harness limit (graduate-instance.sh harness: something this test can't do) with nothing that said no: "harness".
  const v = verdict === "incomplete" && existsSync(join(dir, "harness")) ? "harness" : verdict;
  console.log(`verdict: ${v}`);
  // Whether the candidate's move began (the updater prepared it): only then can a failure be the candidate's.
  const reached = existsSync(join(dir, "reached-candidate")) ? "candidate" : "";
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `verdict=${v}\nreached=${reached}\nfailures<<GRAD_EOF\n${failureLines(result)}\nGRAD_EOF\n`);
  const table = [
    "| check | |", "|---|---|", ...Object.entries(result.checks).map(([k, v]) => `| ${k} | ${v ? "ok" : "FAIL"} |`), "", `Verdict: ${v}`, "",
    "| phase | seconds |", "|---|---|", ...Object.entries(result.timings).map(([k, v]) => `| ${k} | ${v} |`), "",
  ].join("\n");
  console.log(table);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${table}\n`);
}
