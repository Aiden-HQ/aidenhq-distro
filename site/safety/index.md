# Agents act. You decide what matters.

> Agents act, you decide what matters. Every action that changes something is checked by the system, not the agent: some run by themselves, a second AI checks others, and you approve the rest with one tap.

Agents are free to think, plan and draft. Anything that changes something (a message, a deploy, a merge, a settings change) is checked by the system before it happens, and the important ones come to you with the exact request.

_Animation: Aiden sends an approval card to your phone with the exact email it wants to send; you tap Approve and it is sent_

## Three levels, decided by the system.

Which level an action gets is set by rules in code, not by the agent asking. No prompt can talk its way past them, and one setting dials how much runs on its own.

- **Runs by itself:** Safe, reversible steps: updating a task, drafting a reply, reading a doc.
- **A second AI checks it:** Merges, deploys, messages to allowed people. The reviewer is always a different AI model family from the one asking.
- **You decide:** Anything that widens an agent's reach, raises spending, or vetoes a decision. One tap from your phone.

| Action | Who decides |
|---|---|
| Update a task or a board | Runs by itself |
| Remind a teammate on Slack | Second AI |
| Merge a reviewed code change | Second AI |
| Deploy a new app version | Second AI |
| Give an agent a new tool | You |
| Raise a spend limit | You |
| Share an app with a new group | You |

Each card shows exactly what will happen: the full email text, the exact code change, the precise setting. What you approve is what runs.

## Deterministic guardrails, below the AI.

The rules sit below the AI. They read the real state of things: who asked, what changed, which tool.

### Prompt-injection resistant

Emails, chats and documents are fenced as information, so agents read everything and take orders only from you.

### Tool by tool permissions

Every tool call passes one checkpoint that confirms the agent was granted that exact tool.

### A locked box for code

Coding agents work in a sealed space with their own network and no passwords, fully isolated from the rest of your server.

### Their own identity

Agents speak as clearly labelled assistants with their own identity, so you always know who said what.

### Security on staff

Security Watch hunts known vulnerabilities and ships the fixes; a Red Teamer stress-tests your setup the way an attacker would.

### Careful with updates

Every component is pinned to an exact version, and new releases wait a week before they are used, unless they fix a security hole.

## Your server, your keys, your history.

AidenHQ runs on one machine you control. Your settings and history live there and in a private repository you control, and every change is recorded so it can be undone.

- **One door, locked twice.** The board is behind a password and a one-time code, on your server's HTTPS address or only on your private network (Tailscale). Apart from SSH, that is the only door.
- **An encrypted vault.** Passwords and keys are kept encrypted, out of every prompt; each service gets exactly its own.
- **Logins stay with the connection.** Agents use your tools through a connection that holds the sign-in for them.
- **Full history.** Agents, instructions, settings and apps live in your own private repository. Go back to any earlier version.
- **A record of everything.** Every decision, tool change and AI call is logged.
**Your models, your rules**
Pick any model for each agent, frontier or open-weight, through OpenRouter, with zero data retention enforced on every call so providers keep no copy of your prompts. Agents reach out to exactly the tools and services you connect and grant.

## Budgets you set. Every cent on the record.

Every AI call is metered, attributed and capped, so a team that works all night stays exactly on budget.

### Per agent

Budgets per run, per task and per day, enforced at the gateway.

### One monthly budget

The model key carries your monthly budget, so the total is always under your control.

### Right model, right job

Fast, efficient models for everyday work; frontier models where they earn their keep.

### Every cost on record

The Costs page shows spend by agent and by task, so you see exactly where it goes.

---

Install: `curl -fsSL https://get.aidenhq.ai | sh` on an Ubuntu or Debian server, or ask your coding agent to follow [prompt.md](https://aidenhq.ai/prompt.md). Home: [aidenhq.ai](https://aidenhq.ai/index.md). All pages: [llms.txt](https://aidenhq.ai/llms.txt).
