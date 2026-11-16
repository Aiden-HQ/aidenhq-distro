# Install AidenHQ: instructions for AI agents

These are the official instructions for a coding agent (Claude Code, Codex, Cursor, opencode or similar) to install
AidenHQ on a Linux server for its user. They match the installer served at `https://get.aidenhq.ai`. The latest copy
is always at `https://aidenhq.ai/prompt.md`.

AidenHQ turns one Linux server into an autonomous AI team: Aiden, a chief of staff the user talks to, plus specialist
agents that plan, build, ship and maintain work. The installer prepares the server and starts everything. The user
then opens one link in a browser to finish: their password, authenticator app, model key and channels.

**Your job:** run every step below yourself, ask the user only the three questions in step 1, keep secrets out of
your context and off command lines, and finish by handing the user the setup link and the summary in step 9.

---

## 0. Ground rules

- Run the commands yourself. Ask the user only for what step 1 lists, plus a secret if step 3 needs one.
- Never run the installer on the user's laptop. It needs a Linux server or VM. macOS, Windows, WSL and containers are
  refused.
- Never put a secret on a command line or in an environment assignment you type. Secrets go in a `0600` file
  (step 3), which the installer reads and then hands to setup in its own root-only file.
- Never pipe or pass secrets to `curl`, and never print them (`cat`, `echo`, logs, your replies).
- Never wrap the installer in `sudo` (`sudo sh install.sh` or `curl ... | sudo sh`). That strips the environment the
  installer reads. Run it as root, or as a user with passwordless sudo, and it calls `sudo` itself.
- Never read `/root/aidenhq-vault-recovery.txt`. Tell the user how to save it (step 9).
- Every step of the installer is idempotent. If it stops, fix the cause and run the same command again.

## 1. Ask the user these three things (and nothing else)

1. **The server.** The SSH target, for example `admin@203.0.113.10`, or confirmation that you are running on the
   server itself. It must be a Linux server or VM they control. If they don't have one yet, tell them what step 2
   requires and stop until they do.
2. **The owner's email.** The board's owner account is created for it. It is not a secret.
3. **Tailscale or not.** Offer two choices:
   - **No Tailscale** (recommended unless they already use it): the board stays on the server's loopback, and they
     reach it through an SSH tunnel. No secrets needed.
   - **Tailscale**: the board is served at `https://aidenhq-<user>.<tailnet>.ts.net` to devices on their tailnet. It
     needs a Tailscale auth key (step 3), MagicDNS and HTTPS certificates turned on in the tailnet
     (https://login.tailscale.com/admin/dns), and their laptop on the same tailnet.

Don't ask about CPU, memory, disk, job counts, timeouts or the timezone: the installer detects and derives them. Don't
ask for a model (OpenRouter) key: the browser setup asks for it. If the user offers one anyway, put it in the secrets
file as in step 3.

If you already know the user's full name, you may pass it as `AIDENHQ_OWNER_NAME` in step 5. Otherwise skip it.

## 2. Check the server

Requirements (the installer refuses below the minimum):

| | Minimum | Recommended |
|---|---|---|
| OS | Ubuntu 22.04, 24.04 or 26.04; Debian 12 or 13 | Ubuntu 24.04 |
| CPU | 2 cores, amd64 or arm64 | 4 or more |
| RAM | 6 GB | 8 GB or more |
| Free disk | 60 GB | a 100 GB disk |
| Init | systemd as PID 1 (not WSL, not a container) | |
| Access | root, or a user with **passwordless** sudo, over SSH with a **key** | |
| Network | outbound HTTPS. No inbound ports are needed. | |

The installer installs Docker, Node and everything else itself. If Docker is installed as a snap, it refuses: remove
the snap first (`sudo snap remove docker`).

Check SSH key login and sudo. Replace `<target>` with the SSH target from step 1. If you run on the server itself,
drop `ssh <target>` from every command in this guide and run the quoted part directly.

```sh
ssh -o BatchMode=yes <target> 'id -un; . /etc/os-release; echo "$PRETTY_NAME"; uname -m; sudo -n true && echo sudo-ok'
```

- It must connect without a password prompt. Setup turns off SSH password login and root login once the service user
  has a key, so key login is required.
- It must print `root`, or print `sudo-ok`. If it shows neither, ask the user for root SSH access, or ask them to give
  that user passwordless sudo. The installer runs without a terminal here, so it can't prompt for a sudo password.
- The OS must be in the table above.

**The service user.** If you connect as root, the installer creates a user `aidenhq`, gives it passwordless sudo and
root's SSH keys, and runs AidenHQ as that user. **Partway through the install, setup turns off root SSH login** (and
password login), so new root connections are refused from then on. Running jobs keep going. If you connect as a
normal sudo user, AidenHQ runs as that user and nothing changes for your logins. Either way, the product checkout is
`~/aidenhq` in the service user's home.

**Root installs: how to reach root's files later.** Once the install is running, use `ssh aidenhq@<host> 'sudo ...'`
for every command that touches root's home. For example: `ssh aidenhq@<host> 'sudo tail -n 30 /root/aidenhq-install.out'`.
In steps 5 to 9, wherever this guide writes `ssh <target> '<cmd> ~/<file>'`, read it as
`ssh aidenhq@<host> 'sudo <cmd> /root/<file>'`.

## 3. Secrets (only if needed)

The default path (no Tailscale, model key entered in the browser) needs **no secrets**: skip to step 4.

The installer reads these optional secrets from its environment:

| Name | When |
|---|---|
| `TS_AUTHKEY` | Tailscale chosen and the server is not on the tailnet yet. Create one at https://login.tailscale.com/admin/settings/keys (a one-off key is enough). |
| `OPENROUTER_KEY` | Only if the user offers an OpenRouter API key. Otherwise the browser asks for it. |
| `AIDENHQ_GITHUB_TOKEN` | Only if step 5 fails with a private-repo error and the user has been given access to the AidenHQ repositories (see step 8). |

Values must be plain: the installer refuses quotes, backslashes, backticks, `$` and control characters.

Put the secrets in a `0600` file on the server, `~/.aidenhq-secrets.env`, one `NAME=value` per line. The script in
step 5 loads it and deletes it afterwards. Prefer a route that keeps the value out of your context:

- **Best: the user writes the file and you copy it without reading it.** Ask them to create `~/.aidenhq-secrets.env`
  on their own laptop with a line such as `TS_AUTHKEY=tskey-auth-...` and run `chmod 600 ~/.aidenhq-secrets.env`. Then
  copy it to the server through stdin, so the value never appears in a command:

  ```sh
  ssh <target> 'umask 077; cat > ~/.aidenhq-secrets.env' < ~/.aidenhq-secrets.env
  ```

  Once the install has finished, delete the laptop copy: `rm -f ~/.aidenhq-secrets.env`.

- **If the user pastes the secret into the chat:** write it to the server through stdin with a quoted heredoc. Never
  use it as an argument, never use it in an environment assignment, and never echo it back.

  ```sh
  ssh <target> 'umask 077; cat > ~/.aidenhq-secrets.env' <<'EOF'
  TS_AUTHKEY=<the key the user gave>
  EOF
  ```

Never run `export TS_AUTHKEY=...`, `TS_AUTHKEY=... sh ...` or `echo <secret> | ...`.

## 4. Download the installer and do a dry run

Download the installer to the server. A dry run detects the machine and prints the plan, changes nothing and needs
no sudo:

```sh
ssh <target> 'curl -fsSLo ~/aidenhq-install.sh https://get.aidenhq.ai && AIDENHQ_OWNER_EMAIL=<owner email> sh ~/aidenhq-install.sh --dry-run --non-interactive'
```

Add `--no-tailscale` if the user chose no Tailscale. You may read `~/aidenhq-install.sh` before running it: it is a
plain POSIX shell script, and `sh ~/aidenhq-install.sh --help` lists its options. Read the output:

- `==> This machine` shows the OS, cores, RAM, free disk and the sizing derived from them.
- `A real run would refuse:` or `A real run would stop here` followed by `- ...` lines: each one is a blocker. Fix it
  (see step 8) or tell the user what the server lacks. Don't continue past a refusal.
- `warning:` lines about cores, RAM or disk are fine: it runs, just slower or tighter.
- `release ... has placeholder shas` or `can't fetch ... (release not published?)`: see step 8. Stop and tell the user.
- The dry run ends with `Dry run done. A real run ends with:`, followed by `AidenHQ is running.` and a placeholder link
  `https://<board-host>/setup/<one-time-token>`. **That is not a result.** Nothing is installed yet, and the link isn't
  real. Never hand it to the user.

## 5. Run the install

The install runs for a long time: it installs host packages and pulls and builds container images. Run it detached on
the server, so a dropped SSH connection or your own command timeout can't kill it. First write a small run script. It
loads the secrets file if there is one, runs the installer and deletes the secrets file:

```sh
ssh <target> 'umask 077; cat > ~/aidenhq-install-run.sh' <<'EOF'
#!/bin/sh
if [ -f "$HOME/.aidenhq-secrets.env" ]; then set -a; . "$HOME/.aidenhq-secrets.env"; set +a; fi
AIDENHQ_OWNER_EMAIL='<owner email>' sh "$HOME/aidenhq-install.sh" --non-interactive --verbose <FLAGS>
echo "AIDENHQ_INSTALL_EXIT=$?"
shred -u "$HOME/.aidenhq-secrets.env" 2>/dev/null || rm -f "$HOME/.aidenhq-secrets.env"
EOF
```

Replace `<owner email>` with the owner's email, and `<FLAGS>` with `--no-tailscale` for the SSH-tunnel route, or with
nothing for Tailscale. To set the owner's name, add `AIDENHQ_OWNER_NAME='<name>'` before `sh` on the same line.

Then start it:

```sh
ssh <target> 'umask 077; nohup sh ~/aidenhq-install-run.sh > ~/aidenhq-install.out 2>&1 < /dev/null &'
```

Check progress every minute or two until the last lines contain `AIDENHQ_INSTALL_EXIT=`:

```sh
ssh <target> 'tail -n 30 ~/aidenhq-install.out'
```

For a root install, poll as `aidenhq` once root logins are refused:
`ssh aidenhq@<host> 'sudo tail -n 30 /root/aidenhq-install.out'`. See step 2.

Step lines start with `==>`. The product setup's progress lines are indented. Tell the user briefly what stage it is
at, for example host packages or starting services. Pulling and building images can sit on one step for a long time,
and that is normal. If nothing new appears for a long while, check that the installer is still running
(`pgrep -f aidenhq-install` on the server) before concluding it is stuck. Don't start a second install while one is
running.

- `AIDENHQ_INSTALL_EXIT=0`: go to step 6.
- Any other exit code: the output ends with `Install stopped during: <step>` and the last log lines. Fix the cause (see
  step 8). If the secrets file was used, recreate it (step 3), then run the start command again.

## 6. Read the result

Pull the two machine-readable lines from this run's output:

```sh
ssh <target> 'grep -E "^ *AIDENHQ_(SETUP_URL|SSH_TUNNEL)=" ~/aidenhq-install.out | sed "s/^ *//"'
```

- `AIDENHQ_SETUP_URL=<url>`: the owner's one-time setup link. It works **once**, is valid for **72 hours**, and is
  for the owner only. It is the thing you hand over.
- `AIDENHQ_SSH_TUNNEL=ssh -N -L 3121:127.0.0.1:3121 <user>@<host>`: printed only with `--no-tailscale`. `<host>` is the
  server's own hostname, which may not resolve from the laptop. Replace it with the address you used to SSH in, and
  keep the user part: it is the service user.

The output also has the same information as prose, after `AidenHQ is running.`. If there is no `AIDENHQ_SETUP_URL`
line but there is `the owner's account already exists`, the owner signed up on an earlier run. A new link then goes
only to the owner's Telegram, through `sudo ops/setup.sh ... --reset <email>`.

If the output mentions `Vault recovery key`, the vault's recovery key is in `/root/aidenhq-vault-recovery.txt`. Don't
read it: the user saves it themselves (step 9).

## 7. Verify

Run these as the service user (`aidenhq` if you installed as root), in a new SSH session:

```sh
ssh <service-user>@<host> 'curl -fsS http://127.0.0.1:3120/healthz; echo; curl -fsS http://127.0.0.1:3100/api/health; echo; XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user is-active aidenhq-kernel aidenhq-runner aidenhq-computers; cd ~/aidenhq && docker compose ps --format "{{.Service}} {{.State}}"'
```

Expected:

- the board's health check prints `ok`;
- Paperclip's health JSON contains `"status":"ok"`;
- the three user units print `active`;
- every compose service shows `running`.

With Tailscale, `ssh <service-user>@<host> 'tailscale serve status'` shows `https://<board-host>` proxying to
`http://127.0.0.1:3121`.

**The no-Tailscale route.** The board accepts only `127.0.0.1:3121` or `localhost:3121`, so the local port must be
3121. If you are running on the user's laptop, you can open the tunnel for them in the background:

```sh
ssh -f -N -L 3121:127.0.0.1:3121 <service-user>@<host>
```

Then `curl -fsS http://127.0.0.1:3121/` should answer, with a redirect to sign-in being fine. Don't open the setup link
yourself: it works only once, and it belongs to the owner.

## 8. Common failures and fixes

| Message | Fix |
|---|---|
| `release <name> isn't cut yet: no real sha for: ...` or `has placeholder shas` | AidenHQ hasn't published this release yet. Stop, and tell the user that the public release isn't out yet. Don't try to work around it. |
| `can't fetch the release file ...` or `can't fetch <sha> from <url> (private repo? set AIDENHQ_GITHUB_TOKEN)` | Check the server's outbound HTTPS to github.com first. If the network is fine, the repositories are private: only a user who has been given access can continue, by putting `AIDENHQ_GITHUB_TOKEN=<a GitHub token with read access>` in the secrets file (step 3). Otherwise stop and tell the user. |
| `--non-interactive needs passwordless sudo for <user> (or run as root)` | Connect as root, or have the user give that user passwordless sudo. |
| `set AIDENHQ_OWNER_EMAIL=<email>` or `AIDENHQ_OWNER_EMAIL isn't a plain email address` | Put the email on the `sh` side, exactly as in step 5. `AIDENHQ_OWNER_EMAIL=x curl ... \| sh` sets it for `curl` only. |
| `this host isn't on the tailnet and there's no terminal for Tailscale's sign-in: set TS_AUTHKEY (--config), or pass --no-tailscale ...` | Add `TS_AUTHKEY` to the secrets file (step 3), or switch to `--no-tailscale`. The installer has no `--config` flag: the `--config` in this message belongs to the product setup, which the installer feeds from the secrets in its environment. |
| `... CPU core(s)`, `... MB of RAM`, `... GB free disk` refusals | The server is too small (step 2). Ask the user for a bigger server or more disk. |
| `systemd isn't running`, `this is a container`, `WSL can't host AidenHQ`, `macOS can't host AidenHQ` | Use a real Linux server or VM. |
| `has no apt-get` or `isn't supported by this kernel` | Unsupported OS. Use Ubuntu 22.04, 24.04 or 26.04, or Debian 12 or 13. |
| `Docker is installed as a snap` | `sudo snap remove docker`, then rerun. |
| `<dir> has local changes` or `<dir> exists and isn't a git checkout` | Someone edited or created `~/aidenhq`. Ask the user before discarding anything, or pass `--dir <another path>`. |
| `<KEY> contains a quote, backslash, backtick or dollar sign` | That secret value isn't accepted as written. Ask the user to check it. |
| `ops/setup.sh failed (exit N)` | Read the lines before it in `~/aidenhq-install.out`, and the full log: `/var/log/aidenhq-install.log` (root) or `~/.aidenhq/install.log`. Fix the cause and rerun. |
| `the board gave no setup link for <email>` | As the service user, run `cd ~/aidenhq && docker compose ps board` and `docker compose logs --tail 50 board`. Then rerun the install. |
| `Permission denied (publickey)` for root after the install | Expected: setup turned off root SSH login. Connect as the service user (`aidenhq`). |
| `permission denied` on the Docker socket | That SSH session predates the `docker` group. Open a new SSH session. |

**The setup link expired, and no account exists yet.** As the service user, get a new link:
`cd ~/aidenhq && sudo OWNER_EMAIL=<owner email> ops/setup.sh --unattended --link`. Add `--no-tailscale` if you
installed without Tailscale. The new link is on the line `AIDENHQ_SETUP_URL=`.

**Adding a model key later, without the browser.** Put `OPENROUTER_KEY=<key>` in a root-only `0600` file, then run
`cd ~/aidenhq && sudo OWNER_EMAIL=<owner email> ops/setup.sh --unattended --config <that file>`, adding
`--no-tailscale` if used, and delete the file afterwards. Setup prints this same command when it finishes without a
key.

**Removing AidenHQ.** `sh ~/aidenhq-install.sh --uninstall --non-interactive` stops and removes the services. It keeps
the data, the vault, the instance repo and the packages, and lists what it kept.

## 9. Hand over to the user

Clean up the helper file on the server: `rm -f ~/aidenhq-install-run.sh`, or for a root install
`ssh aidenhq@<host> 'sudo rm -f /root/aidenhq-install-run.sh'`. Make sure `~/.aidenhq-secrets.env` is gone too (the
run script deletes it). Keep `aidenhq-install.out` until the user has used the link (it is `0600`). Then show the user
this, filled in:

```
┌─ AidenHQ is installed ─────────────────────────────────────────────┐
│  Server      <host>   (service user: <service-user>)               │
│  Checks      board ok · Paperclip ok · runner ok · containers ok   │
│                                                                    │
│  1. (no Tailscale only) Keep this tunnel open on your laptop:      │
│       ssh -N -L 3121:127.0.0.1:3121 <service-user>@<host>          │
│     (With Tailscale, your laptop must be on the same tailnet.)     │
│                                                                    │
│  2. Open your one-time setup link (one use, 72 hours):             │
│       <AIDENHQ_SETUP_URL>                                          │
│     It sets your password and authenticator app, then asks for     │
│     your OpenRouter key and channels. Aiden then says hello on     │
│     your board.                                                    │
│                                                                    │
│  3. Save the vault recovery key in your password manager:          │
│       ssh <service-user>@<host>                                    │
│       sudo cat /root/aidenhq-vault-recovery.txt                    │
│       sudo shred -u /root/aidenhq-vault-recovery.txt               │
│                                                                    │
│  Logs: ~/aidenhq-install.out, journalctl --user -u aidenhq-runner  │
└────────────────────────────────────────────────────────────────────┘
```

Leave out line 1 for Tailscale installs, and line 3 if the output didn't mention a vault recovery key. Never claim
it's working unless step 7 passed. Report exactly which check failed instead.

---

More: https://aidenhq.ai/llms.txt (index for agents) · https://aidenhq.ai/index.md (what AidenHQ is). These
instructions are published at `https://aidenhq.ai/prompt.md`, so you can check them against the original at any
time.
