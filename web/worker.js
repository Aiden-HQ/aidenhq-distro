// aidenhq.ai serves the site; get.aidenhq.ai serves the installer as plain text, so `curl -fsSL get.aidenhq.ai | sh` works.
export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.hostname.startsWith("get.")) {
      if (url.pathname !== "/" && url.pathname !== "/install.sh") return new Response("Not found\n", { status: 404 });
      const res = await env.ASSETS.fetch(new URL("/install.sh", url));
      return new Response(res.body, {
        status: res.status,
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": "public, max-age=300",
          "x-content-type-options": "nosniff",
          "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
          "referrer-policy": "no-referrer",
        },
      });
    }
    return env.ASSETS.fetch(req);
  },
};
