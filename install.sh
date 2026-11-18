#!/bin/sh
# shellcheck disable=SC2016  # single-quoted sh -c bodies and $releasever are meant literally
# AidenHQ installer: turns a Linux server into a running AidenHQ, then hands you one link for the rest. On a Mac it makes
# an Ubuntu VM (Lima) and runs the Linux install inside it (AIDENHQ_VM_CPUS / _MEMORY / _DISK, AIDENHQ_KEEP_AWAKE=1|0,
# AIDENHQ_CONFIRM_DELETE_VM=1 for an unattended --uninstall; see INSTALL.md, On a Mac).
#
#   curl -fsSL https://get.aidenhq.ai | sh
#   curl -fsSL https://get.aidenhq.ai | sh -s -- --dry-run          # print the plan, change nothing
#
# Flags (each has an environment form):
#   --release <name>    AIDENHQ_RELEASE          release to install (default: the one this script was cut with)
#   --dir <path>        AIDENHQ_DIR              product checkout (default: ~<user>/aidenhq)
#   --non-interactive   AIDENHQ_NON_INTERACTIVE=1  never wait on a terminal (implied when there is none)
#   --dry-run           AIDENHQ_DRY_RUN=1        detect and plan only
#   --no-tailscale      AIDENHQ_NO_TAILSCALE=1   skip Tailscale
#   --uninstall         AIDENHQ_UNINSTALL=1      stop and remove services; keeps data, vault and packages
#   --verbose           AIDENHQ_VERBOSE=1        stream every command's output, not just the steps
# Other inputs: AIDENHQ_OWNER_EMAIL (the board's owner account; asked for on a terminal when unset), AIDENHQ_OWNER_NAME
# (default: the service user's name), AIDENHQ_TIMEZONE (the owner's IANA zone, e.g. Asia/Dubai, for schedules and briefs;
# default: the host's zone, on a Mac this Mac's), AIDENHQ_USER (service user when run as root; default aidenhq), AIDENHQ_GITHUB_TOKEN
# (private repos), AIDENHQ_RELEASE_FILE / AIDENHQ_RELEASE_URL / AIDENHQ_GIT_BASE (mirrors, air-gapped installs and tests).
# Optional secrets, passed to the product's setup in a root-only config file and never printed: OPENROUTER_KEY (or
# OPENROUTER_MANAGEMENT_KEY), TS_AUTHKEY. Without them the first-run page asks for the model key, and a server off a
# tailnet keeps the board on loopback, reached through the SSH tunnel it prints. A private kernel repo's token goes to
# setup in its own root-only file (--kernel-token-file), for its one fetch.
#
# No telemetry. Everything it fetches is pinned: the release file by digest, git checkouts by sha. Host packages are the
# kernel's own pins (ops/vm/pins.json), installed by its setup. The whole script is functions; nothing runs until the
# last line, so a truncated download does nothing.
set -eu
# Whatever umask the caller's shell had (an ssh session may pass 077): the checkout and everything containers read must stay
# readable to the non-root services. Secret files are made 0600 explicitly.
umask 022

DEFAULT_RELEASE=2026.11
# Baked in by the release CI (.github/workflows/release.yml) when it publishes this file beside <release>.json: that file's
# sha256 and the distro commit it was cut from. Empty = an uncut copy, which installs only from AIDENHQ_RELEASE_FILE.
RELEASE_SHA256=""
RELEASE_COMMIT=""
DISTRO_REPO=Aiden-HQ/aidenhq-distro
MIN_CORES=2 WARN_CORES=4 MIN_RAM_MB=5800 WARN_RAM_MB=7400 MIN_DISK_GB=60 WARN_DISK_GB=90
SUPPORTED="Ubuntu 22.04, 24.04, 26.04 and Debian 12, 13"

# ------------------------------------------------------------------------------------------------ output and logging
setup_ui() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    B=$(printf '\033[1m') G=$(printf '\033[32m') Y=$(printf '\033[33m') R=$(printf '\033[31m') D=$(printf '\033[2m') N=$(printf '\033[0m')
  else B='' G='' Y='' R='' D='' N=''; fi
}
log() { [ -n "${LOG:-}" ] && printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >>"$LOG" 2>/dev/null || :; }
# ------------------------------------------------------------------------------------------------ progress
# step() also prints AIDENHQ_PROGRESS=<n>/<total> <percent>% <step> ~<minutes left>, plain at the start of a line, for the
# one-prompt install (site/prompt.md) and scripts to poll. The percent never goes down and the last line before
# AIDENHQ_SETUP_URL= is 100%.
#
# THE WEIGHTS: one row per step: key (what the step's text starts with) | estimated seconds on 4 cores / 8 GB / a good link |
# what the owner is told. They are ESTIMATES from the product's `apply timing:` phase names and image sizes, until Task 0's
# measurements replace them: edit only this table. The percent is the share of the weights before a step; the minutes are
# the share after it. A step that doesn't run (tools already there) is skipped, so the bar jumps over its weight. The setup
# row is the product's whole run: ops/setup.sh and its apply print their own lines inside it (AIDENHQ_PROGRESS_BASE).
PROGRESS_LINUX='This machine|2|checking this server
Service user|5|creating the service user
Bootstrap tools|40|installing base tools
Release|5|fetching the release
Fetch and verify|20|verifying the code
Docker log|3|setting up Docker limits
AidenHQ setup|780|installing AidenHQ and downloading its images
Disk guard|5|finishing up
ready|0|ready'
progress_sum() {
  pg_s=0
  while IFS='|' read -r pg_k pg_w pg_l; do [ -z "$pg_k" ] || pg_s=$((pg_s + pg_w)); done <<EOF
$1
EOF
  echo "$pg_s"
}
# On a Mac the Linux install above runs inside the VM, so one row weighs the whole table above.
progress_mac_table() {
  printf 'This Mac|3|checking this Mac\nLima|60|installing Lima\nLinux VM|120|creating the Linux VM\nAidenHQ in the VM|%s|installing AidenHQ in the VM\nready|0|ready\n' \
    "$(progress_sum "$PROGRESS_LINUX")"
}
# progress_calc TEXT: the table row TEXT starts; sets PG_LABEL PG_N PG_TOTAL PG_PCT PG_END (where the row ends) PG_SECS.
# With AIDENHQ_PROGRESS_BASE=<n>/<total>/<percent>/<span>/<seconds> (the Mac's installer, for the one in the VM) the table
# fills that slice of a bigger run and keeps its n/total.
progress_calc() {
  [ -n "${PG_TABLE:-}" ] || return 1
  pg_sum=$(progress_sum "$PG_TABLE") pg_cum=0 pg_n=0 pg_i=0 pg_row=0
  while IFS='|' read -r pg_k pg_w pg_l; do
    [ -n "$pg_k" ] || continue
    pg_n=$((pg_n + 1))
    if [ "$pg_i" = 0 ]; then
      case "$1" in "$pg_k"*) pg_i=$pg_n PG_LABEL=$pg_l pg_row=$pg_w ;; *) pg_cum=$((pg_cum + pg_w)) ;; esac
    fi
  done <<EOF
$PG_TABLE
EOF
  [ "$pg_i" != 0 ] || return 1
  if [ -n "${AIDENHQ_PROGRESS_BASE:-}" ]; then
    IFS=/ read -r PG_N PG_TOTAL pg_p0 pg_span PG_SECS <<EOF
$AIDENHQ_PROGRESS_BASE
EOF
  else PG_N=$pg_i PG_TOTAL=$pg_n pg_p0=0 pg_span=100 PG_SECS=$pg_sum; fi
  PG_PCT=$((pg_p0 + pg_span * pg_cum / pg_sum)) PG_END=$((pg_p0 + pg_span * (pg_cum + pg_row) / pg_sum))
  [ "$PG_PCT" -ge "${PG_LAST:-0}" ] || PG_PCT=$PG_LAST   # never down
  PG_LAST=$PG_PCT
}
progress_emit() {
  progress_calc "$1" || return 0
  printf 'AIDENHQ_PROGRESS=%s/%s %s%% %s ~%s\n' "$PG_N" "$PG_TOTAL" "$PG_PCT" "$PG_LABEL" "$(( ((100 - PG_PCT) * PG_SECS + 5999) / 6000 ))"
  PROGRESS_SLICE="$PG_N/$PG_TOTAL/$PG_PCT/$((PG_END > PG_PCT ? PG_END - PG_PCT : 0))/$PG_SECS"   # what this step hands its child
}
step() { STEP="$*"; log "== $*"; printf '%s==>%s %s%s%s\n' "$G" "$N" "$B" "$*" "$N"; progress_emit "$*"; }
say() { log "$*"; printf '    %s\n' "$*"; }
warn() { log "WARN $*"; printf '    %swarning:%s %s\n' "$Y" "$N" "$*" >&2; }
die() { log "ERROR $*"; printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
refuse() { REFUSALS="${REFUSALS}    - $*
"; log "REFUSE $*"; }

rm_penv() {
  for f in "${PENV:-}" "${KTOK_FILE:-}"; do [ -z "$f" ] || $SUDO sh -c 'shred -u "$1" 2>/dev/null || rm -f "$1"' _ "$f"; done
  PENV='' KTOK_FILE=''
}
on_exit() {
  rc=$?
  rm_penv 2>/dev/null
  [ -n "${KEEPALIVE:-}" ] && kill "$KEEPALIVE" 2>/dev/null
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
  [ "$rc" = 0 ] && return 0
  [ -n "${STEP:-}" ] || return 0   # refused before any step: the message said it all
  printf '\n%sInstall stopped%s during: %s\n' "$R" "$N" "${STEP:-start}" >&2
  if [ -n "${LOG:-}" ] && [ -s "$LOG" ]; then
    printf '%sLast lines of %s:%s\n' "$D" "$LOG" "$N" >&2; tail -n 15 "$LOG" | sed 's/^/    /' >&2
  fi
  printf 'Fix the cause and run the same command again: every step is safe to repeat.\n' >&2
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
apt_get() { as_root env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 -y -q "$@"; }
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
fetch() { # url dest [header-file]: https only. Credentials only ever go through curl, which (since 7.58) never forwards a
  # custom Authorization header to another host on a redirect; wget would, so it only fetches anonymously.
  if have curl; then curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 3 ${3:+-H "@$3"} -o "$2" "$1"
  elif [ -n "${3:-}" ]; then echo "an authenticated download needs curl (wget would pass the token on through redirects)" >&2; return 1
  elif have wget; then wget -q --https-only -O "$2" "$1"
  else return 127; fi
}
# gh_asset TAG NAME DEST: a private release asset through GitHub's API with the token; the signed redirect target is then
# downloaded with no credentials at all.
gh_asset() {
  curl -fsS --proto '=https' --tlsv1.2 -H "@$AUTH_HDR" -H 'Accept: application/vnd.github+json' \
    -o "$TMPD/rel-meta.json" "https://api.github.com/repos/$DISTRO_REPO/releases/tags/$1" || return 1
  id=$(jq -r --arg n "$2" '.assets[] | select(.name == $n) | .id' "$TMPD/rel-meta.json")
  [ -n "$id" ] || return 1
  loc=$(curl -fsS --proto '=https' --tlsv1.2 -H "@$AUTH_HDR" -H 'Accept: application/octet-stream' -o /dev/null \
    -w '%{redirect_url}' "https://api.github.com/repos/$DISTRO_REPO/releases/assets/$id") || return 1
  case "$loc" in https://*) fetch "$loc" "$3" ;; *) return 1 ;; esac
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
  case "$REL" in *[!0-9.]*|'') die "release names look like 2026.11.18 or 2026.11.18.1, not '$REL'" ;; esac
  for v in DRY NO_TS UNINSTALL VERBOSE NONINT; do eval "case \$$v in 1|true|yes) $v=1 ;; *) $v=0 ;; esac"; done
  # No terminal to wait on: curl | sh in CI, cloud-init, or ssh without -t.
  if ! { [ -t 0 ] || (: </dev/tty) 2>/dev/null; }; then NONINT=1; fi
}
usage() {
  printf '%s\n' 'AidenHQ installer: curl -fsSL https://get.aidenhq.ai | sh -s -- [options]' \
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
  OS_NAME=$(. /etc/os-release; echo "${PRETTY_NAME:-${ID:-unknown}}")
  # shellcheck disable=SC1091
  CODENAME=$(. /etc/os-release; echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")   # a derivative names its Ubuntu base
  # The product's host setup installs with apt; which releases it pins is its own ops/vm/pins.json (checked once fetched).
  have apt-get || die "$OS_NAME has no apt-get. AidenHQ supports $SUPPORTED."
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
  # A rerun: what an earlier run already put in Docker (images, build cache, volumes) is part of the install the minimum is
  # for, so the minimum is checked against free space plus that (DISK_AVAIL_GB); DISK_GB stays the real free space.
  DISK_AVAIL_GB=$DISK_GB
  [ -d "$DIR/.git" ] && DISK_AVAIL_GB=$((DISK_GB + $(installed_gb)))
  :
}

# Docker's used space in whole GB (docker system df: images, containers, volumes, build cache); 0 without Docker. Before
# ensure_sudo: sudo only when it needs no password.
installed_gb() {
  have docker || { echo 0; return 0; }
  { docker system df --format '{{.Size}}' 2>/dev/null || ${SUDO:+$SUDO -n} docker system df --format '{{.Size}}' 2>/dev/null || :; } | awk '
    { v = $1 + 0; u = $1; sub(/^[0-9.]+/, "", u)
      if (u == "TB") v *= 1000; else if (u == "MB") v /= 1000; else if (u == "kB" || u == "KB") v /= 1000000; else if (u == "B") v = 0
      t += v }
    END { print int(t) }'
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
  [ "$DISK_AVAIL_GB" -lt "$MIN_DISK_GB" ] && refuse "$DISK_GB GB free disk; the images alone take ~25 GB and a 40 GB disk fills during the first build: need $MIN_DISK_GB GB free (100 GB disk recommended)"
  [ "$DISK_AVAIL_GB" -ge "$MIN_DISK_GB" ] && [ "$DISK_AVAIL_GB" -lt "$WARN_DISK_GB" ] && warn "$DISK_GB GB free disk: enough to start; 100 GB recommended"
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
  STATE_DIR="$SVC_HOME/.aidenhq"
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
  printf '    install the host packages (Docker, Node 24%s, ...) from fingerprint-pinned repos, at the kernel'"'"'s pinned versions;\n' "$([ "$NO_TS" = 1 ] || echo ', Tailscale')"
  printf '    set Docker log rotation and build-cache limits and a journald cap; enable lingering;\n'
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
  say "creating $SVC (AidenHQ never runs as root); it gets passwordless sudo and root's SSH keys, because setup turns off root SSH login"
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

# ------------------------------------------------------------------------------------------------ the release
# rel KEY: one string from the release file (jq when present; a dry run on a bare box uses the fallback parser, which
# reads only our own one-key-per-line format).
rel() {
  if have jq; then jq -r "$1 // empty" "$RELFILE"; return; fi
  k=${1#.}; k=${k##*.}
  sed -n "s/.*\"$k\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$RELFILE" | head -1
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
    if [ -n "$AUTH_HDR" ] && [ -z "${AIDENHQ_RELEASE_URL:-}" ] && have jq; then got() { gh_asset "$REL" "$REL.json" "$RELFILE"; }
    else got() { fetch "$url" "$RELFILE"; }; fi
    got || {
      if [ "$DRY" = 1 ]; then warn "can't fetch $url yet (release not published?): planning without it"; RELFILE=''; return 0; fi
      die "can't fetch the release file $url"; }
    say "release file: $url"
  fi
  # A fetched release file must be the one this installer was cut with: its digest is baked in, so a release this copy
  # wasn't cut for (another --release, or an uncut copy) is refused; each release's own install.sh carries its digest.
  digest=$(sha256 "$RELFILE")
  if [ -z "${AIDENHQ_RELEASE_FILE:-}" ]; then
    if [ "$REL" != "$DEFAULT_RELEASE" ] || [ -z "$RELEASE_SHA256" ]; then
      why="this installer carries no digest for release $REL: use its own https://github.com/$DISTRO_REPO/releases/download/$REL/install.sh"
      [ "$DRY" = 1 ] || die "$why"
      warn "$why (a real run stops here)"
    else
      [ "$digest" = "$RELEASE_SHA256" ] || die "release file digest $digest isn't the one this installer was cut with ($RELEASE_SHA256)"
      say "digest matches the installer's ($digest)"
    fi
  fi
  # The distro commit setup pins in instance.yaml (release:), only for the release this copy was cut for.
  REL_COMMIT=''; [ "$REL" != "$DEFAULT_RELEASE" ] || REL_COMMIT=$RELEASE_COMMIT
  [ "$(rel .release)" = "$REL" ] || die "the release file says it is '$(rel .release)', not $REL"
  # One product sha is the whole set: the official modules are its own modules/ tree. Images are pulled by digest (the
  # release CI checked each one is built from this sha); here each must be a ghcr.io/aiden-hq digest reference.
  KERNEL_SHA=$(rel .kernel) KERNEL_REPO=$(rel .kernel_repo)
  [ -n "$KERNEL_REPO" ] || KERNEL_REPO=Aiden-HQ/AidenHQ
  if ! is_sha "$KERNEL_SHA"; then
    [ "$DRY" = 1 ] || die "release $REL isn't cut yet: no real kernel sha"
    warn "release $REL has a placeholder kernel sha: a real run stops here"
  fi
  ! have jq || jq -e '(.images // {}) | type == "object" and all(to_entries[]; (.key | test("^[a-z0-9][a-z0-9._-]*$"))
      and (.value | type == "string" and test("^ghcr\\.io/aiden-hq/[a-z0-9][a-z0-9._-]*@sha256:[0-9a-f]{64}$")))' "$RELFILE" >/dev/null \
    || die "release $REL's images aren't all ghcr.io/aiden-hq/<name>@sha256:<digest>"
  say "kernel $KERNEL_REPO@$KERNEL_SHA (the official modules are its modules/)"
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
  as_svc git -C "$1" fetch -q origin main "$3" \
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
  step "Fetch and verify the product"
  [ -n "$RELFILE" ] || { say "(no release file: skipped)"; return 0; }
  checkout_at "$DIR" "$(repo_url "$KERNEL_REPO")" "$KERNEL_SHA"
  verify_at "$DIR" "$KERNEL_SHA"
  as_svc mkdir -p -m 700 "$STATE_DIR"
  [ "$DRY" = 1 ] || say "verified: the product (kernel and official modules) matches the release"
}

# The pinned kernel must carry the unattended setup and its host pins, and list this host's release.
check_product() {
  if [ ! -f "$DIR/ops/vm/pins.json" ] || ! grep -q -- '--unattended' "$DIR/ops/setup.sh" 2>/dev/null; then
    [ "$DRY" = 1 ] && { say "(no checkout in a dry run: the kernel check is skipped)"; return 0; }
    die "$DIR isn't a kernel with the unattended setup (no ops/vm/pins.json, or no --unattended in ops/setup.sh)"
  fi
  jq -e --arg c "$CODENAME" '.releases | has($c)' "$DIR/ops/vm/pins.json" >/dev/null \
    || refuse "$OS_NAME isn't supported by this kernel (Ubuntu 22.04, 24.04, 26.04; Debian 12, 13)"
  :
}

# ------------------------------------------------------------------------------------------------ host tuning
# Docker's log rotation and build-cache limits, and the journal cap. daemon.json is written before the product's setup
# installs Docker; setup then merges its own runtime into it and keeps these keys, so Docker's first start has them all.
host_tuning() {
  step "Docker log and build-cache limits, journal cap (disk headroom)"
  if [ "$DRY" = 1 ]; then
    say "would merge into /etc/docker/daemon.json: json-file logs $LOG_MAX x $LOG_FILES, build cache GC at ${BUILD_CACHE_GB}GB"
  else
    cur=$($SUDO cat /etc/docker/daemon.json 2>/dev/null || echo '{}')
    # Only keys the owner hasn't set: their own choices win.
    printf '%s' "$cur" | jq --arg m "$LOG_MAX" --arg f "$LOG_FILES" --arg k "${BUILD_CACHE_GB}GB" '
      (if has("log-driver") then . else . + {"log-driver": "json-file", "log-opts": {"max-size": $m, "max-file": $f}} end)
      | (if .builder.gc then . else .builder.gc = {"enabled": true, "defaultKeepStorage": $k} end)' >"$TMPD/daemon.json" \
      || die "/etc/docker/daemon.json isn't valid JSON"
    root_write /etc/docker/daemon.json 644 <"$TMPD/daemon.json" || :
  fi
  printf '[Journal]\nSystemMaxUse=%s\n' "$JOURNAL_MAX" | root_write /etc/systemd/journald.conf.d/90-aidenhq.conf 644 \
    && as_root systemctl restart systemd-journald
  :
}

# ------------------------------------------------------------------------------------------------ the product
# safe_val NAME VALUE: a value for setup's KEY="value" config. Its parser reads lines, never sources them; a quote, a
# backslash or any control character (a newline would start a new KEY) is refused rather than escaped.
safe_val() {
  case "$2" in *[\"\'\\\`\$]*) die "$1 contains a quote, backslash, backtick or dollar sign: not accepted" ;; esac
  [ "$(printf '%s' "$2" | tr -d '[:cntrl:]')" = "$2" ] || die "$1 contains a control character (newline?): not accepted"
}
# The owner's email: the board's owner account is made for it, and setup stops without it. AIDENHQ_OWNER_EMAIL, else
# asked for on the terminal (the one thing the installer can't derive).
# An existing install of this user (ops/setup.sh's instance repo): the release it follows and its owner. A run on it is an
# upgrade (or a repair): the owner email is the instance's, and an older release than it follows is refused (check_upgrade).
existing_install() {
  INST_YAML="$SVC_HOME/aidenhq-instance/instance.yaml" INST_REL='' INST_EMAIL=''
  [ -r "$INST_YAML" ] || { INST_YAML=''; return 0; }   # the service user's own file, or root's run
  INST_REL=$(sed -n 's/^release: *{ *name: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}.*/\1/p' "$INST_YAML" | head -1)
  INST_EMAIL=$(sed -n 's/^  owner_email: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$INST_YAML" | head -1)
  [ -n "${AIDENHQ_OWNER_EMAIL:-}" ] || [ -z "$INST_EMAIL" ] || AIDENHQ_OWNER_EMAIL=$INST_EMAIL
}
# check_upgrade: this release against the one the existing instance follows. Newer: the product's setup moves the pin (one
# instance commit: product:, release:, and the obsolete `aidenhq` marketplace entry dropped, since the official modules now
# ship inside the product; other marketplaces stay) before its apply, and reverts that commit when the apply fails, so the
# installer never edits instance.yaml itself; the same: a repair; older: refused, nothing changed.
check_upgrade() {
  [ -n "${INST_YAML:-}" ] || return 0
  if [ -z "$INST_REL" ]; then
    say "existing install with no release pinned (its product is pinned by hand): setup leaves its pin as it is"
  elif [ "$INST_REL" = "$REL" ]; then
    say "existing install on $REL: this run repairs it"
  elif ver_ge "$INST_REL" "$REL"; then
    why="this server runs $INST_REL, newer than $REL: downgrades are refused (use the newest installer, https://get.aidenhq.ai)"
    [ "$DRY" = 1 ] || die "$why"
    warn "$why (a real run stops here)"
  else
    say "upgrading from $INST_REL to $REL: setup moves the instance's pin, then applies; a failed health check goes back to $INST_REL"
    ! grep -Eq '^[[:space:]]*-[[:space:]]*\{[[:space:]]*name:[[:space:]]*"?aidenhq"?[[:space:],]' "$INST_YAML" \
      || say "the instance's aidenhq marketplace entry goes with that pin: the official modules are in the product now"
  fi
}
ensure_owner_email() {
  if [ -z "${AIDENHQ_OWNER_EMAIL:-}" ] && [ "$NONINT" = 0 ] && [ "$DRY" = 0 ]; then
    printf '    Owner email (the board account is made for it): ' >/dev/tty
    read -r AIDENHQ_OWNER_EMAIL </dev/tty || AIDENHQ_OWNER_EMAIL=''
  fi
  case "${AIDENHQ_OWNER_EMAIL:-}" in
    *[!A-Za-z0-9@._+-]*|*@*@*) refuse "AIDENHQ_OWNER_EMAIL isn't a plain email address" ;;
    ?*@?*.?*) ;;
    *) refuse "set AIDENHQ_OWNER_EMAIL=<email>: the board's owner account is made for it" ;;
  esac
}
# The owner's timezone: AIDENHQ_TIMEZONE, a plain IANA zone name, passed to setup as TIMEZONE. Unset on a Mac it is this
# Mac's zone (the VM's clock is UTC); unset on Linux setup uses the host's.
ensure_timezone() {
  case "${AIDENHQ_TIMEZONE:-}" in
    *[!A-Za-z0-9/_+-]*) refuse "AIDENHQ_TIMEZONE isn't a plain IANA zone name (like Asia/Dubai)" ;;
  esac
}
mac_timezone() {
  [ -z "${AIDENHQ_TIMEZONE:-}" ] || return 0
  z=$(readlink /etc/localtime 2>/dev/null || :); z=${z#*zoneinfo/}
  case "$z" in */*|UTC) AIDENHQ_TIMEZONE=$z ;; esac
}
# write_setup_config: secrets only, never read from the environment by setup. mktemp makes the file 0600, root-owned and
# new (O_EXCL) in root's /run before anything is written to it. Owner, sizing and the rest go in the environment.
SECRET_KEYS="OPENROUTER_KEY OPENROUTER_MANAGEMENT_KEY OPENROUTER_LIMIT_USD TS_AUTHKEY TS_APPS_AUTHKEY GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET"
write_setup_config() {
  given=0
  for k in $SECRET_KEYS; do eval "v=\${$k:-}"; [ -z "$v" ] || { safe_val "$k" "$v"; given=1; }; done
  [ "$given" = 1 ] || return 0
  if [ "$DRY" = 1 ]; then PENV="/run/aidenhq-setup.XXXXXX (root-only)"; return 0; fi
  PENV=$($SUDO mktemp /run/aidenhq-setup.XXXXXX) || die "can't create the root-only setup config"
  for k in $SECRET_KEYS; do eval "v=\${$k:-}"; [ -z "$v" ] || printf '%s="%s"\n' "$k" "$v"; done | $SUDO tee "$PENV" >/dev/null
}

# write_token_file: a private kernel repo's token, for setup's own fetch (ops/setup.sh --kernel-token-file): a new
# root-only file (mktemp, 0600), written through stdin (never argv) and deleted with the setup config.
write_token_file() {
  KTOK_FILE='' tok="${AIDENHQ_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"
  [ -n "$tok" ] || return 0
  case "$tok" in *[!A-Za-z0-9_]*) die "AIDENHQ_GITHUB_TOKEN isn't a GitHub token (letters, digits and _ only)" ;; esac
  if [ "$DRY" = 1 ]; then KTOK_FILE="/run/aidenhq-ktoken.XXXXXX (root-only)"; return 0; fi
  KTOK_FILE=$($SUDO mktemp /run/aidenhq-ktoken.XXXXXX) || die "can't create the root-only token file"
  printf '%s' "$tok" | $SUDO tee "$KTOK_FILE" >/dev/null
}

# root_verify: right before root runs the kernel, verify the checkout as root against a root-owned copy of the objects: a
# --no-local clone (the service user serves the objects; root's git rehashes every one it receives; replace refs are
# ignored), then the work tree is compared file by file to the pinned commit through a root-owned index. The service
# user's own .git is never trusted here. The pinned commit is then exported from that clone into root-owned
# $KROOT/<sha> (0755, nothing writable by anyone else): setup runs from there, never from the checkout.
KROOT=/opt/aidenhq/kernel
root_verify() {
  KCOPY="$KROOT/$KERNEL_SHA"
  if [ "$DRY" = 1 ]; then printf '    %swould verify as root:%s %s against a root-owned clone at %s, and export it to %s\n' "$D" "$N" "$DIR" "$KERNEL_SHA" "$KCOPY"; return 0; fi
  up="git upload-pack"; { [ -n "$SUDO" ] || [ "$(id -u)" = 0 ]; } && up="runuser -u $SVC -- git upload-pack"
  RV=$($SUDO mktemp -d /var/tmp/aidenhq-verify.XXXXXX)
  $SUDO env GIT_NO_REPLACE_OBJECTS=1 git clone -q --bare --no-local --upload-pack="$up" "$DIR" "$RV/k.git" >>"$LOG" 2>&1 \
    || die "root verification: can't clone $DIR"
  $SUDO env GIT_NO_REPLACE_OBJECTS=1 GIT_DIR="$RV/k.git" GIT_WORK_TREE="$DIR" GIT_INDEX_FILE="$RV/index" sh -c '
    git cat-file -e "$1^{commit}" && git read-tree "$1" && git update-index -q --refresh >/dev/null; git diff-files --quiet' _ "$KERNEL_SHA" \
    || { $SUDO rm -rf "$RV"; die "root verification failed: $DIR differs from $KERNEL_SHA"; }
  if ! $SUDO test -d "$KCOPY"; then
    $SUDO sh -c 'mkdir -p -m 0755 "$3" && mkdir -m 0755 "$1/tree" \
      && GIT_NO_REPLACE_OBJECTS=1 git --git-dir="$1/k.git" archive -o "$1/k.tar" "$2" && tar -x --no-same-owner --no-same-permissions -f "$1/k.tar" -C "$1/tree" \
      && chmod -R u+rwX,go+rX,go-w "$1/tree" && { [ "$(id -u)" != 0 ] || chown -R root:root "$1/tree"; } && mv "$1/tree" "$3/$2"' _ "$RV" "$KERNEL_SHA" "$KROOT" >>"$LOG" 2>&1 \
      || { $SUDO rm -rf "$RV"; die "can't export $KERNEL_SHA to $KCOPY"; }
  fi
  $SUDO rm -rf "$RV"
}

run_setup() {
  step "AidenHQ setup (ops/setup.sh: host packages, vault, services, Paperclip, board)"
  # ops/setup.sh runs as root from root's verified copy ($KROOT/<sha>, root_verify), but still reads the service user's
  # checkout (its .env and generated config) as root: keep that to a service user that is already root-equivalent (sudo
  # for everything), as it is when it invoked us with sudo or we created it.
  if [ "$DRY" = 0 ] && [ "$(id -u)" = 0 ] && ! sudo -l -U "$SVC" 2>/dev/null | grep -q '(ALL\( : ALL\)\{0,1\}) \(NOPASSWD: \)\{0,1\}ALL'; then
    die "$SVC can't sudo everything, but this kernel's setup reads $SVC's checkout as root: give $SVC sudo, or let the installer create its own user"
  fi
  verify_at "$DIR" "$KERNEL_SHA"
  root_verify
  set -- --checkout "$DIR" --unattended; [ "$NO_TS" = 1 ] && set -- "$@" --no-tailscale
  write_setup_config
  [ -z "$PENV" ] || set -- "$@" --config "$PENV"
  write_token_file
  [ -z "$KTOK_FILE" ] || set -- "$@" --kernel-token-file "$KTOK_FILE"
  if [ "$DRY" = 1 ]; then
    printf '    %swould run:%s %senv AIDENHQ_USER=%s OWNER_EMAIL=%s TIMEZONE=%s MAX_CONCURRENT=%s TIMEOUT_MINUTES=%s CI_RUNNERS=%s bash %s/ops/setup.sh %s\n' \
      "$D" "$N" "${SUDO:+$SUDO }" "$SVC" "${AIDENHQ_OWNER_EMAIL:-<owner email>}" "${AIDENHQ_TIMEZONE:-<host zone>}" "$MAX_CONCURRENT" "$JOB_TIMEOUT" "$CI_RUNNERS" "$KCOPY" "$*"
    return 0
  fi
  log "+ setup $*"
  # The product's own progress lines ("• ..." and AIDENHQ_PROGRESS=...) reach the terminal; everything goes to the log.
  # The release goes into the new instance.yaml (all three, or none when this copy wasn't cut for it).
  { $SUDO env AIDENHQ_USER="$SVC" OWNER_EMAIL="$AIDENHQ_OWNER_EMAIL" OWNER_NAME="${AIDENHQ_OWNER_NAME:-$SVC}" TIMEZONE="${AIDENHQ_TIMEZONE:-}" MODULES="${MODULES:-}" \
      AIDENHQ_RELEASE="${REL_COMMIT:+$REL}" AIDENHQ_RELEASE_REPO="${REL_COMMIT:+$DISTRO_REPO}" AIDENHQ_RELEASE_SHA="$REL_COMMIT" \
      MAX_CONCURRENT="$MAX_CONCURRENT" TIMEOUT_MINUTES="$JOB_TIMEOUT" CI_RUNNERS="$CI_RUNNERS" AIDENHQ_PROGRESS_BASE="${PROGRESS_SLICE:-}" \
      bash "$KCOPY/ops/setup.sh" "$@" </dev/null 2>&1 && echo 0 >"$TMPD/rc" || echo $? >"$TMPD/rc"; } \
    | tee -a "$LOG" "$TMPD/setup.out" | while IFS= read -r l; do
        case "$l" in "• "*) say "${l#• }" ;; AIDENHQ_PROGRESS=*) printf '%s\n' "$l" ;; *) if [ "$VERBOSE" = 1 ]; then printf '    %s\n' "$l"; fi ;; esac
      done
  rc=$(cat "$TMPD/rc")
  rm_penv
  [ "$rc" = 0 ] || die "ops/setup.sh failed (exit $rc)"
  # This run's output only (the log keeps earlier runs): the last of each line wins.
  SETUP_URL=$(sed -n 's/^AIDENHQ_SETUP_URL=//p' "$TMPD/setup.out" | tail -1)
  SSH_TUNNEL=$(sed -n 's/^AIDENHQ_SSH_TUNNEL=//p' "$TMPD/setup.out" | tail -1)
  BOARD_URL=$(sed -n 's/^AIDENHQ_BOARD_URL=//p' "$TMPD/setup.out" | tail -1)
}

# Prune timers: the product's weekly Docker cleanup, plus a guard that prunes harder when free space drops below the reserve.
disk_guard() {
  step "Disk guard and Docker cleanup"
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
  as_svc sh -c 'cat > "$1"' _ "$STATE_DIR/bin/disk-guard.sh" <"$TMPD/guard"
  as_svc sh -c 'cat > "$1"' _ "$units/aidenhq-disk-guard.service" <"$TMPD/gs"
  as_svc sh -c 'cat > "$1"' _ "$units/aidenhq-disk-guard.timer" <"$TMPD/gt"
  as_svc systemctl --user daemon-reload
  as_svc systemctl --user enable --now aidenhq-disk-guard.timer
  [ -f "$DIR/ops/units/prune-docker.timer" ] && as_svc systemctl --user enable --now prune-docker.timer
  say "disk guard: prunes below ${DISK_RESERVE_GB} GB free; weekly Docker cleanup on"
}

finish() {
  if [ "$DRY" = 1 ]; then
    printf '\n%sDry run done.%s A real run ends with:\n' "$Y" "$N"; SETUP_URL="https://<board-host>:8446/setup?token=<one-time-token>"
    [ "$NO_TS" = 0 ] || SSH_TUNNEL="ssh -N -L 3121:127.0.0.1:3121 -L 3120:127.0.0.1:3120 -L 3130:127.0.0.1:3130 $SVC@<this-host>"
  fi
  # Inside a Mac's VM (the macOS path below): the Mac prints the way in and the 100% line, once. The link goes to a file
  # the Mac reads back (0600: it is a one-time sign-in).
  if [ -n "${AIDENHQ_MAC_VM:-}" ]; then
    [ "$DRY" = 1 ] || [ -z "$SETUP_URL" ] || (umask 077; printf '%s\n' "$SETUP_URL" >"$STATE_DIR/setup-url") || :
    return 0
  fi
  progress_emit ready   # 100%, and the link follows
  printf '\n%sAidenHQ is running.%s\n\n' "$G$B" "$N"
  if [ -n "$SSH_TUNNEL" ]; then
    printf '  The board listens on this server only. On your laptop, open this tunnel first and leave it running:\n\n    %s%s%s\n\n' "$B" "$SSH_TUNNEL" "$N"
  fi
  if [ -n "$SETUP_URL" ]; then
    printf '  Open this link to finish in your browser (one use, 72 hours):\n\n    %s%s%s\n\n' "$B" "$SETUP_URL" "$N"
    printf '  It sets up your account and authenticator, your model key and your channels.\n'
    [ -n "$SSH_TUNNEL" ] || printf '  Your device must be on the same tailnet.\n'
  elif [ -n "$INST_YAML" ]; then   # an upgrade or a repair: the owner's account exists, there is no setup link
    printf '  This server is updated to release %s.%s\n' "$REL" "${BOARD_URL:+ The board is at $BOARD_URL}"
  else
    printf '  The setup link is in the log (search for "Done."): %s\n' "$LOG"
  fi
  printf '  Install log: %s    Service logs: journalctl --user -u aidenhq-runner; docker compose logs (in %s)\n' "$LOG" "$DIR"
  if $SUDO test -e /root/aidenhq-vault-recovery.txt 2>/dev/null; then
    printf '  Vault recovery key: sudo cat /root/aidenhq-vault-recovery.txt, store it, then sudo shred -u it.\n'
  fi
  # Machine-readable, plain and at the start of a line (no --verbose needed): scripts and agents grep these.
  printf '\n'
  [ -z "$SETUP_URL" ] || printf 'AIDENHQ_SETUP_URL=%s\n' "$SETUP_URL"
  [ -z "$SSH_TUNNEL" ] || printf 'AIDENHQ_SSH_TUNNEL=%s\n' "$SSH_TUNNEL"
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
  as_svc rm -f "$STATE_DIR/bin/disk-guard.sh"
  printf '\n%s Kept (delete by hand if you want them gone):\n' "$([ "$DRY" = 1 ] && echo 'A real run stops and removes these.' || echo 'Stopped and removed.')"
  printf '  %s (checkout and data/), %s/aidenhq-instance, the vault (%s/.config/aidenhq, %s/.local/share/aidenhq),\n' "$DIR" "$SVC_HOME" "$SVC_HOME" "$SVC_HOME"
  printf '  Docker volumes (docker volume ls), packages (Docker, Node, Tailscale; held: apt-mark showhold), system units aidenhq-*.\n'
}

# ------------------------------------------------------------------------------------------------ macOS: a Linux VM
# AidenHQ's gates need Linux (bwrap user namespaces, pasta, gVisor, the gocryptfs vault, systemd, AppArmor), so on a Mac
# this script makes an Ubuntu 24.04 VM with Lima (Apple's Virtualization.framework) and runs its own Linux path inside
# it, unchanged. Only the browser ports are forwarded, to this Mac's localhost: the board (3121), the admin listener
# (3120: sign-in) and the gate (3130: the owner's apps at <app>.localhost:3130). Never uses sudo.
LIMA_VERSION=2.3.0 LIMA_MIN=2.0.0   # v2.3.0 published 2026-11-06; an existing limactl at LIMA_MIN or newer is used
LIMA_SHA256_arm64=b7af444bd8f91d3c307477e562f2cf3bd7595d62b9429185e4fa841563578cfc
LIMA_SHA256_x86_64=d58bc7d6b8158d638720d8c8fdb17eb58527dfead6a29a5b60f48a35ee4a65a6
UBUNTU_IMG=https://cloud-images.ubuntu.com/releases/noble/release-20261017/ubuntu-24.04-server-cloudimg   # 2026-10-17
UBUNTU_SHA256_arm64=50e24e1fb79e89116e939d90aa7738f7af48c442fa1bc2510131e0b39c50348e
UBUNTU_SHA256_amd64=04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94
VM=aidenhq VM_AGENT=ai.aidenhq.vm

ver_ge() { awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, ".")
  for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 } exit 0 }'; }
vm_state() { [ -x "${LIMACTL:-}" ] && "$LIMACTL" list --format '{{.Status}}' "$VM" 2>/dev/null || :; }   # '' = no VM
vm_sh() { "$LIMACTL" shell --workdir / "$VM" "$@"; }

mac_detect() {
  MACOS=$(sw_vers -productVersion 2>/dev/null) || die "can't read the macOS version (sw_vers)"
  [ "${MACOS%%.*}" -ge 13 ] 2>/dev/null || die "macOS $MACOS is too old: AidenHQ's VM (Lima on Apple's Virtualization framework) needs macOS 13 or later"
  case "$(uname -m)" in
    arm64) MARCH=arm64 IMG_ARCH=aarch64 IMG=$UBUNTU_IMG-arm64.img IMG_SHA256=$UBUNTU_SHA256_arm64 LIMA_SHA256=$LIMA_SHA256_arm64 ;;
    x86_64) MARCH=x86_64 IMG_ARCH=x86_64 IMG=$UBUNTU_IMG-amd64.img IMG_SHA256=$UBUNTU_SHA256_amd64 LIMA_SHA256=$LIMA_SHA256_x86_64 ;;
    *) die "CPU architecture $(uname -m) isn't supported (Apple silicon and Intel Macs are)." ;;
  esac
  MCORES=$(sysctl -n hw.ncpu) MRAM_GB=$(($(sysctl -n hw.memsize) / 1073741824))
  LIMA_HOME="${LIMA_HOME:-$HOME/.lima}"; export LIMA_HOME
  p=$LIMA_HOME; while [ ! -d "$p" ]; do p=$(dirname "$p"); done
  MFREE_GB=$(df -Pk "$p" | awk 'NR==2 { print int($4 / 1048576) }')
  LIMACTL=''
  for c in "$HOME/.aidenhq/lima/bin/limactl" "$(command -v limactl 2>/dev/null || :)"; do   # ours first, then PATH (Homebrew)
    [ -n "$c" ] && [ -x "$c" ] || continue
    LIMA_HAVE=$("$c" --version 2>/dev/null | awk '{ print $NF }')
    if ver_ge "${LIMA_HAVE:-0}" "$LIMA_MIN"; then LIMACTL=$c; break; fi
  done
  :
}

# VM size from the Mac: half its cores (4..8) and half its memory (8..16 GB, leaving macOS at least 4), a 100 GB disk.
# AIDENHQ_VM_CPUS, AIDENHQ_VM_MEMORY (GB) and AIDENHQ_VM_DISK (GB) override them; they apply when the VM is made.
mac_size() {
  for x in "${AIDENHQ_VM_CPUS:-}" "${AIDENHQ_VM_MEMORY:-}" "${AIDENHQ_VM_DISK:-}"; do
    case "$x" in *[!0-9]*) die "AIDENHQ_VM_CPUS, AIDENHQ_VM_MEMORY and AIDENHQ_VM_DISK are whole numbers, not '$x'" ;; esac
  done
  c=$((MCORES / 2)); [ "$c" -lt 4 ] && c=4; [ "$c" -gt 8 ] && c=8; [ "$c" -gt "$MCORES" ] && c=$MCORES
  m=$((MRAM_GB / 2)); [ "$m" -lt 8 ] && m=8; [ "$m" -gt 16 ] && m=16; [ "$m" -gt $((MRAM_GB - 4)) ] && m=$((MRAM_GB - 4))
  VM_CPUS=${AIDENHQ_VM_CPUS:-$c} VM_MEM=${AIDENHQ_VM_MEMORY:-$m} VM_DISK=${AIDENHQ_VM_DISK:-100}
  [ "$VM_CPUS" -ge "$MIN_CORES" ] || refuse "the VM would get $VM_CPUS CPU(s); AidenHQ needs at least $MIN_CORES (4 recommended)"
  [ "$VM_MEM" -ge 6 ] || refuse "this Mac ($MRAM_GB GB) can give the VM only $VM_MEM GB of memory; AidenHQ needs 6 GB (8 recommended), so a Mac with 12 GB or more"
  [ "$VM_DISK" -ge "$MIN_DISK_GB" ] || refuse "a $VM_DISK GB VM disk is too small; AidenHQ needs $MIN_DISK_GB GB (100 recommended)"
  [ -n "$(vm_state)" ] && return 0
  [ "$MFREE_GB" -ge "$MIN_DISK_GB" ] || refuse "$MFREE_GB GB free on this Mac; the VM's disk grows to ~$MIN_DISK_GB GB as the images land: free some space"
  [ "$MFREE_GB" -ge "$MIN_DISK_GB" ] && [ "$MFREE_GB" -lt "$VM_DISK" ] && warn "$MFREE_GB GB free: enough to start, but the VM's disk can grow to $VM_DISK GB"
  for p in 3121 3120 3130; do
    if nc -z 127.0.0.1 "$p" >/dev/null 2>&1; then refuse "port $p on this Mac is taken (lsof -nP -iTCP:$p): AidenHQ's VM forwards it there"; fi
  done
  :
}

mac_lima() {
  step "Lima (the VM manager)"
  if [ -n "$LIMACTL" ]; then say "Lima $LIMA_HAVE: $LIMACTL"; return 0; fi
  url="https://github.com/lima-vm/lima/releases/download/v$LIMA_VERSION/lima-$LIMA_VERSION-Darwin-$MARCH.tar.gz"
  LIMACTL="$HOME/.aidenhq/lima/bin/limactl"
  if [ "$DRY" = 1 ]; then say "would install Lima $LIMA_VERSION into ~/.aidenhq/lima from $url (sha256 checked)"; return 0; fi
  fetch "$url" "$TMPD/lima.tgz" || die "can't download $url"
  got=$(sha256 "$TMPD/lima.tgz")
  [ "$got" = "$LIMA_SHA256" ] || die "the Lima download's digest $got isn't the pinned $LIMA_SHA256"
  rm -rf "$HOME/.aidenhq/lima"; mkdir -p "$HOME/.aidenhq/lima"
  tar -xzf "$TMPD/lima.tgz" -C "$HOME/.aidenhq/lima" || die "can't unpack Lima into ~/.aidenhq/lima"
  say "installed Lima $LIMA_VERSION into ~/.aidenhq/lima (digest checked)"
}

mac_template() {
  cat <<EOF
# AidenHQ's VM, made by install.sh. Resize (stopped): limactl edit $VM --cpus N --memory GB --disk GB (the disk only grows).
minimumLimaVersion: $LIMA_MIN
vmType: vz
images:
- location: $IMG
  arch: $IMG_ARCH
  digest: sha256:$IMG_SHA256
cpus: $VM_CPUS
memory: ${VM_MEM}GiB
disk: ${VM_DISK}GiB
# Nothing of the Mac is shared: Engineer jobs run in here.
mounts: []
containerd:
  system: false
  user: false
# The browser listeners only (the board, the admin listener, the gate's app doors), to this Mac's localhost, each on its
# own port (an app door's origin includes it); every other guest port stays in the VM.
portForwards:
- guestPort: 3121
  hostIP: 127.0.0.1
- guestPort: 3120
  hostIP: 127.0.0.1
- guestPort: 3130
  hostIP: 127.0.0.1
- guestIP: 127.0.0.1
  guestPortRange: [1, 65535]
  proto: any
  ignore: true
- guestIP: 0.0.0.0
  guestPortRange: [1, 65535]
  proto: any
  ignore: true
EOF
}

# Keep the Mac awake while the VM runs? Asked once (default yes); a rerun keeps the answer; AIDENHQ_KEEP_AWAKE=1|0 sets it.
mac_keep_awake() {
  plist="$HOME/Library/LaunchAgents/$VM_AGENT.plist"
  case "${AIDENHQ_KEEP_AWAKE:-}" in
    1|true|yes) AWAKE=1 ;;
    0|false|no) AWAKE=0 ;;
    *) if [ -f "$plist" ]; then if grep -q caffeinate "$plist"; then AWAKE=1; else AWAKE=0; fi
       elif [ "$NONINT" = 1 ] || [ "$DRY" = 1 ]; then AWAKE=0
       else
         printf '    Keep this Mac awake while AidenHQ runs? On power only; when it sleeps, every agent pauses. [Y/n] ' >/dev/tty
         read -r a </dev/tty || a=n
         case "$a" in [nN]*) AWAKE=0 ;; *) AWAKE=1 ;; esac
       fi ;;
  esac
}

# The LaunchAgent: starts the VM at login (launchd owns it, like `limactl autostart`), under `caffeinate -s` when kept awake.
mac_agent_plist() {
  case "$LIMACTL$LIMA_HOME$HOME" in *[\&\<\>]*) die "a path with &, < or > can't go in a launchd plist: $LIMACTL" ;; esac
  awake=''; [ "$AWAKE" = 1 ] && awake='<string>/usr/bin/caffeinate</string><string>-s</string>'
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$VM_AGENT</string>
  <key>EnvironmentVariables</key>
  <dict><key>LIMA_HOME</key><string>$LIMA_HOME</string><key>PATH</key><string>$(dirname "$LIMACTL"):/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>ProgramArguments</key>
  <array>$awake<string>$LIMACTL</string><string>start</string><string>$VM</string><string>--foreground</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$HOME/.aidenhq/vm.log</string>
  <key>StandardErrorPath</key><string>$HOME/.aidenhq/vm.log</string>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF
}

mac_vm() {
  step "Linux VM '$VM' (Ubuntu 24.04 on Apple's Virtualization framework)"
  st=$(vm_state)
  if [ -z "$st" ]; then
    say "making it: $VM_CPUS CPUs, $VM_MEM GB memory, a $VM_DISK GB disk (a sparse file in $LIMA_HOME/$VM: it takes only what is used)"
    mac_template >"$TMPD/$VM.yaml"
    [ "$DRY" = 1 ] || say "the first start downloads Ubuntu 24.04 (~600 MB, digest checked) and boots it"
    run "$LIMACTL" --tty=false start --name "$VM" "$TMPD/$VM.yaml" || die "Lima couldn't make the VM (log: $LOG)"
  else say "exists ($st); its size stays as made (resize: limactl stop $VM; limactl edit $VM --cpus N --memory GB --disk GB)"; fi
  mac_agent_plist >"$TMPD/plist"
  dom="gui/$(id -u)" changed=1
  [ -f "$plist" ] && cmp -s "$TMPD/plist" "$plist" && changed=0
  if [ "$DRY" = 1 ]; then
    [ "$changed" = 0 ] || say "would write $plist (start at login$([ "$AWAKE" = 1 ] && echo ', awake on power' || echo '; the Mac may sleep: AIDENHQ_KEEP_AWAKE=1 keeps it awake on power')) and load it"
    return 0
  fi
  if [ "$changed" = 1 ]; then
    # An old agent takes its VM down with it; bootout returns before the job is gone.
    if launchctl bootout "$dom/$VM_AGENT" >/dev/null 2>&1; then
      n=0; while launchctl print "$dom/$VM_AGENT" >/dev/null 2>&1 && [ "$n" -lt 60 ]; do sleep 1; n=$((n + 1)); done
    fi
    mkdir -p "$(dirname "$plist")" "$HOME/.aidenhq"; cp "$TMPD/plist" "$plist"
  fi
  # launchd owns the VM from here (and caffeinate with it), so a VM started by hand is handed over.
  if ! launchctl print "$dom/$VM_AGENT" >/dev/null 2>&1; then
    [ "$(vm_state)" != Running ] || run "$LIMACTL" --tty=false stop "$VM"
    run launchctl bootstrap "$dom" "$plist" || die "launchctl couldn't load $plist"
  elif [ "$(vm_state)" != Running ]; then run launchctl kickstart "$dom/$VM_AGENT"; fi
  n=0
  until [ "$(vm_state)" = Running ] && vm_sh true >/dev/null 2>&1; do
    n=$((n + 1)); [ "$n" -le 120 ] || die "the VM didn't come up in 10 minutes: see ~/.aidenhq/vm.log and $LIMA_HOME/$VM/ha.stderr.log"
    sleep 5
  done
  say "running; starts at login ($plist)"
}

# The installer for the VM: AIDENHQ_INSTALLER_FILE, else this file when run from one, else get.aidenhq.ai (curl | sh).
mac_installer() {
  if [ -n "${AIDENHQ_INSTALLER_FILE:-}" ]; then echo "$AIDENHQ_INSTALLER_FILE"
  elif [ -f "$0" ] && grep -q '^DISTRO_REPO=' "$0" 2>/dev/null; then echo "$0"
  else fetch https://get.aidenhq.ai "$TMPD/install.sh" || die "can't download the installer for the VM"; echo "$TMPD/install.sh"; fi
}

mac_inner() {
  step "AidenHQ in the VM (this installer's Linux path)"
  set -- --release "$REL"
  [ "$DRY" = 1 ] && set -- "$@" --dry-run
  [ "$NO_TS" = 1 ] && set -- "$@" --no-tailscale
  [ "$VERBOSE" = 1 ] && set -- "$@" --verbose
  [ "$NONINT" = 1 ] && set -- "$@" --non-interactive
  [ -z "$DIR" ] || set -- "$@" --dir "$DIR"
  if [ "$DRY" = 1 ] && [ "$(vm_state)" != Running ]; then say "would run in the VM: sh install.sh $*"; return 0; fi
  src=$(mac_installer)
  # Secrets go over the VM's stdin into a 0600 file that the VM sources, then shreds: never argv, never Lima's YAML.
  # Checked before anything reaches the VM, and sent last, so a failed copy leaves no secret behind.
  (umask 077; : >"$TMPD/secrets")
  if [ "$DRY" = 0 ]; then
    for k in $SECRET_KEYS AIDENHQ_GITHUB_TOKEN GITHUB_TOKEN; do
      eval "v=\${$k:-}"; [ -z "$v" ] || { safe_val "$k" "$v"; printf '%s="%s"\n' "$k" "$v" >>"$TMPD/secrets"; }
    done
  fi
  vm_sh sh -c 'cat >"$HOME/.aidenhq-install.sh"' <"$src" || die "can't copy the installer into the VM"
  w='f=$HOME/.aidenhq-install.env; set -a; . "$f"; set +a; shred -u "$f" 2>/dev/null || rm -f "$f"
    rm -f "$HOME/.aidenhq/setup-url"; exec sh "$HOME/.aidenhq-install.sh" "$@"'
  if [ -n "${AIDENHQ_RELEASE_FILE:-}" ]; then   # a Mac path: the VM gets a copy
    vm_sh sh -c 'cat >"$HOME/.aidenhq-release.json"' <"$AIDENHQ_RELEASE_FILE" || die "can't read AIDENHQ_RELEASE_FILE=$AIDENHQ_RELEASE_FILE"
    w="AIDENHQ_RELEASE_FILE=\$HOME/.aidenhq-release.json; export AIDENHQ_RELEASE_FILE; $w"
  fi
  vm_sh sh -c 'umask 077; cat >"$HOME/.aidenhq-install.env"' <"$TMPD/secrets" || die "can't copy the secrets into the VM"
  rm -f "$TMPD/secrets"
  set -- sh -c "$w" aidenhq-install "$@"
  for k in AIDENHQ_RELEASE_URL AIDENHQ_GIT_BASE MODULES; do eval "v=\${$k:-}"; [ -z "$v" ] || set -- "$k=$v" "$@"; done
  set -- env AIDENHQ_MAC_VM=1 AIDENHQ_PROGRESS_BASE="${PROGRESS_SLICE:-}" AIDENHQ_OWNER_EMAIL="${AIDENHQ_OWNER_EMAIL:-}" AIDENHQ_TIMEZONE="${AIDENHQ_TIMEZONE:-}" \
    AIDENHQ_OWNER_NAME="${AIDENHQ_OWNER_NAME:-$(id -F 2>/dev/null || id -un)}" "$@"
  # A terminal goes through (Tailscale's sign-in link, prompts): limactl gives the VM a terminal only when its own stdout
  # is one, so the VM's output goes straight to it (its own log keeps it) and the link comes back in a file.
  in=/dev/null; [ "$NONINT" = 0 ] && (: </dev/tty) 2>/dev/null && in=/dev/tty
  log "+ limactl shell $VM (the Linux installer; its log is ~/.aidenhq/install.log in the VM)"
  if vm_sh "$@" <"$in"; then rc=0; else rc=$?; fi
  # The VM's installer has already said where and why (STEP cleared: no second log tail).
  # The install added the VM user to the docker group, but Lima's shared SSH connection keeps the groups it started
  # with: close it, so the next limactl shell can run docker.
  ssh -O exit -o ControlPath="$LIMA_HOME/$VM/ssh.sock" "$VM" >/dev/null 2>&1 || :
  [ "$rc" = 0 ] || { STEP=''; die "the install in the VM stopped (exit $rc). The VM stays; fix the cause and run the same command again."; }
  SETUP_URL=$(vm_sh sh -c 'cat "$HOME/.aidenhq/setup-url" 2>/dev/null || :' </dev/null | tr -d '\r')
  # Without Tailscale the link is on the VM's loopback (3120 sign-in, 3121 the board), which Lima forwards to this Mac's.
  case "$SETUP_URL" in http://*:3120/*|http://*:3121/*) SETUP_URL="http://localhost:${SETUP_URL#http://*:}" ;; esac
}

mac_finish() {
  lc=limactl; [ "$(command -v limactl 2>/dev/null)" = "$LIMACTL" ] || lc=$LIMACTL
  progress_emit ready
  if [ "$DRY" = 1 ]; then printf '\n%sDry run done.%s Nothing on this Mac changed. A real run ends with the link to open here.\n' "$Y" "$N"; return 0; fi
  printf '\n%sAidenHQ is running in its Linux VM on this Mac.%s\n\n' "$G$B" "$N"
  if [ -n "$SETUP_URL" ]; then
    printf '  Open this link in a browser on this Mac (one use, 72 hours):\n\n    %s%s%s\n\n' "$B" "$SETUP_URL" "$N"
    case "$SETUP_URL" in
      http://localhost:3120/*|http://localhost:3121/*) printf '  The VM'"'"'s browser ports (3121, 3120, 3130) are forwarded to this Mac'"'"'s localhost; nothing else in the VM is.\n' ;;
      *) printf '  This Mac (and any device you use) must be on the same tailnet as the VM.\n' ;;
    esac
  elif [ -n "$UPGRADED" ]; then printf '  The VM is updated to release %s. Open the board you already use.\n' "$REL"
  else printf '  The setup link is in the log: %s\n' "$LOG"; fi
  printf '  The VM: %s shell %s (a shell in it), %s stop %s. It starts when you log in (%s), or now with\n' "$lc" "$VM" "$lc" "$VM" "$plist"
  printf '  launchctl kickstart gui/%s/%s (not limactl start, which runs it without its login agent or keep-awake).\n' "$(id -u)" "$VM_AGENT"
  if [ "$AWAKE" = 1 ]; then printf '  This Mac stays awake on power while the VM runs. On battery, or with a laptop lid closed, it still sleeps, and every agent pauses.\n'
  else printf '  When this Mac sleeps, every agent pauses until it wakes. To keep it awake on power, run this again with AIDENHQ_KEEP_AWAKE=1.\n'; fi
  if vm_sh sudo -n test -e /root/aidenhq-vault-recovery.txt 2>/dev/null; then
    printf '  Vault recovery key: %s shell %s sudo cat /root/aidenhq-vault-recovery.txt, store it, then shred it (sudo shred -u).\n' "$lc" "$VM"
  fi
  printf '  Install log: %s\n\n' "$LOG"
  [ -z "$SETUP_URL" ] || printf 'AIDENHQ_SETUP_URL=%s\n' "$SETUP_URL"
}

# Uninstall on a Mac deletes the VM, and with it everything AidenHQ kept in it: confirmed by typing, or AIDENHQ_CONFIRM_DELETE_VM=1.
mac_uninstall() {
  step "Uninstall: delete the VM '$VM' and its login agent"
  plist="$HOME/Library/LaunchAgents/$VM_AGENT.plist" st=$(vm_state)
  say "this deletes $LIMA_HOME/$VM and everything in it: AidenHQ's data, its vault and the instance checkout."
  say "unlike on Linux, nothing is kept. To keep a backup, copy it out first (limactl shell $VM, then the product's backup)."
  if [ "$DRY" = 1 ]; then say "would remove $plist and delete the VM ($([ -n "$st" ] && echo "$st" || echo 'not found'))"; return 0; fi
  if [ "${AIDENHQ_CONFIRM_DELETE_VM:-}" != 1 ]; then
    [ "$NONINT" = 0 ] || { STEP=''; die "nothing deleted: with no terminal to confirm on, set AIDENHQ_CONFIRM_DELETE_VM=1"; }
    printf '    Type delete to delete the VM: ' >/dev/tty; read -r a </dev/tty || a=''
    [ "$a" = delete ] || { STEP=''; die "nothing deleted"; }
  fi
  launchctl bootout "gui/$(id -u)/$VM_AGENT" >/dev/null 2>&1 || :
  rm -f "$plist"
  [ -z "$st" ] || run "$LIMACTL" --tty=false delete --force "$VM" || die "limactl couldn't delete $VM"
  if [ -d "$HOME/.aidenhq/lima" ] && [ -z "$("$HOME/.aidenhq/lima/bin/limactl" list -q 2>/dev/null)" ]; then rm -rf "$HOME/.aidenhq/lima"; fi
  printf '\nDeleted. Kept: Lima'"'"'s image cache (~/Library/Caches/lima; limactl prune clears it, for every Lima VM), a Lima you\n'
  printf 'installed yourself (Homebrew), and the install log %s.\n' "$LOG"
}

mac_main() {
  [ "$(id -u)" != 0 ] || die "on a Mac, run the installer as yourself, not with sudo: the VM belongs to your user"
  open_log
  mac_detect
  [ "$DRY" = 1 ] && printf '%sDry run:%s nothing on this Mac changes.\n' "$Y" "$N"
  if [ "$UNINSTALL" = 1 ]; then mac_uninstall; return 0; fi
  mac_size
  step "This Mac"
  say "macOS $MACOS ($MARCH); $MCORES cores, $MRAM_GB GB memory, $MFREE_GB GB free"
  say "AidenHQ runs in a Linux VM ($VM, Lima): the Linux install runs inside it, with every security gate as on a server"
  # A run on an existing VM is an upgrade or a repair: the install inside it reads the owner from its instance.
  UPGRADED=''; [ -z "$(vm_state)" ] || UPGRADED=1
  if [ -n "$UPGRADED" ] && [ -z "${AIDENHQ_OWNER_EMAIL:-}" ]; then say "the VM exists: this run upgrades or repairs it, keeping its owner"
  else ensure_owner_email; fi
  mac_timezone; ensure_timezone
  if [ -n "$REFUSALS" ]; then
    printf '%s%s:%s\n%s' "$R" "$([ "$DRY" = 1 ] && echo 'A real run would refuse' || echo 'Refusing to install')" "$N" "$REFUSALS"
    [ "$DRY" = 1 ] || { STEP=''; exit 1; }
    REFUSALS=''
  fi
  mac_keep_awake
  mac_lima
  mac_vm
  mac_inner
  mac_finish
}

# ------------------------------------------------------------------------------------------------ main
plan_summary() {
  step "This machine"
  say "$OS_NAME ($ARCH); $CORES cores, $RAM_MB MB RAM, $DISK_GB GB free$([ "$DISK_AVAIL_GB" = "$DISK_GB" ] || echo " (+$((DISK_AVAIL_GB - DISK_GB)) GB already installed)")"
  say "service user: $SVC$([ "$NEW_USER" = 1 ] && echo ' (will be created)'); checkout: $DIR"
  say "derived: $MAX_CONCURRENT jobs x $JOB_TIMEOUT min, $CI_RUNNERS CI runner(s), keep ${DISK_RESERVE_GB} GB free, build cache ${BUILD_CACHE_GB} GB, logs $LOG_MAX x $LOG_FILES, journal $JOURNAL_MAX"
}

main() {
  setup_ui
  parse_args "$@"
  TMPD=$(mktemp -d 2>/dev/null || mktemp -d -t aidenhq) STEP='' REFUSALS='' KEEPALIVE='' RELFILE=''
  PG_TABLE=$PROGRESS_LINUX PG_LAST=0 PROGRESS_SLICE=''
  [ "$(uname -s)" != Darwin ] || PG_TABLE=$(progress_mac_table)
  INST_YAML='' INST_REL='' INST_EMAIL=''
  BOARD_URL='' KERNEL_SHA='' KERNEL_REPO='' SETUP_URL='' SSH_TUNNEL='' PENV='' KTOK_FILE='' KCOPY='' AUTH_HDR='' REL_COMMIT=''
  exec </dev/null   # with curl | sh, stdin is the script: nothing below may read it (prompts use /dev/tty)
  trap on_exit EXIT
  trap 'exit 130' INT TERM
  if [ "$(uname -s)" = Darwin ]; then mac_main; return 0; fi
  detect_platform
  resolve_user
  open_log
  [ "$DRY" = 1 ] && printf '%sDry run:%s nothing on this machine changes.\n' "$Y" "$N"
  if [ "$UNINSTALL" = 1 ]; then ensure_sudo; uninstall; return 0; fi
  detect_resources
  derive_defaults
  plan_summary
  check_minimums
  existing_install
  ensure_owner_email; ensure_timezone
  if [ -n "$REFUSALS" ]; then
    printf '%s%s:%s\n%s' "$R" "$([ "$DRY" = 1 ] && echo 'A real run would refuse' || echo 'Refusing to install')" "$N" "$REFUSALS"
    [ "$DRY" = 1 ] || { STEP=''; exit 1; }
    REFUSALS=''
  fi
  ensure_sudo
  ensure_user
  git_auth_env
  # Fail fast: the release and its sources need only curl and git, so they come before the product's heavy installs.
  if [ "$DRY" = 1 ] || ! have git || ! have curl || ! have gpg || ! have jq || ! have sudo; then
    step "Bootstrap tools"
    apt_get update
    apt_get install --no-install-recommends ca-certificates curl git gnupg jq sudo
  fi
  fetch_release
  check_upgrade
  fetch_sources
  check_product
  if [ -n "$REFUSALS" ]; then
    printf '%s%s:%s\n%s' "$R" "$([ "$DRY" = 1 ] && echo 'A real run would stop here' || echo 'Stopping before installing packages (only the bootstrap tools and the service user were set up)')" "$N" "$REFUSALS"
    [ "$DRY" = 1 ] || { STEP=''; exit 1; }
  fi
  host_tuning
  run_setup
  disk_guard
  finish
}

main "$@"
