# Install AidenHQ

On a Linux server or VM with SSH access:

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

It checks the machine, asks for your email (the board's owner account), fetches and verifies the release, runs the
product's unattended setup (which installs the host packages and starts AidenHQ) and prints one link. Everything after
that happens in your browser: your password and authenticator, your model key, your channels.

`get.aidenhq.ai` redirects to the tagged release asset
(`https://github.com/Aiden-HQ/aidenhq-distro/releases/download/<release>/install.sh`). To read the script before running it:

```sh
curl -fsSLo install.sh https://get.aidenhq.ai && less install.sh && sh install.sh
```

## What you need

| | Minimum (refused below) | Recommended |
|---|---|---|
| OS | Ubuntu 22.04, 24.04 or 26.04; Debian 12 or 13 (apt only: other package managers are refused up front) | Ubuntu 24.04 |
| CPU | 2 cores, amd64 or arm64 | 4 or more |
| RAM | 6 GB | 8 GB or more |
| Free disk | 60 GB | a 100 GB disk |
| Init | systemd as PID 1 (not WSL, not a container) | |

macOS and Windows can't host AidenHQ; use a Linux VM.

## Options

Pass options with `sh -s --`, for example `curl -fsSL https://get.aidenhq.ai | sh -s -- --dry-run`. Each option also
has an environment form.

| Flag | Environment | |
|---|---|---|
| `--release <name>` | `AIDENHQ_RELEASE` | release to install (default: the one the script was cut with) |
| `--dir <path>` | `AIDENHQ_DIR` | product checkout (default `~<user>/aidenhq`) |
| `--non-interactive` | `AIDENHQ_NON_INTERACTIVE=1` | never wait on a terminal (implied when there is none) |
| `--dry-run` | `AIDENHQ_DRY_RUN=1` | detect and print the plan; change nothing |
| `--no-tailscale` | `AIDENHQ_NO_TAILSCALE=1` | skip Tailscale: the board stays on the server's loopback and the installer prints the SSH tunnel to reach it |
| `--uninstall` | `AIDENHQ_UNINSTALL=1` | stop and remove the services; keep data, vault, instance repo and packages |
| `--verbose` | `AIDENHQ_VERBOSE=1` | stream every command's output |

Other inputs:

- `AIDENHQ_OWNER_EMAIL`: the email of the board's owner account. Asked for on a terminal when unset; with no terminal
  the installer refuses before changing anything.
- `AIDENHQ_OWNER_NAME`: the owner's name (default: the service user's name).
- `AIDENHQ_USER`: the service user when you run as root. The default is `aidenhq`, created with passwordless sudo and root's SSH keys,
  because setup turns off root SSH login.
- `OPENROUTER_KEY` (or `OPENROUTER_MANAGEMENT_KEY`) and `TS_AUTHKEY`: optional secrets. They go to the product's setup in a
  root-only config file (deleted afterwards) and are never printed. Without a model key the browser steps ask for it; without
  `TS_AUTHKEY` a terminal shows Tailscale's sign-in link (a host already on the tailnet needs neither).
- `AIDENHQ_GITHUB_TOKEN`: a token for private repos.
- `AIDENHQ_RELEASE_FILE`, `AIDENHQ_RELEASE_URL`, `AIDENHQ_GIT_BASE`: for mirrors, air-gapped installs and tests.

## Re-runs, logs and removal

- **Re-runs.** Running the script again is safe: every step, including the product's setup, is idempotent, and every
  checkout is re-verified before anything in it runs.
- **Logs.** The log is `/var/log/aidenhq-install.log` when run as root, otherwise `~/.aidenhq/install.log` (mode 0600). On
  failure the installer prints the step, the last log lines and the log path.
- **Removal.** `--uninstall` stops and removes the services and lists what it kept.

## What it sets from the machine

| | Rule | 4 vCPU, 8 GB, 100 GB | 20 threads, 64 GB, 460 GB |
|---|---|---|---|
| Runner `max_concurrent` (setup's `MAX_CONCURRENT`) | min(cores − 2, (RAM GB − 4) / 1.5), 1..16 | 2 | 16 |
| Runner `timeout_minutes` (`TIMEOUT_MINUTES`) | 60 up to 4 jobs, 90 up to 8, else 120 | 60 | 120 |
| CI runners (`CI_RUNNERS`) | min((cores − 2) / 4, (RAM GB − 4) / 4), 1..4; started by setup once the GitHub App exists | 1 | 4 |
| Disk reserve (disk guard prunes below it, every 15 min) | max(15 GB, 10% of disk) | 15 GB | 45 GB |
| Docker build cache GC | 10% of disk, 10..50 GB | 10 GB | 45 GB |
| Container logs | json-file 10m × 3; 50m × 5 on disks of 200 GB or more | 10m × 3 | 50m × 5 |
| journald cap | 1 GB; 2 GB on disks of 200 GB or more | 1G | 2G |

The three sizing values go to the product's setup in its environment; setup writes them to `config/runner.yaml` and the
CI runner units. Docker settings are added only where `daemon.json` doesn't already set them. The product's weekly
`prune-docker.timer` is turned on.

## Trust

The installer is the one `curl | sh` the project allows. It is served only from a tagged release, and it verifies
everything it fetches:

- the default release's file, against the digest baked into the tagged script (another `--release` relies on its tag
  and the sha checks below);
- the kernel and each module, at the exact sha (HEAD must equal the pin, with no tracked changes);
- the host packages are not the installer's: the verified kernel's own `ops/vm/setup.sh` installs them from the key
  fingerprints, repositories and exact versions in its `ops/vm/pins.json`.

Before root runs the product's setup, the installer verifies the checkout again, this time as root, against a
root-owned clone. That check ignores the service user's `.git` and any replace refs. Secrets reach setup only in a config
file that `mktemp` creates as a new root-owned 0600 file in `/run`, deleted afterwards; every value is checked first: no quotes,
`$`, backticks or control characters. Tokens are only ever sent with curl, which doesn't pass them on through redirects to
another host.

It sends no telemetry.

`releases/2026.11.json` holds placeholder shas until the first release is cut, so a real run refuses it.

## Test

```sh
sh installer/test.sh     # offline: release verification passes, and each kind of tampering stops it
```
