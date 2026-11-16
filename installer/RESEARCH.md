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
| `/etc/os-release` read in a subshell, `ID` then `ID_LIKE`, `UBUNTU_CODENAME` before `VERSION_CODENAME` for derivatives | Tailscale (Docker and Coolify ignore `ID_LIKE`) | yes; an explicit codename table drives the vendor repo pins |
| `uname -m` mapped explicitly; anything else fails loudly | Ollama, k3s (Deno silently falls back to x86_64) | amd64 and arm64 only |
| WSL and container detection | Docker, Ollama (WSL); Ollama checks systemd is running | refuses WSL, containers and hosts without systemd as PID 1 |
| Root → sudo, with every privileged command going through one wrapper; a dry run swaps the wrapper for `echo` | Docker (`sh_c`), k3s (`$SUDO`), Tailscale | `run` / `as_root` / `as_svc`; `--dry-run` prints them |
| Explain sudo once up front; `sudo -n` when non-interactive; keep the timestamp alive | Homebrew | yes |
| Non-interactive when there is no terminal (`CI`, no tty); prompts only from `/dev/tty` | Homebrew, rustup, Deno | asks nothing by default; `exec </dev/null` so no child eats the piped script |
| Log everything to a file, keep the terminal to a step list, and on failure print the last lines and the log path from an EXIT trap | Coolify | yes; log is mode 0600 (the setup link lands there) |
| Idempotent re-runs: only write a file that would change, restart only on change | k3s (pre/post hashes), Coolify | `root_write` + a per-release state file to resume |
| Never change existing data or settings on re-run; generate secrets only when missing | Coolify | owner's own `daemon.json` keys and a tuned `runner.yaml` are left alone |
| Verify what you download, fail on mismatch | k3s (`sha256sum` file) | release file by digest; git checkouts by exact sha; repo keys by fingerprint |
| Pinned versions | k3s, Tailscale, Docker (`--version`) | exact package versions come from the release file's `host` pins |
| Env-var override for every default URL (mirrors, air-gapped) | k3s, Docker | `AIDENHQ_RELEASE_URL`, `AIDENHQ_RELEASE_FILE`, `AIDENHQ_GIT_BASE` |
| `curl --proto '=https' --tlsv1.2 --retry`, `wget` fallback | rustup, Tailscale | yes |
| `mktemp -d` + `trap cleanup EXIT` | k3s, Ollama, rustup | yes |
| Refuse snap Docker | Coolify | yes |
| Colour only on a TTY, `NO_COLOR` honoured, `TERM=dumb` respected | Coolify, Homebrew | yes |
| No telemetry | none of the nine phone home (Homebrew turns its own analytics off for the run) | none |
| An uninstall path | k3s (generates `k3s-uninstall.sh`) | `--uninstall`: stops and removes services, keeps data |

## Pitfalls avoided

- **Running a second installer from inside ours** (`curl get.docker.com | sh || true` in Coolify): we add vendor apt repos
  directly, keyed to a pinned fingerprint, and never pipe a download into a shell.
- **Trusting a key because it came over TLS** (Docker, Tailscale): `add_key` refuses a key whose primary fingerprint
  isn't the pinned one. Fingerprints checked with `gpg --show-keys` on 2026-11-16: Docker apt
  `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`, Docker rpm `060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35`,
  NodeSource `6F71 F525 2828 41EE DAF8 51B4 2F59 B5F9 9B1B E0B4`, Tailscale (apt and rpm)
  `2596 A99E AAB3 3821 893C 0A79 458C A832 957F 5868`.
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
  pinned vendor repos for five releases, resource checks, resume, uninstall and the handover take about 820. Every
  extra line is a check or a pin, not a feature; the length is the cost of "minimal user intervention".
- **Host pins in the release file.** The spec's release schema has no `host` section. We add one (`docker`,
  `containerd`, `buildx`, `compose`, `node`, `tailscale`) so one tested file pins both the code and the host packages,
  and add `kernel_repo`. Both fields need to land in the spec.
