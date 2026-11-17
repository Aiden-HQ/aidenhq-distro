# Agents act. You decide what matters.

> Agents act, you decide what matters. Every action that changes something is checked by the system, not the agent: some run by themselves, a second AI checks others, and you approve the rest with one tap.

Agents are free to think, plan and draft. Anything that changes something (a message, a deploy, a merge, a settings change) is checked by the system before it happens, and the important ones come to you with the exact request.

_Animation: Aiden sends an approval card to your phone with the exact email it wants to send; you tap Approve and it is sent_

## Three levels, decided by the system.

Which level an action gets is set by rules in code, not by the agent asking. An agent cannot talk its way into a lower level, and you can raise or lower how much runs on its own with one setting.

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

## Checked by the system, not by the agent.

The rules sit below the AI. They read the real state of things (who asked, what changed, which tool), never what an agent says about it.

### Text cannot give orders

Emails, chats and documents are treated as information, never instructions. A message saying "ignore your rules" is just a message.

### Tool by tool permissions

Every tool call passes one checkpoint that confirms the agent was granted that exact tool.

### A locked box for code

Coding agents work in a sealed space with their own network and no passwords, so they cannot touch the rest of your server.

### Never as you

Agents speak as a labelled assistant. Nothing is ever sent from your own account.

### Security on staff

Security Watch scans for known security holes and proposes fixes; a Red Teamer attacks your own setup to find weak spots first.

### Careful with updates

Every component is pinned to an exact version, and new releases wait a week before they are used, unless they fix a security hole.

## Your server, your keys, your history.

AidenHQ runs on one machine you control. Your settings and history live there and in a private repository you control, and every change is recorded so it can be undone.

- **No public doors.** The board is reachable only on your private network, behind a password and a one-time code.
- **An encrypted vault.** Passwords and keys are kept encrypted, out of every prompt; each service gets only its own.
- **Logins stay with the connection.** Agents use your tools through a connection that holds the sign-in; they never see it.
- **Full history.** Agents, instructions, settings and apps live in your own private repository. Go back to any earlier version.
- **A record of everything.** Every decision, tool change and AI call is logged.
**What does leave your server**
Agents reach the tools you connect (Slack, Gmail, GitHub and so on), and the AI models run through OpenRouter, with zero data retention enforced on every call, so model providers keep no copy of your prompts. You choose the model for each agent. Outbound access is open by design: agents may call the services they are granted.

## Set the limit. Never get a surprise bill.

Agents that run all night can quietly run up a bill. Here every AI call is metered and capped.

### Per agent

Limits per run, per task and per day. An agent stops when it reaches its limit.

### One monthly cap

The model key has its own monthly limit ($50 by default), so the total can never run away.

### Low-cost by default

Most agents run on a fast, inexpensive model. Premium models only where they earn it.

### Every cost on record

The Costs page shows spend by agent and by task, so you see exactly where it goes.

---

Install: `curl -fsSL https://get.aidenhq.ai | sh` on an Ubuntu or Debian server, or ask your coding agent to follow [prompt.md](https://aidenhq.ai/prompt.md). Home: [aidenhq.ai](https://aidenhq.ai/index.md). All pages: [llms.txt](https://aidenhq.ai/llms.txt).
