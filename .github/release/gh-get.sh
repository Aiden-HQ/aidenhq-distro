#!/bin/sh
# gh-get <url> [label]: one GET of the GitHub API, its response body on stdout.
#   sh .github/release/gh-get.sh <url> [label]
# release.yml runs this before the job that deletes a release tag, so an empty answer must never pass for a real one: a
# transient failure is retried (curl --retry 3 --retry-all-errors: 429, 5xx, network) and a read that still fails exits
# non-zero naming the label, the HTTP status and the body (truncated), and writes nothing to stdout: an empty 2xx body is a
# failure too, since nothing here has a real empty answer. No -f: its body is the diagnostic (a 4xx/5xx JSON message), and
# the status from -w is checked here instead.
# GH_TOKEN, when set, rides on stdin through -H @- (never a file, never argv); it is a no-op for a public repo.
set -u
url=${1:?usage: gh-get.sh <url> [label]}
label=${2:-the API}
body=$(mktemp) || exit 1
err=$(mktemp) || { rm -f "$body"; exit 1; }
trap 'rm -f "$body" "$err"' EXIT

code=$( { [ -z "${GH_TOKEN:-}" ] || printf 'Authorization: Bearer %s\n' "$GH_TOKEN"; printf 'Accept: application/vnd.github+json\n'; } \
  | curl -sS --retry 3 --retry-all-errors -H @- -o "$body" -w '%{http_code}' "$url" 2>"$err" )
rc=$?

if [ "$rc" = 0 ] && [ -s "$body" ]; then
  case "$code" in 2??) cat "$body"; exit 0 ;; esac
  why="HTTP $code"
elif [ "$rc" = 0 ]; then
  why="HTTP $code with an empty body"
else
  why="curl exit $rc (HTTP $code)"
fi
resp=$(tr '\n' ' ' <"$body" | head -c 500)
printf 'gh-get: the %s read failed: %s\n' "$label" "$why" >&2
[ -z "$resp" ] || printf 'gh-get: response body: %s\n' "$resp" >&2
[ ! -s "$err" ] || printf 'gh-get: curl: %s\n' "$(tr '\n' ' ' <"$err" | head -c 300)" >&2
exit 1
