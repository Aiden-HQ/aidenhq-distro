# Connect a tool once. Every agent you allow can use it.

> Connect Slack, Telegram, Gmail, Calendar, Drive, Jira, GitHub, Glean, Grafana and ClickHouse once, with your own accounts. Then grant each agent read or write access, tool by tool.

Every connection speaks MCP, the open standard for agent tools. Sign in to Slack, Gmail, GitHub and the rest with your own accounts, one time. Then decide, agent by agent and tool by tool, who may read and who may write.

_Animation: tools are connected once, then each agent is granted read or write access tool by tool; an agent without a write grant is blocked from posting_

## Works with the tools you already use.

Most integrations are in the default install, so you only connect them; Grafana and ClickHouse are added in one step.

### Talk and message

Slack, Gmail, Telegram

### Work and documents

Calendar, Drive, Jira, GitHub, Glean

### Data and models

Grafana, ClickHouse, OpenRouter, Warehouse

## Tools work best together.

Agents combine connections the way a person would, and every source feeds one shared database your apps can build on.

| Tools | What your agents do with them | Installed by default |
|---|---|---|
| Telegram | Your chief of staff in your pocket: chat, voice notes and one-tap approvals. | Yes |
| Slack | Agents in your channels, follow-ups on what people promised, and /aiden assign-channel. | Yes |
| Gmail, Calendar, Drive | Follow-ups that never drop, meeting prep with every doc you need, and calendar changes on approval. | Yes |
| GitHub | Engineers open changes, reviewers check them, and apps are built and deployed from them. | Yes |
| Jira | A live status board of what every team is working on. | Yes |
| Glean | Answers from across your company's documents when an agent needs context. | Yes |
| Grafana, ClickHouse | Incident digests with the graphs attached, and metrics for your dashboards. | No |
| OpenRouter | The AI models your agents run on: pick any model for any agent. | Yes |
| Warehouse | One shared database every source feeds and every app can read, each with its own private space. | Yes |

## Read for some, write for few.

Every tool is marked as reading or writing. Each agent gets exactly the tools its job needs, and every call is checked against that grant.

### Your own sign-in

Connections use the tool's official sign-in with your account, so access matches what you already have.

### Granted tool by tool

Rhea, the researcher, reads Slack; Tess, the follow-up chaser, posts. Change it any time, with one approval.

### Writes go through approvals

A granted write still passes the approval levels: some run, a second AI checks some, you decide the rest.

### Connect it once

Every agent you allow shares the one connection, so there are no per-agent keys to manage.

### Enforced and logged

Every call is checked against its grant and recorded, whatever an agent was told.

### Add your own

Any tool with an MCP server can be packaged as a module and connected the same way.

---

Install: `curl -fsSL https://get.aidenhq.ai | sh` on an Ubuntu or Debian server, or ask your coding agent to follow [prompt.md](https://aidenhq.ai/prompt.md). Home: [aidenhq.ai](https://aidenhq.ai/index.md). All pages: [llms.txt](https://aidenhq.ai/llms.txt).
