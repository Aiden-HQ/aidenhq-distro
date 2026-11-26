# Shape the workspace around how you work.

> A small kernel that enforces the rules, modules for everything else, and distros: tested bundles of a kernel and a set of modules that fit how you work. Add, swap or publish your own.

Add modules, connect your tools, build your own agents and pin the panels you want. Underneath, AidenHQ is built like Linux. A slim kernel enforces the rules. Modules add the agents, channels, tools and apps. A distro bundles a kernel and a set of modules into one release, tested together, that fits how you work.

_Animation: a distro is assembled: the kernel at the base, then modules for chat, tools, agents and apps stack on top, and the whole set is sealed as one release tested together_

## Browse modules

38 modules ship with AidenHQ today, in 7 groups. Each declares up front what it can read and write. "Core" marks the modules that are always installed; the rest are added in one step.

### Chief of staff and follow-ups

| Module | What it does | Connects to | Always installed |
|---|---|---|---|
| Chief of staff | Aiden takes any request, hands it to the right agent and follows up until it is done. | Board, Telegram | Core |
| Board | Your daily view: Home with what needs you, your named teammates, tasks, apps and insight. | Tasks, Approvals, Apps, Costs | Core |
| Open loops | Tracks what others owe you and turns Slack and labelled email into your tasks. | Slack, Gmail, Calendar, Drive |  |
| Meetings | Meeting memory: transcripts and an Obsidian vault your agents can search. | Obsidian vault, Transcripts |  |
| Tasks | Every agent can read, create, delegate, comment on and close tasks as itself. | Paperclip tasks |  |
| Fast chat lane | Agents with a chat answer in seconds with a light model, and can schedule their own wake-ups. | Board chat, Telegram | Core |

### Engineering

| Module | What it does | Connects to | Always installed |
|---|---|---|---|
| Engineering | Engineers in a locked box write code, run checks and open pull requests. | Locked box, GitHub | Core |
| Codex engine | The coding engine behind Engineer jobs. Engines are modules, so another can be added. | OpenRouter, Agent computer |  |
| Code review | Reviews pull requests on the repos you list, or a whole repository on request. | GitHub, Credential-free box |  |
| Maintainer | Watches your repos, validates labelled issues, hands fixes to an engineer and sees them to a merged PR. | GitHub |  |
| Ship | Takes every pull request from opened to merged: fixes conflicts, chases failing checks and merges once review and CI pass. | GitHub |  |
| Design | A UI/UX designer drafts mockups and a reviewer checks every UI pull request with screenshots. | Design system, Screenshots |  |
| Self-hosted CI | GitHub Actions runners on your server: one fresh container per job. | GitHub Actions |  |
| Local code host | Repositories on your own server, with an atomic squash merge. No GitHub needed. | Bare repos |  |
| Platform checks | The product's own gate on every push, PR and merge. | Product repo |  |

### Work tools

| Module | What it does | Connects to | Always installed |
|---|---|---|---|
| GitHub | Agents read and write GitHub as you, labelled as AidenHQ. | Issues, Pull requests, Reviews, Checks, Projects |  |
| Jira and Confluence | Atlassian's remote MCP server, signed in as you with the scopes you pick. | Jira, Confluence |  |
| Glean | Your organisation's Glean: search, documents, people and meetings. | Glean search, Documents, People, Meetings |  |
| Google Workspace | Gmail, Calendar, Drive and Docs, read by your agents. | Gmail, Calendar, Drive, Docs |  |
| Primer | Read documents, and publish them when asked. | Primer documents |  |

### Apps and data

| Module | What it does | Connects to | Always installed |
|---|---|---|---|
| HubSpot | CRM through HubSpot's remote MCP server, with contacts and deals in the warehouse. | HubSpot CRM, Warehouse |  |
| Grafana | Grafana for Engineer jobs, over a loopback MCP. | Grafana dashboards |  |
| ClickHouse | ClickHouse Cloud's MCP server: services, schemas and read-only SELECT queries. | ClickHouse Cloud |  |
| Apps platform | Apps your agents build, deploy, run and keep healthy, from one starter and design system. | Deploy, Run, Rollback, App API | Core |
| Warehouse | One shared Postgres every source ingests into, ready for apps and agents to query. | Postgres | Core |

### Channels

| Module | What it does | Connects to | Always installed |
|---|---|---|---|
| Telegram | Chat with Aiden and approve from your phone, with typed messages or voice notes. | Telegram | Core |
| Slack | Your agents in Slack: read as you, or run a bot with a live listener. | Slack search, Channels, Drafts, Socket Mode |  |
| Voice notes | Talk to Aiden with voice notes on Telegram, transcribed on your server. | Telegram, Local speech-to-text |  |
| Owner channel | The one way anything reaches you: it lands once, in the right place. | Board, Telegram, Slack |  |

### Agents, memory and quality

| Module | What it does | Connects to | Always installed |
|---|---|---|---|
| Agent builder | Describe an agent and the Agent Architect designs, builds and trials it. | Primer, Engineer | Core |
| Agent memory | Agents keep lessons and facts that carry into their next run. | Agent notes |  |
| Advisor and fan-out | A stronger model for hard calls, and cheap workers for many items at once. | Model gateway |  |
| OpenRouter models | OpenRouter as the model provider: any model it lists works by id. | OpenRouter |  |
| AI reviewer | A second AI checks risky actions and blocks only explicit malice. | Model gateway | Core |
| Graded done | A task is done only when its rubric is met and the grader agrees. | Board | Core |
| Dispatch | Turns wakes into jobs for every agent and posts each outcome once. | Board |  |

### Ops and security

| Module | What it does | Connects to | Always installed |
|---|---|---|---|
| Fleet steward | Unsticks stuck work, reviews outcomes and keeps agent notes tidy. | Board, Fleet |  |
| Monitoring | Host and fleet monitoring with alerts that open tasks for the Fleet Steward. | Prometheus, Grafana, Alertmanager, cAdvisor |  |
| Security | Security Watch scans for CVEs, and the Red Teamer attacks your own apps and agents. | CVE feeds, Your apps |  |

## The part that keeps everyone honest.

The kernel is lean by design. It holds what must be true for every agent and every module, whoever wrote them, and leaves everything else to modules.

### Model gateway

Every AI call goes through one door that meters it, applies spend limits and records it.

### Tool checkpoint

Every tool call is checked against the agent's grants, and outside text is fenced as information.

### Approvals

Every write becomes a record with its exact request, given its level by rules in code, and decided by the right party.

### Identity and the locked box

Sign-in for you and your admins, a sealed workspace for coding jobs, and a log of everything.

## Add a module in one step, and see exactly what it gets.

Add a module from the board or with one command. Before anything changes you see what it will be able to read and write, which agents and schedules it brings and which settings it needs, on a single approval card.

- **Held to its word.** What a module declares is checked on every call, from install onward.
- **Pinned and checked.** Every module is pinned to an exact version and passes the same supply-chain checks as ours.
- **Easy to remove.** Taking a module out is the same single step, and history lets you undo it.

_Animation: one command adds the Jira module; AidenHQ shows exactly what it will be able to read and write, sends you an approval card, and Jira goes live for the agents you chose_

## Start from a workspace that already fits you.

A distro is a tested release: one kernel plus a chosen set of modules, pinned to exact versions and run through the same test suites together before release. Pick the one closest to how you work, then make it yours.

### Founder office

Aiden, follow-ups across Slack and email, meeting notes, a morning brief, and internal apps on demand.

Chief of staff Slack Google Meetings

### Engineering team

Engineers, reviewers, UI design and review, app deploys and security, wired to GitHub and Jira.

Engineering GitHub Jira Security

### Personal life admin

Your personal inbox and calendar, bills and renewals chased, and a weekly plan on Telegram.

Telegram Google Follow-ups

### Tested together

Every release pins a kernel and each module to an exact version, so what you install is exactly what passed the tests. Release 2026.11 is the current one.

### Swap or add anything

Start from a distro, then add Slack, swap the coding engine or trim it down to what you use. Your choices live in your own settings, with history.

### Publish your own

Built a setup that works for your team or your industry? Publish it as a distro so others can install it in one command.

## Anyone can build and publish modules.

The marketplace is open. Publish a module or a whole distro from your own repository, under your own licence, commercial included. Third-party modules follow exactly the rules ours do, and the kernel enforces them for everyone.

### Same rules for everyone

No private shortcuts: official modules use the same public contracts as yours.

### Licences that fit

The kernel is AGPL-3.0. The official modules, app starter and design system are MIT. Your modules can carry any licence you choose.

### Grow from your own setup

Write a module inside your own workspace first, then promote it to the marketplace when it is ready.

---

Install: `curl -fsSL https://get.aidenhq.ai | sh` on an Ubuntu or Debian server, or ask your coding agent to follow [prompt.md](https://aidenhq.ai/prompt.md). Home: [aidenhq.ai](https://aidenhq.ai/index.md). All pages: [llms.txt](https://aidenhq.ai/llms.txt).
