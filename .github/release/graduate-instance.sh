#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2024  # single-quoted programs run in another shell; redirects write the runner's own files
# The host's side of graduation's test instance (.github/workflows/graduate.yml, test job), on a fresh GitHub-hosted runner
# with no token: the service user, the disk, the baseline install with its own published installer, the upgrade by the
# installed updater, and the host checks after it. The owner's side (first run, chats, apps) is graduate-scenario.mjs.
#   bash graduate-instance.sh prepare                 service user (uid 1000, as Paperclip's image wants) and disk
#   bash graduate-instance.sh install                 BASELINE's install.sh (checked against BASELINE_INSTALL_DIGEST)
#   bash graduate-instance.sh upgrade                 TAG through the instance's own updater (AIDENHQ_UPDATE_CANDIDATE)
#   bash graduate-instance.sh host-checks             running release, kernel and images; generation; verify-security.sh
#   bash graduate-instance.sh result                  result.json from checks.json and IDENTITY, and its verdict
#   bash graduate-instance.sh logs <dir>              what a failure needs, secrets redacted
# Each check's outcome goes to $GRAD_DIR/checks.json (the result is built from it). Every wait is bounded.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${GRAD_DIR:?}"
SVC=aidenhq SVC_HOME=/home/aidenhq
CO=$SVC_HOME/aidenhq INST=$SVC_HOME/aidenhq-instance STATE=$SVC_HOME/.local/state/aidenhq   # ops/setup.sh's AIDENHQ_STATE_DIR
NEED_GB=70   # the installer refuses below 60 GB free; the upgrade's images need room on top
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { echo "::error::$*"; exit 1; }
rec() { # name true|false [note]
  local f="$GRAD_DIR/checks.json"
  [ -f "$f" ] || echo '{"checks":{},"notes":[]}' >"$f"
  jq --arg n "$1" --argjson ok "$([ "$2" = true ] && echo true || echo false)" --arg note "${3:-}" \
    '.checks[$n] = $ok | if $note != "" then .notes += ["\($n): \($note[0:280])"] else . end' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  log "$([ "$2" = true ] && echo 'ok  ' || echo FAIL) $1${3:+: $3}"
}
svc_uid() { id -u "$SVC"; }
# As the service user, in its home, with its user systemd bus (setup enables lingering).
as_svc() { local u; u=$(svc_uid); sudo -u "$SVC" -H env XDG_RUNTIME_DIR="/run/user/$u" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$u/bus" bash -c 'cd "$HOME" && "$@"' _ "$@"; }
gb() { df -Pk "$1" | awk 'NR==2 { print int($4 / 1048576) }'; }
# A command line in the checkout, as the service user, with the checkout's .env exported (what the kernel reads); "$1".. are args.
in_co() { local c=$1; shift; as_svc bash -c 'cd ~/aidenhq && set -a && { [ ! -f .env ] || . ./.env; } && set +a && eval "$0"' "$c" "$@"; }
# A kernel record's "state rule" (kernel.db, read-only), empty when there is none.
record_state() {
  [ -n "$2" ] || return 0
  sudo node -e 'const { DatabaseSync } = require("node:sqlite"); const r = new DatabaseSync(process.argv[1], { readOnly: true }).prepare("SELECT state, rule FROM records WHERE id = ?").get(process.argv[2]); if (r) console.log(`${r.state} ${r.rule ?? ""}`)' "$1/kernel/kernel.db" "$2" 2>/dev/null || true
}
# The newest apply generation (ops/lib/generations.sh), as JSON ({} before any); good_on SHA: it is good on that product.
last_gen() { local g; g=$(sudo tail -1 "$STATE/generations.jsonl" 2>/dev/null || true); { [ -n "$g" ] && jq -c . <<<"$g" 2>/dev/null; } || echo '{}'; }
good_on() { [ "$(last_gen | jq -r '"\(.health) \(.product)"')" = "good $1" ]; }

prepare() {
  # The service user as the installer makes it (ensure_user), made first so its uid is 1000: the stack runs as it (PUID) and
  # the pinned Paperclip image writes its own files as 1000 when it starts (distro #49). The installer finds it and keeps it.
  if ! id "$SVC" >/dev/null 2>&1; then
    if getent passwd 1000 >/dev/null; then
      echo "::warning::uid 1000 is $(getent passwd 1000 | cut -d: -f1) on this runner: $SVC gets another uid (Paperclip's image expects 1000)"
      sudo useradd -m -s /bin/bash "$SVC"
    else sudo useradd -m -u 1000 -s /bin/bash "$SVC"; fi
    sudo usermod -aG sudo "$SVC"
    echo "$SVC ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-aidenhq-$SVC" >/dev/null
    sudo chmod 0440 "/etc/sudoers.d/90-aidenhq-$SVC"
  fi
  log "service user $SVC uid $(svc_uid)"
  # The disk, as measured here: the installer's own minimum stays as it is for everyone; the runner makes room for it.
  local before mnt=none
  before=$(gb /); [ -d /mnt ] && mnt=$(gb /mnt)
  log "free before: / ${before} GB, /mnt ${mnt} GB"; df -h / /mnt 2>/dev/null || df -h /
  if [ "$(gb /)" -lt "$NEED_GB" ]; then
    # Preinstalled toolchains nothing here uses.
    sudo rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache/CodeQL /usr/share/swift \
      /usr/local/share/powershell /usr/local/share/chromium /opt/microsoft /opt/google /usr/local/julia* || true
    sudo docker image prune -af >/dev/null 2>&1 || true
    log "free after removing preinstalled toolchains: / $(gb /) GB"
  fi
  local moved=no
  if [ "$(gb /)" -lt "$NEED_GB" ] && [ "$mnt" != none ] && [ "$(gb /mnt)" -ge "$NEED_GB" ]; then
    # Docker's and containerd's data and the service user's home (the checkout) on the runner's second disk, before any of
    # them is used by the install.
    sudo systemctl stop docker.socket docker containerd 2>/dev/null || true
    for d in /var/lib/docker /var/lib/containerd "$SVC_HOME"; do
      sudo mkdir -p "/mnt/grad$d" "$d"
      sudo cp -a "$d/." "/mnt/grad$d/" 2>/dev/null || true
      sudo mount --bind "/mnt/grad$d" "$d"
    done
    sudo systemctl start containerd docker 2>/dev/null || true
    moved=yes
  fi
  local dock=/var/lib/docker
  [ "$(gb "$dock")" -ge 60 ] && [ "$(gb "$SVC_HOME")" -ge 60 ] \
    || die "this runner has $(gb "$dock") GB free for Docker and $(gb "$SVC_HOME") GB for the checkout; the installer needs 60 GB (measured: / ${before} GB, /mnt ${mnt} GB at start)"
  local line
  line="Runner disk: / ${before} GB free at start, $(gb /) GB after cleanup; /mnt ${mnt} GB; data moved to /mnt: ${moved}."
  log "$line"; [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "$line" >>"$GITHUB_STEP_SUMMARY"
}

install_baseline() {
  : "${BASELINE:?}" "${BASELINE_INSTALL_DIGEST:?}" "${GITHUB_REPOSITORY:?}"
  local d="$RUNNER_TEMP/baseline-installer"
  mkdir -p "$d"; chmod 0755 "$d"
  curl -fsSL --retry 3 -o "$d/install.sh" "https://github.com/$GITHUB_REPOSITORY/releases/download/$BASELINE/install.sh"
  [ "sha256:$(sha256sum "$d/install.sh" | cut -d' ' -f1)" = "$BASELINE_INSTALL_DIGEST" ] || die "$BASELINE's install.sh isn't the published asset select read"
  chmod 0644 "$d/install.sh"
  log "installing $BASELINE with its own installer (non-interactive, no Tailscale)"
  # The model key reaches the installer in its environment only (sudo keeps that one variable); the installer writes it to
  # setup's root-only config file. Never on a command line.
  local rc=0
  (cd / && sudo --preserve-env=OPENROUTER_KEY env AIDENHQ_USER="$SVC" AIDENHQ_OWNER_EMAIL=owner@example.com \
    AIDENHQ_OWNER_NAME="Graduation Owner" AIDENHQ_TIMEZONE=UTC sh "$d/install.sh" --non-interactive --no-tailscale) \
    >"$GRAD_DIR/install.log" 2>&1 </dev/null || rc=$?
  # The log without the one-time setup token.
  sed -E 's/(token=)[A-Za-z0-9_-]+/\1REDACTED/g' "$GRAD_DIR/install.log" | grep -E '^(==>|    |AIDENHQ_PROGRESS|error|Install stopped)' | tail -150 || true
  [ "$rc" = 0 ] || { rec baseline_installed false "the installer exited $rc"; exit 1; }
  sed -n 's/^AIDENHQ_SETUP_URL=//p' "$GRAD_DIR/install.log" | tail -1 >"$GRAD_DIR/setup-url"
  [ -s "$GRAD_DIR/setup-url" ] || { rec baseline_installed false "no AIDENHQ_SETUP_URL line"; exit 1; }
  if sudo grep -Eq "^release: \{ *name: \"?${BASELINE//./\\.}\"?" "$INST/instance.yaml"; then rec baseline_installed true "$BASELINE"
  else rec baseline_installed false "instance.yaml doesn't pin $BASELINE"; exit 1; fi
}

upgrade() {
  : "${TAG:?}" "${KERNEL:?}"
  # The bootstrap: a baseline whose updater can't prepare a named pre-release can't be upgraded this way (select checks it too).
  sudo grep -q AIDENHQ_UPDATE_CANDIDATE "$CO/kernel/src/updates.ts" \
    || { rec upgraded false "baseline predates graduation; graduate one release by hand"; die "baseline predates graduation; graduate one release by hand (README \"Release graduation\")"; }
  # Where the kernel keeps its state: its checkout's .env over the defaults, as the kernel reads it (kernel/src/env.ts).
  local data
  data=$(in_co 'node -e "console.log(require(\"node:path\").resolve(process.env.AIDENHQ_DATA_DIR || \"data\"))"')
  # The instance's own updater, asked for exactly this pre-release: verified and prepared as any release, then filed by the
  # kernel as a kernel.apply that the AI reviewer decides (auto-updates are on for a new install). Retried for 25 minutes:
  # GitHub's API, unauthenticated from a shared runner address, may be rate-limited (403/429) until its hourly reset. A check
  # still rate-limited at the end is the infrastructure's failure, never the candidate's: no check is recorded, so the result
  # is incomplete and the candidate stays pending (graduate.mjs onFailure).
  local out='' i
  for i in $(seq 1 13); do
    out=$(in_co 'AIDENHQ_UPDATE_CANDIDATE="$1" node --disable-warning=ExperimentalWarning kernel/src/updates.ts check "$1" graduate' "$TAG" 2>&1) || true
    log "check $i: $out"
    grep -q "^release $TAG prepared" <<<"$out" && break
    if [ "$i" = 13 ]; then
      grep -qE 'answered (403|429)' <<<"$out" && die "GitHub's API rate-limited the instance's updater for 25 minutes (infrastructure, not $TAG): $out"
      rec upgraded false "the updater didn't prepare $TAG: $out"; exit 1
    fi
    sleep 120
  done
  # The kernel files it within 5 minutes and follows its record to the end: installed, or failed with why (75 minutes). A
  # record waiting on the owner (a release that adds module authority is the owner's tap whatever auto_update says) can't
  # end here: it fails at once, and such a release is graduated by hand.
  local st='{}' rec_state='' shown=0 end=$((SECONDS + 75 * 60))
  while [ "$SECONDS" -lt "$end" ]; do
    st=$(sudo cat "$data/updates/state.json" 2>/dev/null || echo '{}')
    [ "$(jq -r '.last.release // ""' <<<"$st")" = "$TAG" ] && break
    rec_state=$(record_state "$data" "$(jq -r '.flight.record // ""' <<<"$st")")
    if [ "${rec_state%% *}" = owner ]; then rec upgraded false "the update waits for the owner's approval (${rec_state#* }): graduate it by hand after checking it"; exit 1; fi
    if [ $((SECONDS - shown)) -ge 300 ]; then log "waiting: $(jq -c '{ready: (.ready.release // null), flight: (.flight | if . then {release, record} else null end), error}' <<<"$st") record: ${rec_state:-none}"; shown=$SECONDS; fi
    sleep 30
  done
  if [ "$(jq -r '.last.release // ""' <<<"$st")" != "$TAG" ]; then rec upgraded false "the update record didn't end within 75 minutes (record: ${rec_state:-none}): $(jq -c '{flight, error}' <<<"$st")"; exit 1; fi
  [ "$(jq -r .last.outcome <<<"$st")" = installed ] || { rec upgraded false "$TAG didn't install: $(jq -r '.last.why // "?"' <<<"$st")"; exit 1; }
  # Its apply generation settled good on the candidate's kernel (20 minutes).
  local end2=$((SECONDS + 20 * 60))
  until good_on "$KERNEL" || [ "$SECONDS" -ge "$end2" ]; do sleep 20; done
  if good_on "$KERNEL"; then rec upgraded true "$TAG installed by the updater; generation $(last_gen | jq -r .n) good"
  else rec upgraded false "the apply generation isn't good on ${KERNEL:0:12}: $(last_gen)"; exit 1; fi
}

host_checks() {
  : "${TAG:?}" "${TAG_SHA:?}" "${KERNEL:?}" "${CANDIDATE_FILE_DIGEST:?}" "${GITHUB_REPOSITORY:?}"
  # What runs: the instance's main pins the candidate, the checkout is its kernel, every AidenHQ image running is one the
  # candidate's release file names by digest.
  local inst head why=''
  inst=$(as_svc bash -c 'cd ~/aidenhq-instance && git fetch -q origin main && git show origin/main:instance.yaml')
  head=$(as_svc git -C "$CO" rev-parse HEAD)
  grep -qx "product: $KERNEL" <<<"$inst" || why+="instance.yaml's product isn't ${KERNEL:0:12}; "
  grep -Eq "^release: \{ *name: \"?${TAG//./\\.}\"?,.* sha: $TAG_SHA *\}" <<<"$inst" || why+="instance.yaml's release isn't $TAG at ${TAG_SHA:0:12}; "
  [ "$head" = "$KERNEL" ] || why+="the checkout is at ${head:0:12}; "
  as_svc systemctl --user is-active --quiet aidenhq-kernel || why+="the kernel unit isn't active; "
  local f="$RUNNER_TEMP/candidate.json"
  curl -fsSL --retry 3 -o "$f" "https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/$TAG.json"
  [ "sha256:$(sha256sum "$f" | cut -d' ' -f1)" = "$CANDIDATE_FILE_DIGEST" ] || die "$TAG.json isn't the asset select read"
  local want running n=0 img
  want=$(jq -r '.images // {} | .[]' "$f" | sort -u)
  running=$(sudo docker ps --format '{{.Image}}' | sort -u)
  if [ -n "$want" ]; then
    while IFS= read -r img; do
      case "$img" in ghcr.io/aiden-hq/*) grep -qxF "$img" <<<"$want" && n=$((n + 1)) || why+="running $img isn't one of $TAG's images; " ;; esac
    done <<<"$running"
    [ "$n" -gt 0 ] || why+="no container runs one of $TAG's images; "
  fi
  if [ -z "$why" ]; then rec running_release true "$TAG, kernel ${KERNEL:0:12}, $n running images by digest"; else rec running_release false "$why"; fi
  if good_on "$KERNEL"; then rec generation_good true "generation $(last_gen | jq -r .n)"; else rec generation_good false "last generation: $(last_gen)"; fi
  local out rc=0
  out=$(as_svc bash -c 'cd ~/aidenhq && bash scripts/verify-security.sh' 2>&1) || rc=$?
  printf '%s\n' "$out" | tail -60
  if [ "$rc" = 0 ]; then rec verify_security true; else rec verify_security false "$(grep -m3 FAIL <<<"$out" | tr '\n' ' ')"; fi
}

result() {
  : "${IDENTITY:?}" "${BASELINE:?}"
  local f="$GRAD_DIR/checks.json"; [ -f "$f" ] || echo '{"checks":{},"notes":[]}' >"$f"
  # Every check graduation needs, false unless it ran and passed (graduate.mjs CHECKS).
  jq -n --argjson id "$IDENTITY" --arg base "$BASELINE" --slurpfile c "$f" --argjson names "$(node -e 'import(process.argv[1]).then((m) => console.log(JSON.stringify(m.CHECKS)))' "$here/graduate.mjs")" '
    ($names | map({ (.): ($c[0].checks[.] == true) }) | add) as $checks
    | { release: $id.tag, release_id: $id.release_id, tag_sha: $id.tag_sha, kernel: $id.kernel, baseline: $base,
        passed: ($checks | all), checks: $checks, notes: ($c[0].notes | map(.[0:300]) | .[-20:]) }' >"$GRAD_DIR/result.json"
  jq . "$GRAD_DIR/result.json"
  # The verdict: passed; failed (a check ran and said no: the candidate's own failure, graduate.mjs onFailure rejects it); or
  # incomplete (checks missing and none said no: a rate limit, a step cut short by its timeout; the candidate stays pending).
  local verdict
  verdict=$(jq -r --slurpfile c "$f" 'if .passed then "passed" elif ($c[0].checks | to_entries | any(.value == false)) then "failed" else "incomplete" end' "$GRAD_DIR/result.json")
  echo "verdict: $verdict"
  [ -z "${GITHUB_OUTPUT:-}" ] || echo "verdict=$verdict" >>"$GITHUB_OUTPUT"
  jq -r '.checks | to_entries[] | "| \(.key) | \(if .value then "ok" else "FAIL" end) |"' "$GRAD_DIR/result.json" \
    | { printf '| check | |\n|---|---|\n'; cat; echo; echo "Verdict: $verdict"; } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

logs() {
  local out=$1; mkdir -p "$out"
  cp "$GRAD_DIR"/{install.log,checks.json,baseline.json} "$out/" 2>/dev/null || true
  if id "$SVC" >/dev/null 2>&1; then
    for u in aidenhq-kernel aidenhq-runner aidenhq-computers; do as_svc journalctl --user -u "$u" --no-pager -n 3000 >"$out/$u.log" 2>&1 || true; done
    sudo cat "$CO/data/updates/state.json" >"$out/updates-state.json" 2>/dev/null || true
    sudo sh -c "cat '$STATE/generations.jsonl'; ls -t '$STATE'/apply-*.log 2>/dev/null | head -3 | xargs -r tail -n 400" >"$out/generations.log" 2>&1 || true
    sudo docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' >"$out/containers.txt" 2>&1 || true
  fi
  df -h >"$out/df.txt" 2>&1 || true
  # The model key and the setup token, wherever they landed; the session (account, authenticator) is never copied.
  node -e '
    const fs = require("node:fs"), path = require("node:path"), k = process.env.GRADUATE_OPENROUTER_KEY || "";
    for (const f of fs.readdirSync(process.argv[1])) {
      const p = path.join(process.argv[1], f); let t = fs.readFileSync(p, "utf8");
      if (k) t = t.split(k).join("REDACTED"); t = t.replace(/(token=)[A-Za-z0-9_-]+/g, "$1REDACTED").replace(/sk-or-[A-Za-z0-9-]{20,}/g, "REDACTED");
      fs.writeFileSync(p, t);
    }' "$out"
}

case "${1:-}" in
  prepare) prepare ;;
  install) install_baseline ;;
  upgrade) upgrade ;;
  host-checks) host_checks ;;
  result) result ;;
  logs) logs "${2:?logs <dir>}" ;;
  *) echo "usage: graduate-instance.sh prepare | install | upgrade | host-checks | result | logs <dir>" >&2; exit 2 ;;
esac
