// The Markdown body of a distro GitHub release (release.yml publish): its install line, its notes as sections and a link to every
// product change since the previous published release (which may be a rejected pre-release, so an upgrader's own range can be wider).
//   TAG, GITHUB_REPOSITORY, GITHUB_TOKEN; node .github/release/release-body.mjs <release.json>   prints the body
import { readFileSync } from "node:fs";
import { api, compare, NAME } from "./nightly.mjs";
import { compareLink, renderBody } from "./notes.mjs";

/** The kernel of the newest published (not draft) release older than `tag`, or "" when there is none or it can't be read. */
export async function previousKernel(tag, repo, get = api) {
  try {
    const older = (await get(`repos/${repo}/releases?per_page=100`)).filter((r) => !r.draft && NAME.test(r.tag_name) && compare(r.tag_name, tag) < 0).map((r) => r.tag_name).sort(compare);
    const prev = older.at(-1);
    const f = prev && (await get(`repos/${repo}/contents/releases/${prev}.json?ref=${prev}`));
    return f ? JSON.parse(Buffer.from(f.content, "base64").toString("utf8")).kernel ?? "" : "";
  } catch (e) {
    console.log(`::warning::no compare link: ${e.message}`);
    return "";
  }
}

if (import.meta.main) {
  const file = JSON.parse(readFileSync(process.argv[2], "utf8"));
  const repo = process.env.GITHUB_REPOSITORY, tag = process.env.TAG;
  const link = compareLink("Aiden-HQ/AidenHQ", await previousKernel(tag, repo), file.kernel);
  process.stdout.write(renderBody(file.notes ?? [], { lead: `Install: \`curl -fsSL https://github.com/${repo}/releases/download/${tag}/install.sh | sh\``, compare: link }));
}
