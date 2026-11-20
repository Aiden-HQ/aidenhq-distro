#!/bin/sh
# shellcheck disable=SC2034  # the variables are read by the sourced install.sh functions
# Fetch and verify a release set, in the release CI (.github/workflows/release.yml):
#   sh .github/release/test-set.sh fetch <release file> <work dir>   fetch and verify (the only run given a token)
# fetch uses install.sh's own functions (fetch_release, fetch_sources: the product checkout must be exactly the release's
# sha; the official modules are its modules/ tree) and runs nothing it fetched. AIDENHQ_GITHUB_TOKEN reads private repos; it
# rides in git's environment only (never a file in a checkout); the steps that run fetched code never get it.
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
mode=$1; shift
[ "$mode" = fetch ] || { echo "usage: test-set.sh fetch <release file> <work dir>" >&2; exit 2; }

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
TMPD=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/aidenhq-fetch.XXXXXX") LOG="$work/install.log"
trap 'rm -rf "$TMPD" "$work/lib.sh"' EXIT
AIDENHQ_RELEASE_FILE=$rel
# The token reaches git through its environment only (install.sh's git_auth_env also writes a curl header file, which
# this local release file never needs): nothing with it is written to disk.
tok="${AIDENHQ_GITHUB_TOKEN:-}"
if [ -n "$tok" ]; then
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$tok" | base64 | tr -d '\n')"
  export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
fi
fetch_release
fetch_sources
