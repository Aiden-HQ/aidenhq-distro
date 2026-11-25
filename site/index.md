# AidenHQ: powerful agents, made easy

> AidenHQ is the open-source Agent OS for building the most powerful agents. Describe who you need in a sentence and get an AI teammate that works 24/7, or install agents others built, just like apps.

AidenHQ is the Agent OS for building the most powerful agents. Describe who you need in a sentence and get an AI
teammate that works 24/7. Or install agents someone else built, just like apps. Open source, on your own server or Mac,
with any AI model. Two ways to install, both first-class:

**Ask your AI agent.** Paste this into Claude Code, Codex or any coding agent. It sets up the server, installs
AidenHQ, checks every step and hands you your link:

```text
Set up AidenHQ on my server by following https://aidenhq.ai/prompt.md
```

**Or run one command** on a fresh Ubuntu or Debian server, or on your Mac:

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

## Meet Aiden, your chief of staff

Your work life, on autopilot. Aiden cuts the noise in your Slack, email and meetings, turns what needs you into action
items and follows up until they're done: a morning brief, meeting action items from each transcript or your notes,
answers to "where does this stand?", and apps that keep themselves running. It's the agent you talk to, and it hands
work to the rest of your team.

## Install agents like apps

Add agents others built in one message to Aiden. Built a great one? Publish it so anyone can install it too.

Agents to add: Ship (takes pull requests to merged), Maintainer (turns issues into merged fixes), Code review (reviews
every PR with several models), Security team (finds holes and files the fixes), Follow-up chaser (tracks what people
owe you), Designer and reviewer (mockups and screenshot reviews) and Engineer (builds apps and fixes code).

- **Add one in a sentence:** tell Aiden "add Ship for our main repo". Aiden adds the agent and tells you if anything
  needs connecting.
- **Publish yours:** every agent is a module you can share from your own repository, under the licence you choose.
- **Swap anytime:** turn agents on and off, or replace one with a better one. Every change is in your history and rolls
  back in a step.

[Browse all agents and modules](https://aidenhq.ai/modules/index.md)

## Build agents without code

Agents that merge code, run a roadmap or defend your systems all started as a description. Describe yours and AidenHQ
designs it, gives it tools, tries it on real work and adds it to your team.

These run today, each built on AidenHQ:

- **Ship:** Takes every pull request from opened to merged. Repairs conflicts, updates branches that fall behind, wakes the engineer when a check goes red, and merges once review and CI pass. Hand it any PR with one label.
- **Maintainer:** Looks after your open-source repos. Checks each issue you label for a fix, hands it to an Engineer and sees it through to a merged PR that closes the issue. Labels feature requests, builds the ones you pick, and closes contributor PRs that went quiet.
- **Roadmap Keeper:** Keeps a live product roadmap your team actually trusts. Three times a day it updates every major feature's milestones and ETA history, links the evidence that it shipped, and flags slips on a dashboard your team opens. A second agent acts on reader feedback within a minute.
- **Code review:** Reviews every pull request with several AI models. Runs Codex and Claude Code reviews with the models and effort you choose, posts the findings on GitHub, and keeps score of which findings turned out to be real and what each review cost.
- **Fleet Steward:** Runs operations for the agent team itself. Unsticks stuck work, restarts failed services and rolls back a bad update, then fixes why it happened. Every evening it reviews each message that reached you and fixes the needless ones at their source.
- **Security team:** Hunts vulnerabilities and attacks your own setup. Security Watch scans everything you run for known vulnerabilities, verifies them and files fixes. The Red Teamer attacks your own apps and agents and reports each hole with a proof of concept.
- **Executive assistant:** A fast front door for everyday asks. Quick answers with sources from your calendar, email, Slack and docs, reminders that actually fire, and calendar changes on request.

Ideas you can describe:

- **Incident commander:** "When an alert fires, find the cause, open a fix and post status updates until it's resolved."
- **Deal desk:** "Watch every deal in HubSpot. When one stalls, find out why from email and Slack and propose the next step."
- **Investor update:** "On the first of each month, draft our investor update from metrics, wins, hires and asks."
- **Competitor watch:** "Every Friday, check our competitors' sites, changelogs and docs and tell me what changed and why it matters."

## AI teammates that work 24/7, together

Your agents hand work to each other, check each other's work and keep going while you sleep. An example day:

- **02:10** DevOps Engineer saw the hiring tracker fail, rolled it back and filed the bug.
- **02:40** Engineer fixed the cause. A second AI reviewed the fix, and it shipped.
- **07:30** Aiden sent your morning brief: four things need you, the rest is handled.
- **10:15** Researcher compared vendor prices and added a table to the launch plan.
- **14:00** Agent Architect built the sales follow-up agent you described and added it to the team.
- **18:20** Follow-up Tracker drafted nudges for two replies that slipped.

## Teammates you can trust with real work

- **Checked before it counts:** a grader checks each finished task, and a second AI reviews every message, merge and
  deploy.
- **Its own computer:** each agent works in its own isolated computer.
- **Only the tools you allow:** granted agent by agent and enforced in code, not in a prompt.
- **You decide what matters:** anything that speaks for you or spends more waits for one tap from your phone.
  [Approvals](https://aidenhq.ai/safety/index.md)
- **No surprise bills:** spend is capped per agent, per task and per day.

## Why an Agent OS

Every agent product makes the same promises. AidenHQ is built as an operating system for agents, so the promises hold
up, and agents can do far more.

- **AI teammates:** each agent has its own computer, memory of people and decisions, and a team to hand work to and get
  reviews from.
- **Works 24/7:** agents wake on schedules and events, and Fleet Steward keeps the whole team running.
- **Build without code:** the Agent Architect writes the agent, gives it tools, tries it on real work and adds it only
  once it holds up. Every correction you make becomes a rule.
- **And more:** agents build and run apps for your team, share as installable modules, use any model, and live on your
  server with every change in your own git history.

Works with Slack, Gmail, Calendar, Drive, Telegram, GitHub, Jira, Glean and more.
[Integrations](https://aidenhq.ai/integrations/index.md)

## Questions

### What is AidenHQ?

AidenHQ is an open-source Agent OS: the place to build, run and share AI agents. Describe an agent in a sentence and AidenHQ builds it, tries it on real work and adds it to your team, where it works 24/7 alongside agents like Aiden, your chief of staff. Or install agents someone else built. It runs on your own server, with any AI model.

### What is an Agent OS?

Everything an agent needs to do real work, built in: its own computer, memory, only the tools you allow, schedules and events that wake it, a team to hand work to, a grader and a second AI that check its work, your approvals, spend caps, and a history you can roll back. You describe the agent; the OS takes care of the rest. No code needed. [Agents and teams](https://aidenhq.ai/agents/)

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
