// The owner's side of graduation's test instance (.github/workflows/graduate.yml, test job): what a new owner does, over
// plain HTTP on the runner's loopback, as the product's own unattended-install test does (no browser).
//   node graduate-scenario.mjs baseline   first run (account, authenticator, model key, welcome skipped), a chat with Aiden,
//                                         then "a tiny page that says hello": what the baseline achieved goes to baseline.json
//   node graduate-scenario.mjs smoke      after the upgrade: agents ready, a fresh reply, the hello app still serves, a
//                                         second app deploys; each check into checks.json
// State lives in $GRAD_DIR (root of the run's scratch, 0700): the account, the authenticator key and the cookies, never printed.
// The model key comes from GRADUATE_OPENROUTER_KEY, for the first run's model step when it asks. Model-dependent steps
// retry within fixed bounds; nothing waits unbounded.
import { createHmac, randomBytes } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import { join } from "node:path";

const DIR = process.env.GRAD_DIR;
if (!DIR) throw new Error("GRAD_DIR is not set");
const BOARD = "http://127.0.0.1:3121";
const MIN = 60_000;
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
const log = (s) => console.log(`${new Date().toISOString().slice(11, 19)} ${s}`);
const readJson = (f, d) => (existsSync(join(DIR, f)) ? JSON.parse(readFileSync(join(DIR, f), "utf8")) : d);
const writeJson = (f, v) => writeFileSync(join(DIR, f), `${JSON.stringify(v, null, 2)}\n`, { mode: 0o600 });

// ------------------------------------------------------------------------------------------------ checks
/** One check's outcome in checks.json (what the result is built from). */
function record(name, ok, note) {
  const c = readJson("checks.json", { checks: {}, notes: [] });
  c.checks[name] = ok === true;
  if (note) c.notes.push(`${name}: ${String(note).replace(/[\r\n]+/g, " ").slice(0, 280)}`);
  writeJson("checks.json", c);
  log(`${ok ? "ok  " : "FAIL"} ${name}${note ? `: ${note}` : ""}`);
}

// ------------------------------------------------------------------------------------------------ HTTP
const session = readJson("session.json", { jar: {} });
const save = () => writeJson("session.json", session);
/** One request to a loopback listener as a browser at `url` would make it: Host and Origin from the URL, the cookie jar. */
function req(method, url, { form, json } = {}) {
  const u = new URL(url);
  const body = form ? new URLSearchParams(form).toString() : json !== undefined ? JSON.stringify(json) : undefined;
  const headers = { host: u.host, origin: u.origin, cookie: Object.entries(session.jar).map(([k, v]) => `${k}=${v}`).join("; "), accept: json !== undefined || u.pathname.startsWith("/api/") ? "application/json" : "text/html" };
  if (form) headers["content-type"] = "application/x-www-form-urlencoded";
  if (json !== undefined) Object.assign(headers, { "content-type": "application/json", "x-aidenhq-board": "1" });
  if (u.pathname.startsWith("/api/")) headers["x-aidenhq-board"] = "1";
  const lib = u.protocol === "https:" ? https : http;
  const loop = u.hostname === "localhost" || u.hostname === "127.0.0.1" || u.hostname.endsWith(".localhost");
  return new Promise((ok, no) => {
    const r = lib.request({ host: loop ? "127.0.0.1" : u.hostname, port: u.port || (u.protocol === "https:" ? 443 : 80), method, path: u.pathname + u.search, headers, timeout: 60_000, servername: u.hostname, rejectUnauthorized: !loop }, (res) => {
      for (const c of res.headers["set-cookie"] ?? []) {
        const [kv] = c.split(";"); const i = kv.indexOf("=");
        const [k, v] = [kv.slice(0, i).trim(), kv.slice(i + 1)];
        if (v && !/max-age=0\b/i.test(c)) session.jar[k] = v; else delete session.jar[k];
      }
      let text = ""; res.setEncoding("utf8"); res.on("data", (d) => (text += d));
      res.on("end", () => { save(); let j; try { j = JSON.parse(text); } catch {} ok({ status: res.statusCode, location: res.headers.location ? new URL(res.headers.location, url).href : undefined, text, json: j }); });
    });
    r.on("timeout", () => r.destroy(new Error(`${method} ${u.origin}${u.pathname} timed out`)));
    r.on("error", no);
    r.end(body);
  });
}
/** GET, following redirects (each hop as the browser would). */
async function follow(url, hops = 8) {
  let r = await req("GET", url);
  while (r.status >= 300 && r.status < 400 && r.location && hops--) { url = r.location; r = await req("GET", url); }
  return { ...r, url };
}
const csrfOf = (t) => /name="csrf" value="([0-9a-f]+)"/.exec(t)?.[1];
const board = async (method, path, json) => {
  const r = await req(method, BOARD + path, method === "GET" ? {} : { json: json ?? {} });
  if (r.status === 401) { await signIn(); return req(method, BOARD + path, method === "GET" ? {} : { json: json ?? {} }); }
  return r;
};
const want = (cond, what) => { if (!cond) throw new Error(what); };

/** RFC 6238: the authenticator's current 6-digit code for a base32 key. */
function totp(key, at = Date.now()) {
  const A = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const bits = [...key.toUpperCase().replace(/=+$/, "")].map((c) => A.indexOf(c).toString(2).padStart(5, "0")).join("");
  const k = Buffer.from(bits.match(/.{8}/g).map((b) => parseInt(b, 2)));
  const ctr = Buffer.alloc(8); ctr.writeBigUInt64BE(BigInt(Math.floor(at / 30_000)));
  const h = createHmac("sha1", k).update(ctr).digest(); const o = h[19] & 15;
  return String((h.readUInt32BE(o) & 0x7fffffff) % 1e6).padStart(6, "0");
}

// ------------------------------------------------------------------------------------------------ the first run
async function firstRun() {
  const setup = readFileSync(join(DIR, "setup-url"), "utf8").trim();
  const u = new URL(setup);
  const K = u.origin;
  Object.assign(session, { email: "owner@example.com", name: "Graduation Owner", password: randomBytes(18).toString("base64url") });
  const page = await req("GET", setup);
  want(page.status === 200 && page.text.includes('name="password"'), `GET /setup: ${page.status}`);
  const made = await req("POST", `${K}/setup`, { form: { token: u.searchParams.get("token"), email: session.email, name: session.name, password: session.password } });
  want(made.status === 303 && /\/auth\/enrol$/.test(made.location ?? ""), `the account wasn't made (${made.status} ${made.location ?? ""})`);
  const enrol = await req("GET", `${K}/auth/enrol`);
  const shown = await req("POST", `${K}/auth/enrol`, { form: { csrf: csrfOf(enrol.text), password: session.password } });
  session.totp = /Key: <code>([A-Z2-7 ]+)<\/code>/.exec(shown.text)?.[1]?.replace(/ /g, "");
  want(session.totp, "no authenticator key was shown");
  save();
  const fin = await req("POST", `${K}/auth/enrol`, { form: { csrf: csrfOf(shown.text), code: totp(session.totp) } });
  want(fin.status === 303, `the authenticator code wasn't taken (${fin.status})`);
  log(`authenticator set up; next ${new URL(fin.location).pathname}`);
  // The model step, when the key in the vault hasn't passed its check yet (the installer's key, or none).
  if (new URL(fin.location).pathname === "/setup/model") {
    const step = await req("GET", `${K}/setup/model`);
    if (!/A working key is already in the vault/.test(step.text)) {
      const key = process.env.GRADUATE_OPENROUTER_KEY ?? "";
      want(key, "the model step asks for a key and GRADUATE_OPENROUTER_KEY is empty");
      const r = await req("POST", `${K}/setup/model`, { form: { csrf: csrfOf(step.text), action: "paste", openrouter_key: key } });
      want(r.status === 303, r.text.includes("Add credit") ? "the model key has no credit" : `the model key wasn't accepted (${r.status})`);
    }
    log("model key ready");
  }
  const rk = await req("GET", `${K}/recovery-key`);
  if (csrfOf(rk.text) && /name="choice"|value="saved"/.test(rk.text)) await req("POST", `${K}/recovery-key`, { form: { csrf: csrfOf(rk.text), choice: "saved" } });
  session.kernel = K;
  save();
  await boardSession();
  const w = await board("GET", "/api/welcome");
  want(w.status === 200, `GET /api/welcome: ${w.status}`);
  if (!w.json.finished) {
    const f = await board("POST", "/api/welcome/finish", { done: [], skipped: w.json.wizard ?? [] });
    want(f.status === 200, `finishing the welcome: ${f.status} ${f.text.slice(0, 200)}`);
  }
  log("welcome finished, every wizard flow skipped");
}
/** The board's own session, through the kernel's handoff. */
async function boardSession() {
  const r = await follow(`${BOARD}/auth/start`);
  const me = await req("GET", `${BOARD}/api/welcome`);
  want(me.status === 200, `the board's sign-in handoff didn't give a session (${r.status} at ${new URL(r.url).pathname}, then ${me.status})`);
}
/** A fresh sign-in (password, then the authenticator), when the board's session is gone (e.g. after the upgrade). */
async function signIn() {
  const K = session.kernel;
  want(K && session.totp, "no account to sign in with (the baseline's first run didn't finish)");
  log("signing in again");
  const r = await req("POST", `${K}/auth/sign-in`, { form: { email: session.email, password: session.password } });
  want(r.status === 303, `sign-in: ${r.status}`);
  if (/\/auth\/totp/.test(r.location ?? "")) {
    const p = await req("GET", r.location);
    const t = await req("POST", r.location, { form: { csrf: csrfOf(p.text) ?? "", code: totp(session.totp) } });
    want(t.status === 303, `the authenticator code at sign-in: ${t.status}`);
  }
  await boardSession();
}

// ------------------------------------------------------------------------------------------------ chats and apps
/** A new chat with Aiden; returns its id (a task identifier, or lane:<key> for the fast lane). */
async function newChat(text) {
  const r = await board("POST", "/api/chats", { text });
  want(r.status === 200 && r.json?.identifier, `starting a chat: ${r.status} ${r.text.slice(0, 200)}`);
  return r.json.identifier;
}
/** The chat now: a reply after `since` (ms), its state, and the work it handed out. */
async function chatNow(id, since) {
  if (id.startsWith("lane:")) {
    const r = await board("GET", `/api/lane/${encodeURIComponent(id.slice(5))}/messages`);
    const reply = (r.json?.messages ?? []).find((m) => m.role === "agent" && m.at >= since - 5000);
    return { reply: reply?.text, state: r.json?.busy ? "working" : "idle", handedOut: [], approvals: [] };
  }
  const r = await board("GET", `/api/chats/${encodeURIComponent(id)}?peek`);
  const c = r.json ?? {};
  const reply = (c.messages ?? []).find((m) => m.kind === "reply" && Date.parse(m.at) >= since - 5000);
  return { reply: reply?.text, state: c.state, reason: c.reason, handedOut: c.handedOut ?? [], approvals: (c.approvals ?? []).map((a) => `${a.kind ?? "?"} ${a.state ?? "?"}`) };
}
const describe = (n) => `state ${n.state}${n.reason ? ` (${n.reason})` : ""}; handed out: ${n.handedOut.map((k) => `${k.identifier} ${k.agent} ${k.state}`).join(", ") || "nothing"}; approvals: ${n.approvals.join(", ") || "none"}`;

/** A scripted chat that must get a reply: two attempts, 12 minutes each. */
async function chatReply(label) {
  let last = "";
  for (let attempt = 1; attempt <= 2; attempt++) {
    const since = Date.now();
    const id = await newChat(`Hi Aiden, this is an automated check (${label}, attempt ${attempt}). Please reply with one short sentence saying you are here.`);
    log(`chat ${id} sent (${label}, attempt ${attempt})`);
    for (const until = since + 12 * MIN; Date.now() < until; await sleep(15_000)) {
      const n = await chatNow(id, since).catch((e) => ({ state: `unreadable: ${e.message}`, handedOut: [], approvals: [] }));
      if (n.reply) return { ok: true, note: `${id} replied` };
      last = `${id}: ${describe(n)}`;
      if (n.state === "failed") break;
    }
  }
  return { ok: false, note: `no reply: ${last}` };
}

/** Ask for a tiny app and wait for a NEW app that is deployed and healthy (50 minutes; one nudge if Aiden asks something). */
async function askForApp(what) {
  const before = new Set(((await board("GET", "/api/apps")).json?.apps ?? []).map((a) => a.name));
  const since = Date.now();
  const id = await newChat(`Please make me a tiny web app: one page that says "${what}". Keep it as small as possible, deploy it, and tell me when it is live. Use your judgment for anything else; you don't need to ask me.`);
  log(`app chat ${id} sent: ${what}`);
  let nudged = false, last = "", shown = 0;
  for (const until = since + 50 * MIN; Date.now() < until; await sleep(30_000)) {
    const apps = (await board("GET", "/api/apps")).json?.apps ?? [];
    const app = apps.find((a) => !before.has(a.name) && a.state === "healthy");
    if (app) return { ok: true, app: app.name, url: app.url, note: `${app.name} healthy${app.url ? ` at ${app.url}` : ""} via ${id}` };
    const n = await chatNow(id, since).catch((e) => ({ state: `unreadable: ${e.message}`, handedOut: [], approvals: [] }));
    const fresh = apps.filter((a) => !before.has(a.name)).map((a) => `${a.name} ${a.state}`).join(", ");
    last = `${id}: ${describe(n)}; new apps: ${fresh || "none"}`;
    if (Date.now() - shown > 5 * MIN) { log(last); shown = Date.now(); }
    if (n.state === "waiting for you" && !nudged && !id.startsWith("lane:")) {
      await board("POST", `/api/issues/${encodeURIComponent(id)}/comments`, { body: "Yes, go ahead. Use your best judgment for anything else.", brief: true });
      nudged = true;
      log(`${id} asked something: answered "go ahead" once`);
    }
  }
  return { ok: false, note: `no new healthy app within 50 minutes: ${last}` };
}

/** The app is still deployed and healthy (the platform's own probe), and its address answers when it has one. */
async function serves(name) {
  const app = ((await board("GET", "/api/apps")).json?.apps ?? []).find((a) => a.name === name);
  if (!app) return { ok: false, note: `${name} isn't in the apps list any more` };
  if (app.state !== "healthy") return { ok: false, note: `${name} is ${app.state}` };
  if (!app.url) return { ok: true, note: `${name} healthy (no address on this install)` };
  const r = await follow(app.url).catch((e) => ({ status: 0, text: e.message }));
  return r.status > 0 && r.status < 500 ? { ok: true, note: `${name} healthy; ${app.url} answered ${r.status}` } : { ok: false, note: `${name} healthy but ${app.url} answered ${r.status || r.text}` };
}

const NOT_READY = ["error", "verifying", "pending_approval"];
async function roster() {
  const r = await board("GET", "/api/agents/roster");
  want(r.status === 200 && Array.isArray(r.json?.roster), `GET /api/agents/roster: ${r.status}`);
  return r.json.roster.map((a) => ({ name: a.name, status: a.status }));
}

// ------------------------------------------------------------------------------------------------ the two phases
async function baseline() {
  try { await firstRun(); record("baseline_first_run", true); } catch (e) { record("baseline_first_run", false, e.message); throw e; }
  const agents = await roster();
  log(`agents: ${agents.map((a) => `${a.name} ${a.status}`).join(", ")}`);
  const c = await chatReply("baseline");
  record("baseline_chat", c.ok, c.note);
  // What the baseline achieves is recorded, not required: a candidate may be the release that fixes it.
  const a = c.ok ? await askForApp("hello") : { ok: false, note: "skipped: Aiden didn't reply" };
  log(`baseline hello app: ${a.note}`);
  writeJson("baseline.json", { agents: agents.filter((x) => !NOT_READY.includes(x.status)).map((x) => x.name), hello: a.ok ? a.app : null, hello_note: a.note });
  if (!c.ok) process.exitCode = 1;
}

async function smoke() {
  const base = readJson("baseline.json", null);
  want(base, "no baseline.json: the baseline scenario didn't run");
  try {
    const agents = await roster();
    const bad = agents.filter((a) => NOT_READY.includes(a.status));
    const gone = base.agents.filter((n) => !agents.some((a) => a.name === n));
    record("agents_ready", !bad.length && !gone.length && agents.length > 0, `${agents.map((a) => `${a.name} ${a.status}`).join(", ")}${gone.length ? `; missing since the baseline: ${gone.join(", ")}` : ""}`);
  } catch (e) { record("agents_ready", false, e.message); }
  const c = await chatReply("after the upgrade").catch((e) => ({ ok: false, note: e.message }));
  record("chat_reply", c.ok, c.note);
  const h = base.hello ? await serves(base.hello).catch((e) => ({ ok: false, note: e.message })) : { ok: true, note: `the baseline had no hello app (${base.hello_note})` };
  record("hello_app_serves", h.ok, h.note);
  const s = c.ok ? await askForApp("goodbye").catch((e) => ({ ok: false, note: e.message })) : { ok: false, note: "skipped: Aiden didn't reply" };
  record("second_app_deploys", s.ok, s.note);
}

const cmd = process.argv[2];
try {
  if (cmd === "baseline") await baseline();
  else if (cmd === "smoke") await smoke();
  else { console.error("usage: graduate-scenario.mjs baseline | smoke"); process.exitCode = 2; }
} catch (e) {
  console.log(`::error::${e.message}`);
  process.exitCode = 1;
}
