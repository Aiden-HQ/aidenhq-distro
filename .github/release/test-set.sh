#!/bin/sh
# shellcheck disable=SC2034  # the variables are read by the sourced install.sh functions
# Install a release set and test it, inside the release CI's container (.github/workflows/release.yml):
#   sh .github/release/test-set.sh <release file> <work dir>
# The kernel and marketplace are fetched and verified with install.sh's own functions (fetch_release, fetch_sources: every
# checkout must be exactly the release's sha, every module sha on the marketplace history), then the release suites run on
# them. The suites that ran go to <work dir>/suites.json. AIDENHQ_GITHUB_TOKEN reads private repos (never printed).
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
rel=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
work=$2
mkdir -p "$work"
sed '$d' "$here/install.sh" >"$work/lib.sh"   # every function, without the final `main "$@"`
# shellcheck disable=SC1091
. "$work/lib.sh"
setup_ui
DRY=0 VERBOSE=1 NONINT=1 NO_TS=0 SUDO='' STEP='' REFUSALS='' AUTH_HDR='' RELFILE=''
REL=$(sed -n 's/.*"release"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$rel" | head -1)
SVC=$(id -un) SVC_HOME=$HOME SVC_UID=$(id -u) DIR="$work/kernel" STATE_DIR="$work/state"
TMPD=$(mktemp -d) LOG="$work/install.log"
AIDENHQ_RELEASE_FILE=$rel
git config --global user.name ci && git config --global user.email ci@example.com
git_auth_env
fetch_release
fetch_sources
rc=0
node "$here/.github/release/suites.mjs" "$DIR" "$MKT_DIR" kernel-only swap parity adversarial twin >"$work/suites.out" 2>&1 || rc=$?
cat "$work/suites.out"
[ "$rc" = 0 ] || die "a release suite failed (exit $rc): this set isn't cut"
tail -1 "$work/suites.out" >"$work/suites.json"
