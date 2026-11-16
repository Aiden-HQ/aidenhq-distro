#!/bin/sh
# shellcheck disable=SC2016  # single-quoted sh -c bodies and $releasever are meant literally
# AidenHQ installer: turns a Linux server into a running AidenHQ, then hands you one link for the rest.
#
#   curl -fsSL https://get.aidenhq.dev | sh
#   curl -fsSL https://get.aidenhq.dev | sh -s -- --dry-run          # print the plan, change nothing
#
# Flags (each has an environment form):
#   --release <name>    AIDENHQ_RELEASE          release to install (default: the one this script was cut with)
#   --dir <path>        AIDENHQ_DIR              product checkout (default: ~<user>/aidenhq)
#   --non-interactive   AIDENHQ_NON_INTERACTIVE=1  never wait on a terminal (implied when there is none)
#   --dry-run           AIDENHQ_DRY_RUN=1        detect and plan only
#   --no-tailscale      AIDENHQ_NO_TAILSCALE=1   skip Tailscale
#   --uninstall         AIDENHQ_UNINSTALL=1      stop and remove services; keeps data, vault and packages
#   --verbose           AIDENHQ_VERBOSE=1        stream every command's output, not just the steps
# Other inputs: AIDENHQ_USER (service user when run as root; default aidenhq), AIDENHQ_GITHUB_TOKEN (private repos),
# AIDENHQ_RELEASE_FILE / AIDENHQ_RELEASE_URL / AIDENHQ_GIT_BASE (mirrors, air-gapped installs and tests).
# Until the product's setup is unattended (INSTALL.md), it also needs AIDENHQ_OWNER_EMAIL and OPENROUTER_KEY (or
# OPENROUTER_MANAGEMENT_KEY), and TS_AUTHKEY when no terminal is attached.
#
# No telemetry. Everything it fetches is pinned: the release file by digest, git checkouts by sha, apt repos by key
# fingerprint and packages by exact version. The whole script is functions; nothing runs until the last line, so a
# truncated download does nothing.
set -eu

DEFAULT_RELEASE=2026.11
RELEASE_SHA256=""   # set by the release cut for DEFAULT_RELEASE; empty = not cut yet (the file's own sha checks still run)
DISTRO_REPO=Aiden-HQ/aidenhq-distro
FPR_DOCKER=9DC858229FC7DD38854AE2D88D81803C0EBFCD88       # download.docker.com/linux/{ubuntu,debian}/gpg
FPR_DOCKER_RPM=060A61C51B558A7F742B77AAC52FEB6B621E9F35   # download.docker.com/linux/{fedora,centos}/gpg
FPR_NODESOURCE=6F71F525282841EEDAF851B42F59B5F99B1BE0B4   # deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
FPR_TAILSCALE=2596A99EAAB33821893C0A79458CA832957F5868    # pkgs.tailscale.com (apt and rpm)
MIN_CORES=2 WARN_CORES=4 MIN_RAM_MB=5800 WARN_RAM_MB=7400 MIN_DISK_GB=60 WARN_DISK_GB=90
MIN_DOCKER=28.0 MIN_COMPOSE=2.33 MIN_NODE=24.0 MIN_GIT=2.30

# ------------------------------------------------------------------------------------------------ output and logging
setup_ui() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    B=$(printf '\033[1m') G=$(printf '\033[32m') Y=$(printf '\033[33m') R=$(printf '\033[31m') D=$(printf '\033[2m') N=$(printf '\033[0m')
  else B='' G='' Y='' R='' D='' N=''; fi
}
log() { [ -n "${LOG:-}" ] && printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >>"$LOG" 2>/dev/null || :; }
step() { STEP="$*"; log "== $*"; printf '%s==>%s %s%s%s\n' "$G" "$N" "$B" "$*" "$N"; }
say() { log "$*"; printf '    %s\n' "$*"; }
warn() { log "WARN $*"; printf '    %swarning:%s %s\n' "$Y" "$N" "$*" >&2; }
die() { log "ERROR $*"; printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
refuse() { REFUSALS="${REFUSALS}    - $*
"; log "REFUSE $*"; }

on_exit() {
  rc=$?
  [ -n "${KEEPALIVE:-}" ] && kill "$KEEPALIVE" 2>/dev/null
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
  [ "$rc" = 0 ] && return 0
  [ -n "${STEP:-}" ] || return 0   # refused before any step: the message said it all
  printf '\n%sInstall stopped%s during: %s\n' "$R" "$N" "${STEP:-start}" >&2
  if [ -n "${LOG:-}" ] && [ -s "$LOG" ]; then
    printf '%sLast lines of %s:%s\n' "$D" "$LOG" "$N" >&2; tail -n 15 "$LOG" | sed 's/^/    /' >&2
  fi
  printf 'Fix the cause and run the same command again: it resumes where it stopped.\n' >&2
}

# run CMD...: a change. Dry run prints it; otherwise its output goes to the log (and the terminal with --verbose).
run() {
  if [ "$DRY" = 1 ]; then printf '    %swould run:%s %s\n' "$D" "$N" "$*"; return 0; fi
  log "+ $*"
  if [ "$VERBOSE" = 1 ]; then
    { "$@" 2>&1 && echo 0 >"$TMPD/rc" || echo $? >"$TMPD/rc"; } | tee -a "$LOG"; return "$(cat "$TMPD/rc")"
  fi
  "$@" >>"$LOG" 2>&1
}
as_root() { if [ -n "$SUDO" ]; then run "$SUDO" "$@"; else run "$@"; fi; }
# as_svc CMD...: as the service user (root invocations drop to it so every file in its home is its own).
as_svc() {
  if [ "$(id -un)" = "$SVC" ]; then run "$@"
  else run runuser -u "$SVC" -- env HOME="$SVC_HOME" XDG_RUNTIME_DIR="/run/user/$SVC_UID" "$@"; fi
}
root_write() { # path mode < content: writes a system file only when it would change; returns 0 when it changed
  cat >"$TMPD/w"
  if [ -f "$1" ] && cmp -s "$TMPD/w" "$1"; then return 1; fi
  if [ "$DRY" = 1 ]; then printf '    %swould write:%s %s\n' "$D" "$N" "$1"; return 0; fi
  log "write $1"; $SUDO install -D -m "$2" "$TMPD/w" "$1"
}
have() { command -v "$1" >/dev/null 2>&1; }
# ugit ARGS: a read of a service-user repo (root reading it as root trips git's "dubious ownership").
ugit() { if [ "$(id -un)" = "$SVC" ]; then git "$@"; else runuser -u "$SVC" -- git "$@"; fi; }
ver_ge() { # A >= B, dotted numbers
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$2" ]
}
fetch() { # url dest [header-file]
  if have curl; then curl -fsSL --proto '=https' --tlsv1.2 --retry 3 ${3:+-H "@$3"} -o "$2" "$1"
  elif have wget; then wget -q ${3:+--header="$(cat "$3")"} -O "$2" "$1"
  else return 127; fi
}
sha256() { if have sha256sum; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# ------------------------------------------------------------------------------------------------ arguments
parse_args() {
  REL="${AIDENHQ_RELEASE:-$DEFAULT_RELEASE}" DIR="${AIDENHQ_DIR:-}" NONINT="${AIDENHQ_NON_INTERACTIVE:-0}"
  DRY="${AIDENHQ_DRY_RUN:-0}" NO_TS="${AIDENHQ_NO_TAILSCALE:-0}" UNINSTALL="${AIDENHQ_UNINSTALL:-0}"
  VERBOSE="${AIDENHQ_VERBOSE:-0}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --release) [ $# -ge 2 ] || die "--release needs a name"; REL="$2"; shift ;;
      --release=*) REL="${1#*=}" ;;
      --dir) [ $# -ge 2 ] || die "--dir needs a path"; DIR="$2"; shift ;;
      --dir=*) DIR="${1#*=}" ;;
      --non-interactive|-y|--yes) NONINT=1 ;;
      --dry-run) DRY=1 ;;
      --no-tailscale) NO_TS=1 ;;
      --uninstall) UNINSTALL=1 ;;
      --verbose|-v) VERBOSE=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done
  case "$REL" in *[!0-9.]*|'') die "release names look like 2026.11 or 2026.11.1, not '$REL'" ;; esac
  for v in DRY NO_TS UNINSTALL VERBOSE NONINT; do eval "case \$$v in 1|true|yes) $v=1 ;; *) $v=0 ;; esac"; done
  # No terminal to wait on: curl | sh in CI, cloud-init, or ssh without -t.
  if ! { [ -t 0 ] || (: </dev/tty) 2>/dev/null; }; then NONINT=1; fi
}
usage() {
  printf '%s\n' 'AidenHQ installer: curl -fsSL https://get.aidenhq.dev | sh -s -- [options]' \
    '  --release <name>   release to install (AIDENHQ_RELEASE; default '"$DEFAULT_RELEASE"')' \
    '  --dir <path>       product checkout (AIDENHQ_DIR; default ~<user>/aidenhq)' \
    '  --non-interactive  never wait on a terminal (AIDENHQ_NON_INTERACTIVE=1)' \
    '  --dry-run          detect and plan only (AIDENHQ_DRY_RUN=1)' \
    '  --no-tailscale     skip Tailscale (AIDENHQ_NO_TAILSCALE=1)' \
    '  --uninstall        stop and remove services, keep data (AIDENHQ_UNINSTALL=1)' \
    '  --verbose          stream every command (AIDENHQ_VERBOSE=1)' \
    'More: https://github.com/'"$DISTRO_REPO"'/blob/main/INSTALL.md'
}

# ------------------------------------------------------------------------------------------------ detection
detect_platform() {
  case "$(uname -s)" in
    Linux) ;;
    Darwin) die "macOS can't host AidenHQ. Use a Linux server or VM (Ubuntu 24.04 recommended), then run this there." ;;
    MINGW*|MSYS*|CYGWIN*|Windows*) die "Windows can't host AidenHQ. Use a Linux server or VM (Ubuntu 24.04 recommended)." ;;
    *) die "$(uname -s) isn't supported. Use a Linux server or VM (Ubuntu 24.04 recommended)." ;;
  esac
  if grep -qi microsoft /proc/version 2>/dev/null; then
    die "WSL can't host AidenHQ (it needs its own systemd, Docker and AppArmor). Use a Linux server or VM."
  fi
  case "$(uname -m)" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) die "CPU architecture $(uname -m) isn't supported (amd64 and arm64 are)." ;;
  esac
  [ -r /etc/os-release ] || die "no /etc/os-release: can't tell which Linux this is"
  # shellcheck disable=SC1091
  OS_ID=$(. /etc/os-release; echo "${ID:-}") OS_LIKE=$(. /etc/os-release; echo "${ID_LIKE:-}")
  # shellcheck disable=SC1091
  OS_VER=$(. /etc/os-release; echo "${VERSION_ID:-}") OS_NAME=$(. /etc/os-release; echo "${PRETTY_NAME:-$ID}")
  # shellcheck disable=SC1091
  CODENAME=$(. /etc/os-release; echo "${UBUNTU_CODENAME:-${DEBIAN_CODENAME:-${VERSION_CODENAME:-}}}")
  # Debian-family releases we pin for: codename -> the vendor repos' distro and version.
  case "$CODENAME" in
    jammy) BASE=ubuntu BASE_VER=22.04 ;; noble) BASE=ubuntu BASE_VER=24.04 ;; resolute) BASE=ubuntu BASE_VER=26.04 ;;
    bookworm) BASE=debian BASE_VER=12 ;; trixie) BASE=debian BASE_VER=13 ;; *) BASE='' BASE_VER='' ;;
  esac
  TIER=''
  case " $OS_ID $OS_LIKE " in
    *" ubuntu "*|*" debian "*)
      PM=apt
      if [ -n "$BASE" ] && { [ "$OS_ID" = ubuntu ] || [ "$OS_ID" = debian ]; }; then TIER=first
      elif [ -n "$BASE" ]; then TIER=best
      fi ;;
    *" fedora "*|*" rhel "*|*" centos "*) PM=dnf TIER=best ;;
    *" arch "*) PM=pacman TIER=best ;;
    *) PM='' ;;
  esac
  [ -n "$TIER" ] || die "$OS_NAME isn't supported. Supported: Ubuntu 22.04/24.04/26.04, Debian 12/13 (best effort: Fedora/RHEL family, Arch)."
  pmbin=$PM; [ "$PM" = apt ] && pmbin=apt-get
  have "$pmbin" || die "package manager $PM not found on $OS_NAME"
  IN_CONTAINER=0
  { [ -f /.dockerenv ] || [ -f /run/.containerenv ]; } && IN_CONTAINER=1
  if [ -d /run/systemd/system ]; then SYSTEMD=1; else SYSTEMD=0; fi
  :
}

detect_resources() {
  CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
  RAM_MB=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
  # Free space where the bulk lands: Docker's data root (images ~25 GB) and the checkout's filesystem.
  DOCKER_ROOT=/var/lib/docker
  have docker && DOCKER_ROOT=$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo /var/lib/docker)
  DISK_GB=999999 DISK_TOTAL_GB=999999
  for p in "$DOCKER_ROOT" "$DIR"; do
    while [ ! -d "$p" ]; do p=$(dirname "$p"); done
    # shellcheck disable=SC2046
    set -- $(df -Pk "$p" | awk 'NR==2 { print int($4 / 1048576), int($2 / 1048576) }')
    [ "$1" -lt "$DISK_GB" ] && DISK_GB=$1
    [ "$2" -lt "$DISK_TOTAL_GB" ] && DISK_TOTAL_GB=$2
  done
  :
}

# Defaults derived from the machine. Calibrated on two real hosts: the minimum VM (4 vCPU, 8 GB) gives the runner's
# shipped 2 jobs / 60 min, the 20-thread / 64 GB EX44 its tuned 16 / 120. The stack itself (Paperclip, board,
# warehouse, gateway, apps) keeps ~2 cores and ~4 GB; an Engineer job wants ~1 core and ~1.5 GB.
derive_defaults() {
  ram_gb10=$((RAM_MB * 10 / 1024))                     # tenths of a GiB, integer maths only
  by_cpu=$((CORES - 2)) by_ram=$(((ram_gb10 - 40) / 15))
  MAX_CONCURRENT=$by_cpu; [ "$by_ram" -lt "$MAX_CONCURRENT" ] && MAX_CONCURRENT=$by_ram
  [ "$MAX_CONCURRENT" -lt 1 ] && MAX_CONCURRENT=1; [ "$MAX_CONCURRENT" -gt 16 ] && MAX_CONCURRENT=16
  # More jobs at once share the machine, so each takes longer: the timeout grows with concurrency.
  if [ "$MAX_CONCURRENT" -le 4 ]; then JOB_TIMEOUT=60; elif [ "$MAX_CONCURRENT" -le 8 ]; then JOB_TIMEOUT=90; else JOB_TIMEOUT=120; fi
  # CI runners (the ci module, once the GitHub App is set up): each builds images, ~4 cores and ~4 GB.
  CI_RUNNERS=$(((CORES - 2) / 4)); ci_ram=$(((ram_gb10 - 40) / 40))
  [ "$ci_ram" -lt "$CI_RUNNERS" ] && CI_RUNNERS=$ci_ram
  [ "$CI_RUNNERS" -lt 1 ] && CI_RUNNERS=1; [ "$CI_RUNNERS" -gt 4 ] && CI_RUNNERS=4
  # Disk: keep a reserve free (max of 15 GB and 10%), cap Docker's build cache, rotate container logs, cap the journal.
  DISK_RESERVE_GB=$((DISK_TOTAL_GB / 10)); [ "$DISK_RESERVE_GB" -lt 15 ] && DISK_RESERVE_GB=15
  BUILD_CACHE_GB=$((DISK_TOTAL_GB / 10)); [ "$BUILD_CACHE_GB" -lt 10 ] && BUILD_CACHE_GB=10
  [ "$BUILD_CACHE_GB" -gt 50 ] && BUILD_CACHE_GB=50
  if [ "$DISK_TOTAL_GB" -ge 200 ]; then LOG_MAX=50m LOG_FILES=5 JOURNAL_MAX=2G; else LOG_MAX=10m LOG_FILES=3 JOURNAL_MAX=1G; fi
}

check_minimums() {
  [ "$CORES" -lt "$MIN_CORES" ] && refuse "$CORES CPU core(s); AidenHQ needs at least $MIN_CORES (4 recommended)"
  [ "$CORES" -ge "$MIN_CORES" ] && [ "$CORES" -lt "$WARN_CORES" ] && warn "$CORES cores: it runs, but slowly; 4 or more recommended"
  [ "$RAM_MB" -lt "$MIN_RAM_MB" ] && refuse "$RAM_MB MB of RAM; AidenHQ needs at least 6 GB (8 GB recommended)"
  [ "$RAM_MB" -ge "$MIN_RAM_MB" ] && [ "$RAM_MB" -lt "$WARN_RAM_MB" ] && warn "$RAM_MB MB of RAM: tight; 8 GB recommended"
  [ "$DISK_GB" -lt "$MIN_DISK_GB" ] && refuse "$DISK_GB GB free disk; the images alone take ~25 GB and a 40 GB disk fills during the first build: need $MIN_DISK_GB GB free (100 GB disk recommended)"
  [ "$DISK_GB" -ge "$MIN_DISK_GB" ] && [ "$DISK_GB" -lt "$WARN_DISK_GB" ] && warn "$DISK_GB GB free disk: enough to start; 100 GB recommended"
  [ "$SYSTEMD" = 1 ] || refuse "systemd isn't running (PID 1); AidenHQ runs as systemd services"
  [ "$IN_CONTAINER" = 1 ] && refuse "this is a container; AidenHQ needs a real server or VM (it runs Docker and systemd itself)"
  if have snap && snap list docker >/dev/null 2>&1; then refuse "Docker is installed as a snap; remove it (sudo snap remove docker) so the installer can add Docker Engine"; fi
  [ "$SYSTEMD" = 1 ] && ! have loginctl && refuse "loginctl is missing: AidenHQ's user services need systemd-logind lingering"
  :
}

# ------------------------------------------------------------------------------------------------ users and privilege
resolve_user() {
  if [ "$(id -u)" = 0 ]; then
    SUDO='' SVC="${AIDENHQ_USER:-aidenhq}"
  else
    SUDO=sudo SVC="$(id -un)"
    [ -z "${AIDENHQ_USER:-}" ] || [ "$AIDENHQ_USER" = "$SVC" ] || die "AIDENHQ_USER only applies when run as root"
  fi
  case "$SVC" in root) die "AidenHQ runs as a normal user; set AIDENHQ_USER" ;; *[!a-z0-9_-]*|'') die "AIDENHQ_USER must be a plain user name" ;; esac
  if id "$SVC" >/dev/null 2>&1; then
    SVC_HOME=$(getent passwd "$SVC" | cut -d: -f6) SVC_UID=$(id -u "$SVC") NEW_USER=0
  else SVC_HOME="/home/$SVC" SVC_UID='?' NEW_USER=1; fi
  [ -n "$DIR" ] || DIR="$SVC_HOME/aidenhq"
  STATE_DIR="$SVC_HOME/.aidenhq" STATE="$SVC_HOME/.aidenhq/install.state"
}

open_log() {
  if [ "$DRY" = 1 ]; then LOG="$TMPD/dry-run.log"
  elif [ "$(id -u)" = 0 ]; then LOG=/var/log/aidenhq-install.log
  else LOG="$HOME/.aidenhq/install.log"; mkdir -p "$HOME/.aidenhq" 2>/dev/null || LOG="$TMPD/install.log"; fi
  # 0600: the one-time setup link lands here.
  (umask 077; : >>"$LOG") && chmod 600 "$LOG" 2>/dev/null || LOG="$TMPD/install.log"
  log "AidenHQ installer, release $REL, args: dry=$DRY nonint=$NONINT no_ts=$NO_TS uninstall=$UNINSTALL"
}

ensure_sudo() {
  [ -n "$SUDO" ] || return 0
  if ! have sudo; then
    [ "$DRY" = 1 ] || die "run this as root, or install sudo and give $SVC sudo rights"
    warn "sudo isn't installed: a real run needs root or sudo"
  fi
  printf '\n%sSystem steps need sudo, once:%s\n' "$B" "$N"
  printf '    install packages (Docker, Node 24, git, bubblewrap, passt, gocryptfs, jq%s) from fingerprint-pinned repos;\n' "$([ "$NO_TS" = 1 ] || echo ', Tailscale')"
  printf '    set Docker log rotation and build-cache limits, a journald cap, the bwrap AppArmor profile; enable lingering;\n'
  printf '    then run the product setup (ops/setup.sh) as root, which makes the vault and the services.\n'
  [ "$DRY" = 1 ] && return 0
  if [ "$NONINT" = 1 ]; then sudo -n true 2>/dev/null || die "--non-interactive needs passwordless sudo for $SVC (or run as root)"
  else sudo -v || die "sudo failed"; fi   # sudo prompts on the terminal itself
  # Keep the sudo timestamp fresh through a long install.
  ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) & KEEPALIVE=$!
}

ensure_user() {
  [ "$NEW_USER" = 1 ] || return 0
  step "Service user $SVC"
  say "creating $SVC (AidenHQ never runs as root); it gets sudo and root's SSH keys, because setup turns off root SSH login"
  run useradd -m -s /bin/bash "$SVC"
  grp=sudo; getent group sudo >/dev/null 2>&1 || grp=wheel
  run usermod -aG "$grp" "$SVC"
  echo "$SVC ALL=(ALL) NOPASSWD:ALL" | root_write "/etc/sudoers.d/90-aidenhq-$SVC" 0440 || :
  if [ -s /root/.ssh/authorized_keys ]; then
    run install -d -m 700 -o "$SVC" -g "$SVC" "$SVC_HOME/.ssh"
    run install -m 600 -o "$SVC" -g "$SVC" /root/.ssh/authorized_keys "$SVC_HOME/.ssh/authorized_keys"
  fi
  [ "$DRY" = 1 ] || SVC_UID=$(id -u "$SVC")
  NEW_USER=0
}

# ------------------------------------------------------------------------------------------------ state (resume)
state_init() { # a different release (or release file) starts over
  KEY="$REL@$(sha256 "$RELFILE")"
  [ "$DRY" = 1 ] && return 0
  as_svc mkdir -p -m 700 "$STATE_DIR"
  if [ "$(sed -n 's/^release=//p' "$STATE" 2>/dev/null)" != "$KEY" ]; then
    printf 'release=%s\n' "$KEY" | as_svc tee "$STATE" >/dev/null
  fi
}
done_step() { grep -qx "done:$1" "$STATE" 2>/dev/null; }
mark() { [ "$DRY" = 1 ] || echo "done:$1" | as_svc tee -a "$STATE" >/dev/null; }

# ------------------------------------------------------------------------------------------------ the release
# rel KEY: one string from the release file (jq when present; a dry run on a bare box uses the fallback parser, which
# reads only our own one-key-per-line format).
rel() {
  if have jq; then jq -r "$1 // empty" "$RELFILE"; return; fi
  k=${1#.}; k=${k##*.}
  sed -n "s/.*\"$k\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$RELFILE" | head -1
}
rel_modules() { # name sha, one per line
  if have jq; then jq -r '.modules // {} | to_entries[] | "\(.key) \(.value)"' "$RELFILE"; return; fi
  awk '/"modules"[[:space:]]*:/ { m = 1; next } m && /}/ { m = 0 } m { gsub(/[",]/, ""); sub(":", ""); print $1, $2 }' "$RELFILE"
}
is_sha() { case "$1" in *[!0-9a-f]*) return 1 ;; esac; [ ${#1} = 40 ]; }

fetch_release() {
  step "Release $REL"
  RELFILE="$TMPD/release.json"
  if [ -n "${AIDENHQ_RELEASE_FILE:-}" ]; then
    cp "$AIDENHQ_RELEASE_FILE" "$RELFILE" || die "can't read AIDENHQ_RELEASE_FILE=$AIDENHQ_RELEASE_FILE"
    say "release file: $AIDENHQ_RELEASE_FILE (local)"
  else
    url="${AIDENHQ_RELEASE_URL:-https://github.com/$DISTRO_REPO/releases/download/$REL/$REL.json}"
    fetch "$url" "$RELFILE" "${AUTH_HDR:-}" || {
      if [ "$DRY" = 1 ]; then warn "can't fetch $url yet (release not published?): planning without it"; RELFILE=''; return 0; fi
      die "can't fetch the release file $url"; }
    say "release file: $url"
  fi
  digest=$(sha256 "$RELFILE")
  if [ "$REL" = "$DEFAULT_RELEASE" ] && [ -n "$RELEASE_SHA256" ] && [ -z "${AIDENHQ_RELEASE_FILE:-}" ]; then
    [ "$digest" = "$RELEASE_SHA256" ] || die "release file digest $digest isn't the one this installer was cut with"
    say "digest matches the installer's ($digest)"
  fi
  [ "$(rel .release)" = "$REL" ] || die "the release file says it is '$(rel .release)', not $REL"
  KERNEL_SHA=$(rel .kernel) KERNEL_REPO=$(rel .kernel_repo) MKT_SHA=$(rel .marketplace.sha) MKT_REPO=$(rel .marketplace.source.repo)
  [ -n "$KERNEL_REPO" ] || KERNEL_REPO=Aiden-HQ/AidenHQ
  bad=''
  is_sha "$KERNEL_SHA" || bad="$bad kernel"
  is_sha "$MKT_SHA" || bad="$bad marketplace"
  rel_modules >"$TMPD/modules"
  [ -s "$TMPD/modules" ] || bad="$bad modules(empty)"
  while read -r m s; do is_sha "$s" || bad="$bad $m"; done <"$TMPD/modules"
  if [ -n "$bad" ]; then
    [ "$DRY" = 1 ] || die "release $REL isn't cut yet: no real sha for:$bad"
    warn "release $REL has placeholder shas ($(echo "$bad" | wc -w | tr -d ' ') entries): a real run stops here"
  fi
  say "kernel $KERNEL_REPO@$KERNEL_SHA; marketplace $MKT_REPO@$MKT_SHA; $(wc -l <"$TMPD/modules" | tr -d ' ') modules"
  H_DOCKER=$(rel .host.docker) H_CONTAINERD=$(rel .host.containerd) H_BUILDX=$(rel .host.buildx)
  H_COMPOSE=$(rel .host.compose) H_NODE=$(rel .host.node) H_TAILSCALE=$(rel .host.tailscale)
}

repo_url() { echo "${AIDENHQ_GIT_BASE:-https://github.com}/$1.git"; }
# Private repos: the token rides in git's environment config (never argv, never a file in a checkout).
git_auth_env() {
  tok="${AIDENHQ_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"
  [ -n "$tok" ] || return 0
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$tok" | base64 | tr -d '\n')"
  export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
  AUTH_HDR="$TMPD/auth"; (umask 077; printf 'Authorization: Bearer %s' "$tok" >"$AUTH_HDR")
}

# checkout_at DIR URL SHA: DIR holds exactly SHA from URL (its main is fetched too: setup checks the sha is on it).
checkout_at() {
  if [ "$DRY" = 1 ]; then printf '    %swould check out:%s %s at %s in %s\n' "$D" "$N" "$2" "$3" "$1"; return 0; fi
  if [ ! -d "$1/.git" ] && [ ! -f "$1/.git" ]; then
    [ ! -e "$1" ] || [ -z "$(ls -A "$1" 2>/dev/null)" ] || die "$1 exists and isn't a git checkout; move it or pass --dir"
    as_svc mkdir -p "$(dirname "$1")"
    as_svc git init -q "$1"
    as_svc git -C "$1" remote add origin "$2"
  fi
  as_svc git -C "$1" fetch -q --filter=blob:none origin main "$3" || as_svc git -C "$1" fetch -q origin main "$3" \
    || die "can't fetch $3 from $2 (private repo? set AIDENHQ_GITHUB_TOKEN)"
  if [ "$(ugit -C "$1" rev-parse HEAD 2>/dev/null)" != "$3" ]; then
    ugit -C "$1" diff --quiet HEAD 2>/dev/null || [ -z "$(ugit -C "$1" rev-parse -q --verify HEAD)" ] \
      || die "$1 has local changes; commit or discard them, then rerun"
    as_svc git -C "$1" -c advice.detachedHead=false checkout -q --detach "$3"
  fi
}
# verify_at DIR SHA: the tree on disk is exactly SHA. Runs on every invocation, right before anything from it executes.
verify_at() {
  [ "$DRY" = 1 ] && { printf '    %swould verify:%s HEAD of %s = %s, no tracked changes\n' "$D" "$N" "$1" "$2"; return 0; }
  head=$(ugit -C "$1" rev-parse HEAD 2>/dev/null || echo none)
  [ "$head" = "$2" ] || die "verification failed: $1 is at $head, the release pins $2"
  ugit -C "$1" diff --quiet HEAD -- || die "verification failed: $1 has tracked changes against $2"
}

fetch_sources() {
  step "Fetch and verify the kernel and modules"
  [ -n "$RELFILE" ] || { say "(no release file: skipped)"; return 0; }
  checkout_at "$DIR" "$(repo_url "$KERNEL_REPO")" "$KERNEL_SHA"
  verify_at "$DIR" "$KERNEL_SHA"
  MKT_DIR="$STATE_DIR/modules/marketplace"
  checkout_at "$MKT_DIR" "$(repo_url "$MKT_REPO")" "$MKT_SHA"
  verify_at "$MKT_DIR" "$MKT_SHA"
  # Every module sha must be on the marketplace's history at the release's sha, and is materialised and checked.
  cut -d' ' -f2 "$TMPD/modules" | sort -u >"$TMPD/shas"
  while read -r s; do
    [ "$s" = "$MKT_SHA" ] && continue
    wt="$STATE_DIR/modules/$(echo "$s" | cut -c1-12)"
    if [ "$DRY" = 0 ]; then
      ugit -C "$MKT_DIR" merge-base --is-ancestor "$s" "$MKT_SHA" 2>/dev/null \
        || die "verification failed: module sha $s isn't on the marketplace history at $MKT_SHA"
      [ -e "$wt" ] || as_svc git -C "$MKT_DIR" worktree add -q --detach "$wt" "$s"
    fi
    verify_at "$wt" "$s"
  done <"$TMPD/shas"
  [ "$DRY" = 1 ] || say "verified: kernel and $(wc -l <"$TMPD/modules" | tr -d ' ') module pins match the release"
}

# What the product's setup can do decides what this run can do: check before any heavy step.
check_product() {
  UNATTENDED=0
  if [ -f "$DIR/ops/setup.sh" ]; then
    grep -q -- '--unattended' "$DIR/ops/setup.sh" && UNATTENDED=1
  elif [ "$DRY" = 1 ]; then say "(no checkout in a dry run: checks assume today's kernel setup)"
  else die "$DIR/ops/setup.sh is missing: not an AidenHQ kernel checkout"; fi
  if [ ! -f "$DIR/ops/vm/setup.sh" ]; then
    case "$CODENAME" in noble|resolute) ;; *) refuse "today's kernel setup supports only Ubuntu 24.04/26.04, not $OS_NAME" ;; esac
  elif [ "$TIER" != first ] || ! grep -q "$CODENAME" "$DIR/ops/vm/setup.sh"; then
    refuse "this kernel's ops/vm/setup.sh doesn't support $OS_NAME yet (it supports: $(sed -n 's/^ *\([a-z|]*\)) ;;$/\1/p' "$DIR/ops/vm/setup.sh" 2>/dev/null | head -1 | tr '|' ' ')). Nothing was installed."
  fi
  [ "$DIR" = "$SVC_HOME/aidenhq" ] || refuse "this kernel's setup requires the checkout at $SVC_HOME/aidenhq, not $DIR"
  [ "$NO_TS" = 1 ] && [ "$UNATTENDED" = 0 ] && refuse "--no-tailscale needs a kernel whose setup runs without Tailscale; this one serves the board only on the tailnet"
  if [ "$UNATTENDED" = 0 ]; then
    [ -n "${AIDENHQ_OWNER_EMAIL:-}" ] || refuse "this kernel's setup isn't unattended yet: set AIDENHQ_OWNER_EMAIL (the board's owner account)"
    [ -n "${OPENROUTER_KEY:-}${OPENROUTER_MANAGEMENT_KEY:-}" ] || refuse "this kernel's setup isn't unattended yet: set OPENROUTER_KEY (or OPENROUTER_MANAGEMENT_KEY)"
    if [ -z "${TS_AUTHKEY:-}" ] && [ "$NONINT" = 1 ] && ! tailscale status >/dev/null 2>&1; then
      refuse "no terminal to show Tailscale's sign-in link: set TS_AUTHKEY, or run with a terminal"
    fi
  fi
  :
}

# ------------------------------------------------------------------------------------------------ packages
apt_get() { as_root env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 -y -q "$@"; }
# add_key URL FINGERPRINT DEST: the key must carry FINGERPRINT as a primary key, or nothing is written.
add_key() {
  if [ "$DRY" = 1 ]; then printf '    %swould add key:%s %s (fingerprint %s) -> %s\n' "$D" "$N" "$1" "$2" "$3"; return 0; fi
  fetch "$1" "$TMPD/key" || die "can't download the signing key $1"
  gpg --batch --show-keys --with-colons "$TMPD/key" 2>/dev/null \
    | awk -F: '$1 == "pub" { p = 1; next } p && $1 == "fpr" { print $10; p = 0 }' | grep -qx "$2" \
    || die "the key at $1 doesn't have the pinned fingerprint $2: refusing to trust it"
  if grep -q 'BEGIN PGP' "$TMPD/key"; then gpg --batch --yes --dearmor -o "$TMPD/key.gpg" "$TMPD/key"; else cp "$TMPD/key" "$TMPD/key.gpg"; fi
  $SUDO install -D -m 644 "$TMPD/key.gpg" "$3"; log "key $2 -> $3"
}
need_docker() {
  have docker || return 0
  dv=$(docker version -f '{{.Server.Version}}' 2>/dev/null || docker --version | sed 's/[^0-9]*\([0-9][0-9.]*\).*/\1/')
  cv=$(docker compose version --short 2>/dev/null | sed 's/^v//' || echo 0)
  if ver_ge "$dv" "$MIN_DOCKER" && ver_ge "${cv:-0}" "$MIN_COMPOSE"; then say "Docker $dv, compose $cv: ok"; return 1; fi
  say "Docker ${dv:-?} / compose ${cv:-none} is below $MIN_DOCKER / $MIN_COMPOSE: upgrading"
}
need_node() {
  have node || return 0
  nv=$(node -v | sed 's/^v//')
  if ver_ge "$nv" "$MIN_NODE"; then say "Node $nv: ok"; return 1; fi
  say "Node $nv is below $MIN_NODE: upgrading"
}
need_tailscale() { [ "$NO_TS" = 0 ] || return 1; have tailscale || return 0; say "Tailscale $(tailscale version | head -1): ok"; return 1; }

install_apt() {
  apt_get update
  base="ca-certificates curl gnupg git jq bubblewrap gocryptfs fuse3 openssl uidmap"
  if apt-cache show passt >/dev/null 2>&1 || [ "$DRY" = 1 ]; then base="$base passt"
  else warn "passt isn't packaged for $OS_NAME: Engineer jobs will share the host network (the runner warns)"; fi
  # shellcheck disable=SC2086
  apt_get install --no-install-recommends $base
  as_root install -d -m 755 /etc/apt/keyrings
  pins='' holds='' sfx="~$BASE.$BASE_VER~$CODENAME"
  if need_docker; then
    add_key "https://download.docker.com/linux/$BASE/gpg" "$FPR_DOCKER" /etc/apt/keyrings/aidenhq-docker.gpg
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/aidenhq-docker.gpg] https://download.docker.com/linux/$BASE $CODENAME stable" \
      | root_write /etc/apt/sources.list.d/aidenhq-docker.list 644 || :
    pins="$pins docker-ce=5:$H_DOCKER-1$sfx docker-ce-cli=5:$H_DOCKER-1$sfx docker-ce-rootless-extras=5:$H_DOCKER-1$sfx"
    pins="$pins containerd.io=$H_CONTAINERD$sfx docker-buildx-plugin=$H_BUILDX-1$sfx docker-compose-plugin=$H_COMPOSE-1$sfx"
    holds="$holds docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io docker-buildx-plugin docker-compose-plugin"
  fi
  if need_node; then
    add_key https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key "$FPR_NODESOURCE" /etc/apt/keyrings/aidenhq-nodesource.gpg
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/aidenhq-nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
      | root_write /etc/apt/sources.list.d/aidenhq-nodesource.list 644 || :
    pins="$pins nodejs=$H_NODE-1nodesource1" holds="$holds nodejs"
  fi
  if need_tailscale; then
    add_key "https://pkgs.tailscale.com/stable/$BASE/$CODENAME.noarmor.gpg" "$FPR_TAILSCALE" /etc/apt/keyrings/aidenhq-tailscale.gpg
    echo "deb [signed-by=/etc/apt/keyrings/aidenhq-tailscale.gpg] https://pkgs.tailscale.com/stable/$BASE $CODENAME main" \
      | root_write /etc/apt/sources.list.d/aidenhq-tailscale.list 644 || :
    pins="$pins tailscale=$H_TAILSCALE" holds="$holds tailscale"
  fi
  [ -n "$pins" ] || return 0
  [ "$DRY" = 1 ] || case "$H_DOCKER$H_NODE" in '') die "the release file has no host pins (host.docker, host.node, ...)" ;; esac
  apt_get update
  # shellcheck disable=SC2086
  apt_get install --allow-downgrades --allow-change-held-packages $pins || die "a pinned package isn't in its vendor repo for $CODENAME/$ARCH: see the log"
  # shellcheck disable=SC2086
  as_root apt-mark hold $holds
}

install_dnf() {
  warn "$OS_NAME is best effort: packages come from Fedora/EPEL and vendor repos at their current versions, not the release's pins"
  as_root dnf -y -q install ca-certificates curl gnupg2 git jq bubblewrap passt fuse3 openssl dnf-plugins-core
  as_root dnf -y -q install gocryptfs || warn "gocryptfs not found (on RHEL enable EPEL); the vault needs it"
  dist=centos; case " $OS_ID $OS_LIKE " in *" fedora "*) [ "$OS_ID" = fedora ] && dist=fedora ;; esac
  if need_docker; then
    add_key "https://download.docker.com/linux/$dist/gpg" "$FPR_DOCKER_RPM" /etc/pki/rpm-gpg/aidenhq-docker.gpg
    printf '[aidenhq-docker]\nname=Docker CE\nbaseurl=https://download.docker.com/linux/%s/$releasever/$basearch/stable\nenabled=1\ngpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/aidenhq-docker.gpg\n' "$dist" \
      | root_write /etc/yum.repos.d/aidenhq-docker.repo 644 || :
    as_root dnf -y -q install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  if need_node; then as_root dnf -y -q install nodejs24 || as_root dnf -y -q module install nodejs:24/common; fi
  if need_tailscale; then
    add_key "https://pkgs.tailscale.com/stable/fedora/repo.gpg" "$FPR_TAILSCALE" /etc/pki/rpm-gpg/aidenhq-tailscale.gpg
    printf '[aidenhq-tailscale]\nname=Tailscale\nbaseurl=https://pkgs.tailscale.com/stable/fedora/$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/aidenhq-tailscale.gpg\n' \
      | root_write /etc/yum.repos.d/aidenhq-tailscale.repo 644 || :
    as_root dnf -y -q install tailscale
  fi
}

install_pacman() {
  warn "Arch is best effort: a rolling release can't be pinned; packages are Arch's current ones"
  pk="ca-certificates curl gnupg git jq bubblewrap passt gocryptfs fuse3 openssl"
  need_docker && pk="$pk docker docker-compose docker-buildx"
  need_node && pk="$pk nodejs-lts-krypton"
  need_tailscale && pk="$pk tailscale"
  # shellcheck disable=SC2086
  as_root pacman -Syu --needed --noconfirm $pk
}

install_packages() {
  step "Packages ($PM)"
  if done_step packages && have docker && have node && have git; then say "done in an earlier run"; return 0; fi
  "install_$PM"
  [ "$DRY" = 1 ] && return 0
  have node || die "Node isn't installed after the package step"
  ver_ge "$(node -v | sed 's/^v//')" "$MIN_NODE" || die "Node $MIN_NODE or later isn't installed after the package step"
  ver_ge "$(git --version | awk '{ print $3 }')" "$MIN_GIT" || die "git $MIN_GIT or later is required"
  mark packages
}

# bubblewrap: Engineer jobs run in it, and Ubuntu 24.04+ restricts the user namespace it needs. The same private copy
# and profile as the product's ops/vm/setup.sh (which re-asserts them), so the two never disagree.
configure_bwrap() {
  step "Sandbox (bubblewrap, user namespaces)"
  if [ "$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo 1)" = 0 ]; then
    echo 'kernel.unprivileged_userns_clone = 1' | root_write /etc/sysctl.d/90-aidenhq-userns.conf 644 && as_root sysctl -q --system
  fi
  if [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)" = 1 ] && [ -e /etc/apparmor.d/abi/4.0 ]; then
    grp=$(id -gn "$SVC" 2>/dev/null || echo "$SVC")
    as_root install -d -m 0750 -o root -g "$grp" /opt/aidenhq/bwrap
    as_root install -m 0750 -o root -g "$grp" /usr/bin/bwrap /opt/aidenhq/bwrap/bwrap
    printf '%s\n' 'abi <abi/4.0>,' 'include <tunables/global>' '' \
      'profile aidenhq-bwrap /opt/aidenhq/bwrap/bwrap flags=(unconfined) {' '  userns,' \
      '  include if exists <local/aidenhq-bwrap>' '}' | root_write /etc/apparmor.d/aidenhq-bwrap 644 || :
    as_root apparmor_parser -r /etc/apparmor.d/aidenhq-bwrap
    say "AppArmor restricts user namespaces: private bwrap copy with the aidenhq-bwrap profile"
  else say "user namespaces available to bwrap"; fi
}

configure_host() {
  step "Docker, journal, lingering (disk headroom)"
  if [ "$DRY" = 1 ] || ! have jq; then
    say "would merge into /etc/docker/daemon.json: json-file logs $LOG_MAX x $LOG_FILES, build cache GC at ${BUILD_CACHE_GB}GB"
  else
    cur=$($SUDO cat /etc/docker/daemon.json 2>/dev/null || echo '{}')
    # Only keys the owner hasn't set: their own choices win.
    printf '%s' "$cur" | jq --arg m "$LOG_MAX" --arg f "$LOG_FILES" --arg k "${BUILD_CACHE_GB}GB" '
      (if has("log-driver") then . else . + {"log-driver": "json-file", "log-opts": {"max-size": $m, "max-file": $f}} end)
      | (if .builder.gc then . else .builder.gc = {"enabled": true, "defaultKeepStorage": $k} end)' >"$TMPD/daemon.json" \
      || die "/etc/docker/daemon.json isn't valid JSON"
    if root_write /etc/docker/daemon.json 644 <"$TMPD/daemon.json"; then
      if [ -z "$($SUDO docker ps -q 2>/dev/null)" ]; then as_root systemctl restart docker
      else warn "containers are running: Docker's new log and cache limits apply at its next restart"; fi
    fi
  fi
  printf '[Journal]\nSystemMaxUse=%s\n' "$JOURNAL_MAX" | root_write /etc/systemd/journald.conf.d/90-aidenhq.conf 644 \
    && as_root systemctl restart systemd-journald
  as_root systemctl enable --now docker
  as_root usermod -aG docker "$SVC"
  as_root loginctl enable-linger "$SVC"
}

# ------------------------------------------------------------------------------------------------ the product
join_tailnet() { # only for a kernel whose setup can't do it unattended
  [ "$NO_TS" = 0 ] && [ "$UNATTENDED" = 0 ] || return 0
  tailscale status >/dev/null 2>&1 && return 0
  [ -n "${TS_AUTHKEY:-}" ] && return 0     # setup joins with it
  step "Join your tailnet"
  say "Open the link Tailscale prints to add this server to your tailnet (it waits for you):"
  [ "$DRY" = 1 ] && { say "(would run: tailscale up --hostname=aidenhq-$SVC)"; return 0; }
  $SUDO tailscale up --hostname="aidenhq-$SVC" </dev/tty || die "tailscale up failed"
}

run_setup() {
  step "AidenHQ setup (ops/setup.sh: vault, services, Paperclip, board)"
  verify_at "$DIR" "$KERNEL_SHA"          # again, right before root runs it
  if [ "$UNATTENDED" = 1 ]; then
    set -- --unattended; [ "$NO_TS" = 1 ] && set -- "$@" --no-tailscale
  else
    PENV="$STATE_DIR/person.env"
    if [ "$DRY" = 0 ]; then
      gecos=$(getent passwd "$SVC" | cut -d: -f5 | cut -d, -f1)
      tz=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo UTC)
      { printf 'AIDENHQ_USER=%s\nOWNER_NAME="%s"\nOWNER_EMAIL=%s\nTIMEZONE=%s\n' "$SVC" "${AIDENHQ_OWNER_NAME:-${gecos:-$SVC}}" "$AIDENHQ_OWNER_EMAIL" "${tz:-UTC}"
        for k in OPENROUTER_KEY OPENROUTER_MANAGEMENT_KEY OPENROUTER_LIMIT_USD TS_AUTHKEY TS_APPS_AUTHKEY GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET MODULES; do
          eval "v=\${$k:-}"; [ -n "$v" ] && printf '%s="%s"\n' "$k" "$v"; done; } \
        | as_svc sh -c 'umask 077; cat > "$1"' _ "$PENV"
    fi
    set -- --config "$PENV"
  fi
  [ "$DRY" = 1 ] && { printf '    %swould run:%s %senv AIDENHQ_USER=%s bash %s/ops/setup.sh %s\n' "$D" "$N" "${SUDO:+$SUDO }" "$SVC" "$DIR" "$*"; return 0; }
  log "+ setup $*"
  # The product's own progress lines ("• ...") reach the terminal; everything goes to the log.
  { $SUDO env AIDENHQ_USER="$SVC" bash "$DIR/ops/setup.sh" "$@" </dev/null 2>&1 && echo 0 >"$TMPD/rc" || echo $? >"$TMPD/rc"; } \
    | tee -a "$LOG" | while IFS= read -r l; do
        case "$l" in "• "*) say "${l#• }" ;; *) if [ "$VERBOSE" = 1 ]; then printf '    %s\n' "$l"; fi ;; esac
      done
  rc=$(cat "$TMPD/rc")
  [ -n "${PENV:-}" ] && as_svc sh -c 'shred -u "$1" 2>/dev/null || rm -f "$1"' _ "$PENV"
  [ "$rc" = 0 ] || die "ops/setup.sh failed (exit $rc)"
  SETUP_URL=$(sed -n 's/^AIDENHQ_SETUP_URL=//p' "$LOG" | tail -1)
  [ -n "$SETUP_URL" ] || SETUP_URL=$(awk '/^Done\./ { d = 1; next } d && /^https:\/\// { u = $1 } END { print u }' "$LOG")
  mark setup
}

tune_runner() {
  step "Fit the runner and cleanup to this machine"
  cfg="$DIR/config/runner.yaml"
  if [ "$DRY" = 1 ]; then say "would set max_concurrent: $MAX_CONCURRENT, timeout_minutes: $JOB_TIMEOUT (only while still the shipped 2 / 60)"
  elif [ -f "$cfg" ] && grep -qx 'max_concurrent: 2' "$cfg" && grep -qx 'timeout_minutes: 60' "$cfg"; then
    as_svc sed -i -e "s/^max_concurrent: 2$/max_concurrent: $MAX_CONCURRENT/" -e "s/^timeout_minutes: 60$/timeout_minutes: $JOB_TIMEOUT/" "$cfg"
    # Graceful: the runner exits once nothing is half done; jobs keep running (KillMode=process).
    as_svc systemctl --user kill --kill-whom=main -s SIGUSR2 aidenhq-runner || :
    say "runner: $MAX_CONCURRENT jobs at once, $JOB_TIMEOUT min each"
  else say "runner.yaml already tuned: left as it is"; fi
  printf 'CI_RUNNERS=%s\nMAX_CONCURRENT=%s\nJOB_TIMEOUT=%s\nDISK_RESERVE_GB=%s\n' "$CI_RUNNERS" "$MAX_CONCURRENT" "$JOB_TIMEOUT" "$DISK_RESERVE_GB" \
    | if [ "$DRY" = 1 ]; then cat >/dev/null; else as_svc sh -c 'cat > "$1"' _ "$STATE_DIR/host-defaults.env"; fi
  say "CI runners for the ci module (started once the GitHub App is set up): $CI_RUNNERS"
  # Prune timers: the product's weekly Docker cleanup, plus a guard that prunes harder when free space drops below the reserve.
  units="$SVC_HOME/.config/systemd/user"
  as_svc mkdir -p "$units" "$STATE_DIR/bin"
  [ -f "$DIR/ops/units/prune-docker.timer" ] && as_svc cp "$DIR/ops/units/prune-docker.service" "$DIR/ops/units/prune-docker.timer" "$units/"
  cat >"$TMPD/guard" <<EOF
#!/bin/sh
# AidenHQ disk guard (install.sh): below ${DISK_RESERVE_GB} GB free, drop Docker build cache and images unused for a day.
free=\$(df -Pk "\$(docker info -f '{{.DockerRootDir}}')" | awk 'NR==2 { print int(\$4 / 1048576) }')
[ "\$free" -ge ${DISK_RESERVE_GB} ] && exit 0
echo "disk guard: \${free} GB free, below ${DISK_RESERVE_GB} GB: pruning" >&2
docker builder prune -af
docker image prune -af --filter until=24h
EOF
  printf '[Unit]\nDescription=AidenHQ disk guard\n\n[Service]\nType=oneshot\nExecStart=/bin/sh %s/bin/disk-guard.sh\n' "$STATE_DIR" >"$TMPD/gs"
  printf '[Unit]\nDescription=AidenHQ disk guard, every 15 minutes\n\n[Timer]\nOnBootSec=5min\nOnUnitActiveSec=15min\n\n[Install]\nWantedBy=timers.target\n' >"$TMPD/gt"
  chmod 644 "$TMPD/guard" "$TMPD/gs" "$TMPD/gt"
  as_svc cp "$TMPD/guard" "$STATE_DIR/bin/disk-guard.sh"
  as_svc cp "$TMPD/gs" "$units/aidenhq-disk-guard.service"
  as_svc cp "$TMPD/gt" "$units/aidenhq-disk-guard.timer"
  as_svc systemctl --user daemon-reload
  as_svc systemctl --user enable --now aidenhq-disk-guard.timer
  [ -f "$DIR/ops/units/prune-docker.timer" ] && as_svc systemctl --user enable --now prune-docker.timer
  say "disk guard: prunes below ${DISK_RESERVE_GB} GB free; weekly Docker cleanup on"
}

finish() {
  if [ "$DRY" = 1 ]; then
    printf '\n%sDry run done.%s A real run ends with:\n' "$Y" "$N"; SETUP_URL="https://<board-host>/setup/<one-time-token>"
  fi
  printf '\n%sAidenHQ is running.%s\n\n' "$G$B" "$N"
  if [ -n "${SETUP_URL:-}" ]; then
    printf '  Open this link to finish in your browser (one use, 72 hours):\n\n    %s%s%s\n\n' "$B" "$SETUP_URL" "$N"
    [ "$UNATTENDED" = 1 ] && printf '  It sets up your account and authenticator, your model key and your channels.\n'
    [ "$UNATTENDED" = 0 ] && printf '  It sets your password and authenticator. Your device must be on the same tailnet.\n'
  else
    printf '  The setup link is in the log (search for "Done."): %s\n' "$LOG"
  fi
  printf '  Install log: %s    Service logs: journalctl --user -u aidenhq-runner; docker compose logs (in %s)\n' "$LOG" "$DIR"
  if [ "$UNATTENDED" = 0 ] && $SUDO test -e /root/aidenhq-vault-recovery.txt 2>/dev/null; then
    printf '  Vault recovery key: sudo cat /root/aidenhq-vault-recovery.txt, store it, then sudo shred -u it.\n'
  fi
}

# ------------------------------------------------------------------------------------------------ uninstall
uninstall() {
  step "Uninstall AidenHQ services (data, vault, instance repo and packages stay)"
  units="aidenhq-disk-guard.timer prune-docker.timer prune-runs.timer aidenhq-runner aidenhq-kernel aidenhq-computers aidenhq-gateway"
  for u in $units; do as_svc systemctl --user disable --now "$u" 2>/dev/null || :; done
  for f in aidenhq-disk-guard.service aidenhq-disk-guard.timer prune-docker.service prune-docker.timer prune-runs.service \
           prune-runs.timer aidenhq-runner.service aidenhq-kernel.service aidenhq-computers.service aidenhq-gateway.service; do
    [ -e "$SVC_HOME/.config/systemd/user/$f" ] && as_svc rm -f "$SVC_HOME/.config/systemd/user/$f"
  done
  as_svc systemctl --user daemon-reload 2>/dev/null || :
  if [ -f "$DIR/compose.yaml" ]; then as_svc sh -c 'cd "$1" && docker compose down --remove-orphans' _ "$DIR" || warn "docker compose down failed"; fi
  have tailscale && { as_root tailscale serve --https=443 off 2>/dev/null || :; }
  as_root rm -f /etc/systemd/journald.conf.d/90-aidenhq.conf /etc/sysctl.d/90-aidenhq-userns.conf
  as_svc rm -f "$STATE" "$STATE_DIR/bin/disk-guard.sh"
  printf '\n%s Kept (delete by hand if you want them gone):\n' "$([ "$DRY" = 1 ] && echo 'A real run stops and removes these.' || echo 'Stopped and removed.')"
  printf '  %s (checkout and data/), %s/aidenhq-instance, the vault (%s/.config/aidenhq, %s/.local/share/aidenhq),\n' "$DIR" "$SVC_HOME" "$SVC_HOME" "$SVC_HOME"
  printf '  Docker volumes (docker volume ls), packages (Docker, Node, Tailscale; held: apt-mark showhold), system units aidenhq-*.\n'
}

# ------------------------------------------------------------------------------------------------ main
plan_summary() {
  step "This machine"
  say "$OS_NAME [$OS_ID $OS_VER] ($ARCH), support: $([ "$TIER" = first ] && echo 'first class' || echo 'best effort'); $CORES cores, $RAM_MB MB RAM, $DISK_GB GB free"
  say "service user: $SVC$([ "$NEW_USER" = 1 ] && echo ' (will be created)'); checkout: $DIR"
  say "derived: $MAX_CONCURRENT jobs x $JOB_TIMEOUT min, $CI_RUNNERS CI runner(s), keep ${DISK_RESERVE_GB} GB free, build cache ${BUILD_CACHE_GB} GB, logs $LOG_MAX x $LOG_FILES, journal $JOURNAL_MAX"
}

main() {
  setup_ui
  parse_args "$@"
  TMPD=$(mktemp -d 2>/dev/null || mktemp -d -t aidenhq) STEP='' REFUSALS='' KEEPALIVE='' RELFILE='' UNATTENDED=0
  KERNEL_SHA='' KERNEL_REPO='' MKT_SHA='' MKT_REPO='' SETUP_URL='' PENV='' AUTH_HDR=''
  H_DOCKER='' H_CONTAINERD='' H_BUILDX='' H_COMPOSE='' H_NODE='' H_TAILSCALE=''
  exec </dev/null   # with curl | sh, stdin is the script: nothing below may read it (prompts use /dev/tty)
  trap on_exit EXIT
  trap 'exit 130' INT TERM
  detect_platform
  resolve_user
  open_log
  [ "$DRY" = 1 ] && printf '%sDry run:%s nothing on this machine changes.\n' "$Y" "$N"
  if [ "$UNINSTALL" = 1 ]; then ensure_sudo; uninstall; return 0; fi
  detect_resources
  derive_defaults
  plan_summary
  check_minimums
  if [ -n "$REFUSALS" ]; then
    printf '%s%s:%s\n%s' "$R" "$([ "$DRY" = 1 ] && echo 'A real run would refuse' || echo 'Refusing to install')" "$N" "$REFUSALS"
    [ "$DRY" = 1 ] || { STEP=''; exit 1; }
    REFUSALS=''
  fi
  ensure_sudo
  ensure_user
  git_auth_env
  # Fail fast: the release and its sources need only curl and git, so they come before the heavy installs.
  if [ "$DRY" = 1 ] || ! have git || ! have curl || ! have gpg; then
    step "Bootstrap tools"
    case "$PM" in
      apt) apt_get update; apt_get install --no-install-recommends ca-certificates curl git gnupg jq ;;
      dnf) as_root dnf -y -q install ca-certificates curl git gnupg2 jq ;;
      pacman) as_root pacman -Sy --needed --noconfirm ca-certificates curl git gnupg jq ;;
    esac
  fi
  fetch_release
  [ -n "$RELFILE" ] && state_init
  fetch_sources
  check_product
  if [ -n "$REFUSALS" ]; then
    printf '%s%s:%s\n%s' "$R" "$([ "$DRY" = 1 ] && echo 'A real run would stop here' || echo 'Stopping before any system change')" "$N" "$REFUSALS"
    [ "$DRY" = 1 ] || { STEP=''; exit 1; }
  fi
  install_packages
  configure_bwrap
  configure_host
  join_tailnet
  run_setup
  tune_runner
  finish
}

main "$@"
