// Release notes (README "Nightly releases"). A release file carries two copies:
//   changelog: the readable notes (an intro, highlights with a short write-up each, then New, Improved and Fixed items and one
//              Under the hood paragraph), written by changelog.mjs and rendered as the GitHub release body;
//   notes:     the machine copy, a string[] the kernel's updater lists and the owner's "AidenHQ is updated" message quotes
//              (highlight titles first, then `New: `, `Improved: `, `Fixed: ` items, then one `Under the hood: ` line).
// A file without a changelog (the commit-title fallback, a hand cut) renders its notes as sections.
// Model and commit-title text is untrusted data: it only ever becomes plain single-line text here, escaped when rendered.

export const CATEGORIES = { new: "New", improved: "Improved", fixed: "Fixed" };
const HOOD = "Under the hood";
const MAX = 300; // the updater truncates each note to this

/** One line of plain text: no control or format characters, no links, URLs, HTML or code spans; bounded. */
export const clean = (v, n = MAX) => String(v ?? "")
  .replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]+/gu, " ")
  .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
  .replace(/\b(?:(?:https?|ftp):\/\/|www\.)\S+/gi, "")
  .replace(/[<>`]/g, "")
  .replace(/\s+/g, " ").trim().slice(0, n);

// Text that could pass for graduation's line-start marks (`graduation: failed`, `graduation: incomplete`) is dropped.
const text = (v, n) => { const t = typeof v === "string" ? clean(v, n) : ""; return /^graduation\b/i.test(t) ? "" : t; };

/** The model's answer as a changelog: every field checked and cleaned; invalid items are dropped, never repaired. */
export function tidy(raw) {
  const o = raw && typeof raw === "object" ? raw : {};
  const items = (list, body, n, limit) => (Array.isArray(list) ? list : [])
    .map((i) => ({ title: text(i?.title, 80), [body]: text(i?.[body], n) }))
    .filter((i) => i.title && i[body]).slice(0, limit);
  const c = { summary: text(o.summary, 700), highlights: items(o.highlights, "body", 600, 4) };
  for (const k of Object.keys(CATEGORIES)) c[k] = items(o[k], "text", 280, 10);
  c.under_the_hood = text(o.under_the_hood, 500);
  return c;
}

/** The machine copy of a changelog (the updater reads the first 20; the Under the hood line keeps the last slot). */
export function assemble(c) {
  const out = c.highlights.map((h) => h.title);
  for (const [k, label] of Object.entries(CATEGORIES)) for (const i of c[k]) out.push(clean(`${label}: ${i.title}. ${i.text}`));
  const last = c.under_the_hood ? [clean(`${HOOD}: ${c.under_the_hood}`)] : [];
  return [...out.slice(0, 20 - last.length), ...last];
}

/** Notes back into sections. An item with no known prefix is a highlight (or, with no prefixed items at all, a plain change). */
export function sections(notes) {
  const s = { Highlights: [], ...Object.fromEntries(Object.values(CATEGORIES).map((l) => [l, []])), [HOOD]: [] };
  for (const n of notes.map((x) => clean(x)).filter(Boolean)) {
    const m = /^(New|Improved|Fixed|Under the hood): (.+)$/.exec(n);
    (m ? s[m[1]] : s.Highlights).push(m ? m[2] : n);
  }
  return s;
}

/** Markdown-safe text: every character that could start a link, mention, reference, HTML or emphasis becomes an entity. */
export const escape = (t) => clean(t, 1000).replace(/[\\*_\[\]<>#!|~&@`]/g, (c) => `&#${c.charCodeAt(0)};`);

/** A changelog with anything to say: a highlight, an item or the Under the hood paragraph. */
export const hasContent = (c) => Boolean(c.highlights.length || Object.keys(CATEGORIES).some((k) => c[k].length) || c.under_the_hood);

/** Escaped text that starts its own block: a leading list or rule marker stays text too. */
const para = (t) => escape(t).replace(/^(\d+)([.)])/, "$1\\$2").replace(/^[-+=]/, (c) => `&#${c.charCodeAt(0)};`);

/** The changelog as Markdown: the intro, a heading per highlight, then the lists and Under the hood. */
function renderChangelog(c) {
  const parts = [c.summary && para(c.summary)];
  if (c.highlights.length) parts.push("## Highlights", ...c.highlights.map((h) => `### ${escape(h.title)}\n\n${para(h.body)}`));
  for (const [k, label] of Object.entries(CATEGORIES)) {
    if (c[k].length) parts.push(`## ${label}\n\n${c[k].map((i) => `- **${escape(i.title)}:** ${escape(i.text)}`).join("\n")}`);
  }
  if (c.under_the_hood) parts.push(`## ${HOOD}\n\n${para(c.under_the_hood)}`);
  return parts.filter(Boolean);
}

/** The notes-only body: Highlights, New, Improved, Fixed, one Under the hood line (or one plain list for unprefixed notes). */
function renderNotes(notes) {
  const s = sections(notes);
  const hood = s[HOOD];
  delete s[HOOD];
  const flat = !Object.values(s).slice(1).some((i) => i.length) && !hood.length;
  const parts = [];
  for (const [title, items] of Object.entries(s)) {
    if (items.length) parts.push(`## ${flat ? "What's new" : title}\n\n${items.map((i) => `- ${escape(i)}`).join("\n")}`);
  }
  if (hood.length) parts.push(`**${HOOD}:** ${hood.map(escape).join("; ")}`);
  return parts;
}

/** The GitHub release body for a release file: its changelog (or its notes), then the lead and the compare link. */
export function renderBody(file, { lead = "", compare = "" } = {}) {
  const c = file?.changelog ? tidy(file.changelog) : null;
  const parts = c && hasContent(c) ? renderChangelog(c) : renderNotes(file?.notes ?? []);
  if (lead.trim()) parts.push(lead.trim());
  if (compare) parts.push(`**Every change:** ${compare}`);
  return `${parts.join("\n\n")}\n`;
}

/** Product commit range as a link. */
export const compareLink = (repo, from, to) => (from && to ? `https://github.com/${repo}/compare/${from.slice(0, 12)}...${to.slice(0, 12)}` : "");
