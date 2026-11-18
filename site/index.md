# AidenHQ: the workspace that runs itself

> The autonomous agentic workspace: AI agents plan, build, ship and follow up around the clock, and you drop in to shape the work whenever you like. On a server you own.

Agents plan, build, ship, maintain and follow up on their own, with the tools, data and instructions they need. You
join in however you like: comment on a shared doc, chat with any agent, give one a Slack channel, approve with a tap.
Self-hosted and open source. Install it with one command on a fresh Ubuntu or Debian server (or a Mac):

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

**Using Claude Code, Codex or another coding agent?** Paste this into it:

```text
Set up AidenHQ on my server by following https://aidenhq.ai/prompt.md
```

## What sets it apart

- **Never off the clock: work that moves while you sleep.** They plan, build, ship, maintain and follow up on
  schedules and events, day and night, without being prompted, and every piece of work is graded against a clear
  definition of done. [Agents](https://aidenhq.ai/agents/index.md) · [Apps](https://aidenhq.ai/apps/index.md)
- **Side by side: shape the work without taking it over.** Shared pages and whiteboards with comments that
  wake agents, chat with any agent (or ask Aiden, the chief of staff), agents in your Slack channels, approvals from
  your phone. [Workspace](https://aidenhq.ai/workspace/index.md) · [Approvals](https://aidenhq.ai/safety/index.md)
- **Made to measure: a workspace that fits you.** Start from a distro, add modules, connect any tool,
  build your own agents, pin board panels, and keep a working-style profile every agent follows.
  [Modules and distros](https://aidenhq.ai/modules/index.md) · [Integrations](https://aidenhq.ai/integrations/index.md)

Also: sovereign AI on your own server, deterministic guardrails on every action, open source, any model (frontier or
open-weight), and budgets per agent, task and day.

Built for one person and their agents. Invite teammates whenever you like: they join the same docs, channels and
approvals, and work with the same agents.

## An AI workforce that runs as a team

Not one assistant: a multi-agent team that orchestrates itself. Aiden, the chief of staff, routes each request to the
right specialist; specialists delegate, hand off with full context, review each other's work and pass finished work to
DevOps to ship. Agents keep long-term memory of people, decisions and your preferences. Every correction becomes a rule
and an eval, the Agent Coach refines and prunes the shared handbook, and evals gate every change, so the team gets
better every week. Agents also design new agents and build the tools they need.

## A day in the workspace

Most of the day the agents work on their own. When you want to shape something, you drop in where the work lives.

- **09:30, shared docs: comment, and an agent picks it up.** Mention an agent in a comment on a doc or whiteboard. It
  wakes, makes the change while you watch, and answers in the thread.
- **11:00, apps: an app from one sentence.** Ask for a tracker, a dashboard or a form. You pick a layout, agents
  build it, a second AI checks it, and it goes live for your team. [Apps](https://aidenhq.ai/apps/index.md)
- **14:00, a new agent from a description.** The Agent Architect writes its instructions, picks its tools, tries it
  out and adds it to the workspace once its work holds up.
- **02:00, apps that fix themselves.** When something breaks, the DevOps Engineer rolls it back, an Engineer fixes
  the cause, and the fix ships after a second AI checks it.

## Full autonomy, with you in the loop where it counts

Agents act on their own, and deterministic guardrails check every action that changes something: a message, a deploy,
a merge, a settings change. For the ones that matter, you see the exact request and approve with one tap, from your
phone.

1. **Runs by itself:** safe, reversible steps, like updating a board or drafting a reply.
2. **A second AI checks it:** merges, deploys and messages are reviewed by a different AI model first.
3. **You decide:** anything that gives an agent more power, spends more or speaks for you.

## Plugged into your whole stack, through MCP

Slack, Telegram, Gmail, Calendar, Drive, Jira, GitHub, Glean, Grafana, ClickHouse, OpenRouter and a shared
warehouse. Connect each once with your own accounts; every agent you grant can use it, tool by tool, and every source
feeds one shared warehouse for context. [Integrations](https://aidenhq.ai/integrations/index.md)

## Yours, and open

- **Your server, your AI:** sovereign by default, on one machine you control and your private network.
- **Open source:** the kernel is AGPL-3.0-only; the official modules, the app starter and the design system are MIT.
- **Any model, open-weight included:** pick the best model for each agent and switch whenever you like.
- **Everything as code:** agents, handbooks and apps live in your own repository with full history.
- **Budgets you control:** per agent, per task and per day, with every cost on the record.
- **Distros that fit you:** a lean kernel, modules on top, and tested bundles such as a founder's office or an
  engineering team. [Modules and distros](https://aidenhq.ai/modules/index.md)

## Questions

### What is AidenHQ?

AidenHQ is an open-source, self-hosted workspace where a team of AI agents runs work end to end: it plans, builds and ships, follows up with people, and maintains the internal apps it builds. You talk to Aiden, the chief of staff, on the web, Telegram or Slack. Aiden hands work to specialist agents and brings you only the decisions.

### How do I install it?

Paste one line into Claude Code, Codex or another coding assistant: “Set up AidenHQ on my server by following https://aidenhq.ai/prompt.md”. Or run `curl -fsSL https://get.aidenhq.ai | sh` on the server yourself. The install ends with a one-time setup link: open it, create your password and authenticator, and add your model key. [Get started](https://aidenhq.ai/start/index.md)

### What do I need?

A Linux server with Ubuntu 22.04, 24.04 or 26.04, or Debian 12 or 13: at least 2 cores, 6 GB of memory and 60 GB of disk (4 cores, 8 GB and 100 GB recommended), reachable over SSH with a key. A Mac with macOS 13 or later, 12 GB of memory and 60 GB free also works. You also need an OpenRouter key for the AI models. Telegram, Slack and Google are optional. [Install guide](https://aidenhq.ai/install/index.md)

### What does it cost to run?

AidenHQ itself is free and open source. You pay for your own server and for model usage, which OpenRouter bills to your own key. Each agent has spend caps per run, per task and per day, you can put a monthly limit on the key itself, and the Costs page shows where every cent goes. [Spend limits](https://aidenhq.ai/safety/index.md#costs)

### Where does my data live?

On the server you run it on. The workspace has no open ports: you reach it over an SSH tunnel or your private network. Every agent, instruction and app lives in your own git repository, so every change is reviewable and can be rolled back. [Private by design](https://aidenhq.ai/safety/index.md#private)

### Is it open source?

Yes. The kernel is AGPL-3.0-only. The official modules, the app starter and the design system are MIT, so the apps your agents build carry no AGPL obligations. [Source on GitHub](https://github.com/Aiden-HQ/AidenHQ)

## Get started

Requirements, the three ways to install and what happens next: [Install guide](https://aidenhq.ai/install/index.md).
Index for agents: [llms.txt](https://aidenhq.ai/llms.txt).
