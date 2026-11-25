#!/bin/sh
# Test of .github/release/gh-get.sh with a stub curl first on PATH: a 429, a rate-limited 403, a 500 and a transport
# error each exit non-zero naming the HTTP status and the body (a failed read must never pass for an empty answer), a 200
# passes the body through, and the token reaches curl on stdin, never in argv.
#   sh .github/release/gh-get.test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
verdict() { # 1: name: the caller's $1 (ok|bad) decided it; the evidence is in $work
  if [ "$1" = ok ]; then ok "$2"; else bad "$2"; sed 's/^/     /' "$work/out" "$work/err"; fi
}

# The stub: STUB_STATUS sets the HTTP status, STUB_BODY the response body, STUB_FAIL=1 makes curl itself fail. It writes
# -o's target, prints -w's status, records its argv (to prove the token isn't in it) and its stdin (to prove the bearer
# header rides there). Like curl --fail-with-body, a 4xx/5xx makes it exit non-zero after writing the body.
mkdir -p "$work/bin"
cat >"$work/bin/curl" <<'EOS'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_ARGV"
cat >"$STUB_STDIN"
out='' prev=''
for a in "$@"; do
  case "$prev" in -o) out=$a ;; esac
  prev=$a
done
[ "${STUB_FAIL:-0}" = 0 ] || { echo "curl: (7) Connection refused" >&2; exit 7; }
[ -z "$out" ] || cat "$STUB_BODY" >"$out"
printf '%s' "$STUB_STATUS"
case "$STUB_STATUS" in [45][0-9][0-9]) exit 22 ;; esac
exit 0
EOS
chmod +x "$work/bin/curl"

run() { # status body [env...]: one gh-get call; $work/{out,err,argv,stdin} hold what it did; returns gh-get's status
  status=$1 body=$2; shift 2
  printf '%s' "$body" >"$work/stub-body"
  : >"$work/argv" "$work/stdin"
  env "$@" STUB_STATUS="$status" STUB_BODY="$work/stub-body" STUB_ARGV="$work/argv" STUB_STDIN="$work/stdin" \
    PATH="$work/bin:$PATH" sh "$here/gh-get.sh" "https://api.example/read" compare \
    >"$work/out" 2>"$work/err"
}

for spec in "429:API rate limit exceeded" "403:API rate limit exceeded" "500:Server Error"; do
  st=${spec%%:*} msg=${spec#*:}
  if run "$st" "{\"message\":\"$msg\"}" >/dev/null 2>&1; then r=bad; else r=ok; fi
  verdict "$r" "a $st fails the read"
  if grep -q "$st" "$work/err" && grep -q "$msg" "$work/err" && [ ! -s "$work/out" ]; then r=ok; else r=bad; fi
  verdict "$r" "the $st names the status and the body, and leaves stdout empty"
  if grep -q 'the compare read' "$work/err"; then r=ok; else r=bad; fi
  verdict "$r" "the $st names which read failed"
done

if run 000 '' STUB_FAIL=1 >/dev/null 2>&1; then r=bad; else r=ok; fi
verdict "$r" "a transport failure fails the read"
if grep -q 'curl exit 7' "$work/err"; then r=ok; else r=bad; fi
verdict "$r" "a transport failure names curl's exit"

if run 200 '{"status":"identical"}' >/dev/null 2>&1; then r=ok; else r=bad; fi
verdict "$r" "a 200 passes"
if [ "$(cat "$work/out")" = '{"status":"identical"}' ] && [ ! -s "$work/err" ]; then r=ok; else r=bad; fi
verdict "$r" "a 200's body is on stdout and stderr is empty"

if run 200 '' >/dev/null 2>&1; then r=bad; else r=ok; fi
verdict "$r" "a 200 with an empty body fails"
if grep -q 'empty body' "$work/err" && [ ! -s "$work/out" ]; then r=ok; else r=bad; fi
verdict "$r" "a 200 with an empty body fails instead of passing for an answer"

if run 401 '{"message":"Bad credentials"}' GH_TOKEN=tok-canary >/dev/null 2>&1; then r=bad; else r=ok; fi
verdict "$r" "a 401 with a token fails"
if grep -q tok-canary "$work/err"; then r=bad; else r=ok; fi
verdict "$r" "the token is not in the message"
if grep -q tok-canary "$work/argv"; then r=bad; else r=ok; fi
verdict "$r" "the token is not in curl's argv"
if grep -qx 'Authorization: Bearer tok-canary' "$work/stdin" && grep -qx 'Accept: application/vnd.github+json' "$work/stdin"; then r=ok; else r=bad; fi
verdict "$r" "the token and Accept reach curl on stdin"
if grep -q -- '--retry 3' "$work/argv" && grep -q -- '--retry-all-errors' "$work/argv" \
  && grep -q -- '--max-time' "$work/argv" && grep -q -- '--connect-timeout' "$work/argv"; then r=ok; else r=bad; fi
verdict "$r" "the read retries transient failures within a bounded attempt"

if run 200 '{"status":"identical"}' >/dev/null 2>&1; then :; fi
if grep -qx 'Authorization:.*' "$work/stdin"; then r=bad; else r=ok; fi
verdict "$r" "without a token no Authorization header is sent"
if grep -qx 'Accept: application/vnd.github+json' "$work/stdin"; then r=ok; else r=bad; fi
verdict "$r" "without a token Accept still reaches curl on stdin"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
