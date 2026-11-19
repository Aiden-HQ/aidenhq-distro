// The owner's side of graduation's test instance (.github/workflows/graduate.yml, test job): what a new owner does, over
// plain HTTP on the runner's loopback, as the product's own unattended-install test does (no browser).
//   node graduate-scenario.mjs baseline   first run (account, authenticator, model key, welcome skipped) and a chat with
//                                         Aiden, while the hello app (graduate-instance.sh fixture: the app starter, through
//                                         the apps platform's host path, no model) deploys beside them; what the baseline
//                                         achieved goes to baseline.json
//   node graduate-scenario.mjs smoke      after the upgrade, side by side and each within its bound: the release and its
//                                         generation, every agent ready, a fresh reply, the hello app still serves,
//                                         verify-security.sh (graduate-checks.mjs runParallel)
// State lives in $GRAD_DIR (root of the run's scratch, 0700): the account, the authenticator key and the cookies, never printed.
// The model key comes from GRADUATE_OPENROUTER_KEY, for the first run's model step when it asks. Model-dependent steps
// retry within fixed bounds; nothing waits unbounded.
import { createHmac, randomBytes } from "node:crypto";
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { child, runParallel, writeCheck, writeTiming } from "./graduate-checks.mjs";

const DIR = process.env.GRAD_DIR;
if (!DIR) throw new Error("GRAD_DIR is not set");
const HERE = dirname(fileURLToPath(import.meta.url));
const INSTANCE_SH = join(HERE, "graduate-instance.sh");
const BOARD = "http://127.0.0.1:3121";
const MIN = 60_000;
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
const log = (s) => console.log(`${new Date().toISOString().slice(11, 19)} ${s}`);
const readJson = (f, d) => (existsSync(join(DIR, f)) ? JSON.parse(readFileSync(join(DIR, f), "utf8")) : d);
const writeJson = (f, v) => writeFileSync(join(DIR, f), `${JSON.stringify(v, null, 2)}\n`, { mode: 0o600 });

// ------------------------------------------------------------------------------------------------ checks
/** One check's outcome, in its own file (graduate-checks.mjs). */
const record = (name, ok, note) => writeCheck(DIR, name, ok === true, note);

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
  if (r.status === 401) { await signInOnce(); return req(method, BOARD + path, method === "GET" ? {} : { json: json ?? {} }); }
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
/** One sign-in at a time: checks running side by side share it (an authenticator code is taken once). */
let signing;
const signInOnce = () => (signing ??= signIn().finally(() => { signing = undefined; }));
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

/** A scripted chat that must get a reply: two attempts, 10 minutes each. */
async function chatReply(label) {
  let last = "";
  for (let attempt = 1; attempt <= 2; attempt++) {
    const since = Date.now();
    const id = await newChat(`Hi Aiden, this is an automated check (${label}, attempt ${attempt}). Please reply with one short sentence saying you are here.`);
    log(`chat ${id} sent (${label}, attempt ${attempt})`);
    for (const until = since + 10 * MIN; Date.now() < until; await sleep(5000)) {
      const n = await chatNow(id, since).catch((e) => ({ state: `unreadable: ${e.message}`, handedOut: [], approvals: [] }));
      if (n.reply) return { ok: true, note: `${id} replied` };
      last = `${id}: ${describe(n)}`;
      if (n.state === "failed") break;
    }
  }
  return { ok: false, note: `no reply: ${last}` };
}

/** The app is still deployed and healthy (the platform's own probe), and its address answers when it has one. */
async function servesNow(name) {
  const app = ((await board("GET", "/api/apps")).json?.apps ?? []).find((a) => a.name === name);
  if (!app) return { ok: false, note: `${name} isn't in the apps list any more` };
  if (app.state !== "healthy") return { ok: false, note: `${name} is ${app.state}` };
  if (!app.url) return { ok: true, note: `${name} healthy (no address on this install)` };
  const r = await follow(app.url).catch((e) => ({ status: 0, text: e.message }));
  return r.status > 0 && r.status < 500 ? { ok: true, note: `${name} healthy; ${app.url} answered ${r.status}` } : { ok: false, note: `${name} healthy but ${app.url} answered ${r.status || r.text}` };
}
/** servesNow, asked again for up to `minutes` (after a restart the platform's first health pass may not have run yet). */
async function serves(name, minutes = 3) {
  let r;
  for (const until = Date.now() + minutes * MIN; ; await sleep(5000)) {
    r = await servesNow(name).catch((e) => ({ ok: false, note: e.message }));
    if (r.ok || Date.now() >= until) return r;
  }
}

const NOT_READY = ["error", "verifying", "pending_approval"];
async function roster() {
  const r = await board("GET", "/api/agents/roster");
  want(r.status === 200 && Array.isArray(r.json?.roster), `GET /api/agents/roster: ${r.status}`);
  return r.json.roster.map((a) => ({ name: a.name, status: a.status }));
}

// ------------------------------------------------------------------------------------------------ the two phases
/** A child process's own outcome (graduate-instance.sh fixture): it ends within `ms`, else it is killed. */
const within = (ms, run) => new Promise((ok) => {
  const ac = new AbortController(), t = setTimeout(() => ac.abort(), ms);
  run(ac.signal).then(() => { clearTimeout(t); ok(!ac.signal.aborted); });
});

async function baseline() {
  const t0 = Date.now();
  try { await firstRun(); record("baseline_first_run", true); } catch (e) { record("baseline_first_run", false, e.message); throw e; }
  // The hello app deploys beside the chat: it needs no model, only the platform.
  const fixture = within(20 * MIN, child("bash", [INSTANCE_SH, "fixture"])).then((ended) => ({ ...readJson("fixture.json", { ok: false, note: "no fixture.json" }), ended }));
  const agents = await roster();
  log(`agents: ${agents.map((a) => `${a.name} ${a.status}`).join(", ")}`);
  const c = await chatReply("baseline");
  record("baseline_chat", c.ok, c.note);
  const f = await fixture;
  // What the baseline achieves is recorded, not required: a candidate may be the release that fixes it. Judged by the same
  // probe as the smoke check after the upgrade, so a fault in this test shows here, before the candidate is reached.
  // Whenever the deploy ended, the platform's own state decides (the deploy's answer is only its note).
  const app = f.app ?? "grad-hello";
  const a = f.ended ? await serves(app) : { ok: false, note: "the fixture deploy didn't end within 20 minutes" };
  if (!a.ok) a.note = `${a.note}; deploy: ${f.note}`;
  log(`baseline hello app: ${a.note}`);
  if (!a.ok) {
    // Not required (the candidate may fix it), but loud: without it the hello check after the upgrade has nothing to test.
    console.log(`::warning::the baseline has no hello app, so hello_app_serves can't test the upgrade: ${a.note.slice(0, 300)}`);
    if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `**No hello app on the baseline**: hello_app_serves passes without testing it. ${a.note.slice(0, 300)}\n`);
  }
  writeJson("baseline.json", { agents: agents.filter((x) => !NOT_READY.includes(x.status)).map((x) => x.name), hello: a.ok ? app : null, hello_note: a.note });
  writeTiming(DIR, "scenario", (Date.now() - t0) / 1000);
  if (!c.ok) process.exitCode = 1;
}

async function smoke() {
  const t0 = Date.now();
  const base = readJson("baseline.json", null);
  want(base, "no baseline.json: the baseline scenario didn't run");
  // One sign-in for the checks below (the board's session may be gone after the upgrade).
  await board("GET", "/api/welcome").catch((e) => log(`signing in before the checks: ${e.message}`));
  const sh = (cmd) => child("bash", [INSTANCE_SH, cmd]);
  await runParallel(DIR, [
    { names: ["running_release", "generation_good"], ms: 5 * MIN, run: sh("release-check") },
    { names: ["verify_security"], ms: 10 * MIN, run: sh("verify-security") },
    { names: ["agents_ready"], ms: 5 * MIN, run: async () => {
      const agents = await roster();
      const bad = agents.filter((a) => NOT_READY.includes(a.status));
      const gone = base.agents.filter((n) => !agents.some((a) => a.name === n));
      return [{ name: "agents_ready", ok: !bad.length && !gone.length && agents.length > 0, note: `${agents.map((a) => `${a.name} ${a.status}`).join(", ")}${gone.length ? `; missing since the baseline: ${gone.join(", ")}` : ""}` }];
    } },
    { names: ["chat_reply"], ms: 22 * MIN, run: async () => [{ name: "chat_reply", ...(await chatReply("after the upgrade")) }] },
    { names: ["hello_app_serves"], ms: 5 * MIN, run: async () => [{ name: "hello_app_serves", ...(base.hello ? await serves(base.hello) : { ok: true, note: `the baseline had no hello app (${base.hello_note})` }) }] },
  ]);
  writeTiming(DIR, "smoke", (Date.now() - t0) / 1000);
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
// A check cut off at its bound may still be waiting on the network: the outcomes are written, so end here.
process.exit();
