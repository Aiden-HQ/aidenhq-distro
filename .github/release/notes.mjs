// Release notes (README "Nightly releases"): the machine copy (the release file's `notes`, a string[] the kernel's updater lists
// and the owner's "AidenHQ is updated" message quotes) and the readable Markdown body of a GitHub release.
//   notes: Highlights first (no prefix), then `New: `, `Improved: ` and `Fixed: ` items, then one `Under the hood: ` line.
//   body:  the same items as Markdown sections, plus a compare link; every text is neutralised first.
// Model and commit-title text is untrusted data: it only ever becomes plain single-line text here.

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

/** Release notes from `{ highlights, entries: [{ category, text }], hood }`; invalid items are dropped, never repaired. */
export function assemble({ highlights = [], entries = [], hood = "" }) {
  const text = (t) => (typeof t === "string" ? clean(t, MAX - 15) : "");
  const out = highlights.map(text).filter(Boolean);
  for (const [key, label] of Object.entries(CATEGORIES)) {
    for (const e of entries) if (e?.category === key && text(e.text)) out.push(`${label}: ${text(e.text)}`);
  }
  if (text(hood)) out.push(`${HOOD}: ${text(hood)}`);
  return out;
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
export const escape = (t) => clean(t).replace(/[\\*_\[\]<>#!|~&@`]/g, (c) => `&#${c.charCodeAt(0)};`);

/** The GitHub release body: Highlights, New, Improved, Fixed, one Under the hood line, then the compare link. */
export function renderBody(notes, { lead = "", compare = "" } = {}) {
  const s = sections(notes);
  const hood = s[HOOD];
  delete s[HOOD];
  // Notes with no prefixed item (a hand-cut file, a fallback) are one plain list.
  const flat = !Object.values(s).slice(1).some((i) => i.length) && !hood.length;
  const parts = [lead.trim()].filter(Boolean);
  for (const [title, items] of Object.entries(s)) {
    if (items.length) parts.push(`## ${flat ? "What's new" : title}\n\n${items.map((i) => `- ${escape(i)}`).join("\n")}`);
  }
  if (hood.length) parts.push(`**${HOOD}:** ${hood.map(escape).join("; ")}`);
  if (compare) parts.push(`Every change: ${compare}`);
  return `${parts.join("\n\n")}\n`;
}

/** Product commit range as a link. */
export const compareLink = (repo, from, to) => (from && to ? `https://github.com/${repo}/compare/${from.slice(0, 12)}...${to.slice(0, 12)}` : "");
