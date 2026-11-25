# AidenHQ: your work life, on autopilot

> Aiden is an open-source AI chief of staff on your own server. It reads your Slack, email and meetings, turns what needs you into action items, follows up with people, and builds new agents for everything else.

Meet Aiden, your AI chief of staff, and a team of agents that works for you 24/7. Aiden cuts the noise in your Slack,
email and meetings and follows up on what matters. Describe any agent in a sentence, and Aiden builds it and puts it
to work. Open source, on your own server, with any AI model. Install it with one command on a fresh Ubuntu or Debian
server (or a Mac):

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

**Using Claude Code, Codex or another coding agent?** Paste this into it:

```text
Set up AidenHQ on my server by following https://aidenhq.ai/prompt.md
```

## Cut the noise. Focus on what matters

Most of what reaches you doesn't need you. Aiden reads it all, keeps what does, and makes sure nothing slips.

1. **Reads everything:** your Slack channels and DMs, the email you hand it, your meeting transcripts and notes, and
   anything you forward on Telegram.
2. **Keeps what needs you:** asks, promises and deadlines become one action item each, linked to where they came from.
   The rest stays out of your way.
3. **Follows up until it's done:** Aiden tracks what people owe you, drafts the nudge when something slips, and tells you
   when it's settled.
   Only urgent things interrupt you.

Also: a morning brief on Telegram or Slack, decisions and action items filed from each meeting transcript or your notes, answers to
"where does this stand?" from your messages, docs and tasks, and apps that agents build and keep running.
[Apps](https://aidenhq.ai/apps/index.md)

## Build any agent in a sentence

Describe the job. Aiden designs the agent, gives it the tools it needs, tries it on real work and adds it to your team.
Agents can build their own tools and apps too. For example:

- **Follow-up chaser:** "Chase anyone who hasn't answered me in two days." Runs every two hours on workdays; checks
  with you before writing to anyone outside your team.
- **Sales follow-up:** "Every morning, draft follow-ups for leads that went quiet in HubSpot." Drafts wait for your OK.
- **Weekly digest:** "Every Friday, tell me what each team shipped and what slipped." Reads GitHub, Jira and Slack.
- **Hiring tracker:** "Build a hiring tracker for the team and keep it running." An app your team can open.
- **Support triage:** "Watch #support and file a Jira ticket for every real bug." A second AI reviews each ticket.
- **Build fixer:** "When the build breaks on main, find the cause and open a fix." A second AI reviews the fix.

Agents you build join the same team: Aiden hands them work, and they learn from every correction you make.
[How agents get built](https://aidenhq.ai/agents/index.md)

## A team that works together, 24/7

Your agents hand work to each other, check each other's work and keep going while you sleep. You see every handoff and
can step in whenever you like. An example day:

- **02:10** DevOps Engineer saw the hiring tracker fail, rolled it back and filed the bug.
- **02:40** Engineer fixed the cause. A second AI reviewed the fix, and it shipped.
- **07:30** Aiden sent your morning brief: four things need you, the rest is handled.
- **10:15** Researcher compared vendor prices and added a table to the launch plan.
- **14:00** Agent Architect built the sales follow-up agent you described and added it to the team.
- **18:20** Follow-up Tracker drafted nudges for two replies that slipped.

Work moves between agents with the goal, the history and a clear definition of done. A grader checks the work before a
task counts as done. Safe steps run on their own, a second AI reviews merges, deploys and messages, and you decide
anything that matters. Agents remember people, decisions
and how you like things; correct one once and the whole team learns it.
[Agents and teams](https://aidenhq.ai/agents/index.md)

## Autonomous, and still yours

- **Nothing speaks for you unchecked:** a second AI reviews every message, merge and deploy, and anything that matters
  waits for one tap from your phone. [Approvals](https://aidenhq.ai/safety/index.md)
- **Your server, your data:** it runs on a machine you own. Open source, with every agent and instruction in your own
  repository. [Source](https://github.com/Aiden-HQ/AidenHQ)
- **Any model, a budget you set:** pick the model for each agent, open-weight included. Spend is capped per agent, per
  task and per day. [Spend limits](https://aidenhq.ai/safety/index.md#costs)

Works with Slack, Gmail, Calendar, Drive, Telegram, GitHub, Jira, Glean and more.
[Integrations](https://aidenhq.ai/integrations/index.md)

## Questions

### What is AidenHQ?

AidenHQ is an open-source AI chief of staff and agent team that runs on your own server. Aiden reads your Slack, the email you hand it and your meeting notes, turns what needs you into action items and follows up with people. For anything else you want off your plate, describe an agent and Aiden builds it. You talk to Aiden on Telegram, Slack or the web.

### Will it send messages without asking?

Not unchecked. Safe, reversible steps run by themselves. Messages, merges and deploys are reviewed by a second AI model first, and anything that speaks for you, spends more or gives an agent more power waits for your one-tap approval. A new install starts quiet: nothing runs on a schedule until you turn it on. [How approvals work](https://aidenhq.ai/safety/)

### Where does my data live?

On the server you run it on. You reach it over HTTPS on your server's own address, behind your password and a one-time code, or keep it on your private network with Tailscale. Every agent, instruction and app lives in your own git repository, so every change can be reviewed and rolled back. [Private by design](https://aidenhq.ai/safety/#private)

### What does it cost?

AidenHQ is free and open source. You pay for your own server and for the AI models, which OpenRouter bills to your own key. Spend is capped per agent, per task and per day, and the Costs page shows where every cent goes. [Spend limits](https://aidenhq.ai/safety/#costs)

### How do I set it up?

Paste one line into Claude Code, Codex or another coding agent: “Set up AidenHQ on my server by following https://aidenhq.ai/prompt.md”. Or run `curl -fsSL https://get.aidenhq.ai | sh` yourself on a fresh Ubuntu or Debian server, or a Mac. It ends with a setup link where you create your password and add your model key. [Install guide](https://aidenhq.ai/install/)

## Get started

Requirements, the three ways to install and what happens next: [Install guide](https://aidenhq.ai/install/index.md).
Index for agents: [llms.txt](https://aidenhq.ai/llms.txt).
