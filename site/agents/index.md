# Agents that run the work end to end.

> Autonomous agents that run work end to end: specialists who plan, build, ship, maintain and follow up on schedules and events, a chief of staff to route requests, and new agents built from a one-sentence description.

An AI workforce of specialists that plan, build, ship, maintain and follow up on their own, around the clock, with the tools, data and instructions to finish the job. Need someone new? Describe them in a sentence and the Agent Architect builds them.

_Animation: the team at work: Aiden hands a task to the Researcher, the Follow-up Tracker chases a reply, the Meeting Librarian files notes, and the DevOps Engineer confirms every app is healthy_

## Named teammates, each with clear instructions.

Every capability has one teammate you talk to: a face, a name and a role, a short set of instructions you can read, the tools it is allowed to use and a model picked for the job. Start with one and add the rest one at a time.

- **Aiden · Chief of staff:** Triages your inbox, routes any request to the right teammate and chases it.
- **Tess · Follow-up chaser:** Spots what people owe you in Slack and email and drafts the nudges.
- **Nora · Meeting notes:** Keeps notes, decisions and actions from your meetings.
- **Rhea · Researcher:** Finds and checks facts across the web and your tools.
- **Max · PR reviewer:** Reviews every pull request with several AI models.
- **Sam · Release manager:** Takes pull requests from opened to merged.
- **Mia · Repo maintainer:** Turns the issues you label into merged fixes.
- **Iris · App builder:** Builds the apps you ask for, ships them and keeps them healthy.
- **Archie · Agent Architect:** Hires for you: finds the right teammate or builds a new one.
- **Vik · Security:** Hunts vulnerabilities, attacks your own setup and files the fixes.
- **The staff behind them:** Engineers, UI Designer and Reviewer, Red Teamer, Intake and the Fleet Steward work behind your teammates.
- **Names are yours:** Rename any teammate. Their faces show who is working and who needs you.

## Agents that work as a team, not in silos.

Every request becomes coordinated teamwork. Aiden, the chief of staff, routes it to the right specialist. Specialists delegate to each other, hand off with full context, call in reviewers and pass finished work to Iris, the app builder, to ship. You see every handoff in the open, and can step into any of them.

- **Routing:** Aiden reads your messages and forwards and picks who does what.
- **Agent-to-agent handoffs** carry the goal, the context and a definition of done.
- **Peer review:** agents check each other's work before anything ships.
- **Fan-out:** big jobs split into parallel tasks that come back together.

_Animation: one request moves through a team of agents: Aiden routes it to the Researcher, the Researcher hands findings to an Engineer, the UI Reviewer sends back two fixes, the Engineer resolves them, and DevOps ships it live_

## Always on, and wide awake when work arrives.

Agents run in the background on a heartbeat. They wake on a schedule, the moment something happens in your tools, or when another agent hands them a task, and they book their own follow-ups.

### On a schedule

The morning brief at 08:00, a weekly metrics review on Mondays, a health check every hour.

### On events

A new email, a failed deploy, a Slack mention or a comment on a doc wakes the right agent instantly.

### Self-scheduled

Agents set their own reminders: "check back on Thursday if Dana has not replied".

## Describe the agent you wish you had.

Open Team › Hire and say who you need in plain words. Archie, the Agent Architect, looks in your team and your marketplaces first: often a teammate you have can take it on, or one is ready to install. Only when nothing fits does he design a new one: its instructions, the tools it may use, when it wakes and which model it runs on. It runs a trial, a grader checks the results, you name it, and once the work holds up it joins your team.

- **No prompt writing.** You describe the outcome; Archie writes the instructions.
- **Proven on trial.** New agents earn their full reach once their work is graded.
- **Tools on demand.** When an agent needs a tool that does not exist, the team builds it as an MCP connection.
- **One tap to keep it.** You approve the new agent like any other change, and can undo it later.
- **Readable.** Every agent is a short file you can read, edit or hand to a colleague.

_Animation: you describe an agent in one sentence; the Agent Architect writes its instructions, picks its tools and schedule, runs it on trial, and the new agent joins your team_

## One company handbook every agent follows.

Each agent gets exactly the context its job needs. How your company works is written once, in short sections, and every agent loads what applies to it. Skills, from writing a brief to reviewing a design, are shared the same way.

### Sectioned and targeted

Each section says who it applies to. Agents load what they need and look up the rest on demand.

### Shared vocabulary

One glossary and one list of your goals, so every task links back to something you care about.

### Skills

Reusable how-tos any agent can pick up, from drafting a reply to preparing a meeting.

### Your working style

A short profile of how you like to read, decide and be asked, followed by every agent.

## Agents that remember, and get better every week.

Agents keep long-term memory of people, decisions and your preferences, and carry it into every task. Each correction you make becomes a rule and an eval. The Agent Coach studies how the team works, proposes sharper handbooks and skills, and prunes what no longer helps. Evals gate every change, so the team only ever levels up.

- **Long-term memory** of people, projects, decisions and preferences.
- **Learn once:** corrections turn into rules and automatic checks.
- **A coach on the team** that refines and prunes the playbook.
- **Evals gate every change** to an agent's instructions.
- **Done means graded** against a clear definition of done.

_Animation: you correct an agent once; it saves the preference to long-term memory, the Agent Coach proposes a handbook change, the evals pass, and every agent follows the new rule_

**Autonomy with guardrails**
Agents make their own decisions, and deterministic guardrails in code check every action they take. Each agent works with exactly the tools you grant it, every change passes approvals, and changes to an agent's own instructions are reviewed like any other change. [More on safety](https://aidenhq.ai/safety/index.md)

---

Install: `curl -fsSL https://get.aidenhq.ai | sh` on an Ubuntu or Debian server, or ask your coding agent to follow [prompt.md](https://aidenhq.ai/prompt.md). Home: [aidenhq.ai](https://aidenhq.ai/index.md). All pages: [llms.txt](https://aidenhq.ai/llms.txt).
