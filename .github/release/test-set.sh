#!/bin/sh
# shellcheck disable=SC2034  # the variables are read by the sourced install.sh functions
# Install a release set and test it, in the release CI's containers (.github/workflows/release.yml), in two runs:
#   sh .github/release/test-set.sh fetch  <release file> <work dir>   fetch and verify (the only run given a token)
#   sh .github/release/test-set.sh suites <work dir>                  the release suites, on the verified checkouts
# fetch uses install.sh's own functions (fetch_release, fetch_sources: every checkout must be exactly the release's sha,
# every module sha on the marketplace history) and runs nothing it fetched. AIDENHQ_GITHUB_TOKEN reads private repos; it
# rides in git's environment only (never a file in a checkout), and the suites run in a separate container that never
# gets it. The suites that ran go to <work dir>/suites.json.
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
mode=$1; shift

if [ "$mode" = fetch ]; then
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
  git_auth_env
  fetch_release
  fetch_sources
  rm -rf "$TMPD" "$work/lib.sh"
  exit 0
fi

[ "$mode" = suites ] || { echo "usage: test-set.sh fetch <release file> <work dir> | suites <work dir>" >&2; exit 2; }
work=$1
for v in AIDENHQ_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN GIT_CONFIG_COUNT; do
  eval "[ -z \"\${$v:-}\" ]" || { echo "refusing: $v is set; the suites run without credentials" >&2; exit 1; }
done
git config --global user.name ci && git config --global user.email ci@example.com
rc=0
node "$here/.github/release/suites.mjs" "$work/kernel" "$work/state/modules/marketplace" kernel-only swap parity adversarial twin >"$work/suites.out" 2>&1 || rc=$?
cat "$work/suites.out"
[ "$rc" = 0 ] || { echo "a release suite failed (exit $rc): this set isn't cut" >&2; exit 1; }
tail -1 "$work/suites.out" >"$work/suites.json"
