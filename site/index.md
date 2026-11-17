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
  schedules and events, day and night, without being prompted, and work counts as done only when a grader has checked
  it. [Agents](https://aidenhq.ai/agents/index.md) · [Apps](https://aidenhq.ai/apps/index.md)
- **Side by side: shape the work without taking it over.** Shared pages and whiteboards with comments that
  wake agents, chat with any agent (or ask Aiden, the chief of staff), agents in your Slack channels, approvals from
  your phone. [Workspace](https://aidenhq.ai/workspace/index.md) · [Approvals](https://aidenhq.ai/safety/index.md)
- **Made to measure: a workspace that fits you.** Start from a distro, add modules, connect any tool,
  build your own agents, pin board panels, and keep a working-style profile every agent follows.
  [Modules and distros](https://aidenhq.ai/modules/index.md) · [Integrations](https://aidenhq.ai/integrations/index.md)

Also: it runs on your own server, every action that changes something is checked in code, it is open source, and
spend is capped per agent, task and day.

Built for one person and their agents. Invite teammates whenever you like: they join the same docs, channels and
approvals, and work with the same agents.

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

## You decide, agents act

Agents act on their own, but every action that changes something (a message, a deploy, a merge, a settings change)
is checked by the system, not by the agent. You see the exact request and decide with one tap, from your phone.

1. **Runs by itself:** safe, reversible steps, like updating a board or drafting a reply.
2. **A second AI checks it:** merges, deploys and messages are reviewed by a different AI model first.
3. **You decide:** anything that gives an agent more power, spends more or speaks for you.

## Works with your tools

Slack, Telegram, Gmail, Calendar, Drive, Jira, GitHub, Glean, Grafana, ClickHouse, OpenRouter and a shared
warehouse. Connect each once with your own accounts, then grant each agent read or write access, tool by tool.
[Integrations](https://aidenhq.ai/integrations/index.md)

## Yours, and open

- **Your server:** one machine you control, reachable only on your private network.
- **Open source:** the kernel is AGPL-3.0-only; the official modules, the app starter and the design system are MIT.
- **Your choice of AI:** pick the model for each agent and switch whenever you like.
- **Every change can be undone:** agents, instructions and apps live in a private repository with full history.
- **No surprise bills:** spend limits per agent, per task and per day.
- **Distros that fit you:** a small kernel, modules on top, and tested bundles such as a founder's office or an
  engineering team. [Modules and distros](https://aidenhq.ai/modules/index.md)

## Get started

Requirements, the three ways to install and what happens next: [Install guide](https://aidenhq.ai/install/index.md).
Index for agents: [llms.txt](https://aidenhq.ai/llms.txt).
