#!/bin/sh
# shellcheck disable=SC2016  # single-quoted sh -c bodies and $releasever are meant literally
# AidenHQ installer: turns a Linux server into a running AidenHQ, then hands you one link for the rest.
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
# (default: the service user's name), AIDENHQ_USER (service user when run as root; default aidenhq), AIDENHQ_GITHUB_TOKEN
# (private repos), AIDENHQ_RELEASE_FILE / AIDENHQ_RELEASE_URL / AIDENHQ_GIT_BASE (mirrors, air-gapped installs and tests).
# Optional secrets, passed to the product's setup in a root-only config file and never printed: OPENROUTER_KEY (or
# OPENROUTER_MANAGEMENT_KEY), TS_AUTHKEY. Without them the browser steps ask for the model key; Tailscale's sign-in
# link is shown on the terminal.
#
# No telemetry. Everything it fetches is pinned: the release file by digest, git checkouts by sha. Host packages are the
# kernel's own pins (ops/vm/pins.json), installed by its setup. The whole script is functions; nothing runs until the
# last line, so a truncated download does nothing.
set -eu

DEFAULT_RELEASE=2026.11
RELEASE_SHA256=""   # set by the release cut for DEFAULT_RELEASE; empty = not cut yet (the file's own sha checks still run)
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
step() { STEP="$*"; log "== $*"; printf '%s==>%s %s%s%s\n' "$G" "$N" "$B" "$*" "$N"; }
say() { log "$*"; printf '    %s\n' "$*"; }
warn() { log "WARN $*"; printf '    %swarning:%s %s\n' "$Y" "$N" "$*" >&2; }
die() { log "ERROR $*"; printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
refuse() { REFUSALS="${REFUSALS}    - $*
"; log "REFUSE $*"; }

rm_penv() { [ -z "${PENV:-}" ] || $SUDO sh -c 'shred -u "$1" 2>/dev/null || rm -f "$1"' _ "$PENV"; PENV=''; }
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
  case "$REL" in *[!0-9.]*|'') die "release names look like 2026.11 or 2026.11.1, not '$REL'" ;; esac
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
    if [ -n "$AUTH_HDR" ] && [ -z "${AIDENHQ_RELEASE_URL:-}" ] && have jq; then got() { gh_asset "$REL" "$REL.json" "$RELFILE"; }
    else got() { fetch "$url" "$RELFILE"; }; fi
    got || {
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
  step "Fetch and verify the kernel and modules"
  [ -n "$RELFILE" ] || { say "(no release file: skipped)"; return 0; }
  checkout_at "$DIR" "$(repo_url "$KERNEL_REPO")" "$KERNEL_SHA"
  verify_at "$DIR" "$KERNEL_SHA"
  as_svc mkdir -p -m 700 "$STATE_DIR"
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

# root_verify: right before root executes the checkout, verify it as root against a root-owned copy of the objects:
# a --no-local clone (git rehashes every object it receives; replace refs are ignored), then the work tree is compared
# file by file to the pinned commit through a root-owned index. The service user's own .git is never trusted here.
root_verify() {
  if [ "$DRY" = 1 ]; then printf '    %swould verify as root:%s %s against a root-owned clone at %s\n' "$D" "$N" "$DIR" "$KERNEL_SHA"; return 0; fi
  RV=$($SUDO mktemp -d /var/tmp/aidenhq-verify.XXXXXX)
  $SUDO env GIT_NO_REPLACE_OBJECTS=1 git -c safe.directory='*' clone -q --bare --no-local "$DIR" "$RV/k.git" >>"$LOG" 2>&1 \
    || die "root verification: can't clone $DIR"
  $SUDO env GIT_NO_REPLACE_OBJECTS=1 GIT_DIR="$RV/k.git" GIT_WORK_TREE="$DIR" GIT_INDEX_FILE="$RV/index" sh -c '
    git cat-file -e "$1^{commit}" && git read-tree "$1" && git update-index -q --refresh >/dev/null; git diff-files --quiet' _ "$KERNEL_SHA" \
    || { $SUDO rm -rf "$RV"; die "root verification failed: $DIR differs from $KERNEL_SHA"; }
  $SUDO rm -rf "$RV"
}

run_setup() {
  step "AidenHQ setup (ops/setup.sh: host packages, vault, services, Paperclip, board)"
  # ops/setup.sh runs as root from the checkout, which the service user owns: that is safe only when the service user
  # is already root-equivalent (sudo for everything), as it is when it invoked us with sudo or we created it.
  if [ "$DRY" = 0 ] && [ "$(id -u)" = 0 ] && ! sudo -l -U "$SVC" 2>/dev/null | grep -q '(ALL\( : ALL\)\{0,1\}) \(NOPASSWD: \)\{0,1\}ALL'; then
    die "$SVC can't sudo everything, but this kernel's setup runs as root from $SVC's checkout: give $SVC sudo, or let the installer create its own user"
  fi
  verify_at "$DIR" "$KERNEL_SHA"
  root_verify
  set -- --unattended; [ "$NO_TS" = 1 ] && set -- "$@" --no-tailscale
  write_setup_config
  [ -z "$PENV" ] || set -- "$@" --config "$PENV"
  if [ "$DRY" = 1 ]; then
    printf '    %swould run:%s %senv AIDENHQ_USER=%s OWNER_EMAIL=%s MAX_CONCURRENT=%s TIMEOUT_MINUTES=%s CI_RUNNERS=%s bash %s/ops/setup.sh %s\n' \
      "$D" "$N" "${SUDO:+$SUDO }" "$SVC" "${AIDENHQ_OWNER_EMAIL:-<owner email>}" "$MAX_CONCURRENT" "$JOB_TIMEOUT" "$CI_RUNNERS" "$DIR" "$*"
    return 0
  fi
  log "+ setup $*"
  # The product's own progress lines ("• ...") reach the terminal; everything goes to the log. Tailscale's sign-in link
  # (when it needs one) goes straight to the terminal from setup.
  { $SUDO env AIDENHQ_USER="$SVC" OWNER_EMAIL="$AIDENHQ_OWNER_EMAIL" OWNER_NAME="${AIDENHQ_OWNER_NAME:-$SVC}" MODULES="${MODULES:-}" \
      MAX_CONCURRENT="$MAX_CONCURRENT" TIMEOUT_MINUTES="$JOB_TIMEOUT" CI_RUNNERS="$CI_RUNNERS" \
      bash "$DIR/ops/setup.sh" "$@" </dev/null 2>&1 && echo 0 >"$TMPD/rc" || echo $? >"$TMPD/rc"; } \
    | tee -a "$LOG" "$TMPD/setup.out" | while IFS= read -r l; do
        case "$l" in "• "*) say "${l#• }" ;; *) if [ "$VERBOSE" = 1 ]; then printf '    %s\n' "$l"; fi ;; esac
      done
  rc=$(cat "$TMPD/rc")
  rm_penv
  [ "$rc" = 0 ] || die "ops/setup.sh failed (exit $rc)"
  # This run's output only (the log keeps earlier runs): the last of each line wins.
  SETUP_URL=$(sed -n 's/^AIDENHQ_SETUP_URL=//p' "$TMPD/setup.out" | tail -1)
  SSH_TUNNEL=$(sed -n 's/^AIDENHQ_SSH_TUNNEL=//p' "$TMPD/setup.out" | tail -1)
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
    printf '\n%sDry run done.%s A real run ends with:\n' "$Y" "$N"; SETUP_URL="https://<board-host>/setup/<one-time-token>"
    [ "$NO_TS" = 0 ] || SSH_TUNNEL="ssh -N -L 3121:127.0.0.1:3121 $SVC@<this-host>"
  fi
  printf '\n%sAidenHQ is running.%s\n\n' "$G$B" "$N"
  if [ -n "$SSH_TUNNEL" ]; then
    printf '  The board listens on this server only. On your laptop, open this tunnel first and leave it running:\n\n    %s%s%s\n\n' "$B" "$SSH_TUNNEL" "$N"
  fi
  if [ -n "$SETUP_URL" ]; then
    printf '  Open this link to finish in your browser (one use, 72 hours):\n\n    %s%s%s\n\n' "$B" "$SETUP_URL" "$N"
    printf '  It sets up your account and authenticator, your model key and your channels.\n'
    [ -n "$SSH_TUNNEL" ] || printf '  Your device must be on the same tailnet.\n'
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

# ------------------------------------------------------------------------------------------------ main
plan_summary() {
  step "This machine"
  say "$OS_NAME ($ARCH); $CORES cores, $RAM_MB MB RAM, $DISK_GB GB free"
  say "service user: $SVC$([ "$NEW_USER" = 1 ] && echo ' (will be created)'); checkout: $DIR"
  say "derived: $MAX_CONCURRENT jobs x $JOB_TIMEOUT min, $CI_RUNNERS CI runner(s), keep ${DISK_RESERVE_GB} GB free, build cache ${BUILD_CACHE_GB} GB, logs $LOG_MAX x $LOG_FILES, journal $JOURNAL_MAX"
}

main() {
  setup_ui
  parse_args "$@"
  TMPD=$(mktemp -d 2>/dev/null || mktemp -d -t aidenhq) STEP='' REFUSALS='' KEEPALIVE='' RELFILE=''
  KERNEL_SHA='' KERNEL_REPO='' MKT_SHA='' MKT_REPO='' SETUP_URL='' SSH_TUNNEL='' PENV='' AUTH_HDR=''
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
  ensure_owner_email
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
