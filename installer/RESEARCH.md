# Installer research

We read the full source of nine one-line installers (fetched 2026-11-16, not run) and kept what makes them good. Sources:
[rustup](https://sh.rustup.rs), [Docker](https://get.docker.com), [k3s](https://get.k3s.io),
[Tailscale](https://tailscale.com/install.sh), [Ollama](https://ollama.com/install.sh),
[Coolify](https://cdn.coollabs.io/coolify/install.sh),
[Homebrew](https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh), [Deno](https://deno.land/install.sh),
[Bun](https://bun.sh/install).

## Patterns adopted

| Pattern | Where we saw it | In `install.sh` |
|---|---|---|
| Whole script in functions, `main "$@"` on the last line, so a truncated download runs nothing | Tailscale, Ollama, Docker, rustup (k3s uses a trailing `{ … }`) | yes |
| POSIX `sh` (dash on Debian/Ubuntu), not bash | rustup, Docker, k3s, Tailscale, Ollama | `#!/bin/sh`, `shellcheck -s sh` clean, tested under dash |
| `/etc/os-release` read in a subshell, `ID` then `ID_LIKE`, `UBUNTU_CODENAME` before `VERSION_CODENAME` for derivatives | Tailscale (Docker and Coolify ignore `ID_LIKE`) | yes; the kernel's `ops/vm/pins.json` says which releases are supported |
| `uname -m` mapped explicitly; anything else fails loudly | Ollama, k3s (Deno silently falls back to x86_64) | amd64 and arm64 only |
| WSL and container detection | Docker, Ollama (WSL); Ollama checks systemd is running | refuses WSL, containers and hosts without systemd as PID 1 |
| Root → sudo, with every privileged command going through one wrapper; a dry run swaps the wrapper for `echo` | Docker (`sh_c`), k3s (`$SUDO`), Tailscale | `run` / `as_root` / `as_svc`; `--dry-run` prints them |
| Explain sudo once up front; `sudo -n` when non-interactive; keep the timestamp alive | Homebrew | yes |
| Non-interactive when there is no terminal (`CI`, no tty); prompts only from `/dev/tty` | Homebrew, rustup, Deno | asks nothing by default; `exec </dev/null` so no child eats the piped script |
| Log everything to a file, keep the terminal to a step list, and on failure print the last lines and the log path from an EXIT trap | Coolify | yes; log is mode 0600 (the setup link lands there) |
| Idempotent re-runs: only write a file that would change, restart only on change | k3s (pre/post hashes), Coolify | `root_write`; the product's setup is idempotent |
| Never change existing data or settings on re-run; generate secrets only when missing | Coolify | owner's own `daemon.json` keys are left alone; setup writes `runner.yaml` |
| Verify what you download, fail on mismatch | k3s (`sha256sum` file) | release file by digest; git checkouts by exact sha (repo keys: the kernel's setup, by fingerprint) |
| Pinned versions | k3s, Tailscale, Docker (`--version`) | exact package versions come from the kernel's `ops/vm/pins.json`, installed by its setup |
| Env-var override for every default URL (mirrors, air-gapped) | k3s, Docker | `AIDENHQ_RELEASE_URL`, `AIDENHQ_RELEASE_FILE`, `AIDENHQ_GIT_BASE` |
| `curl --proto '=https' --tlsv1.2 --retry`, `wget` fallback | rustup, Tailscale | yes |
| `mktemp -d` + `trap cleanup EXIT` | k3s, Ollama, rustup | yes |
| Refuse snap Docker | Coolify | yes |
| Colour only on a TTY, `NO_COLOR` honoured, `TERM=dumb` respected | Coolify, Homebrew | yes |
| No telemetry | none of the nine phone home (Homebrew turns its own analytics off for the run) | none |
| An uninstall path | k3s (generates `k3s-uninstall.sh`) | `--uninstall`: stops and removes services, keeps data |

## Pitfalls avoided

- **Running a second installer from inside ours** (`curl get.docker.com | sh || true` in Coolify): the kernel's setup adds vendor
  apt repos directly, keyed to a pinned fingerprint, and never pipes a download into a shell.
- **Trusting a key because it came over TLS** (Docker, Tailscale): the kernel's `ops/vm/setup.sh` refuses a key whose
  primary fingerprint isn't the one in `ops/vm/pins.json`.
- **"Latest" lookups with no integrity check** (Deno, Coolify's `versions.json`): a release file is the only input, and
  its digest is baked into the tagged installer.
- **`sleep 20` "press Ctrl+C" warnings** (Docker): an existing Docker or Node at or above the minimum is kept, and the plan
  says so; nothing waits.
- **`set -e` silently off inside `if`, `&&` and `||`** (Coolify toggles it; Homebrew avoids it): functions end in a
  command that succeeds, pipelines record the real exit status in a file, and `die` is explicit.
- **Reading stdin in a piped script** (Homebrew's reference fix: `/dev/tty`): stdin is closed after argument parsing.
- **Hard root requirement** (Coolify): we run as a normal user and use sudo for system steps only; as root we create or
  choose a service user.
- **Fragile `/etc/os-release` grepping** (Coolify): we source it in a subshell.
- **Partial writes on failure** leave nothing half-done: system files go through a temp file and `install`; each step is
  safe to repeat.

## Deliberate departures

- **Line count.** The lean-core spec (§6.8, A37) asks for an installer of 150 lines or fewer. Platform detection,
  resource checks, release and checkout verification, uninstall and the handover take about 630, and the macOS VM path about 300 more (the host packages are the
  kernel's setup, not ours). Every
  extra line is a check or a pin, not a feature; the length is the cost of "minimal user intervention".
- **`kernel_repo` in the release file.** The spec's release schema has no `kernel_repo`; it needs to land in the spec.

## macOS: a Linux VM (2026-11-16)

AidenHQ's gates need Linux kernel features (bwrap user namespaces under AppArmor, pasta network namespaces, gVisor,
gocryptfs on FUSE, systemd user units), so a Mac runs it in a VM and the installer runs its own Linux path there.

| Option | Verdict | Source |
|---|---|---|
| **Lima** (`vmType: vz`, Apache-2.0) | **picked**: a CLI with no sudo, a full Ubuntu cloud image with systemd, image pinned by digest, port-forward rules, `--foreground` for launchd. vz needs macOS 13+ and is the default since Lima 1.0; guests must match the host's architecture (no Rosetta needed: arm64 Ubuntu on Apple silicon, amd64 on Intel) | [vz docs](https://lima-vm.io/docs/config/vmtype/vz/), [port docs](https://lima-vm.io/docs/config/port/) |
| Apple `container` / Containerization | not suitable: one lightweight VM per container with `vminitd` as init and a minimal kernel config, not a systemd host; recommended on macOS 26+ only | [technical overview](https://github.com/apple/container/blob/main/docs/technical-overview.md), [containerization](https://github.com/apple/containerization) |
| OrbStack | avoided: closed source; commercial use needs a paid licence | [FAQ](https://docs.orbstack.dev/faq) |
| Multipass | not picked: a `.pkg` that needs an administrator account; QEMU by default on macOS | [install docs](https://canonical.com/multipass/docs//en/latest/how-to-guides/install-multipass/) |
| UTM | not picked: a GUI app; `utmctl` lives in the app bundle and wraps AppleScript | [scripting docs](https://docs.getutm.app/scripting/scripting/) |

**Pins.** Lima v2.3.0 (published 2026-11-06, 10 days before; v2.2.1 is 2026-10-03), the GitHub release tarball checked
against its `SHA256SUMS` (Darwin-arm64 `b7af444b…`, Darwin-x86_64 `d58bc7d6…`); an existing `limactl` >= 2.0 (Homebrew's)
is used as is, and `brew install lima` is never run (unpinned). Ubuntu 24.04 cloud image `release-20261017`
(arm64 `50e24e1f…`, amd64 `04e8f246…`). Canonical serves only the last ~4 months of dated images from
`cloud-images.ubuntu.com` (checked: 7 serve, older ones 302 to `http://cloud-images-archive.ubuntu.com/…`, 3 are 404), so
bump this pin with each release cut; the digest still guards an archived download.

**Verified on a real VM** (Apple M-series, macOS 26.7.1, Lima 2.3.0, 2026-11-16), after running the product's own
`ops/vm/setup.sh` inside it:

- Ubuntu 24.04.5, kernel 6.8, systemd `running` (system and `--user` with lingering); AppArmor on with
  `kernel.apparmor_restrict_unprivileged_userns=1`.
- The runner's private bwrap (`/opt/aidenhq/bwrap/bwrap`, profile `aidenhq-bwrap`) gets a user and network namespace;
  setup's own `CAP_NET_ADMIN` self-test passes; the distro `/usr/bin/bwrap` stays blocked, as intended.
- The runner's real jail (`engines.mjs` `jailProblem` and `hiding`): pasta gives the job its own network, egress works
  (HTTP 200); an HTTP request to the Lima host gateway from the job got no answer (no control listener, so weak evidence).
- gVisor `runsc` 20261102.0 runs `hello-world` and `alpine` (kernel `4.19.0-gvisor`) with no `/dev/kvm`: no nested
  virtualization needed, so the template leaves it off.
- gocryptfs 2.4.0 init and mount over `/dev/fuse` as the user.
- After stop/start everything above still works and `limactl shell` survives setup's sshd hardening and public firewall.
- `limactl edit --cpus --memory --disk` resizes a stopped VM; the root filesystem grows with the disk; the 100–110 GB disk
  took 4 GB on the Mac.
- `mounts: []` leaves no `/Users` in the guest.

**Port forwards.** Lima forwards every guest loopback listener to the Mac's 127.0.0.1 by default. A catch-all
`guestIP: 0.0.0.0` ignore rule alone still let a guest `127.0.0.1:3120` through (Lima 2.x defaults `guestIPMustBeZero` to
true for 0.0.0.0, as its docs say). The template forwards 3121 and then ignores `127.0.0.1` and `0.0.0.0` on every port:
tested, 3121 reachable from the Mac, 3120, 3100, `0.0.0.0:5000` and `[::1]:5001` not. Host port 3121 stays 3121 because
setup pins `BOARD_LAN_HOSTS` to `127.0.0.1:3121,localhost:3121`.

**Interactive runs.** `limactl shell` gives the guest a pty only when its own stdout is a terminal (tested), so the VM's
installer writes straight to the terminal and the Mac reads the link back from a 0600 file in the VM
(`~/.aidenhq/setup-url`); tested under `script`: the guest saw a tty and `/dev/tty`.

**Start at login and sleep.** The LaunchAgent mirrors the plist `limactl autostart` writes (`limactl start <vm>
--foreground`, `KeepAlive` on failure only), so launchd owns the host agent; tested: the VM stays up, `limactl stop` exits
0 and isn't restarted, a changed plist is booted out and reloaded. Keeping awake wraps that command in `caffeinate -s`: a
process assertion held only while the VM runs and only on AC power, gone with the agent; no `pmset` change (system-wide,
needs sudo). Closing a laptop's lid sleeps it regardless, and sleep pauses every agent. `caffeinate` passes SIGTERM on to its child
(tested), so a bootout or logout still stops the VM cleanly. A LaunchAgent runs at login, not at boot.

**Found on the way (product, not fixed here):** `ops/vm/setup.sh` installs the amd64 `gh` .deb on every host, so it
fails on arm64 (Apple silicon VMs, and arm64 servers): `package architecture (amd64) does not match system (arm64)`. The
test VM used the arm64 .deb (`cac3ff84…`). The product assumes amd64 hosts elsewhere too: `ops/vm/setup.sh` installs
agent-browser's `linux-x64` binary and Chrome for Testing `linux64` (no error, but no browser on arm64),
`ops/backup-offsite.sh` downloads restic `linux_amd64`, and `scripts/supply-chain/image-scan.mjs` says "CI and the hosts
are amd64". Until those carry arm64 pins, a full install on Apple silicon stops in host setup; Intel Macs (amd64 guests)
don't hit this.
