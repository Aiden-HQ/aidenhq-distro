# Install AidenHQ

On a Linux server or VM with SSH access:

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

It checks the machine, asks for your email (the board's owner account), fetches and verifies the release, runs the
product's unattended setup (which installs the host packages and starts AidenHQ) and prints one link (plus the machine-readable `AIDENHQ_SETUP_URL=` line, and `AIDENHQ_SSH_TUNNEL=` with `--no-tailscale`, for scripts and agents). Along the way it prints `AIDENHQ_PROGRESS=<n>/<total> <percent>% <step> ~<minutes left>` lines (the percent never goes down and reaches 100 just before the link; the weights are estimates in one table at the top of `install.sh`). Everything after
that happens in your browser: your password and authenticator, your model key, your channels.

`get.aidenhq.ai` is a Cloudflare Worker (`web/worker.js`) that serves one tagged release's `install.sh` (its release file's digest baked in) as `text/plain`, only if it matches the sha256 pinned beside the tag in `wrangler.jsonc`. To read the script before running it:

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

Windows can't host AidenHQ; use a Linux VM. On a Mac, run the same command: it makes the Linux VM for you (see
[On a Mac](#on-a-mac)).

## On a Mac

AidenHQ's security gates need Linux (bwrap user namespaces, pasta, gVisor, the gocryptfs vault, systemd, AppArmor), so on
macOS the installer makes an Ubuntu 24.04 VM named `aidenhq` with [Lima](https://lima-vm.io) on Apple's Virtualization
framework and runs its own Linux path inside it, unchanged. It never uses sudo on the Mac.

- **Needs** macOS 13 or later, Apple silicon or Intel, 12 GB of memory or more (16 GB recommended) and 60 GB free.
- **Lima**: an existing `limactl` 2.0 or newer (Homebrew's, say) is used; otherwise Lima 2.3.0 is downloaded from its GitHub
  release, checked against a pinned sha256 and unpacked into `~/.aidenhq/lima`. The Ubuntu cloud image is pinned by sha256 too.
- **Size**: half the Mac's cores (4 to 8) and half its memory (8 to 16 GB, leaving macOS at least 4), and a 100 GB disk
  that is a sparse file in `~/.lima/aidenhq` (it takes only what is used). Override when the VM is made with
  `AIDENHQ_VM_CPUS`, `AIDENHQ_VM_MEMORY` and `AIDENHQ_VM_DISK` (GB). Later: `limactl stop aidenhq`,
  `limactl edit aidenhq --cpus 6 --memory 12 --disk 150` (the disk only grows), then run the installer again (it starts
  the VM under its login agent).
- **Isolation**: no Mac folder is shared with the VM, and only the board's port 3121 is forwarded, to the Mac's localhost;
  every other port stays inside the VM.
- **The link**: with `--no-tailscale` the setup link is `http://127.0.0.1:3121/setup/...`: open it on the Mac, no tunnel.
  With Tailscale the VM joins your tailnet as its own machine and the link is its tailnet address.
- **Secrets** (`OPENROUTER_KEY`, `TS_AUTHKEY`, `AIDENHQ_GITHUB_TOKEN`, ...) go into the VM over stdin as a 0600 file that
  is sourced and shredded there: never on a command line, never in Lima's config.
- **Start at login**: a LaunchAgent, `~/Library/LaunchAgents/ai.aidenhq.vm.plist`, runs `limactl start aidenhq
  --foreground`. `limactl stop aidenhq` stops the VM until the next login or installer run.
- **Sleep**: a Mac that sleeps pauses every agent. The installer asks once whether to keep the Mac awake while the VM
  runs (`AIDENHQ_KEEP_AWAKE=1` or `0` without a terminal; the default there is no). Yes runs the VM under
  `caffeinate -s`, which holds off system sleep on power only, while the VM runs; it changes no power settings, and
  closing a laptop's lid or running on battery still sleeps it. Run the installer again with `AIDENHQ_KEEP_AWAKE=0` to undo it.
- **Uninstall**: `--uninstall` deletes the VM and, with it, everything AidenHQ kept there (data, vault, instance checkout),
  unlike on Linux where data stays. It asks you to type `delete`; without a terminal it needs `AIDENHQ_CONFIRM_DELETE_VM=1`.
  It keeps Lima's image cache (`~/Library/Caches/lima`) and a Lima you installed yourself.

## Options

Pass options with `sh -s --`, for example `curl -fsSL https://get.aidenhq.ai | sh -s -- --dry-run`. Each option also
has an environment form.

| Flag | Environment | |
|---|---|---|
| `--release <name>` | `AIDENHQ_RELEASE` | release to install (default and only: the one the script was cut with; each release's own `install.sh` installs it) |
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
  root-only config file (deleted afterwards) and are never printed. Without a model key the first-run page asks for it; without
  `TS_AUTHKEY` a host off the tailnet keeps the board on loopback, reached through the SSH tunnel the installer prints.
- `AIDENHQ_GITHUB_TOKEN`: a token for private repos. Setup gets it in its own root-only file for its one fetch; it is never
  written into the checkout.
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

- the release file, against the sha256 baked into the tagged script when the release was cut (a release the script
  wasn't cut for, or an uncut copy, is refused unless you pass a local `AIDENHQ_RELEASE_FILE`);
- the kernel and each module, at the exact sha (HEAD must equal the pin, with no tracked changes);
- the host packages are not the installer's: the verified kernel's own `ops/vm/setup.sh` installs them from the key
  fingerprints, repositories and exact versions in its `ops/vm/pins.json`.

Before root runs the product's setup, the installer verifies the checkout again, this time as root, against a
root-owned clone. That check ignores the service user's `.git` and any replace refs. Secrets reach setup only in a config
file that `mktemp` creates as a new root-owned 0600 file in `/run`, deleted afterwards; every value is checked first: no quotes,
`$`, backticks or control characters. Tokens are only ever sent with curl, which doesn't pass them on through redirects to
another host.

It sends no telemetry.

The new instance pins the release it was installed from (`release:` in `instance.yaml`, with the distro commit it was cut
from); every apply reads that file again at that commit and refuses a kernel other than the release's.

## Releases

A release is cut by pushing its tag (`2026.11`, patch releases `2026.11.1`) on a `main` commit whose `releases/<tag>.json`
names real shas. `.github/workflows/release.yml` then installs exactly that set on GitHub-hosted runners (this script's own fetch
and verify), runs the release suites on it, writes `tested`, bakes the file's sha256 and the commit into `install.sh` and
publishes both as the release's assets (a draft until they are checked), then opens a PR pinning `get.aidenhq.ai` to that `install.sh` by tag and sha256; merging it deploys the site. Never
to a branch.

`releases/2026.11.json` holds placeholder shas until the first release is cut, so a real run refuses it.

## Test

```sh
sh installer/test.sh     # offline: release verification passes, each kind of tampering stops it; the macOS path with stubs
```
