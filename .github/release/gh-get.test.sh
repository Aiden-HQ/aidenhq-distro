#!/bin/sh
# Test of .github/release/gh-get.sh with a stub curl first on PATH: a 429, a 500 and a transport error each exit non-zero
# naming the HTTP status and the body (a failed read must never pass for an empty answer), a 200 passes the body through,
# and the token reaches curl on stdin, never in argv.
#   sh .github/release/gh-get.test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { # name: the caller's last command decided it; the reason is in $work/err
  if [ "$1" = ok ]; then ok "$2"; else bad "$2"; sed 's/^/     /' "$work/out" "$work/err"; fi
}

# The stub: STUB_STATUS sets the HTTP status, STUB_BODY the response body, STUB_FAIL=1 makes curl itself fail. It writes
# -o's target, prints -w's status, and records its argv (to prove the token isn't in it).
mkdir -p "$work/bin"
cat >"$work/bin/curl" <<'EOS'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_ARGV"
out='' prev=''
for a in "$@"; do
  case "$prev" in -o) out=$a ;; esac
  prev=$a
done
[ "${STUB_FAIL:-0}" = 0 ] || { echo "curl: (7) Connection refused" >&2; exit 7; }
[ -z "$out" ] || cat "$STUB_BODY" >"$out"
printf '%s' "$STUB_STATUS"
EOS
chmod +x "$work/bin/curl"

# run STATUS BODY [env...]: one gh-get call; $work/{out,err,argv} hold its stdout, stderr and curl's argv; returns gh-get's.
run() { # status body [env...]: the output goes to the caller (discarded), stderr and argv are always kept
  status=$1 body=$2; shift 2
  printf '%s' "$body" >"$work/stub-body"
  : >"$work/argv"
  env "$@" STUB_STATUS="$status" STUB_BODY="$work/stub-body" STUB_ARGV="$work/argv" \
    PATH="$work/bin:$PATH" sh "$here/gh-get.sh" "https://api.example/read" compare \
    >"$work/out" 2>"$work/err"
}

if run 429 '{"message":"API rate limit exceeded"}' >/dev/null 2>&1; then res=pass; else res=fail; fi
if [ "$res" = fail ]; then ok "a 429 fails the read"; else bad "a 429 fails the read"; fi
if grep -q 429 "$work/err" && grep -q 'API rate limit exceeded' "$work/err" && [ ! -s "$work/out" ]; then r=ok; else r=bad; fi
check "$r" "the 429 names the status and the body, and leaves stdout empty"
if grep -q 'the compare read' "$work/err"; then r=ok; else r=bad; fi
check "$r" "the 429 names which read failed"

if run 500 '{"message":"Server Error"}' >/dev/null 2>&1; then res=pass; else res=fail; fi
if [ "$res" = fail ]; then ok "a 500 fails the read"; else bad "a 500 fails the read"; fi
if grep -q 500 "$work/err" && grep -q 'Server Error' "$work/err"; then r=ok; else r=bad; fi
check "$r" "the 500 names the status and the body"

if run 000 '' STUB_FAIL=1 >/dev/null 2>&1; then res=pass; else res=fail; fi
if [ "$res" = fail ]; then ok "a transport failure fails the read"; else bad "a transport failure fails the read"; fi
if grep -q 'curl exit 7' "$work/err"; then r=ok; else r=bad; fi
check "$r" "a transport failure names curl's exit"

if run 200 '{"status":"identical"}' >/dev/null 2>&1; then res=pass; else res=fail; fi
if [ "$res" = pass ]; then ok "a 200 passes"; else bad "a 200 passes"; fi
if [ "$(cat "$work/out")" = '{"status":"identical"}' ] && [ ! -s "$work/err" ]; then r=ok; else r=bad; fi
check "$r" "a 200's body is on stdout and stderr is empty"

if run 200 '' >/dev/null 2>&1; then res=pass; else res=fail; fi
if [ "$res" = fail ]; then ok "a 200 with an empty body fails"; else bad "a 200 with an empty body fails"; fi
if grep -q 'empty body' "$work/err" && [ ! -s "$work/out" ]; then r=ok; else r=bad; fi
check "$r" "a 200 with an empty body fails instead of passing for an answer"

if run 401 '{"message":"Bad credentials"}' GH_TOKEN=tok-canary >/dev/null 2>&1; then res=pass; else res=fail; fi
if [ "$res" = fail ]; then ok "a 401 with a token fails"; else bad "a 401 with a token fails"; fi
if grep -q tok-canary "$work/err"; then r=bad; else r=ok; fi
check "$r" "the token is not in the message"
if grep -q tok-canary "$work/argv"; then r=bad; else r=ok; fi
check "$r" "the token is not in curl's argv"
if grep -q -- '--retry 3' "$work/argv" && grep -q -- '--retry-all-errors' "$work/argv"; then r=ok; else r=bad; fi
check "$r" "the read retries transient failures"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
