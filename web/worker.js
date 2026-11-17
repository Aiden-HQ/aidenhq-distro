// aidenhq.ai serves the site; get.aidenhq.ai serves the installer as plain text, so `curl -fsSL get.aidenhq.ai | sh` works.
// On `/`, an agent that asks for markdown (Accept: text/markdown, or text/plain without text/html) gets /index.md.
const RELEASES = "https://github.com/Aiden-HQ/aidenhq-distro/releases/download";
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

async function sha256(buf) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", buf))].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.hostname.startsWith("get.")) {
      if (url.pathname !== "/" && url.pathname !== "/install.sh") return new Response("Not found\n", { status: 404 });
      // The pinned release's install.sh (wrangler.jsonc vars INSTALLER_TAG and INSTALLER_SHA256, set by the release workflow's
      // PR): fetched, checked against its sha256, and served only if it matches. The repo's own copy is uncut and can't install.
      const res = await fetch(`${RELEASES}/${env.INSTALLER_TAG}/install.sh`, { cf: { cacheTtl: 300 } });
      const body = res.ok ? await res.arrayBuffer() : null;
      if (!body || (await sha256(body)) !== env.INSTALLER_SHA256) return new Response("The installer is unavailable; try again shortly.\n", { status: 502 });
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
