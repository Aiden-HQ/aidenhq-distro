#!/bin/sh
# gh-get <url> [label]: one GET of the GitHub API, its response body on stdout.
#   sh .github/release/gh-get.sh <url> [label]
# release.yml runs this before the job that deletes a release tag, so a failed read must never pass for an answer:
#   - transient failures are retried (--retry 3 --retry-all-errors: 5xx, a timeout, a refused connection) and GitHub's
#     rate limits with it — 429, and the 403 with an exhausted budget or a Retry-After that this step hit on the shared
#     unauthenticated budget (--fail-with-body is what makes a 403 a retryable failure at all, without losing its body);
#   - each attempt is bounded (--connect-timeout 10 --max-time 30) so a stalled read retries and then fails instead of
#     holding the job until its timeout;
#   - a read that still fails exits non-zero naming the label, the HTTP status and the body (truncated), and writes
#     nothing to stdout. An empty 2xx body is a failure too: nothing here has a real empty answer.
# The token, when there is one, rides on stdin through -H @- (never a file, never argv); an unset one sends only Accept.
set -u
url=${1:?usage: gh-get.sh <url> [label]}
label=${2:-the API}
body=$(mktemp) || exit 1
err=$(mktemp) || { rm -f "$body"; exit 1; }
trap 'rm -f "$body" "$err"' EXIT

code=$( { [ -z "${GH_TOKEN:-}" ] || printf 'Authorization: Bearer %s\n' "$GH_TOKEN"; printf 'Accept: application/vnd.github+json\n'; } \
  | curl -sS --fail-with-body --retry 3 --retry-all-errors --connect-timeout 10 --max-time 30 \
      -H @- -o "$body" -w '%{http_code}' "$url" 2>"$err" )
rc=$?
case "$code" in ''|*[!0-9]*) code=000 ;; esac

if [ "$rc" = 0 ]; then
  case "$code" in
    2??) if [ -s "$body" ]; then cat "$body"; exit 0; fi; why="HTTP $code with an empty body" ;;
    *) why="HTTP $code" ;;
  esac
elif [ "$code" = 000 ]; then
  why="curl exit $rc, no HTTP status (the request never completed)"
else
  why="HTTP $code (curl exit $rc)"
fi
resp=$(tr '\n' ' ' <"$body" | head -c 500)
printf 'gh-get: the %s read failed: %s\n' "$label" "$why" >&2
[ -z "$resp" ] || printf 'gh-get: response body: %s\n' "$resp" >&2
[ ! -s "$err" ] || printf 'gh-get: curl: %s\n' "$(tr '\n' ' ' <"$err" | head -c 300)" >&2
exit 1
