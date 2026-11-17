// The release suites (lean-core spec §6.8, §9) on a verified checkout of the release set:
//   node suites.mjs <kernel checkout> <marketplace checkout | -> <suite>...
// Prints, as its last line, the JSON list of suites that ran and passed; a suite with no test in this kernel yet is skipped
// (and said so). Exit 1 when any test fails: the release is not cut.
//
// A suite is a list of test files: the kernel's own checklists (scripts/lean/adversarial.json, parity.json) or one named
// file. Each file runs in its package (the nearest package.json; installed once with `npm ci --ignore-scripts` when it has
// a lockfile): `.mjs` with node's test runner, `.ts` with vitest when the package uses it, else node. A `modules/<m>/…`
// file missing from the kernel checkout is looked up in the marketplace checkout (after the modules move to their own
// repository). The twin runs with the kernel CI's own command for it (the PACKAGES table in .github/workflows/ci.yml).
import { execFileSync, execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";

const [kernel, market, ...suites] = process.argv.slice(2);
const mkt = market && market !== "-" && existsSync(market) ? market : "";
const json = (p) => JSON.parse(readFileSync(join(kernel, p), "utf8"));

const files = {
  "kernel-only": () => ["kernel/test/kernel-only.test.ts"].filter((f) => existsSync(join(kernel, f))),
  swap: () => ["scripts/test/swap.test.mjs"].filter((f) => existsSync(join(kernel, f))),
  twin: () => (existsSync(join(kernel, "fixtures/twin/module.yaml")) ? ["fixtures/twin"] : []),
  adversarial: () => testsOf(json("scripts/lean/adversarial.json").map((r) => r.test).filter(Boolean)),
  parity: () => testsOf(json("scripts/lean/parity.json").flatMap((r) => r.today)),
};

/** The test files of a checklist; its other entries (a planted reviewer case, a script) must exist, and run elsewhere. */
function testsOf(list) {
  for (const f of list) locate(f);
  return [...new Set(list.filter((f) => /\.test\.\w+$/.test(f)))];
}

/** Where a file is: [package dir (absolute), path inside it]. */
function locate(file) {
  let abs = join(kernel, file);
  let top = kernel;
  if (!existsSync(abs)) {
    const rel = file.replace(/^modules\//, "");
    if (!mkt || rel === file || !existsSync(join(mkt, rel))) throw new Error(`${file}: not in the kernel or the marketplace checkout`);
    [abs, top] = [join(mkt, rel), mkt];
  }
  let d = dirname(abs);
  while (d.startsWith(top) && d !== top && !existsSync(join(d, "package.json"))) d = dirname(d);
  // No package.json (a module whose tests need nothing installed): its tests run from the folder holding test/.
  if (!existsSync(join(d, "package.json"))) d = abs.includes("/test/") ? abs.slice(0, abs.lastIndexOf("/test/")) : dirname(abs);
  return [d, relative(d, abs)];
}

const sh = (cmd, cwd) => execSync(cmd, { cwd, stdio: "inherit", shell: "/bin/bash", timeout: 45 * 60_000 });
const installed = new Set();
function install(dir) {
  if (installed.has(dir)) return;
  installed.add(dir);
  if (existsSync(join(dir, "package-lock.json"))) execFileSync("npm", ["ci", "--ignore-scripts", "--no-audit", "--no-fund"], { cwd: dir, stdio: "inherit" });
}

/** Runs one suite's files, grouped by package; true when every one passed. */
function runSuite(name, list) {
  if (name === "twin") {
    const ci = readFileSync(join(kernel, ".github/workflows/ci.yml"), "utf8");
    const cmd = /^\s*fixtures\/twin\|([^|]+)\|/m.exec(ci)?.[1];
    if (!cmd) throw new Error("the kernel's CI has no fixtures/twin row");
    try { sh(cmd, join(kernel, "fixtures/twin")); return true; } catch { return false; }
  }
  const byPkg = new Map();
  for (const f of list) {
    const [dir, rel] = locate(f);
    byPkg.set(dir, [...(byPkg.get(dir) ?? []), rel]);
  }
  let ok = true;
  for (const [dir, rels] of byPkg) {
    const pkg = existsSync(join(dir, "package.json")) ? JSON.parse(readFileSync(join(dir, "package.json"), "utf8")) : {};
    const vitest = Boolean(pkg.devDependencies?.vitest ?? pkg.dependencies?.vitest);
    const [ts, mjs] = [rels.filter((r) => r.endsWith(".ts") && vitest), rels.filter((r) => !(r.endsWith(".ts") && vitest))];
    console.log(`::group::${name}: ${relative(kernel, dir) || dir}: ${rels.length} files`);
    try {
      install(dir);
      if (mjs.length) execFileSync(process.execPath, ["--disable-warning=ExperimentalWarning", "--test", "--test-timeout=300000", ...mjs], { cwd: dir, stdio: "inherit", timeout: 45 * 60_000 });
      if (ts.length) execFileSync("npx", ["vitest", "run", ...ts], { cwd: dir, stdio: "inherit", timeout: 45 * 60_000 });
    } catch {
      ok = false;
      console.log(`::error::${name}: ${dir} failed`);
    }
    console.log("::endgroup::");
  }
  return ok;
}

// scripts/node_modules is read by the scripts tests and the kernel's authority CLI: once, first (ci.yml does the same).
install(join(kernel, "scripts"));
const ran = [];
let failed = false;
for (const s of suites) {
  if (!files[s]) throw new Error(`unknown suite ${s}`);
  const list = files[s]();
  if (!list.length) { console.log(`suite ${s}: no test in this kernel yet, skipped`); continue; }
  const ok = runSuite(s, list);
  console.log(`suite ${s}: ${list.length} test files: ${ok ? "passed" : "FAILED"}`);
  if (ok) ran.push(s); else failed = true;
}
console.log(JSON.stringify(ran));
process.exitCode = failed ? 1 : 0;
