# Shape the workspace around how you work.

> A small kernel that enforces the rules, modules for everything else, and distros: tested bundles of a kernel and a set of modules that fit how you work. Add, swap or publish your own.

Add modules, connect your tools, build your own agents and pin the panels you want. Underneath, AidenHQ is built like Linux. A slim kernel enforces the rules. Modules add the agents, channels, tools and apps. A distro bundles a kernel and a set of modules into one release, tested together, that fits how you work.

_Animation: a distro is assembled: the kernel at the base, then modules for chat, tools, agents and apps stack on top, and the whole set is sealed as one release tested together_

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

## Everything else is a module.

A module is a folder that can add agents, chat channels, tool connections, apps or coding engines. Ours use exactly the same public rules as anyone else's, and each declares up front what it can read and write.

| Module | What it adds | Included |
|---|---|---|
| Chief of staff | Aiden, who routes any request, and the morning brief | Core |
| Board | Your daily view: tasks, chats, approvals, apps, costs and panels | Core |
| Agent builder and coach | The Agent Architect and the Agent Coach | Core |
| Engineering | Engineers in the locked box, with code checks and reviews | Core |
| Apps platform and warehouse | Apps your agents build and run, on one shared database | Core |
| AI reviewer and grader | The second AI that checks risky actions, and the grader that checks finished work | Core |
| Telegram | Chat with your agents and approve from your phone | Core |
| Slack | Your agents in your Slack channels | Add-on |
| Google Workspace | Gmail, Calendar and Drive | Add-on |
| Follow-ups and meetings | The Follow-up Tracker and the Meeting Librarian | Add-on |
| Jira, Glean, Grafana, ClickHouse | Connections to your work and data tools | Add-on |
| Security | Security Watch and the Red Teamer | Add-on |
| Coding engines | Codex by default; Claude Code or opencode instead | Swap |

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

Engineers, reviewers, UI design and review, DevOps and security, wired to GitHub and Jira.

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
