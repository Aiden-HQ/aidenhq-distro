# AidenHQ

**Your agents ship autonomously.**

AidenHQ gives you a whole AI team that runs itself: a chief of staff you talk to, and specialists who plan, build,
ship and follow up around the clock, on your own server.

Not a chatbot. Not a workflow builder. A team that works.

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

One line on your Linux server with Docker and Node. Site: [aidenhq.ai](https://aidenhq.ai) (source in
[`site/`](site/)).

## Hand over real work, in a sentence

- **A chief of staff that follows up for you.** Aiden tracks every commitment made in Slack and email, chases people
  when things slip, and briefs you every morning on what moved.
- **An app from one sentence.** "Build me a roadmap tracker" becomes a live app your team signs in to, maintained
  after launch.
- **A new agent from a description.** "I need an agent that watches our support channel" becomes a working agent. The
  Agent Architect designs it, runs it on trial and graduates it once its work holds up.
- **An engineering team that ships.** A designer, engineers, a reviewer, DevOps and security, each a specialist agent.
  Issues become designed, built, reviewed and deployed work.

## Why it works where other agents stall

- **Stop babysitting your agents.** Talk to Aiden like a chief of staff. The work fans out to specialists who wake on
  schedules and events, and Aiden chases it until it lands.
- **Done means checked.** A grader checks the work before a task counts as done, and an AI reviewer checks every risky
  action before it happens.
- **Apps that look after themselves.** Agents watch every app's health, roll back a bad deploy, raise and fix incidents,
  patch dependencies and security issues with pull requests, and catch visual regressions in UI review.
- **It learns your corrections.** Every correction becomes a rule or an automated check. Agents keep a memory of what
  worked, a coach agent proposes better playbooks, weekly fleet reviews fix the causes of repeat defects, and agents
  propose changes to their own instructions and tools, tested before they land.
- **Plugs into the tools you already use.** Slack, Gmail, Calendar, Drive, Jira, GitHub, Glean, Grafana, ClickHouse,
  Telegram and OpenRouter, connected once and granted tool by tool. Every source feeds one shared warehouse your apps
  can build on.
- **Set the cap. No surprise bills.** Spend caps per agent, per run, per task and per day; fast, efficient models by
  default; and a ledger of every model call.
- **Add, swap or extend any capability.** Engines (Codex, Claude Code, opencode), channels, connections, agents and
  apps are modules. Ours cover most needs, and the marketplace is open for anyone to extend.
- **Yours end to end.** Your server, any OpenRouter model per agent, and every agent, playbook and app in your own git
  repository, ready to review and revert. Under the hood, a small kernel holds the gates, identity, sandbox, metering
  and audit log; everything else is a module on the same public contracts.

## Agents decide. Code approves.

- **AI review of every write.** Each push, merge, deploy and message is checked first. Changes that expand authority
  get a second reviewer from another model family, and every false reject becomes a test case.
- **Rules in code, below the model.** Gates and per-tool permissions are enforced by one proxy that no prompt can
  argue with. You keep the final say on spend, autonomy and what agents may write.
- **Attacked and patched.** A Red Teamer agent probes your system, Security Watch scans images and dependencies for
  known vulnerabilities and opens patch PRs, and every dependency is pinned with a 7-day minimum age, gitleaks secret
  scanning and image scans.
- **Locked down.** Coding jobs run jailed with their own network, no secrets and read-only tokens. Untrusted text is
  fenced as data. Secrets live in an encrypted vault. There are no public ports, and shared apps sit behind your
  company's single sign-on.
- **Every action on the record.** Spend caps, an audit log of gate decisions and tool writes, and every change in git.

## One line to install

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

The installer checks your server, fetches a tested release of the kernel and the essential modules pinned by commit,
verifies every commit, and hands you to setup. Aiden says hello on your board when it's ready.
