#!/bin/sh
# shellcheck disable=SC2034,SC2016,SC2030,SC2031  # variables are read by the sourced install.sh; hook bodies are eval'd later
# Offline test of install.sh's release verification (lean-core spec A17): local fixture repos and a release file pass;
# a tampered release, a moved checkout or a module sha off the marketplace history each stop it.
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
mkrepo modules m1 m2 m3
mkrepo other x1
K=$(git -C "$work/git/kernel.git.src" rev-parse HEAD)
M=$(git -C "$work/git/modules.git.src" rev-parse HEAD)
M1=$(git -C "$work/git/modules.git.src" rev-parse HEAD~2)
X=$(git -C "$work/git/other.git.src" rev-parse HEAD)

flip() { echo "$1" | awk '{ c = substr($0, 40, 1); print substr($0, 1, 39) (c == "0" ? "1" : "0") }'; }
release() { # kernel marketplace module-a module-b
  cat <<EOF
{ "name": "AidenHQ", "release": "2026.11", "kernel": "$1", "kernel_repo": "acme/kernel",
  "marketplace": { "name": "aidenhq", "source": { "source": "github", "repo": "acme/modules" }, "sha": "$2" },
  "modules": {
    "board": "$3",
    "tasks": "$4"
  } }
EOF
}

# case NAME EXPECT(pass|stop) RELEASE-ARGS... [-- SETUP-CMD]: a fresh home each time; SETUP-CMD runs between fetch and verify.
case_() {
  name=$1 expect=$2; shift 2
  home="$work/home-$pass-$fail"; mkdir -p "$home"
  release "$1" "$2" "$3" "$4" >"$work/rel.json"
  shift 4; pre="${1:-}"
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

case_ "a real release verifies"                  pass "$K" "$M" "$M" "$M1"
case_ "placeholder shas stop it"                 stop "TODO-kernel-sha" "$M" "$M" "$M1"
case_ "one flipped hex digit in the kernel sha"  stop "$(flip "$K")" "$M" "$M" "$M1"
case_ "a kernel sha from another repo"           stop "$X" "$M" "$M" "$M1"
case_ "a module sha off the marketplace history" stop "$K" "$M" "$M" "$X"
case_ "a tracked change in the checkout"         stop "$K" "$M" "$M" "$M1" 'echo evil >>"$DIR/ops-a"'
case_ "a checkout moved to another commit"       stop "$K" "$M" "$M" "$M1" 'git -C "$DIR" checkout -q --detach HEAD~1; checkout_at() { :; }'
case_ "a rerun on a verified checkout"           pass "$K" "$M" "$M" "$M1" ':'


# lib CMDS: run CMDS with install.sh's functions loaded and a neutral environment; exit status is the result.
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

# Derived defaults on the two calibration hosts (lean VM and the EX44).
expect "4 vCPU / 8 GB / 100 GB -> 2 jobs, 60 min, 1 CI runner, 15 GB reserve" pass \
  'CORES=4 RAM_MB=7812 DISK_TOTAL_GB=96; derive_defaults; [ "$MAX_CONCURRENT/$JOB_TIMEOUT/$CI_RUNNERS/$DISK_RESERVE_GB" = 2/60/1/15 ]'
expect "20 threads / 64 GB / 460 GB -> 16 jobs, 120 min, 4 CI runners" pass \
  'CORES=20 RAM_MB=64076 DISK_TOTAL_GB=458; derive_defaults; [ "$MAX_CONCURRENT/$JOB_TIMEOUT/$CI_RUNNERS" = 16/120/4 ]'

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

# The owner's email is needed and checked; the pinned kernel's pins.json decides which hosts are supported.
expect "a plain email is accepted" pass 'NONINT=1 DRY=0 REFUSALS=""; AIDENHQ_OWNER_EMAIL=a.b+c@example.com; ensure_owner_email; [ -z "$REFUSALS" ]'
expect "a missing email is refused" pass 'NONINT=1 DRY=0 REFUSALS=""; AIDENHQ_OWNER_EMAIL=""; ensure_owner_email; [ -n "$REFUSALS" ]'
expect "an email with a space is refused" pass 'NONINT=1 DRY=0 REFUSALS=""; AIDENHQ_OWNER_EMAIL="a b@example.com"; ensure_owner_email; [ -n "$REFUSALS" ]'
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
while [ $# -gt 0 ]; do [ "$1" = --config ] && cfg=$2; shift; done
echo "cfgmode=$(ls -l "$cfg" | cut -c1-10)"; echo "cfg=$(tr '\n' ' ' <"$cfg")"; echo "cfgpath=$cfg"
echo AIDENHQ_SSH_TUNNEL=ssh-x; echo AIDENHQ_SETUP_URL=http://old; echo AIDENHQ_SETUP_URL=http://127.0.0.1:3121/setup/t
EOS
expect "setup is driven unattended: env, a 0600 config, parsed links, config deleted" pass \
  "sudo() { echo '(ALL) NOPASSWD: ALL'; }; verify_at() { :; }; root_verify() { :; }; mktemp() { command mktemp '$work/pe.XXXX'; }
   DIR='$work/h' NO_TS=1 NONINT=1 SETUP_URL='' SSH_TUNNEL='' PENV='' KERNEL_SHA=x MAX_CONCURRENT=2 JOB_TIMEOUT=60 CI_RUNNERS=1
   AIDENHQ_OWNER_EMAIL=a@example.com OPENROUTER_KEY=sk-or-x; run_setup
   grep -qx 'args=--unattended --no-tailscale --config .*' \"\$LOG\" && grep -qx 'env=a@example.com,2,60,1,'\"\$SVC\" \"\$LOG\" \
     && grep -qx 'cfgmode=-rw-------' \"\$LOG\" && grep -qx 'cfg=OPENROUTER_KEY=\"sk-or-x\" ' \"\$LOG\" \
     && [ \"\$SETUP_URL\" = http://127.0.0.1:3121/setup/t ] && [ \"\$SSH_TUNNEL\" = ssh-x ] \
     && [ ! -e \"\$(sed -n 's/^cfgpath=//p' \"\$LOG\")\" ]"

expect "the final output carries the two machine-readable lines, no --verbose needed" pass \
  "DRY=0 VERBOSE=0 N='' B='' G='' Y='' LOG=/dev/null DIR=/x SETUP_URL=http://127.0.0.1:3121/setup/t SSH_TUNNEL=ssh-x
   sudo() { return 1; }; out=\$(finish); printf '%s\n' \"\$out\" | grep -qx 'AIDENHQ_SETUP_URL=http://127.0.0.1:3121/setup/t' \
     && printf '%s\n' \"\$out\" | grep -qx 'AIDENHQ_SSH_TUNNEL=ssh-x'"

# Root verification ignores the service user's .git (replace refs) and catches any tracked change.
g init -q "$work/rv"; echo good >"$work/rv/f"; g -C "$work/rv" add -A; g -C "$work/rv" commit -qm one
RK=$(git -C "$work/rv" rev-parse HEAD)
expect "root verification passes a clean checkout" pass "DIR='$work/rv' KERNEL_SHA=$RK; root_verify"
echo evil >"$work/rv/f"; g -C "$work/rv" commit -qam evil; EVIL=$(git -C "$work/rv" rev-parse HEAD)
git -C "$work/rv" checkout -q --detach "$RK"; echo evil >"$work/rv/f"; git -C "$work/rv" replace "$RK" "$EVIL"
expect "a replace ref fools the user-side check" pass "DIR='$work/rv' SVC_HOME=x KERNEL_SHA=$RK; verify_at '$work/rv' $RK"
expect "but not root verification" stop "DIR='$work/rv' KERNEL_SHA=$RK; root_verify"

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
expect "the VM: vz, the pinned image digest, no Mac folders shared, only 3121 forwarded" pass "$(mac 'mac_detect; mac_size; mac_template >"$TMPD/t.yaml"
  grep -qx "vmType: vz" "$TMPD/t.yaml" && grep -qx "  digest: sha256:$UBUNTU_SHA256_arm64" "$TMPD/t.yaml" && grep -qx "mounts: \[\]" "$TMPD/t.yaml" \
    && grep -qx "  arch: aarch64" "$TMPD/t.yaml" && [ "$(grep -c -- "^- guestPort:" "$TMPD/t.yaml")" = 1 ] && grep -qx -- "- guestPort: 3121" "$TMPD/t.yaml" \
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
