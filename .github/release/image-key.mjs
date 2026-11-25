// Content keys for release images (release.yml's plan job; README "Nightly releases").
//   node .github/release/image-key.mjs <kernel dir> < chains.json > chains-with-keys.json
// chains.json is the lister's output: chains of { name, context, base? } in build order (a computer image builds FROM
// its parent). Each entry gets a `key`, which names the registry tag `k-<key>` (the multi-arch image) and
// `k-<key>-<arch>` (one platform). The same key means the same build inputs, so a registry hit is the image a build
// would produce and the build is skipped. The key covers:
//   KEY_VERSION   bump it to force a full rebuild (a changed build recipe in release.yml, a changed flag)
//   week          the ISO week of the run: a build pulls unpinned base images and apt packages, so a week-old image
//                 is rebuilt once a week and picks up their security updates
//   context       every file under the build context (path, executable bit, content; symlinks by target), Dockerfile
//                 included, minus .git and node_modules (the tarball the images job builds from has neither).
//                 .dockerignore isn't applied: hashing an ignored file only costs a spurious rebuild, never a stale image
//   parent key    the key of the image it builds FROM (the only build arg is BASE, the parent's digest)
// The key is computed once, in plan, so every build leg and the manifest job use the same one.
import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readdirSync, readlinkSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

export const KEY_VERSION = 1;

export function isoWeek(date) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day); // the Thursday of this week names its year
  const year = d.getUTCFullYear();
  const week = Math.ceil(((d - Date.UTC(year, 0, 1)) / 86400000 + 1) / 7);
  return `${year}-W${String(week).padStart(2, "0")}`;
}

export function contextHash(dir) {
  const h = createHash("sha256");
  const walk = (rel) => {
    for (const e of readdirSync(join(dir, rel), { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))) {
      if (e.name === ".git" || e.name === "node_modules") continue;
      const p = rel ? `${rel}/${e.name}` : e.name;
      const full = join(dir, p);
      if (e.isDirectory()) walk(p);
      else if (e.isSymbolicLink()) h.update(`L ${JSON.stringify(p)} ${JSON.stringify(readlinkSync(full))}\n`);
      else if (e.isFile()) {
        const body = readFileSync(full);
        h.update(`F ${JSON.stringify(p)} ${lstatSync(full).mode & 0o111 ? "x" : "-"} ${body.length} `).update(body).update("\n");
      }
    }
  };
  walk("");
  return h.digest("hex");
}

export function withKeys(chains, kernelDir, now = new Date()) {
  const week = isoWeek(now);
  return chains.map((chain) => {
    const keys = {};
    return chain.map((img) => {
      const parent = img.base ? keys[img.base] : null;
      if (img.base && !parent) throw new Error(`${img.name} builds FROM ${img.base}, which isn't earlier in its chain`);
      const key = createHash("sha256")
        .update(JSON.stringify([KEY_VERSION, week, contextHash(join(kernelDir, img.context)), parent]))
        .digest("hex")
        .slice(0, 32);
      keys[img.name] = key;
      return { ...img, key };
    });
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const chains = JSON.parse(readFileSync(0, "utf8"));
  console.log(JSON.stringify(withKeys(chains, process.argv[2])));
}
