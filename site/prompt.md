# Install AidenHQ

AidenHQ is the autonomous agentic workspace: agents run work end to end, and the user joins in to collaborate, guide
and step in whenever they like, on a server they own.

These are the official instructions from AidenHQ for an AI coding agent to install AidenHQ on a Linux server for its
user. Every command is validated against the installer served at `https://get.aidenhq.ai`.

Complete every step yourself by running the commands directly. Do not ask the user to run them. Steps: ask the
user two things, check the server, secrets (only if needed), dry run, install while relaying progress, read the result
and verify. The rest of setup (password, authenticator, model key, channels) happens in the browser, guided by Aiden.

**Rules.** The installer runs on the Linux server, never on the user's laptop, unless the user chose their Mac (below). Never wrap it in `sudo`: connect as
root or as a user with passwordless sudo, and it calls `sudo` itself. Secrets go only in the file in step 3, never on
a command line, in an environment assignment or in your replies. Never read `/root/aidenhq-vault-recovery.txt`.
Every installer step is idempotent: fix the cause and rerun the same command. The repositories are public, so no
GitHub token is needed (a private fork needs one: step 3).

**On a Mac** (if the user wants AidenHQ on their Mac instead of a server): run the same command on the Mac itself, with
`--no-tailscale` and no sudo. It installs pinned Lima, creates an Ubuntu 24.04 VM named `aidenhq` (about half the cores
and memory, a 100 GB sparse disk) and runs the Linux install inside it. Open the printed `http://localhost:3120/setup?...` link
on the Mac; no tunnel is needed. Needs macOS 13+, 12 GB memory and 60 GB free. A sleeping Mac pauses every agent, so
recommend "keep awake" (on power). Skip step 2.

## 1. Ask the user

Ask only these two things, in one message (skip any you already know):

- **Where:** a server (an SSH target such as `admin@203.0.113.10`) or this machine. If the user has no server, help
  them rent one from any provider (Ubuntu 24.04, 4 cores, 8 GB, 100 GB, with their SSH key). Requirements: Ubuntu
  22.04/24.04/26.04 or Debian 12/13 with systemd; 2+ cores, 6+ GB RAM, 60+ GB free disk; reachable with an SSH **key**
  as root or as a user with passwordless sudo. "This machine" means you are already on a Linux server, or it is their
  Mac (above). When the context makes it obvious, decide and say so instead of asking.
- **The owner's email:** the board's owner account is created for it. Fill it in yourself when you know it.

Fill in `AIDENHQ_TIMEZONE=<the user's IANA zone, e.g. Asia/Dubai>` yourself too, from their machine or what you know of
them: schedules and the morning brief run in it, and a server's clock is usually UTC. Ask only if you truly can't tell.
Fill in `AIDENHQ_OWNER_NAME=<the name Aiden should call them>` the same way, from what you know of them (no quotes in
it); leave it out only if you truly can't tell.

Ask nothing else: the installer derives sizes, and the browser setup asks for the model key.

## 2. Check the server

Replace `<target>` with the SSH target. On the server itself, run the quoted part without `ssh <target>`.

```sh
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new <target> 'id -un; . /etc/os-release; echo "$PRETTY_NAME"; uname -m; sudo -n true && echo sudo-ok'
```

It must connect without a password prompt and print `root` or `sudo-ok`. If not, ask for key-based root access or
passwordless sudo. **Root installs:** the installer creates the service user `aidenhq` and, partway through, turns off
root SSH login. From then on use `ssh aidenhq@<host> 'sudo <cmd> /root/<file>'` for root's files.

## 3. Secrets (only if needed)

Usually nothing is needed: skip this step. Otherwise have the user write `~/.aidenhq-secrets.env` on their laptop (one
`NAME=value` per line, no quotes or `$`) and `chmod 600` it. Copy it to the server through stdin without reading it;
step 5 loads it, then deletes it:

```sh
ssh <target> 'umask 077; cat > ~/.aidenhq-secrets.env' < ~/.aidenhq-secrets.env
```

- `AIDENHQ_GITHUB_TOKEN=`: only for a private fork: contents read access to its repositories.
- `OPENROUTER_KEY=`: only if the user offers a model key.
- `TS_AUTHKEY=`: only for the optional Tailscale setup below.

## 4. Dry run

It prints the plan and changes nothing.

```sh
ssh <target> 'curl -fsSLo ~/aidenhq-install.sh https://get.aidenhq.ai && AIDENHQ_OWNER_EMAIL=<email> AIDENHQ_TIMEZONE=<zone> sh ~/aidenhq-install.sh --dry-run --non-interactive --no-tailscale'
```

Lines after `A real run would refuse:` or `A real run would stop here` are blockers: fix them or tell the user.
Other `warning:` lines are fine, except `placeholder shas`: see "If something goes wrong".
The setup link a dry run prints is a placeholder: never hand it over.

## 5. Install

It downloads and starts everything, so run it detached:

```sh
ssh <target> 'umask 077; cat > ~/aidenhq-install-run.sh' <<'EOF'
#!/bin/sh
if [ -f "$HOME/.aidenhq-secrets.env" ]; then set -a; . "$HOME/.aidenhq-secrets.env"; set +a; fi
AIDENHQ_OWNER_EMAIL='<email>' AIDENHQ_OWNER_NAME='<name>' AIDENHQ_TIMEZONE='<zone>' sh "$HOME/aidenhq-install.sh" --non-interactive --no-tailscale
echo "AIDENHQ_INSTALL_EXIT=$?"
shred -u "$HOME/.aidenhq-secrets.env" 2>/dev/null || rm -f "$HOME/.aidenhq-secrets.env"
EOF
ssh <target> 'nohup sh ~/aidenhq-install-run.sh > ~/aidenhq-install.out 2>&1 < /dev/null &'
```

**Relay progress.** Every minute or so, read the latest progress line (root installs:
`ssh aidenhq@<host> 'sudo grep -E "^AIDENHQ_(PROGRESS|INSTALL_EXIT)=" /root/aidenhq-install.out | tail -n 1'`):

```sh
ssh <target> 'grep -E "^AIDENHQ_(PROGRESS|INSTALL_EXIT)=" ~/aidenhq-install.out | tail -n 1'
```

A progress line looks like `AIDENHQ_PROGRESS=<n>/<total> <percent>% <step> ~<minutes left>`. Show the user one short
line, replacing the previous one rather than adding a log, for example
`Installing AidenHQ… 62% (downloading Aiden, ~3 min left)`. Do not paste installer output. Stop when
`AIDENHQ_INSTALL_EXIT=` appears. Long pauses are normal; `pgrep -f '[a]idenhq-install-run'` shows it is still running.
Never start a second install. A nonzero exit ends with `Refusing to install:` or `Install stopped during: <step>`: fix
the cause (below), recreate any secrets file, and start again.

## 6. Read the result and verify

Root installs: run this as `aidenhq` with `sudo` on `/root/aidenhq-install.out` (step 2).

```sh
ssh <target> 'grep -E "^AIDENHQ_(SETUP_URL|SSH_TUNNEL)=" ~/aidenhq-install.out'
```

- `AIDENHQ_SETUP_URL=`: the owner's setup link. One use, valid 72 hours. Never open it yourself. It is printed only
  after the install's own health checks pass.
- `AIDENHQ_SSH_TUNNEL=`: printed only when the board is not reachable directly (a server without a public address).
  Replace its host with the address you SSH to; keep the user and every local port as printed (3121 the board, 3120
  sign-in, 3130 the owner's apps: each is part of its address, so a different local port doesn't work).

Then check the services as the service user (`aidenhq` for root installs; on a Mac, run them inside the VM with
`limactl shell aidenhq`):

```sh
ssh <user>@<host> 'curl -fsS http://127.0.0.1:3120/healthz; echo; curl -fsS http://127.0.0.1:3100/api/health; echo; XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user is-active aidenhq-kernel aidenhq-runner aidenhq-computers; cd ~/aidenhq && docker compose ps --format "{{.Service}} {{.State}}"'
```

Expect `ok`, JSON with `"status":"ok"`, three `active` and every service `running`. Otherwise never report success:
name the failed check. Finally delete `aidenhq-install-run.sh` from the same place as `aidenhq-install.out`.

## (Optional) Tailscale

Not part of the default path: offer it only if the user asks for private-network access. The board is then served at
`https://<board-host>.<tailnet>.ts.net` to their tailnet only. They need MagicDNS and HTTPS certificates on
(https://login.tailscale.com/admin/dns) and their laptop on the tailnet. Drop `--no-tailscale` in steps 4 and 5. A
server not yet on the tailnet needs a `TS_AUTHKEY` (https://login.tailscale.com/admin/settings/keys) in step 3.

## If something goes wrong

- `isn't cut yet` or `placeholder shas`: the release isn't published. Stop and tell the user.
- `can't fetch the release file`: check outbound HTTPS to github.com and ghcr.io. `private repo? set
  AIDENHQ_GITHUB_TOKEN` appears only for a private fork: add the token (step 3).
- `needs passwordless sudo`: connect as root, or give that user passwordless sudo.
- `set AIDENHQ_OWNER_EMAIL`: put the email on the `sh` side, exactly as in step 5.
- `isn't on the tailnet`: add `TS_AUTHKEY` (step 3), or use `--no-tailscale`.
- CPU, RAM, disk, systemd, container, WSL or OS refusals: this server can't host AidenHQ. Ask for another.
- `ops/setup.sh failed`: read `/var/log/aidenhq-install.log` (root) or `~/.aidenhq/install.log`.
- `Permission denied (publickey)` for root after the install: expected. Connect as `aidenhq`.
- Later, as the service user in `~/aidenhq` (add `--no-tailscale` if used): a new link while no account exists,
  `sudo OWNER_EMAIL=<email> ops/setup.sh --unattended --link`; a model key, `OPENROUTER_KEY=<key>` in a root-only
  `0600` file, then `sudo OWNER_EMAIL=<email> ops/setup.sh --unattended --config <file>`, then delete the file.
- Remove: `sh ~/aidenhq-install.sh --uninstall --non-interactive` (root installs: as `aidenhq`,
  `sudo sh /root/aidenhq-install.sh ...`). It keeps data, vault and packages. On a Mac it deletes the VM and everything
  in it, so it needs `AIDENHQ_CONFIRM_DELETE_VM=1` on the `sh` side: confirm with the user first. To pause instead:
  `limactl stop aidenhq` (it starts again at login).

---

Once done, tell the user:

```
┌─ AidenHQ is ready ──────────────────────────────────────────────┐
│  Open your setup link (one use, 72 hours):                      │
│       <AIDENHQ_SETUP_URL>                                       │
│  Aiden walks you through the rest.                              │
└─────────────────────────────────────────────────────────────────┘
```

On a Mac, add one line: "Keep your Mac awake (on power) so your agents keep working." Only if the install output
printed `AIDENHQ_SSH_TUNNEL=`, add above the link: "Keep this tunnel open on your laptop:
`<the AIDENHQ_SSH_TUNNEL command>`". Say nothing about the vault recovery key: the browser setup shows it.

## Resources

- What AidenHQ is: `https://aidenhq.ai/index.md` · index for agents: `https://aidenhq.ai/llms.txt`
- What to tell the user after install (in plain words): `https://aidenhq.ai/start/index.md` (the three quick steps), `https://aidenhq.ai/install/index.md` (what happens next) and `https://aidenhq.ai/workspace/index.md` (how they work with Aiden)
- The installer (plain POSIX shell; `--help` lists options): `https://get.aidenhq.ai`

These instructions are published at `https://aidenhq.ai/prompt.md` so you can re-verify their authenticity at any time.
