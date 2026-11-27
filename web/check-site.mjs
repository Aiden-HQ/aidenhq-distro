// Fails the build when a page would share or index badly: run by web/build.sh on the assembled web/public.
// Every HTML page needs a title, a description, a canonical URL, the full Open Graph and Twitter set with an og:image
// that exists here (a 1200x630 PNG under 300 KB), JSON-LD that parses, ordered headings, a markdown twin and a
// sitemap entry; every internal link must resolve. Zero dependencies.
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative } from "node:path";

const ORIGIN = "https://aidenhq.ai";
const root = new URL("./public/", import.meta.url).pathname;
const errors = [];
const fail = (where, msg) => errors.push(`${where}: ${msg}`);

const files = (dir) => readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? files(join(dir, n)) : [join(dir, n)]));
const all = files(root).map((f) => "/" + relative(root, f));
const pages = all.filter((f) => f.endsWith(".html"));
const urlOf = (f) => f.replace(/index\.html$/, "");
// A site path (no origin) to the file that serves it, or null.
const resolve = (path) => {
  path = decodeURIComponent(path.split(/[?#]/)[0]);
  for (const c of [path, path + (path.endsWith("/") ? "" : "/") + "index.html"]) if (all.includes(c)) return c;
  return null;
};
const attrs = (tag) => Object.fromEntries([...tag.matchAll(/([a-z:-]+)="([^"]*)"/g)].map((m) => [m[1], m[2]]));
const pngSize = (buf) => buf.toString("ascii", 1, 4) === "PNG" && { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };

const sitemap = readFileSync(join(root, "sitemap.xml"), "utf8");
const locs = [...sitemap.matchAll(/<url>\s*<loc>([^<]+)<\/loc>\s*<lastmod>(\d{4}-\d{2}-\d{2})<\/lastmod>\s*<\/url>/g)].map((m) => m[1]);
if (locs.length !== (sitemap.match(/<url>/g) || []).length) fail("sitemap.xml", "every <url> needs a <loc> then a <lastmod> (YYYY-MM-DD)");
for (const loc of locs) if (!loc.startsWith(ORIGIN + "/") || !resolve(loc.slice(ORIGIN.length))) fail("sitemap.xml", `${loc} is not a file on this site`);

for (const page of pages) {
  const html = readFileSync(join(root, page), "utf8");
  const head = html.split("</head>")[0];
  const meta = {};
  for (const m of head.matchAll(/<meta\s[^>]*>/g)) {
    const a = attrs(m[0]);
    const key = a.property || a.name;
    if (key && !(key in meta)) meta[key] = a.content;
  }
  const link = (rel) => [...head.matchAll(/<link\s[^>]*>/g)].map((m) => attrs(m[0])).find((a) => a.rel === rel)?.href;
  const url = ORIGIN + urlOf(page);

  if (!/^<!doctype html>\s*<html lang="[a-z]{2}(-[A-Z]{2})?">/i.test(html)) fail(page, "starts with <!doctype html><html lang=…>");
  if (!/^<meta charset="utf-8">$/m.test(html.slice(0, 1024))) fail(page, '<meta charset="utf-8"> must be in the first 1024 bytes');
  const title = head.match(/<title>([^<]+)<\/title>/)?.[1];
  if (!title) fail(page, "no <title>");
  if (!(meta.description?.length >= 50)) fail(page, "no meta description (50+ characters)");
  if (link("canonical") !== url) fail(page, `canonical must be ${url}`);
  for (const k of ["og:type", "og:site_name", "og:title", "og:description", "og:url", "og:image", "og:image:width", "og:image:height", "og:image:alt", "twitter:card", "twitter:title", "twitter:description", "twitter:image"])
    if (!meta[k]) fail(page, `no ${k}`);
  if (meta["og:url"] && meta["og:url"] !== url) fail(page, `og:url must be ${url}`);
  if (meta["twitter:card"] && meta["twitter:card"] !== "summary_large_image") fail(page, "twitter:card must be summary_large_image");
  for (const k of ["og:image", "twitter:image"]) {
    const img = meta[k];
    if (!img) continue;
    if (!img.startsWith(ORIGIN + "/")) { fail(page, `${k} must be an absolute ${ORIGIN}/ URL`); continue; }
    const file = resolve(img.slice(ORIGIN.length));
    if (!file) { fail(page, `${k} ${img} is not in site/`); continue; }
    const buf = readFileSync(join(root, file));
    const size = pngSize(buf);
    if (!size || size.w !== 1200 || size.h !== 630) fail(page, `${k} ${file} must be a 1200x630 PNG`);
    else if (k === "og:image" && (meta["og:image:width"] !== "1200" || meta["og:image:height"] !== "630")) fail(page, "og:image:width/height must be 1200/630");
    if (buf.length > 300_000) fail(page, `${k} ${file} is over 300 KB`);
  }
  for (const rel of ["icon", "apple-touch-icon", "manifest"]) {
    const href = link(rel);
    if (!href || !resolve(href)) fail(page, `no ${rel} link to a file on this site`);
  }

  const ld = [...head.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
  if (!ld.length) fail(page, "no JSON-LD in <head>");
  for (const [, json] of ld) {
    try { const d = JSON.parse(json); if (d["@context"] !== "https://schema.org") fail(page, "JSON-LD @context must be https://schema.org"); }
    catch (e) { fail(page, `JSON-LD does not parse: ${e.message}`); }
  }

  const body = html.slice(html.indexOf("<body"));
  const levels = [...body.matchAll(/<h([1-6])[\s>]/g)].map((m) => +m[1]);
  if (levels.filter((l) => l === 1).length !== 1) fail(page, "needs exactly one <h1>");
  levels.forEach((l, i) => { if (i && l > levels[i - 1] + 1) fail(page, `heading jumps from h${levels[i - 1]} to h${l}`); });
  for (const m of body.matchAll(/<img\s[^>]*>/g)) if (!/\salt="/.test(m[0])) fail(page, `image without alt: ${m[0].slice(0, 80)}`);
  for (const m of html.matchAll(/\s(?:href|src)="(\/[^"]*)"/g)) if (!m[1].startsWith("//") && !resolve(m[1])) fail(page, `broken internal link ${m[1]}`);

  const twin = urlOf(page) + "index.md";
  if (!all.includes(twin)) fail(page, `no markdown twin ${twin}`);
  else if (existsSync(join(root, twin))) {
    // Twins are written by hand; a conversion of the logo chips once left "#**Slack** :**" and empty "``" lines behind.
    const md = readFileSync(join(root, twin), "utf8");
    for (const [re, what] of [[/^#\*\*/m, "line starting #**"], [/\*\* :\*\*/, "stray ** :** markup"], [/^``$/m, "empty `` line"]])
      if (re.test(md)) fail(twin, `garbled markdown: ${what}`);
  }
  for (const u of [url, ORIGIN + twin]) if (!locs.includes(u)) fail("sitemap.xml", `missing ${u}`);
}
for (const f of ["/llms.txt", "/llms-full.txt", "/prompt.md"]) if (!all.includes(f) || !locs.includes(ORIGIN + f)) fail("sitemap.xml", `missing ${f}`);
for (const m of readFileSync(join(root, "llms.txt"), "utf8").matchAll(/\]\((https:\/\/aidenhq\.ai[^)]*)\)/g))
  if (!resolve(m[1].slice(ORIGIN.length) || "/")) fail("llms.txt", `broken link ${m[1]}`);
if (!existsSync(join(root, "robots.txt")) || !readFileSync(join(root, "robots.txt"), "utf8").includes(`Sitemap: ${ORIGIN}/sitemap.xml`)) fail("robots.txt", "must point at the sitemap");

if (errors.length) {
  console.error(`check-site: ${errors.length} problem(s)\n  ` + errors.join("\n  "));
  process.exit(1);
}
console.log(`check-site: ${pages.length} pages ok`);
