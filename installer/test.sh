#!/bin/sh
# shellcheck disable=SC2034,SC2016,SC2030,SC2031,SC2329  # variables are read by the sourced install.sh; hook bodies are eval'd later
# Offline test of install.sh's release verification (lean-core spec A17): local fixture repos and a release file pass;
# a tampered release or a moved checkout each stop it. A release pins one product sha; the official modules are its modules/.
#   sh installer/test.sh            (any POSIX sh with git; also run under dash)
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
sed '$d' "$here/install.sh" >"$work/lib.sh"   # every function, without the final `main "$@"`
pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

g() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main "$@"; }
mkrepo() { # name files...: a repo with one commit per file on main; prints nothing
  g init -q "$work/git/$1.git.src"
  for f in "$@"; do [ "$f" = "$1" ] && continue; echo "$f" >"$work/git/$1.git.src/$f"; g -C "$work/git/$1.git.src" add -A; g -C "$work/git/$1.git.src" commit -qm "$f"; done
  g clone -q --bare "$work/git/$1.git.src" "$work/git/acme/$1.git"
}
mkdir -p "$work/git/acme"
mkrepo kernel ops-a ops-b
mkrepo other x1
K=$(git -C "$work/git/kernel.git.src" rev-parse HEAD)
X=$(git -C "$work/git/other.git.src" rev-parse HEAD)

flip() { echo "$1" | awk '{ c = substr($0, 40, 1); print substr($0, 1, 39) (c == "0" ? "1" : "0") }'; }
release() { # kernel
  cat <<EOF
{ "release": "2026.11", "kernel": "$1", "kernel_repo": "acme/kernel",
  "images": { "board": "ghcr.io/aiden-hq/board@sha256:$(printf '%064d' 0)" },
  "notes": ["A note"] }
EOF
}

# case NAME EXPECT(pass|stop) RELEASE-ARGS... [-- SETUP-CMD]: a fresh home each time; SETUP-CMD runs between fetch and verify.
case_() {
  name=$1 expect=$2; shift 2
  home="$work/home-$pass-$fail"; mkdir -p "$home"
  release "$1" >"$work/rel.json"
  shift; pre="${1:-}"
  if (
    # shellcheck disable=SC1091
    . "$work/lib.sh"
    setup_ui; DRY=0 VERBOSE=0 NONINT=1 NO_TS=0 REL=2026.11 SUDO='' STEP='' REFUSALS='' AUTH_HDR=''
    SVC=$(id -un) SVC_HOME="$home" SVC_UID=$(id -u) DIR="$home/aidenhq" STATE_DIR="$home/.aidenhq"
    TMPD=$(mktemp -d "$work/t.XXXX") LOG="$TMPD/log"
    AIDENHQ_RELEASE_FILE="$work/rel.json" AIDENHQ_GIT_BASE="file://$work/git"
    fetch_release >/dev/null
    if [ -n "$pre" ]; then fetch_sources >/dev/null; eval "$pre"; fi
    fetch_sources >/dev/null
  ) >"$work/out" 2>&1; then got=pass; else got=stop; fi
  why=$(grep -E 'error:' "$work/out" | tail -1 | sed 's/.*error:[^ ]* //')
  if [ "$got" = "$expect" ]; then ok "$name${why:+  ($why)}"; else bad "$name (got $got)"; sed 's/^/     /' "$work/out"; fi
}

case_ "a real release verifies, fetching only the product" pass "$K" '[ ! -e "$STATE_DIR/modules" ]'
case_ "a placeholder sha stops it"               stop "TODO-kernel-sha"
case_ "one flipped hex digit in the kernel sha"  stop "$(flip "$K")"
case_ "a kernel sha from another repo"           stop "$X"
case_ "a tracked change in the checkout"         stop "$K" 'echo evil >>"$DIR/ops-a"'
case_ "a checkout moved to another commit"       stop "$K" 'git -C "$DIR" checkout -q --detach HEAD~1; checkout_at() { :; }'
case_ "a rerun on a verified checkout"           pass "$K" ':'
case_ "an image by tag, not digest, stops it"    stop "$K" 'sed -i.b "s/@sha256:0*/:latest/" "$AIDENHQ_RELEASE_FILE"; fetch_release'


lib() {
  (
    # shellcheck disable=SC1091
    . "$work/lib.sh"
    setup_ui; DRY=0 VERBOSE=0 SUDO='' STEP='' AUTH_HDR='' SVC=$(id -un)
    TMPD=$(mktemp -d "$work/t.XXXX") LOG="$TMPD/log"
    eval "$1"
  ) >"$work/out" 2>&1
}
expect() { # NAME pass|stop CMDS
  if lib "$3"; then got=pass; else got=stop; fi
  why=$(grep -E 'error:|refus' "$work/out" | tail -1 | sed 's/.*error:[^ ]* //')
  if [ "$got" = "$2" ]; then ok "$1${why:+  ($why)}"; else bad "$1 (got $got)"; sed 's/^/     /' "$work/out"; fi
}

# The baked digest: a fetched release file must be the one this copy was cut with (the release CI bakes RELEASE_SHA256).
release "$K" >"$work/cut.json"
CUT=$(sha256sum "$work/cut.json" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$work/cut.json" | cut -d' ' -f1)
fetched() { echo "fetch() { cp '$work/cut.json' \"\$2\"; }; DRY=0 REL=$1 RELEASE_SHA256=$2 RELEASE_COMMIT=$K; fetch_release; ${3:-:}"; }
expect "a fetched release with the baked digest is accepted, and its commit goes to setup" pass "$(fetched 2026.11 "$CUT" '[ "$REL_COMMIT" = '"$K"' ]')"
expect "a fetched release with another digest stops"            stop "$(fetched 2026.11 "$(flip "$CUT")")"
expect "an uncut installer (no baked digest) stops on a fetched file" stop "$(fetched 2026.11 '')"
expect "another --release than the one this copy was cut for stops" stop "$(fetched 2026.12 "$CUT")"

# A rerun on a 2026.11.2 install: its checkout ignores /modules/ (materialised from the modules repo); the one-sha product
# tracks modules/. Moving the checkout replaces the materialised files with the tracked ones and verifies.
g init -q "$work/two"; printf '/modules/\n' >"$work/two/.gitignore"; echo a >"$work/two/k"; g -C "$work/two" add -A; g -C "$work/two" commit -qm old
OLD=$(git -C "$work/two" rev-parse HEAD); g -C "$work/two" rm -q .gitignore; mkdir -p "$work/two/modules/board"; echo tracked >"$work/two/modules/board/module.yaml"
g -C "$work/two" add -A; g -C "$work/two" commit -qm one-sha; NEW=$(git -C "$work/two" rev-parse HEAD); g clone -q "$work/two" "$work/twoc"
expect "a 2026.11.2 checkout with materialised modules/ moves to a product that tracks modules/" pass \
  "DIR='$work/twoc'; git -C \"\$DIR\" checkout -q --detach $OLD; mkdir -p \"\$DIR/modules/board\"; echo materialised >\"\$DIR/modules/board/module.yaml\"
   as_svc() { \"\$@\"; }; checkout_at \"\$DIR\" '$work/two' $NEW && verify_at \"\$DIR\" $NEW && [ \"\$(cat \"\$DIR/modules/board/module.yaml\")\" = tracked ]"

# A run on an existing install (an upgrade by hand): the instance's release and owner are read; an older release is refused.
mkdir -p "$work/up/aidenhq-instance"
cat >"$work/up/aidenhq-instance/instance.yaml" <<'EOS'
product: 1111111111111111111111111111111111111111
release: { name: "2026.11.2", source: { source: github, repo: Aiden-HQ/aidenhq-distro }, sha: 2222222222222222222222222222222222222222 }
marketplaces:
  - { name: aidenhq, source: { source: github, repo: Aiden-HQ/aidenhq-modules }, sha: 3333333333333333333333333333333333333333 }
  - { name: acme-extras, source: { source: github, repo: acme/extras }, sha: 4444444444444444444444444444444444444444 }
settings:
  owner_name: "Acme"
  owner_email: "owner@example.com"
EOS
up() { echo "SVC_HOME='$work/up' DRY=0 REL=$1; unset AIDENHQ_OWNER_EMAIL; existing_install; check_upgrade; ${2:-:}"; }
cp "$work/up/aidenhq-instance/instance.yaml" "$work/up.before"
expect "an upgrade from 2026.11.2 to 2026.11.3 goes on, with the instance's owner email" pass "$(up 2026.11.3 '[ "$INST_REL" = 2026.11.2 ] && [ "$AIDENHQ_OWNER_EMAIL" = owner@example.com ]')"
# The aidenhq marketplace entry goes in setup's own pin commit (reverted with it on a failed apply), never by the installer.
expect "an upgrade says the aidenhq marketplace entry goes with setup's pin, and leaves instance.yaml as it is" pass \
  "$(up 2026.11.3 'grep -q "aidenhq marketplace entry goes with that pin" "$LOG" && cmp -s "$INST_YAML" '"'$work/up.before'"'')"
expect "the same release again is a repair" pass "$(up 2026.11.2)"
expect "an older release than the instance runs is refused" stop "$(up 2026.11.1)"
expect "a fresh server has no existing install" pass "SVC_HOME='$work/none' DRY=0 REL=2026.11.3; existing_install; check_upgrade; [ -z \"\$INST_YAML\" ]"

# Derived defaults on the two calibration hosts (lean VM and the EX44).
expect "4 vCPU / 8 GB / 100 GB -> 2 jobs, 60 min, 1 CI runner, 15 GB reserve" pass \
  'CORES=4 RAM_MB=7812 DISK_TOTAL_GB=96; derive_defaults; [ "$MAX_CONCURRENT/$JOB_TIMEOUT/$CI_RUNNERS/$DISK_RESERVE_GB" = 2/60/1/15 ]'
expect "20 threads / 64 GB / 460 GB -> 16 jobs, 120 min, 4 CI runners" pass \
  'CORES=20 RAM_MB=64076 DISK_TOTAL_GB=458; derive_defaults; [ "$MAX_CONCURRENT/$JOB_TIMEOUT/$CI_RUNNERS" = 16/120/4 ]'

# Disk on a rerun: the first run's images (here 40 GB in Docker) count toward the minimum; a fresh host is checked as before.
dfstub='df() { printf "Filesystem 1K-blocks Used Available\n/dev/sda 104857600 0 55574528\n"; }; docker() { case "$1 $2" in "system df") printf "17.4GB\n7.65GB\n14.9GB\n330.2MB\n0B\n" ;; "info -f") echo /var/lib/docker ;; esac; }; have() { :; }'
expect "a rerun at 53 GB free with 40 GB already in Docker passes the 60 GB minimum" pass \
  "$dfstub; DIR='$work/rerun'; mkdir -p \"\$DIR/.git\"; detect_resources; [ \"\$DISK_GB/\$DISK_AVAIL_GB\" = 53/93 ]; CORES=4 RAM_MB=7812 SYSTEMD=1 IN_CONTAINER=0 REFUSALS=; check_minimums; [ -z \"\$REFUSALS\" ]"
expect "a fresh host at 53 GB free is refused" pass \
  "$dfstub; DIR='$work/fresh'; detect_resources; [ \"\$DISK_GB/\$DISK_AVAIL_GB\" = 53/53 ]; CORES=4 RAM_MB=7812 SYSTEMD=1 IN_CONTAINER=0 REFUSALS=; check_minimums; printf %s \"\$REFUSALS\" | grep -q 'GB free disk'"
expect "the installer sets its own umask 022" pass "grep -q '^umask 022\$' '$here/install.sh'"

# Config injection: setup's config is line-parsed; a newline or quote in any value would forge a key.
expect "a plain value is accepted" pass 'safe_val N "Alex Doe (CTO), acme.example"'
expect "a newline in a value is refused" stop 'safe_val N "$(printf "x\nOPENROUTER_KEY=evil")"'
expect "a double quote in a key is refused" stop 'safe_val K "sk-or\"x"'
expect "a dollar sign is refused" stop 'safe_val K "sk-\$(id)"'
expect "write_setup_config refuses an injected key before writing anything" stop \
  'OPENROUTER_KEY="$(printf "k\nTS_AUTHKEY=x")"; mktemp() { echo "$TMPD/never"; }; write_setup_config'
# The setup config holds the secrets only, in a root-only (0600) file, and no secret means no file.
expect "secrets land in a 0600 config file, nothing else does" pass \
  "mktemp() { command mktemp '$work/pe.XXXX'; }; PENV=''; OPENROUTER_KEY=sk-or-x TS_AUTHKEY=tskey-x AIDENHQ_OWNER_EMAIL=a@example.com; write_setup_config
   [ \"\$(ls -l \"\$PENV\" | cut -c1-10)\" = -rw------- ] && [ \"\$(cat \"\$PENV\")\" = 'OPENROUTER_KEY=\"sk-or-x\"
TS_AUTHKEY=\"tskey-x\"' ]"
expect "no secret, no config file" pass 'PENV=""; write_setup_config; [ -z "$PENV" ]'
# A private kernel repo's token reaches setup only as a 0600 file (--kernel-token-file), and only a token-shaped one.
expect "the kernel token lands alone in a 0600 file" pass \
  "mktemp() { command mktemp '$work/kt.XXXX'; }; KTOK_FILE=''; AIDENHQ_GITHUB_TOKEN=ghp_abc123; write_token_file
   [ \"\$(ls -l \"\$KTOK_FILE\" | cut -c1-10)\" = -rw------- ] && [ \"\$(cat \"\$KTOK_FILE\")\" = ghp_abc123 ]"
expect "a token with other characters is refused" stop 'AIDENHQ_GITHUB_TOKEN="ghp_x;id"; write_token_file'
expect "no token, no file" pass 'KTOK_FILE=""; AIDENHQ_GITHUB_TOKEN="" GITHUB_TOKEN=""; write_token_file; [ -z "$KTOK_FILE" ]'

# The owner's email is needed and checked; the pinned kernel's pins.json decides which hosts are supported.
expect "a plain email is accepted" pass 'NONINT=1 DRY=0 REFUSALS=""; AIDENHQ_OWNER_EMAIL=a.b+c@example.com; ensure_owner_email; [ -z "$REFUSALS" ]'
expect "a missing email is refused" pass 'NONINT=1 DRY=0 REFUSALS=""; AIDENHQ_OWNER_EMAIL=""; ensure_owner_email; [ -n "$REFUSALS" ]'
expect "an email with a space is refused" pass 'NONINT=1 DRY=0 REFUSALS=""; AIDENHQ_OWNER_EMAIL="a b@example.com"; ensure_owner_email; [ -n "$REFUSALS" ]'
expect "a zone name is accepted" pass 'REFUSALS=""; AIDENHQ_TIMEZONE=America/Argentina/Buenos_Aires; ensure_timezone; [ -z "$REFUSALS" ]'
expect "a zone name with other characters is refused" pass 'REFUSALS=""; AIDENHQ_TIMEZONE="UTC;id"; ensure_timezone; [ -n "$REFUSALS" ]'
mkdir -p "$work/k/ops/vm"; echo '--unattended' >"$work/k/ops/setup.sh"; echo '{"releases":{"noble":{}}}' >"$work/k/ops/vm/pins.json"
expect "a host the pins list is accepted" pass "DIR='$work/k' CODENAME=noble REFUSALS=''; check_product; [ -z \"\$REFUSALS\" ]"
expect "a host the pins don't list is refused" pass "DIR='$work/k' CODENAME=bionic OS_NAME=Ubuntu REFUSALS=''; check_product; [ -n \"\$REFUSALS\" ]"

# The handover, end to end against a stub setup: owner and sizing arrive in the environment, the secrets only in a 0600
# --config file that is gone afterwards, and the last link lines of this run are the ones read.
mkdir -p "$work/h/ops"
cat >"$work/h/ops/setup.sh" <<'EOS'
#!/bin/bash
echo "• a step"
echo "args=$*"; echo "env=$OWNER_EMAIL,$MAX_CONCURRENT,$TIMEOUT_MINUTES,$CI_RUNNERS,$AIDENHQ_USER"
echo "release=$AIDENHQ_RELEASE,$AIDENHQ_RELEASE_REPO,$AIDENHQ_RELEASE_SHA"
while [ $# -gt 0 ]; do [ "$1" = --config ] && cfg=$2; shift; done
echo "cfgmode=$(ls -l "$cfg" | cut -c1-10)"; echo "cfg=$(tr '\n' ' ' <"$cfg")"; echo "cfgpath=$cfg"
echo AIDENHQ_SSH_TUNNEL=ssh-x; echo AIDENHQ_SETUP_URL=http://old; echo AIDENHQ_SETUP_URL=http://127.0.0.1:3121/setup/t
EOS
expect "setup is driven unattended: env, a 0600 config, parsed links, config deleted" pass \
  "sudo() { echo '(ALL) NOPASSWD: ALL'; }; verify_at() { :; }; root_verify() { KCOPY='$work/h'; }; mktemp() { command mktemp '$work/pe.XXXX'; }
   DIR='$work/h' NO_TS=1 NONINT=1 SETUP_URL='' SSH_TUNNEL='' PENV='' KERNEL_SHA=x MAX_CONCURRENT=2 JOB_TIMEOUT=60 CI_RUNNERS=1
   REL=2026.11 REL_COMMIT=$K DISTRO_REPO=acme/distro
   AIDENHQ_OWNER_EMAIL=a@example.com OPENROUTER_KEY=sk-or-x; run_setup
   grep -qx 'args=--checkout $work/h --unattended --no-tailscale --config .*' \"\$LOG\" && grep -qx 'env=a@example.com,2,60,1,'\"\$SVC\" \"\$LOG\" \
     && grep -qx 'release=2026.11,acme/distro,$K' \"\$LOG\" \
     && grep -qx 'cfgmode=-rw-------' \"\$LOG\" && grep -qx 'cfg=OPENROUTER_KEY=\"sk-or-x\" ' \"\$LOG\" \
     && [ \"\$SETUP_URL\" = http://127.0.0.1:3121/setup/t ] && [ \"\$SSH_TUNNEL\" = ssh-x ] \
     && [ ! -e \"\$(sed -n 's/^cfgpath=//p' \"\$LOG\")\" ]"

expect "the final output carries the two machine-readable lines, no --verbose needed" pass \
  "DRY=0 VERBOSE=0 N='' B='' G='' Y='' LOG=/dev/null DIR=/x SETUP_URL=http://127.0.0.1:3121/setup/t SSH_TUNNEL=ssh-x
   sudo() { return 1; }; out=\$(finish); printf '%s\n' \"\$out\" | grep -qx 'AIDENHQ_SETUP_URL=http://127.0.0.1:3121/setup/t' \
     && printf '%s\n' \"\$out\" | grep -qx 'AIDENHQ_SSH_TUNNEL=ssh-x'"

# Progress lines (AIDENHQ_PROGRESS=<n>/<total> <percent>% <step> ~<minutes left>): the weights table keys are real step texts.
expect "every weights row is the start of a step() text in install.sh, Linux and Mac" pass \
  "for t in \"\$PROGRESS_LINUX\" \"\$(progress_mac_table)\"; do printf '%s\n' \"\$t\" | while IFS='|' read -r k w l; do
     [ \"\$k\" = ready ] || grep -q \"step \\\"\$k\" '$here/install.sh' || { echo \"no step for \$k\"; exit 1; }; done || exit 1; done"
# A stub setup in the product's role: it reads AIDENHQ_PROGRESS_BASE, prints its own lines inside that slice, mints the one
# valid token (a new one replaces the old, as the kernel's mintSetup does) and ends with the link, as ops/setup.sh does.
mkdir -p "$work/p/ops"
cat >"$work/p/ops/setup.sh" <<'EOS'
#!/bin/bash
IFS=/ read -r n t p0 span secs <<<"$AIDENHQ_PROGRESS_BASE"
echo "• packages"; echo "AIDENHQ_PROGRESS=$n/$t $((p0 + span * 10 / 100))% installing packages ~9"
echo "AIDENHQ_PROGRESS=$n/$t $((p0 + span * 40 / 100))% downloading Aiden ~6"
[ -z "${STUB_KILL_PULL:-}" ] || kill -9 $$   # the pull is killed here
echo "AIDENHQ_PROGRESS=$n/$t $((p0 + span * 90 / 100))% starting services ~1"
echo "tok-$$" >"$STUB_TOKEN"   # replaces any earlier token
echo "AIDENHQ_SETUP_URL=http://127.0.0.1:3121/setup?token=$(cat "$STUB_TOKEN")"
EOS
# A whole Linux install's output (every step() text in main's order, the stub setup, finish) into $work/inst.N.
install_run() { # N [kill-pull]
  (
    # shellcheck disable=SC1091
    . "$work/lib.sh"
    setup_ui; DRY=0 VERBOSE=0 NONINT=1 NO_TS=1 SUDO='' STEP='' AUTH_HDR='' SVC=$(id -un) SVC_HOME="$work/p" STATE_DIR="$work/p/.s"
    TMPD=$(mktemp -d "$work/t.XXXX") LOG="$TMPD/log" DIR="$work/p" SETUP_URL='' SSH_TUNNEL='' PENV='' KERNEL_SHA=x MAX_CONCURRENT=2 JOB_TIMEOUT=60 CI_RUNNERS=1
    REL=2026.11 REL_COMMIT=$K DISTRO_REPO=acme/distro AIDENHQ_OWNER_EMAIL=a@example.com
    PG_TABLE=$PROGRESS_LINUX PG_LAST=0 PROGRESS_SLICE=''
    sudo() { echo '(ALL) NOPASSWD: ALL'; }; verify_at() { :; }; root_verify() { KCOPY="$work/p"; }
    export STUB_TOKEN="$work/p/token"; [ -z "${2:-}" ] || export STUB_KILL_PULL=1
    step "This machine"; step "Service user x"; step "Bootstrap tools"; step "Release 2026.11"
    step "Fetch and verify the product"; step "Docker log and build-cache limits"
    run_setup; step "Disk guard and Docker cleanup"; finish
  ) >"$work/inst.$1" 2>&1
}
pcts() { sed -n 's/^AIDENHQ_PROGRESS=[0-9]*\/[0-9]* \([0-9]*\)%.*/\1/p' "$1"; }
install_run 1
if [ "$(pcts "$work/inst.1" | sort -n | tr '\n' ' ')" = "$(pcts "$work/inst.1" | tr '\n' ' ')" ] && [ "$(pcts "$work/inst.1" | wc -l)" -ge 10 ] \
   && [ "$(grep -n '^AIDENHQ_PROGRESS=' "$work/inst.1" | tail -1 | cut -d: -f1)" -lt "$(grep -n '^AIDENHQ_SETUP_URL=' "$work/inst.1" | cut -d: -f1)" ] \
   && [ "$(pcts "$work/inst.1" | tail -1)" = 100 ] && grep -q '^AIDENHQ_PROGRESS=[0-9]*/[0-9]* [0-9]*% downloading Aiden ~[0-9]*$' "$work/inst.1"; then
  ok "progress is monotonic and ends at 100% before the link, the product's lines inside the setup step"
else bad "progress is monotonic and ends at 100% before the link"; sed 's/^/     /' "$work/inst.1"; fi
# The kill-mid-pull case runs here: the stub kills itself (SIGKILL) while pulling, the installer stops, and the rerun
# finishes with the one link, from the one token in the store.
rm -f "$work/p/token"
if ! install_run 2 kill && ! grep -q '^AIDENHQ_SETUP_URL=' "$work/inst.2" && grep -q 'downloading Aiden' "$work/inst.2" \
   && install_run 3 && [ "$(grep -c '^AIDENHQ_SETUP_URL=' "$work/inst.3")" = 1 ] \
   && [ "$(sed -n 's/^AIDENHQ_SETUP_URL=.*token=//p' "$work/inst.3")" = "$(cat "$work/p/token")" ] && [ "$(pcts "$work/inst.3" | tail -1)" = 100 ] \
   && [ "$(pcts "$work/inst.3" | sort -n | tr '\n' ' ')" = "$(pcts "$work/inst.3" | tr '\n' ' ')" ]; then
  ok "rerun after a killed pull: no link from the killed run, one link and the one token from the rerun, progress again to 100%"
else bad "rerun after a killed pull"; sed 's/^/     /' "$work/inst.2" "$work/inst.3"; fi
# On a Mac the VM's install runs inside the outer's slice: its percent never passes the row's end and it prints no link.
expect "the install in the Mac's VM keeps to its slice and the Mac prints the one 100% line" pass \
  "PG_TABLE=\$(progress_mac_table); PG_LAST=0; progress_emit 'This Mac' >/dev/null; progress_emit 'Lima' >/dev/null; progress_emit 'Linux VM' >/dev/null
   progress_emit 'AidenHQ in the VM' >/dev/null; b=\$PROGRESS_SLICE
   PG_TABLE=\$PROGRESS_LINUX PG_LAST=0 AIDENHQ_PROGRESS_BASE=\$b; a=\$(progress_emit 'This machine'); z=\$(progress_emit 'Disk guard')
   case \"\$a\" in AIDENHQ_PROGRESS=4/5\ *) : ;; *) exit 1 ;; esac
   n=\${z#*/*/ }; p=\$(echo \"\$z\" | sed 's/^[^ ]* \([0-9]*\)%.*/\1/'); [ \"\$p\" -lt 100 ] && [ \"\$p\" -gt 50 ]"

# Root verification ignores the service user's .git (replace refs) and catches any tracked change.
g init -q "$work/rv"; echo good >"$work/rv/f"; g -C "$work/rv" add -A; g -C "$work/rv" commit -qm one
RK=$(git -C "$work/rv" rev-parse HEAD)
expect "root verification passes a clean checkout and exports it for setup, nothing in it group- or world-writable" pass \
  "DIR='$work/rv' KERNEL_SHA=$RK KROOT='$work/kroot'; root_verify; [ \"\$KCOPY\" = '$work/kroot/$RK' ] && [ -f \"\$KCOPY/f\" ] && [ -z \"\$(find \"\$KCOPY\" -perm -020 -o -perm -002)\" ]"
echo evil >"$work/rv/f"; g -C "$work/rv" commit -qam evil; EVIL=$(git -C "$work/rv" rev-parse HEAD)
git -C "$work/rv" checkout -q --detach "$RK"; echo evil >"$work/rv/f"; git -C "$work/rv" replace "$RK" "$EVIL"
expect "a replace ref fools the user-side check" pass "DIR='$work/rv' SVC_HOME=x KERNEL_SHA=$RK; verify_at '$work/rv' $RK"
expect "but not root verification" stop "DIR='$work/rv' KERNEL_SHA=$RK KROOT='$work/kroot2'; root_verify"

# Credentials never go through wget (it forwards headers across redirects).
echo 'Authorization: Bearer x' >"$work/hdr"
expect "an authenticated download without curl is refused" stop \
  "have() { [ \"\$1\" != curl ] && command -v \"\$1\" >/dev/null; }; fetch https://example.com/x '$work/x' '$work/hdr'"

# macOS: the Lima VM path, with uname, sw_vers, sysctl, limactl and launchctl stubbed (runs on any POSIX host).
mkdir -p "$work/mac/bin" "$work/mac/home"
cat >"$work/mac/bin/limactl" <<'EOS'
#!/bin/sh
# Stub limactl: each call's args (one per line) to args.N and, for shell, its stdin to stdin.N.
d=$STUB_DIR; n=$(ls "$d" | grep -c '^args\.' || :)
printf '%s\n' "$@" >"$d/args.$n"
case "$1" in
  --version) echo "limactl version ${STUB_LIMA_VERSION:-2.3.0}" ;;
  list) [ -n "${STUB_STATE:-}" ] || exit 1; echo "$STUB_STATE" ;;
  shell) cat >"$d/stdin.$n"; case "$*" in *setup-url*) printf 'http://lima-aidenhq:3121/setup/t\r\n' ;; esac ;;
esac
EOS
chmod +x "$work/mac/bin/limactl"
echo '#!/bin/sh' >"$work/mac/inst.sh"
# mac CMDS: a fresh stub-call directory, a Mac-like environment, then CMDS.
mac() {
  rm -rf "$work/mac/calls" "$work/mac/home/Library"; mkdir -p "$work/mac/calls"
  printf '%s\n' "export STUB_DIR='$work/mac/calls' HOME='$work/mac/home' LIMA_HOME='$work/mac/home/.lima'
    uname() { case \"\$1\" in -m) echo arm64 ;; *) echo Darwin ;; esac; }; sw_vers() { echo 15.4; }
    sysctl() { case \"\$2\" in hw.ncpu) echo 8 ;; hw.memsize) echo 17179869184 ;; esac; }
    nc() { return 1; }; launchctl() { echo \"launchctl \$*\" >>'$work/mac/calls/launchctl'; [ \"\$1\" != print ]; }
    DRY=0 NONINT=1 NO_TS=1 REL=2026.11 DIR='' REFUSALS='' AWAKE=0 SETUP_URL=''
    LIMACTL='$work/mac/bin/limactl'; PATH='$work/mac/bin':\$PATH
    $1"
}
calls() { cat "$work/mac/calls"/args.* 2>/dev/null; }

expect "a Mac on macOS 12 is refused" stop "$(mac 'sw_vers() { echo 12.7.4; }; mac_detect')"
expect "an 8-core, 16 GB Mac makes a 4 CPU / 8 GB / 100 GB VM, Homebrew's Lima 2.2.1 is used" pass "$(mac 'export STUB_LIMA_VERSION=2.2.1
  mac_detect; mac_size; [ "$VM_CPUS/$VM_MEM/$VM_DISK" = 4/8/100 ] && [ "$LIMACTL" = "$work/mac/bin/limactl" ] && [ -z "$REFUSALS" ]')"
expect "an 18-core, 64 GB Mac makes an 8 CPU / 16 GB VM" pass "$(mac 'MCORES=18 MRAM_GB=64 MFREE_GB=500; mac_size; [ "$VM_CPUS/$VM_MEM" = 8/16 ]')"
expect "an 8 GB Mac is refused" pass "$(mac 'MCORES=8 MRAM_GB=8 MFREE_GB=500; mac_size; [ -n "$REFUSALS" ]')"
expect "a Lima older than 2.0 isn't used (the pinned one is installed instead)" pass "$(mac 'export STUB_LIMA_VERSION=1.2.0; mac_detect; [ -z "$LIMACTL" ]')"
expect "a Lima download with the wrong digest stops before unpacking" stop "$(mac 'mac_detect; LIMACTL=""; fetch() { echo junk >"$2"; }
  mac_lima; true')"
expect "the VM: vz, the pinned image digest, no Mac folders shared, only 3121, 3120 and 3130 forwarded" pass "$(mac 'mac_detect; mac_size; mac_template >"$TMPD/t.yaml"
  grep -qx "vmType: vz" "$TMPD/t.yaml" && grep -qx "  digest: sha256:$UBUNTU_SHA256_arm64" "$TMPD/t.yaml" && grep -qx "mounts: \[\]" "$TMPD/t.yaml" \
    && grep -qx "  arch: aarch64" "$TMPD/t.yaml" && [ "$(grep -c -- "^- guestPort:" "$TMPD/t.yaml")" = 3 ] && grep -qx -- "- guestPort: 3121" "$TMPD/t.yaml" && grep -qx -- "- guestPort: 3120" "$TMPD/t.yaml" && grep -qx -- "- guestPort: 3130" "$TMPD/t.yaml" \
    && [ "$(grep -c "ignore: true" "$TMPD/t.yaml")" = 2 ]')"
expect "the login agent runs limactl start --foreground, under caffeinate -s only when kept awake" pass "$(mac 'mac_detect
  AWAKE=0; mac_agent_plist >"$TMPD/p0"; AWAKE=1; mac_agent_plist >"$TMPD/p1"
  ! grep -q caffeinate "$TMPD/p0" && grep -q "<string>/usr/bin/caffeinate</string><string>-s</string><string>$LIMACTL</string><string>start</string><string>aidenhq</string><string>--foreground</string>" "$TMPD/p1" \
    && { ! command -v plutil >/dev/null || { plutil -lint "$TMPD/p0" && plutil -lint "$TMPD/p1"; }; }')"
expect "a Mac dry run with no VM creates, writes and loads nothing" pass "$(mac 'DRY=1; mac_detect; mac_size; mac_keep_awake; mac_vm; mac_inner
  ! calls | grep -qx "shell" && ! calls | grep -q "^--tty=false" && [ ! -e "$HOME/Library" ] && [ ! -e "$STUB_DIR/launchctl" ]')"
expect "the VM's run gets the flags and owner in argv, the secrets only over stdin, and the link comes back on localhost" pass "$(mac 'export STUB_STATE=Running
  mac_detect; AIDENHQ_INSTALLER_FILE="$work/mac/inst.sh" AIDENHQ_OWNER_EMAIL=a@example.com OPENROUTER_KEY=sk-or-canary AIDENHQ_GITHUB_TOKEN=ghp-canary; mac_inner
  ! calls | grep -q canary && grep -qx "OPENROUTER_KEY=\"sk-or-canary\"" "$STUB_DIR"/stdin.* && grep -qx "AIDENHQ_GITHUB_TOKEN=\"ghp-canary\"" "$STUB_DIR"/stdin.* \
    && calls | grep -qx -- --no-tailscale && calls | grep -qx AIDENHQ_OWNER_EMAIL=a@example.com && calls | grep -qx AIDENHQ_MAC_VM=1 \
    && [ "$SETUP_URL" = http://127.0.0.1:3121/setup/t ]')"
expect "a secret with a newline is refused before anything reaches the VM" pass "$(mac 'export STUB_STATE=Running
  mac_detect; AIDENHQ_INSTALLER_FILE="$work/mac/inst.sh" OPENROUTER_KEY="$(printf "k\nTS_AUTHKEY=x")"; (mac_inner) && exit 1; ! ls "$STUB_DIR"/stdin.* 2>/dev/null')"
expect "uninstall with no terminal and no confirmation deletes nothing" pass "$(mac 'export STUB_STATE=Running; mac_detect; (mac_uninstall) && exit 1
  ! calls | grep -qx delete && [ ! -e "$STUB_DIR/launchctl" ]')"
expect "uninstall confirmed with AIDENHQ_CONFIRM_DELETE_VM=1 removes the agent and deletes the VM" pass "$(mac 'export STUB_STATE=Running; mac_detect
  mkdir -p "$HOME/Library/LaunchAgents"; : >"$HOME/Library/LaunchAgents/ai.aidenhq.vm.plist"; AIDENHQ_CONFIRM_DELETE_VM=1; mac_uninstall
  calls | grep -qx delete && calls | grep -qx -- --force && grep -q "bootout gui/" "$STUB_DIR/launchctl" && [ ! -e "$HOME/Library/LaunchAgents/ai.aidenhq.vm.plist" ]')"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
