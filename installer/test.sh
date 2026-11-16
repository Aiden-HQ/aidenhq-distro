#!/bin/sh
# shellcheck disable=SC2034,SC2016  # variables are read by the sourced install.sh; hook bodies are eval'd later
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
  },
  "host": { "docker": "29.9.3", "node": "24.22.3" } }
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
    SVC=$(id -un) SVC_HOME="$home" SVC_UID=$(id -u) DIR="$home/aidenhq" STATE_DIR="$home/.aidenhq" STATE="$home/.aidenhq/install.state"
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

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
