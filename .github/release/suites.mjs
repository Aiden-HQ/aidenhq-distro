// The release suites (lean-core spec §6.8, §9) on a verified checkout of the release set:
//   node suites.mjs <kernel checkout> <marketplace checkout | -> <suite>...
// Prints, as its last line, the JSON list of suites that ran and passed; a suite with no test in this kernel yet is skipped
// (and said so). Exit 1 when any package fails: the release is not cut.
//
// A suite is a list of test files: the kernel's own checklists (scripts/lean/adversarial.json, parity.json), or one named file.
// Each file runs as part of its package, with the command the kernel's CI runs for that package (the PACKAGES table in
// .github/workflows/ci.yml), so the release runs what CI runs. A `modules/<m>/…` file missing from the kernel checkout is
// looked up in the marketplace checkout (after the modules move to their own repository) and runs with `npm test` there.
import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";

const [kernel, market, ...suites] = process.argv.slice(2);
const mkt = market && market !== "-" ? market : "";
const json = (p) => JSON.parse(readFileSync(join(kernel, p), "utf8"));

// The kernel CI's packages: "dir|command|paths". Runner and board have their own jobs there: their commands are here.
const OWN_JOB = { "services/runner": "npm ci && npm test", "services/board": "npm ci && npx vitest run" };
const ci = readFileSync(join(kernel, ".github/workflows/ci.yml"), "utf8");
const table = /<<'PACKAGES'\n([\s\S]*?)\n\s*PACKAGES\n/.exec(ci)?.[1] ?? "";
const packages = new Map(table.split("\n").map((l) => l.trim().split("|")).filter((r) => r.length >= 2 && !r[0].includes("#")).map(([dir, cmd]) => [dir, cmd.startsWith("(its own") ? OWN_JOB[dir] : cmd]));

const files = {
  "kernel-only": () => ["kernel/test/kernel-only.test.ts"].filter((f) => existsSync(join(kernel, f))),
  swap: () => ["scripts/test/swap.test.mjs"].filter((f) => existsSync(join(kernel, f))),
  twin: () => ["fixtures/twin/module.yaml"].filter((f) => existsSync(join(kernel, f))),
  adversarial: () => json("scripts/lean/adversarial.json").map((r) => r.test).filter(Boolean),
  parity: () => json("scripts/lean/parity.json").flatMap((r) => r.today).filter((f) => /\.test\.\w+$/.test(f)),
};

/** The package a file runs in: [root, dir, command]. */
function packageOf(file) {
  if (existsSync(join(kernel, file))) {
    const dir = [...packages.keys()].filter((d) => file.startsWith(`${d}/`)).sort((a, b) => b.length - a.length)[0];
    if (!dir || !packages.get(dir)) throw new Error(`${file}: no package in the kernel's CI table runs it`);
    return [kernel, dir, packages.get(dir)];
  }
  const rel = file.replace(/^modules\//, "");
  if (!mkt || rel === file || !existsSync(join(mkt, rel))) throw new Error(`${file}: not in the kernel or the marketplace checkout`);
  let d = dirname(join(mkt, rel));
  while (d.startsWith(mkt) && !existsSync(join(d, "package.json"))) d = dirname(d);
  if (!existsSync(join(d, "package.json"))) throw new Error(`${file}: no package.json above it in the marketplace checkout`);
  return [mkt, relative(mkt, d) || ".", existsSync(join(d, "package-lock.json")) ? "npm ci && npm test" : "npm test"];
}

const results = new Map(); // "<root>\0<dir>" -> passed
const run = (root, dir, cmd) => {
  const key = `${root}\0${dir}`;
  if (!results.has(key)) {
    console.log(`::group::${root === kernel ? "kernel" : "marketplace"}: ${dir}: ${cmd}`);
    try { execSync(cmd, { cwd: join(root, dir), stdio: "inherit", shell: "/bin/bash", timeout: 45 * 60_000 }); results.set(key, true); } catch { results.set(key, false); }
    console.log("::endgroup::");
    if (!results.get(key)) console.log(`::error::${dir} failed`);
  }
  return results.get(key);
};

// scripts/node_modules is read by the scripts suite and the kernel's authority CLI: once, first (ci.yml does the same).
execSync("npm ci --ignore-scripts --no-audit --no-fund", { cwd: join(kernel, "scripts"), stdio: "inherit" });
const ran = [];
let failed = false;
for (const s of suites) {
  if (!files[s]) throw new Error(`unknown suite ${s}`);
  const list = files[s]();
  if (!list.length) { console.log(`suite ${s}: no test in this kernel yet, skipped`); continue; }
  const pkgs = [...new Map(list.map((f) => { const p = packageOf(f); return [`${p[0]}\0${p[1]}`, p]; })).values()];
  const ok = pkgs.map(([root, dir, cmd]) => run(root, dir, cmd)).every(Boolean);
  console.log(`suite ${s}: ${list.length} test files in ${pkgs.length} packages: ${ok ? "passed" : "FAILED"}`);
  if (ok) ran.push(s); else failed = true;
}
console.log(JSON.stringify(ran));
process.exitCode = failed ? 1 : 0;
