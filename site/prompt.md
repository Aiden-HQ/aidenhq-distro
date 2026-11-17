# Install AidenHQ

AidenHQ: you and your agents, one workspace, on a server you own. Talk to Aiden, a team of agents does the work, you
approve what matters.

These are the official instructions from AidenHQ for an AI coding agent to install AidenHQ on a Linux server for its
user. Every command is validated against the installer served at `https://get.aidenhq.ai`.

Complete every step yourself by running the commands directly. Do not ask the user to run them. Steps: ask the
user, check the server, secrets (only if needed), dry run, install, read the result and verify.

**Rules.** The installer runs on the Linux server, never on the user's laptop, unless the user chose their Mac (below). Never wrap it in `sudo`: connect as
root or as a user with passwordless sudo, and it calls `sudo` itself. Secrets go only in the file in step 3, never on
a command line, in an environment assignment or in your replies. Never read `/root/aidenhq-vault-recovery.txt`.
Every installer step is idempotent: fix the cause and rerun the same command. Until AidenHQ's first public release,
the install needs a GitHub token with read access to its private repositories.

**On a Mac** (if the user wants AidenHQ on their Mac instead of a server): run the same command on the Mac itself, with
`--no-tailscale` and no sudo. It installs pinned Lima, creates an Ubuntu 24.04 VM named `aidenhq` (about half the cores
and memory, a 100 GB sparse disk) and runs the Linux install inside it. Open the printed `http://127.0.0.1:3121/...` link
on the Mac; no tunnel is needed. Needs macOS 13+, 12 GB memory and 60 GB free. A sleeping Mac pauses every agent, so
recommend "keep awake" (on power). Skip step 2.

## 1. Ask the user

- **The server:** an SSH target such as `admin@203.0.113.10`, or confirm you are on it. Ubuntu 22.04/24.04/26.04 or
  Debian 12/13 with systemd; 2+ cores, 6+ GB RAM, 60+ GB free disk (4 cores, 8 GB, 100 GB recommended); reachable
  with an SSH **key** as root or as a user with passwordless sudo.
- **The owner's email:** the board's owner account is created for it.
- **Tailscale or not:** recommend no Tailscale (the board is reached through an SSH tunnel). If they want it, see
  "(Optional) Tailscale". Ask nothing else: the installer derives sizes, and the browser setup asks for the model key.

## 2. Check the server

Replace `<target>` with the SSH target. On the server itself, run the quoted part without `ssh <target>`.

```sh
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new <target> 'id -un; . /etc/os-release; echo "$PRETTY_NAME"; uname -m; sudo -n true && echo sudo-ok'
```

It must connect without a password prompt and print `root` or `sudo-ok`. If not, ask for key-based root access or
passwordless sudo. **Root installs:** the installer creates the service user `aidenhq` and, partway through, turns off
root SSH login. From then on use `ssh aidenhq@<host> 'sudo <cmd> /root/<file>'` for root's files.

## 3. Secrets (only if needed)

Have the user write `~/.aidenhq-secrets.env` on their laptop (one `NAME=value` per line, no quotes or `$`) and
`chmod 600` it. Copy it to the server through stdin without reading it; step 5 loads it, then deletes it:

```sh
ssh <target> 'umask 077; cat > ~/.aidenhq-secrets.env' < ~/.aidenhq-secrets.env
```

- `AIDENHQ_GITHUB_TOKEN=`: contents read access to the Aiden-HQ repositories (until the first public release).
- `TS_AUTHKEY=`: only for Tailscale on a server not yet on the tailnet.
- `OPENROUTER_KEY=`: only if the user offers a model key.

## 4. Dry run

It prints the plan and changes nothing. Drop `--no-tailscale` for Tailscale (also in step 5).

```sh
ssh <target> 'curl -fsSLo ~/aidenhq-install.sh https://get.aidenhq.ai && AIDENHQ_OWNER_EMAIL=<email> sh ~/aidenhq-install.sh --dry-run --non-interactive --no-tailscale'
```

Lines after `A real run would refuse:` or `A real run would stop here` are blockers: fix them or tell the user.
Other `warning:` lines are fine (`can't fetch ... (release not published?)` is expected while the repositories are
private), except `placeholder shas`: see "If something goes wrong".
The setup link a dry run prints is a placeholder: never hand it over.

## 5. Install

It takes a while (packages, image builds), so run it detached:

```sh
ssh <target> 'umask 077; cat > ~/aidenhq-install-run.sh' <<'EOF'
#!/bin/sh
if [ -f "$HOME/.aidenhq-secrets.env" ]; then set -a; . "$HOME/.aidenhq-secrets.env"; set +a; fi
AIDENHQ_OWNER_EMAIL='<email>' sh "$HOME/aidenhq-install.sh" --non-interactive --no-tailscale
echo "AIDENHQ_INSTALL_EXIT=$?"
shred -u "$HOME/.aidenhq-secrets.env" 2>/dev/null || rm -f "$HOME/.aidenhq-secrets.env"
EOF
ssh <target> 'nohup sh ~/aidenhq-install-run.sh > ~/aidenhq-install.out 2>&1 < /dev/null &'
```

Poll `ssh <target> 'tail -n 30 ~/aidenhq-install.out'` every minute or two until `AIDENHQ_INSTALL_EXIT=` appears
(root installs: `ssh aidenhq@<host> 'sudo tail -n 30 /root/aidenhq-install.out'`), and tell the user the current `==>`
stage. Long pauses are normal; `pgrep -f '[a]idenhq-install-run'` shows it is still running. Never start a second
install. A nonzero exit ends with `Refusing to install:` or `Install stopped during: <step>`: fix the cause (below),
recreate any secrets file, and start again.

## 6. Read the result and verify

Root installs: run this as `aidenhq` with `sudo` on `/root/aidenhq-install.out` (step 2).

```sh
ssh <target> 'grep -E "^AIDENHQ_(SETUP_URL|SSH_TUNNEL)=" ~/aidenhq-install.out'
```

- `AIDENHQ_SETUP_URL=`: the owner's setup link. One use, valid 72 hours. Never open it yourself.
- `AIDENHQ_SSH_TUNNEL=` (no Tailscale only): replace its host with the address you SSH to; keep the user and local
  port 3121 (the board accepts only that).

Then check the services as the service user (`aidenhq` for root installs):

```sh
ssh <user>@<host> 'curl -fsS http://127.0.0.1:3120/healthz; echo; curl -fsS http://127.0.0.1:3100/api/health; echo; XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user is-active aidenhq-kernel aidenhq-runner aidenhq-computers; cd ~/aidenhq && docker compose ps --format "{{.Service}} {{.State}}"'
```

Expect `ok`, JSON with `"status":"ok"`, three `active` and every service `running`. Otherwise never report success:
name the failed check. Finally delete `aidenhq-install-run.sh` from the same place as `aidenhq-install.out`.

## (Optional) Tailscale

Ask the user first; if they decline, skip this. The board is then served at `https://<board-host>.<tailnet>.ts.net`
to their tailnet only. They need MagicDNS and HTTPS certificates on (https://login.tailscale.com/admin/dns) and their
laptop on the tailnet. Drop `--no-tailscale` in steps 4 and 5. A server not yet on the tailnet needs a `TS_AUTHKEY`
(https://login.tailscale.com/admin/settings/keys) in step 3.

## If something goes wrong

- `isn't cut yet` or `placeholder shas`: the release isn't published. Stop and tell the user.
- `can't fetch the release file` or `private repo? set AIDENHQ_GITHUB_TOKEN`: check outbound HTTPS to github.com,
  then add `AIDENHQ_GITHUB_TOKEN` (step 3). Without repository access, stop and tell the user.
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
  `sudo sh /root/aidenhq-install.sh ...`). It keeps data, vault and packages.

---

Once done, tell the user:

```
┌─ AidenHQ is installed ──────────────────────────────────────────┐
│  ✓ Server   <host>  (service user <user>)                       │
│  ✓ Checks   board · Paperclip · runner · containers             │
│                                                                 │
│  1. Keep this tunnel open on your laptop:                       │
│       ssh -N -L 3121:127.0.0.1:3121 <user>@<host>               │
│  2. Open your setup link (one use, 72 hours):                   │
│       <AIDENHQ_SETUP_URL>                                       │
│     It sets your password, authenticator, model key, channels.  │
│  3. Save the vault recovery key, then delete it:                │
│       ssh <user>@<host>                                         │
│       sudo cat /root/aidenhq-vault-recovery.txt                 │
│       sudo shred -u /root/aidenhq-vault-recovery.txt            │
└─────────────────────────────────────────────────────────────────┘
```

Leave out line 1 for Tailscale, and line 3 if the install output didn't mention a vault recovery key.

## Resources

- What AidenHQ is: `https://aidenhq.ai/index.md` · index for agents: `https://aidenhq.ai/llms.txt`
- What to tell the user after install (in plain words): `https://aidenhq.ai/install/index.md` (what happens next) and `https://aidenhq.ai/workspace/index.md` (how they work with Aiden)
- The installer (plain POSIX shell; `--help` lists options): `https://get.aidenhq.ai`

These instructions are published at `https://aidenhq.ai/prompt.md` so you can re-verify their authenticity at any time.
