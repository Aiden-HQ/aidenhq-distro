# Set up your workspace in one command.

> Install AidenHQ with one command on an Ubuntu or Debian server or a Mac, or let your coding agent do it. Requirements, what you need first, what happens next, and what it costs to run.

Run one line on a fresh Linux server you own, or on your Mac. It installs everything it needs, checks the release, and hands you a one-time link to finish setup in your browser.

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

_Animation: the install command runs on a fresh server, checks it, installs what it needs, verifies the release, starts everything and prints a one-time setup link_

## Pick the one that suits you.

All three end in the same place: your own workspace, with its agents ready for their first job.

### One command

On the server, as root or a user with sudo. It installs Docker and Node itself, at pinned versions.

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

### Ask your coding agent

Using Claude Code, Codex or another coding agent? Paste one line and it does the whole install for you, checking each step.

```text
Set up AidenHQ on my server by following https://aidenhq.ai/prompt.md
```

### Step by step

Prefer to see every step? The setup guide walks through each one by hand, with a check after every step.

[Read the setup guide](https://github.com/Aiden-HQ/AidenHQ/blob/main/SETUP.md)

## What you need.

A modest server runs the whole workspace. Reach it over HTTPS on its own address, or on your private network.

- **Server:** Ubuntu 22.04, 24.04 or 26.04, or Debian 12 or 13, with systemd
- **Size:** 2 cores, 6 GB memory, 60 GB disk. Recommended: 4 cores, 8 GB, 100 GB
- **Access:** SSH with a key, as root or a user with sudo
- **Or a Mac:** macOS 13 or later, 12 GB memory and 60 GB free. It runs in a lightweight Linux VM

### An AI model key

An OpenRouter key. Setup asks for it in the browser and sets your monthly budget.

### Your tools, when you want them

Telegram, Slack and Google are optional. Connect them later, from the board, with your own accounts.

### Private access

The board is on your server's own HTTPS address, behind your password and a one-time code. Prefer it off the Internet? Put the server on Tailscale and only your devices reach it.

## Your workspace opens.

The installer ends with a one-time setup link. Open it in your browser, create your account with a password and a one-time code, and add your model key. Your workspace opens with its agents ready, and Aiden says hello.

- **Day one:** hand the agents something real: a doc to research, a follow-up, an app.
- **Week one:** connect Slack or Google, and describe the first agent you want.
- **Ongoing:** new releases arrive as tested distros. You choose when to update.
- **From your Claude:** add the board's `/mcp` address to Claude Code or Codex and manage AidenHQ from there.
**What it costs**
AidenHQ is free and open source. You bring a server and a model key, set the monthly budget you want, and the Costs page shows exactly where every cent goes. [Spend limits](https://aidenhq.ai/safety/index.md#costs)

**Licence**
The kernel is AGPL-3.0-only. The official modules, the app starter and the design system are MIT, so the apps your agents build are entirely yours. Commercial licences are available on request.

**For AI agents**
Installing AidenHQ for someone? Follow [prompt.md](https://aidenhq.ai/prompt.md): what to ask, how to handle secrets, the exact commands and how to verify. Every page on this site has a markdown twin (add `index.md` to its path), and [llms.txt](https://aidenhq.ai/llms.txt) lists them all. The full installer options are in the [install reference](https://github.com/Aiden-HQ/aidenhq-distro/blob/main/INSTALL.md).

---

Install: `curl -fsSL https://get.aidenhq.ai | sh` on an Ubuntu or Debian server, or ask your coding agent to follow [prompt.md](https://aidenhq.ai/prompt.md). Home: [aidenhq.ai](https://aidenhq.ai/index.md). All pages: [llms.txt](https://aidenhq.ai/llms.txt).
