# Agents that run the work end to end.

> Autonomous agents that run work end to end: specialists who plan, build, ship, maintain and follow up on schedules and events, a chief of staff to route requests, and new agents built from a one-sentence description.

Specialists that plan, build, ship, maintain and follow up on their own, with the tools, data and instructions to finish the job. Need someone new? Describe them in a sentence and the Agent Architect builds them.

_Animation: the team at work: Aiden hands a task to the Researcher, the Follow-up Tracker chases a reply, the Meeting Librarian files notes, and the DevOps Engineer confirms every app is healthy_

## Specialists, each with clear instructions.

Every agent has a role, a short set of instructions you can read, the tools it is allowed to use and a model picked for the job. Start with the core team and add the rest as add-ons.

- **Aiden:** Chief of staff. Routes any request to the right agent and chases it.
- **Researcher:** Finds and checks facts across the web and your tools.
- **Agent Architect:** Designs new agents from your description and tries them out.
- **Agent Coach:** Reviews agents' work and proposes better instructions.
- **DevOps Engineer:** Deploys apps, watches their health and rolls back bad releases.
- **Platform Engineer:** Applies approved changes to your setup, with full history.
- **Follow-up Tracker:** Spots promises in Slack and email and chases them.
- **Meeting Librarian:** Keeps notes, decisions and follow-ups from your meetings.
- **Engineers:** Write code in a locked-down workspace and open changes for review.
- **UI Designer and Reviewer:** Draft layouts, then check screenshots of every change.
- **Security Watch:** Scans for known security holes and proposes fixes.
- **Red Teamer:** Attacks your own setup to find weak spots first.

## Not sure who to ask? Ask Aiden.

You can talk to any agent directly. When you would rather not choose, Aiden takes the request: it reads your messages and forwards, decides who should do the work, keeps track of it and comes back with results or a decision.

- **Delegates** each request to the right specialist, with a clear definition of done.
- **Chases** people and agents until the work lands, and tells you if something stalls.
- **Briefs you** every morning and batches the rest into a digest.
- **Relays your approvals** word for word, and never sends anything as you.

_Animation: Aiden's morning brief lists what moved overnight, what was chased and what is due; low-priority updates are held for the evening digest_

## Agents wake up when there is work.

Agents do not run in endless loops burning money. They wake on a schedule, when something happens in one of your tools, or when someone hands them a task, and they plan their own follow-ups.

### On a schedule

The morning brief at 08:00, a weekly metrics review on Mondays, a health check every hour.

### When something happens

A new email, a failed deploy, a mention in Slack or a comment on a doc wakes the right agent.

### Self-scheduled

Agents set their own reminders: "check back on Thursday if Sam has not replied".

## Describe the agent you wish you had.

Say what you need in plain words. The Agent Architect asks a question or two, then designs the agent: its instructions, the tools it may use, when it wakes and which model it runs on. It runs a trial, a grader checks the results, and once the work holds up the agent joins your team.

- **No prompt writing.** You describe the outcome; the Architect writes the instructions.
- **Trial first.** New agents run on trial with limited reach until their work is graded.
- **One tap to keep it.** You approve the new agent like any other change, and can undo it later.
- **Readable.** Every agent is a short file you can read, edit or hand to a colleague.

_Animation: you describe an agent in one sentence; the Agent Architect writes its instructions, picks its tools and schedule, runs it on trial, and the new agent joins your team_

## One company handbook every agent follows.

How your company works is written down once, in short sections, and every agent reads what applies to its job. Skills (how to write a brief, how to review a design) are shared the same way.

### Sections, not walls of text

Each section says who it applies to. Agents load what they need and look up the rest.

### Shared vocabulary

One glossary and one list of your goals, so every task links back to something you care about.

### Skills

Reusable how-tos any agent can pick up, from drafting a reply to preparing a meeting.

### Your working style

A short profile of how you like to read, decide and be asked, followed by every agent.

## Correct an agent once. It stays fixed.

When you correct an agent, the correction becomes a rule or an automatic check, so the same mistake does not come back.

### Done means checked

A grader checks the work against its definition of done before a task counts as finished.

### A coach on the team

The Agent Coach reviews runs, spots repeat mistakes and proposes better instructions.

### Memory

Agents keep short notes of what worked, checked against the source before they rely on them.

**How it stays safe**
Agents may decide, but they cannot act on their own say-so. Each agent can use only the tools you granted it, every change it wants to make passes approvals in code, and changes to an agent's own instructions are reviewed like any other change. [More on safety](https://aidenhq.ai/safety/index.md)

---

Install: `curl -fsSL https://get.aidenhq.ai | sh` on an Ubuntu or Debian server, or ask your coding agent to follow [prompt.md](https://aidenhq.ai/prompt.md). Home: [aidenhq.ai](https://aidenhq.ai/index.md). All pages: [llms.txt](https://aidenhq.ai/llms.txt).
