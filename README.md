# AidenHQ

**Your agents ship autonomously.**

AidenHQ runs a fleet of autonomous AI agents on your own server. You talk to one chief of staff, Aiden, on Telegram,
Slack or the web. Aiden hands the work to agents that plan it, build it, review it, ship it and keep it running, day
and night.

```sh
curl -fsSL https://get.aidenhq.dev | sh
```

Needs Linux, Docker and Node on a server you control. Site: [aidenhq.dev](https://aidenhq.dev) (source in
[`site/`](site/)).

## What you get

- **One chief of staff.** Ask for an app, forward a thread, set a deadline. Aiden turns it into tasks for the right
  agent, chases them and reports back when it's done. You never write a prompt.
- **A crew that works while you don't.** Agents wake on schedules and events: research, code, deploys, follow-ups,
  daily briefs.
- **Apps your agents build and run.** Dashboards, trackers and internal tools, shipped to a sandboxed apps platform,
  watched by the DevOps Engineer and fixed when they break. Share them with your team behind sign-in.
- **Shared connections, scoped per tool.** Slack, Google Workspace, GitHub, Jira, Glean and more, connected once.
  Agents get grants tool by tool, checked on every call, and never see a credential.
- **A shared warehouse.** Your sources land in one Postgres that agents query and apps build on.
- **Any model, any engine.** Pick any OpenRouter model per agent. Engineers run on Codex, Claude Code or opencode, and
  you can swap the engine whenever you like. One metered gateway caps spend per run, task and day.
- **A small kernel, everything else a module.** The kernel holds the gates, identity, owner proof, the sandbox and
  metering. Engines, channels, connections, agents and apps are modules: from the official distro, a marketplace, or
  your own, each held to exactly what it declares it can read and write.
- **Yours, end to end.** Your server, your models, your data. Every agent, handbook and app lives in your own git
  repository, so every change can be reviewed and reverted.
- **Autonomous, with guardrails in code.** Code decides what each agent may touch, and an AI reviewer from a different
  model family judges every risky action before it runs. You keep the final say on what matters: spend, the autonomy
  level and anything that widens what agents can write. Inbound stays private (LAN or Tailscale, password and TOTP),
  and secrets live in an encrypted vault, never in a prompt.

## How it works

1. **Say what you need** to Aiden on Telegram, Slack or the board.
2. **Aiden delegates** to the agent that knows the job and keeps the thread with you.
3. **Agents do the work** on a code-gated runner and a sandboxed apps platform.
4. **Agents ship it.** The AI reviewer checks every risky action, and the work lands on its own.

## Install

```sh
curl -fsSL https://get.aidenhq.dev | sh
```

The installer checks your server, fetches a tested release of the kernel and the essential modules pinned by commit,
verifies every commit against the release file, and hands you to setup. Aiden says hello on your board when it's done.
