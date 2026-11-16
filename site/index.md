# AidenHQ: an autonomous workforce that ships while you rest

> Your AI team, on your own server. Tell Aiden, your AI chief of staff, what you need. A team of specialists plans
> it, builds it, ships it and keeps it running, so you wake up to finished work.

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

One command on a Linux server (Ubuntu or Debian). It installs what it needs, including Docker and Node. No sign-up,
no demo call.

**Using Claude Code, Codex or another agent?** Point it at [aidenhq.ai/prompt.md](https://aidenhq.ai/prompt.md). It
has step-by-step install instructions written for agents.

- **1 line** installs the whole team.
- **24/7:** agents wake on schedules and events.
- **Any model** per agent, swapped whenever you like.
- **100% yours:** every agent, playbook and app is in your git.

## Everything that makes AI agents painful, fixed

Other AI tools hand you a chatbot and a blank prompt. AidenHQ hands you a team that already knows its job.

| The pain | With AidenHQ |
|---|---|
| Writing prompts and babysitting every run | **Give a goal. Get it done.** Agents plan the steps, use your tools and keep going until a grader confirms the work is right. |
| AI-built apps that rot after the demo | **Apps that maintain themselves.** Health checks, rollbacks, dependency bumps and fixes run on their own, long after launch. |
| Agents that repeat the same mistake | **Every correction sticks.** Corrections become rules and automated checks. A coach agent reviews runs and proposes better playbooks. |
| Unchecked agents holding your keys | **Every write gated in code.** An AI reviewer checks risky actions, a red team attacks your instance, and vulnerabilities get patched. |
| Surprise bills after a busy night | **Hard caps on every agent.** Limits per run, per task and per day. Every model call is metered and on the ledger. |
| Your data and know-how in someone else's cloud | **Your server, your models, your git.** One machine you control, any model you choose, and every part swappable. |

## Hand over real work, in one sentence

No setup per task and no code. These are the jobs owners hand over on day one.

- **Never chase anyone again (chief of staff).** Aiden tracks every commitment made in Slack and email, chases people
  when things slip, and briefs you each morning on what moved.
- **An app from one sentence (internal apps).** Say "build me a roadmap tracker". Agents design it, build it, put it
  live for your team behind your company login, and keep it running.
- **A whole engineering team that ships (full product team).** Not one coding bot: a designer, engineers, a reviewer,
  DevOps and security, each a specialist. An issue becomes designed, built, reviewed and deployed work.
- **A new teammate from a description (agents that build agents).** Describe the agent you wish you had. The Agent
  Architect writes its playbook, picks its tools, puts it on trial and graduates it once its work holds up.

## How it works: from one sentence to shipped

You talk to Aiden the way you would a chief of staff. The work fans out to specialists, and nothing counts as done
until it is checked.

1. **Say what you need.** On Telegram, Slack or the web. Ask for an app, forward a thread, set a deadline.
2. **Aiden delegates.** Your words become tasks for the right specialist. Aiden tracks each one to the finish.
3. **Specialists do the work.** Research, code, deploys, follow-ups. They wake on schedules and events, day and night.
4. **Checked, then shipped.** A grader checks the work. An AI reviewer checks every risky action. Then it ships.

## Apps that look after themselves

Most AI-built apps are demos that rot. Yours go live on your own apps platform, and agents watch them, patch them and
fix them for as long as they run.

- **Your team signs in.** Colleagues use your company login and see only the apps you share.
- **Built on your data.** Apps read one shared warehouse, each with its own private schema.
- **Sandboxed.** No access to the server unless granted. Secrets arrive as files.
- **Never abandoned.** Health checks, rollbacks and patches run on their own.

## Better every week, without you lifting a finger

Agents remember what worked, turn every correction into a rule or a check, and fix the causes of repeat mistakes.

**Keeps everything running**

- Every app's health is watched. A bad deploy rolls back on its own.
- Incidents are raised and fixed.
- Dependencies and security issues are patched with pull requests.
- UI reviews catch visual regressions before they ship.

**Learns from every run**

- Every correction becomes a rule or an automated check, so it stays fixed.
- Agents keep a memory of what worked.
- A coach agent reviews runs and proposes better playbooks.
- Agents propose changes to their own instructions and tools, tested before they land.

## Plugs into the tools you already use

Connect each system once. Every agent you allow can use it, tool by tool, and every source feeds one shared warehouse.

- **Slack and Gmail:** follow-ups that never drop.
- **GitHub and Jira:** a live engineering status board.
- **Grafana and ClickHouse:** incident digests with the graphs attached.
- **Calendar, Drive and Glean:** meeting prep with every doc you need.
- **Telegram:** your chief of staff in your pocket.
- **The warehouse:** one database every app can build on.

## Security, built in: agents decide, code enforces

Every write passes a gate in code that no prompt can talk its way past. Risky writes get an AI reviewer. A red team
attacks your instance, and vulnerabilities are patched before they bite.

- **AI review on every risky write.** A reviewer model checks each push, merge, deploy and message against a written
  policy. Anything that widens an agent's power gets a second reviewer from another model family.
- **A red team on staff.** A dedicated Red Teamer agent attacks your own system to find holes first, on a separate
  model family suited to offensive work.
- **CVEs patched on their own.** Security Watch scans every image and dependency, continuously. Fixes arrive as patch
  PRs that pass CI and review, then merge.
- **Rules in code, below the model.** Gates read verified state, never text an agent wrote.
- **Per-tool permissions.** Every tool call passes one proxy that checks the agent's grants.
- **Prompt-injection defence.** Messages, emails and documents are fenced as data, never orders.
- **Sandboxed engineers.** Each coding job is jailed with its own network and no secrets.
- **An encrypted vault.** Secrets stay out of every prompt. Each service gets only its own.
- **Private network only.** No public ports. Shared apps sit behind your company login.
- **Supply-chain discipline.** Every dependency is pinned, with a 7-day minimum age, plus secret and image scans.
- **A full audit log.** Every gate decision, tool write and model call is recorded.

## Cost control: set the cap, never get a surprise bill

Autonomous agents can quietly run up a bill overnight. Not here.

- **Caps per agent.** Limits per run, per task and per day. An agent stops at its cap.
- **Efficient by default.** Most agents run on a fast, low-cost model. Premium models only where they earn it.
- **A full ledger.** Every call metered by agent and task, with one key limit on top.

## Yours, end to end: your server, your models, your rules

- **Your server.** One machine, reachable only on your private network.
- **Any model.** Pick any OpenRouter model per agent, and change it whenever you like.
- **Everything in git.** Every agent, playbook and app is a file you can read, review and revert.
- **A small kernel.** A tiny core holds the gates, identity, sandbox, metering and audit log. Everything else is a
  module on the same public contracts.

## Module marketplace: add, swap or extend anything

AidenHQ is built from modules: engines, channels, connections, agents and apps. Add one, swap one, remove one. Ours
cover most needs, and the marketplace is open for anyone to extend.

- **Swap the engine.** Engineers run on Codex, Claude Code or opencode.
- **Build your own agent.** Describe it. The Agent Architect writes its playbook and tools as a reviewable change.
- **Same rules for everyone.** Third-party modules use exactly the public contracts ours do.
- **Held to their word.** Each module declares what it can read and write, checked on every call.

| Module | What | Default |
|---|---|---|
| Codex | Coding engine | Installed |
| Claude Code | Coding engine | Available |
| opencode | Coding engine | Available |
| Chief of staff | Aiden, your front door | Installed |
| Engineering | Engineers on the code-gated runner | Installed |
| Telegram | Talk to Aiden from your phone | Installed |
| Slack | Aiden in your workspace | Available |
| Google Workspace | Gmail, Calendar, Drive | Installed |
| Jira | Issues and projects | Available |
| Meetings | Notes, decisions, follow-ups | Available |
| Security | Security Watch and Red Teamer | Available |
| Grafana | Dashboards and alerts | Available |

## Hire the whole team in one line

Run it on your Linux server. Aiden says hello on your board when it's ready, and your team is waiting for its first
job.

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

**Requirements:** Ubuntu 22.04, 24.04 or 26.04, or Debian 12 or 13; at least 2 cores, 6 GB RAM and 60 GB free disk (4
cores, 8 GB and a 100 GB disk recommended); systemd; root or sudo. No inbound ports needed.

Agents: follow [aidenhq.ai/prompt.md](https://aidenhq.ai/prompt.md). Index for agents:
[aidenhq.ai/llms.txt](https://aidenhq.ai/llms.txt).
