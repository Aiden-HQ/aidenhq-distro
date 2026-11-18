// aidenhq.ai serves the site; get.aidenhq.ai serves the installer as plain text, so `curl -fsSL get.aidenhq.ai | sh` works.
// On `/`, an agent that asks for markdown (Accept: text/markdown, or text/plain without text/html) gets /index.md.
// The latest published release's install.sh. GitHub's "latest" is the newest non-draft, non-prerelease release; release.yml
// publishes only after the release's install-and-test passed (a draft until then, deleted if it fails) and marks it latest only
// when no published release has a newer name. So this serves exactly the installer GitHub published for that tested release.
const LATEST = "https://github.com/Aiden-HQ/aidenhq-distro/releases/latest/download/install.sh";
// Cache API keys: a fresh copy for a few minutes, and the last good one for when GitHub fails.
const FRESH = "https://get.aidenhq.ai/.installer/fresh";
const LAST = "https://get.aidenhq.ai/.installer/last";
const LINK = '</index.md>; rel="alternate"; type="text/markdown", </llms.txt>; rel="describedby"; type="text/plain"';

// q-value of a media type in an Accept header (0 when absent; wildcards ignored).
function q(accept, type) {
  for (const part of accept.toLowerCase().split(",")) {
    const [t, ...params] = part.trim().split(";");
    if (t.trim() !== type) continue;
    const p = params.map((s) => s.trim()).find((s) => s.startsWith("q="));
    return p ? Number(p.slice(2)) || 0 : 1;
  }
  return 0;
}
function wantsMarkdown(accept) {
  const html = q(accept, "text/html");
  const md = q(accept, "text/markdown");
  return (md > 0 && md >= html) || (html === 0 && q(accept, "text/plain") > 0);
}

/** A cut installer: release.yml bakes its release, the release file's sha256 and the distro commit in; the repo's copy has none. */
export function isCut(text) {
  return /^DEFAULT_RELEASE=\d{4}\.\d{1,2}(\.\d+){0,2}$/m.test(text) && /^RELEASE_SHA256="[0-9a-f]{64}"$/m.test(text)
    && /^RELEASE_COMMIT="[0-9a-f]{40}"$/m.test(text) && text.trimEnd().endsWith('main "$@"');
}

const kept = (text, seconds) => new Response(text, { headers: { "cache-control": `public, max-age=${seconds}` } });

/** The installer to serve: the cached fresh copy, else GitHub's latest (cached), else the last good copy; null when none. */
export async function installer(cache, get = fetch) {
  const fresh = await cache.match(FRESH);
  if (fresh) return fresh.text();
  try {
    const res = await get(LATEST, { redirect: "follow" });
    const text = res.ok ? await res.text() : "";
    if (isCut(text)) {
      await Promise.all([cache.put(FRESH, kept(text, 300)), cache.put(LAST, kept(text, 30 * 86400))]);
      return text;
    }
  } catch {
    // GitHub unreachable: the last good copy below.
  }
  const last = await cache.match(LAST);
  return last ? last.text() : null;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.hostname.startsWith("get.")) {
      if (url.pathname !== "/" && url.pathname !== "/install.sh") return new Response("Not found\n", { status: 404 });
      const body = await installer(caches.default);
      if (body === null) return new Response("The installer is unavailable; try again shortly.\n", { status: 502 });
      return new Response(body, {
        status: 200,
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": "public, max-age=300",
          "x-content-type-options": "nosniff",
          "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
          "referrer-policy": "no-referrer",
        },
      });
    }
    if (url.pathname !== "/") return env.ASSETS.fetch(req);
    const md = wantsMarkdown(req.headers.get("accept") || "");
    const res = await env.ASSETS.fetch(md ? new Request(new URL("/index.md", url), req) : req);
    const out = new Response(res.body, res);
    if (md) out.headers.set("content-type", "text/markdown; charset=utf-8");
    out.headers.append("vary", "Accept");
    out.headers.set("link", LINK);
    return out;
  },
};
