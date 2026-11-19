#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2024  # single-quoted programs run in another shell; redirects write the runner's own files
# The host's side of graduation's test instance (.github/workflows/graduate.yml, test job), on a fresh GitHub-hosted runner
# with no token, or on a fresh Ubuntu VM given the same env (README "Release graduation", `run`): the service user, the disk,
# the baseline install with its own published installer, the fixture app, the upgrade by the installed updater, and the host
# checks after it. The owner's side (first run, a chat, the checks after the upgrade) is graduate-scenario.mjs.
#   bash graduate-instance.sh prepare                 service user (uid 1000, as Paperclip's image wants) and disk
#   bash graduate-instance.sh prepull-start           in the background: the candidate's images the baseline runs (prepull)
#   bash graduate-instance.sh install                 BASELINE's install.sh (checked against BASELINE_INSTALL_DIGEST)
#   bash graduate-instance.sh fixture                 the hello app: the baseline's app starter, registered and deployed
#                                                     through the apps platform's host path (no model)
#   bash graduate-instance.sh upgrade                 TAG through the instance's own updater (AIDENHQ_UPDATE_CANDIDATE)
#   bash graduate-instance.sh release-check           running release, kernel and images; generation
#   bash graduate-instance.sh verify-security         scripts/verify-security.sh
#   bash graduate-instance.sh result                  result.json, its verdict and the timings (graduate-checks.mjs)
#   bash graduate-instance.sh logs <dir>              what a failure needs, secrets redacted
#   bash graduate-instance.sh run                     every phase in order, then result (a manual VM run)
# Each check's outcome goes to $GRAD_DIR/checks/<name>.json and each phase's seconds to $GRAD_DIR/timings/<phase>.json
# (graduate-checks.mjs reads them). Every wait is bounded.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${GRAD_DIR:=$HOME/graduate-run}" "${GITHUB_REPOSITORY:=Aiden-HQ/aidenhq-distro}"
export GRAD_DIR GITHUB_REPOSITORY
[ -d "$GRAD_DIR" ] || mkdir -m 0700 "$GRAD_DIR"
TMPD=${RUNNER_TEMP:-/tmp}
SVC=aidenhq SVC_HOME=/home/aidenhq
CO=$SVC_HOME/aidenhq INST=$SVC_HOME/aidenhq-instance STATE=$SVC_HOME/.local/state/aidenhq   # ops/setup.sh's AIDENHQ_STATE_DIR
NEED_GB=70   # the installer refuses below 60 GB free; the upgrade's images need room on top
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { echo "::error::$*"; exit 1; }
rec() { # name true|false [note]: its own file, as graduate-checks.mjs writeCheck
  mkdir -p "$GRAD_DIR/checks"
  jq -nc --argjson ok "$([ "$2" = true ] && echo true || echo false)" --arg note "${3:-}" '{ok: $ok, note: ($note | gsub("[\r\n]+"; " ") | .[0:280])}' >"$GRAD_DIR/checks/$1.json"
  log "$([ "$2" = true ] && echo 'ok  ' || echo FAIL) $1${3:+: $3}"
}
# What this test can't do (e.g. an owner's tap): a note only, never a decided check, and the `harness` mark, so the verdict
# is "harness" and the candidate stays pending without counting toward its rejection (graduate.mjs onFailure); exits.
harness() { # name note
  mkdir -p "$GRAD_DIR/checks"
  jq -nc --arg note "harness: $2" '{ok: null, note: ($note | gsub("[\r\n]+"; " ") | .[0:280])}' >"$GRAD_DIR/checks/$1.json"
  touch "$GRAD_DIR/harness"
  die "the test can't judge $TAG: $2"
}
timing() { # phase seconds
  mkdir -p "$GRAD_DIR/timings"; echo "$2" >"$GRAD_DIR/timings/$1.json"; echo "timing: $1 $2s"
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
# Where the kernel keeps its state: its checkout's .env over the defaults, as the kernel reads it (kernel/src/env.ts).
data_dir() { in_co 'node -e "console.log(require(\"node:path\").resolve(process.env.AIDENHQ_DATA_DIR || \"data\"))"'; }
# The candidate's release file, checked against the digest select read; its path.
candidate_file() {
  : "${TAG:?}" "${CANDIDATE_FILE_DIGEST:?}"
  local f="$TMPD/candidate-$TAG.json"
  [ -s "$f" ] || curl -fsSL --retry 3 -o "$f" "https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/$TAG.json"
  [ "sha256:$(sha256sum "$f" | cut -d' ' -f1)" = "$CANDIDATE_FILE_DIGEST" ] || { rm -f "$f"; die "$TAG.json isn't the asset select read"; }
  echo "$f"
}

prepare() {
  # The baseline's installer and host setup may predate the retry setting: a mirror's transient error (a 503) retries
  # instead of failing the install. The same file the product's host setup writes.
  echo 'Acquire::Retries "5";' | sudo tee /etc/apt/apt.conf.d/80-aidenhq-retries >/dev/null
  # The service user as the installer makes it (ensure_user), made first so its uid is 1000: the stack runs as it (PUID) and
  # the pinned Paperclip image writes its own files as 1000 when it starts (distro #49). The installer finds it and keeps it.
  if ! id "$SVC" >/dev/null 2>&1; then
    # GitHub's ubuntu-24.04 image keeps its build user (packer) at uid and gid 1000: on a hosted runner only, move it aside
    # (it runs nothing) so the service user gets 1000, as on a fresh server.
    local other
    other=$(getent passwd 1000 | cut -d: -f1 || true)
    if [ -n "$other" ] && [ "${GITHUB_ACTIONS:-}" = true ] && ! pgrep -u 1000 >/dev/null; then
      sudo usermod -u 1990 "$other"
      ! getent group 1000 >/dev/null || sudo groupmod -g 1990 "$(getent group 1000 | cut -d: -f1)"
      log "moved $other off uid 1000 (to 1990)"
    fi
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
  # Only on a GitHub-hosted runner: a VM's own files and images are never touched.
  if [ "${GITHUB_ACTIONS:-}" = true ] && [ "$(gb /)" -lt "$NEED_GB" ]; then
    # Preinstalled toolchains nothing here uses.
    sudo rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache/CodeQL /usr/share/swift \
      /usr/local/share/powershell /usr/local/share/chromium /opt/microsoft /opt/google /usr/local/julia* || true
    sudo docker image prune -af >/dev/null 2>&1 || true
    log "free after removing preinstalled toolchains: / $(gb /) GB"
  fi
  local moved=no
  if [ "${GITHUB_ACTIONS:-}" = true ] && [ "$(gb /)" -lt "$NEED_GB" ] && [ "$mnt" != none ] && [ "$(gb /mnt)" -ge "$NEED_GB" ]; then
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
  [ -d "$dock" ] || dock=/var/lib
  [ "$(gb "$dock")" -ge 60 ] && [ "$(gb "$SVC_HOME")" -ge 60 ] \
    || die "this runner has $(gb "$dock") GB free for Docker and $(gb "$SVC_HOME") GB for the checkout; the installer needs 60 GB (measured: / ${before} GB, /mnt ${mnt} GB at start)"
  local line
  line="Runner disk: / ${before} GB free at start, $(gb /) GB after cleanup; /mnt ${mnt} GB; data moved to /mnt: ${moved}."
  log "$line"; [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "$line" >>"$GITHUB_STEP_SUMMARY"
}


# The candidate's images that the baseline runs, pulled by digest while the baseline installs and its scenario runs, so the
# upgrade's apply mostly restarts (its own `compose pull --policy missing` fetches whatever isn't here yet). Only images of a
# repository the baseline itself pulled: nearly every image changes with each cut, and the release file also lists images
# this install never runs. Started after prepare (Docker's data is where it stays) and only pulls a repository the
# installer has already pulled, so it never takes disk before the installer's own disk check. It never records a check or
# fails the run: anything it misses, the apply pulls.
prepull_start() {
  ( candidate_file >/dev/null ) || { log "no pre-pull: the candidate's release file didn't load (the apply pulls everything)"; return 0; }
  setsid nohup bash "$here/graduate-instance.sh" prepull >"$GRAD_DIR/prepull.log" 2>&1 </dev/null &
  log "pre-pulling $TAG's images in the background (prepull.log)"
}
prepull() {
  local f t0=$SECONDS end=$((SECONDS + 120 * 60)) last=0 pulled=0 ref repo present todo
  declare -A tries=()
  f=$(candidate_file)
  # Until the install has ended and a pass after it found nothing left to pull (2 hours at most).
  while [ "$SECONDS" -lt "$end" ]; do
    [ -f "$GRAD_DIR/install.done" ] && last=$((last + 1))
    todo=()
    if present=$(sudo docker images --format '{{.Repository}}' 2>/dev/null | sort -u) && [ -n "$present" ]; then
      while IFS= read -r ref; do
        repo=${ref%@*}
        grep -qxF "$repo" <<<"$present" || continue
        sudo docker image inspect "$ref" >/dev/null 2>&1 && continue
        [ "${tries[$ref]:-0}" -lt 3 ] || continue
        tries[$ref]=$((${tries[$ref]:-0} + 1)); todo+=("$ref")
      done < <(jq -r '.images // {} | .[]' "$f" | sort -u)
    fi
    if [ "${#todo[@]}" -gt 0 ]; then
      log "pulling ${#todo[@]}: ${todo[*]##*/}"
      printf '%s\n' "${todo[@]}" | xargs -P 6 -I{} sh -c 'sudo docker pull -q "$1" >/dev/null 2>&1 || echo "pull failed (retried next pass): $1"' _ {}
      pulled=$((pulled + ${#todo[@]}))
    elif [ "$last" -ge 2 ]; then break
    else sleep 10; fi
  done
  log "done: $pulled pulls in $((SECONDS - t0))s"
  timing prepull $((SECONDS - t0))
  touch "$GRAD_DIR/prepull.done"
}

install_baseline() {
  : "${BASELINE:?}" "${BASELINE_INSTALL_DIGEST:?}"
  local d="$TMPD/baseline-installer"
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
  touch "$GRAD_DIR/install.done"
  # The log without the one-time setup token.
  sed -E 's/(token=)[A-Za-z0-9_-]+/\1REDACTED/g' "$GRAD_DIR/install.log" | grep -E '^(==>|    |AIDENHQ_PROGRESS|error|Install stopped)' | tail -150 || true
  [ "$rc" = 0 ] || { rec baseline_installed false "the installer exited $rc"; exit 1; }
  sed -n 's/^AIDENHQ_SETUP_URL=//p' "$GRAD_DIR/install.log" | tail -1 >"$GRAD_DIR/setup-url"
  [ -s "$GRAD_DIR/setup-url" ] || { rec baseline_installed false "no AIDENHQ_SETUP_URL line"; exit 1; }
  # The installer recreates Paperclip and the board just before it prints the link, and returns without waiting for them
  # (setup.sh up to at least 2026.11.19.9). An owner opens the link minutes later, this test within a second: in runs
  # 44622279180 and 44624263587 the board's first call met a Paperclip 3 seconds old ("fetch failed"). Both healthy first.
  local st='' hend=$((SECONDS + 5 * 60))
  until [ "$st" = healthy ]; do
    st=$(in_co 'docker compose ps -q paperclip board | xargs -r docker inspect -f "{{.State.Health.Status}}"' 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')
    [ "$st" = healthy ] && break
    [ "$SECONDS" -lt "$hend" ] || { rec baseline_installed false "Paperclip and the board weren't healthy 5 minutes after the install (${st:-no containers})"; exit 1; }
    sleep 2
  done
  if sudo grep -Eq "^release: \{ *name: \"?${BASELINE//./\\.}\"?" "$INST/instance.yaml"; then rec baseline_installed true "$BASELINE"
  else rec baseline_installed false "instance.yaml doesn't pin $BASELINE"; exit 1; fi
}

# The hello app without a model: the baseline's own app starter (what an Engineer starts every app from), in a repository on
# this server (codehost-local's org `local`, a bare repo under the data dir) and registered in the instance's apps.yaml as
# app_create does (committed and pushed to the instance's main), then deployed through the apps platform's host path
# (ops/app-deploy.sh: apps-mcp's /internal/deploy, its per-app lock, build, health and the post-deploy checks). Its outcome
# goes to fixture.json; graduate-scenario.mjs judges it with the same probe the smoke check uses after the upgrade.
FIXTURE=grad-hello FIXTURE_PORT=18731
fixture() {
  local data bare out status
  data=$(data_dir); bare="$data/codehost/local/$FIXTURE.git"
  as_svc bash -c '
    set -euo pipefail
    co=$1 bare=$2 inst=$3 name=$4 port=$5
    id=(-c user.name="AidenHQ graduation" -c user.email=graduation@aidenhq.invalid)
    [ -d "$co/modules/apps-platform/starter" ] || { echo "the checkout has no app starter"; exit 1; }
    if [ ! -d "$bare" ]; then
      w=$(mktemp -d)
      tar -C "$co/modules/apps-platform/starter" --exclude=./node_modules --exclude=./dist -cf - . | tar -C "$w" -xf -
      git -C "$w" init -q -b main && git -C "$w" add -A && git -C "$w" "${id[@]}" commit -q -m "hello: the app starter"
      mkdir -p "$(dirname "$bare")" && git init -q --bare -b main "$bare" && git -C "$w" push -q "$bare" main
      rm -rf "$w"
    fi
    cd "$inst"
    git pull -q --ff-only origin main
    if ! grep -q "name: $name[ ,]" apps.yaml; then
      entry="{ name: $name, repo: local/$name, owner: graduation, description: \"The graduation test hello app\", port: $port, health: { url: \"http://app:8080/api/health\" } }"
      if grep -qx "apps: \[\]" apps.yaml; then printf "apps:\n  - %s\n" "$entry" >apps.yaml
      else
        ind=$(grep -m1 -E "^ *- " apps.yaml | sed -E "s/-.*//")
        grep -qx "apps:" apps.yaml && [ -n "$(grep -m1 -E "^ *- " apps.yaml)" ] || { echo "apps.yaml has a layout this test does not edit"; exit 1; }
        [ -z "$(tail -c1 apps.yaml)" ] || echo >>apps.yaml
        printf "%s- %s\n" "$ind" "$entry" >>apps.yaml
      fi
      git add apps.yaml && git "${id[@]}" commit -q -m "apps: add $name (graduation fixture)" && git push -q origin HEAD:main
    fi' _ "$CO" "$bare" "$INST" "$FIXTURE" "$FIXTURE_PORT" || { jq -n --arg n "registering it failed" '{ok: false, note: $n}' >"$GRAD_DIR/fixture.json"; exit 1; }
  # apps-mcp reads apps.yaml from its own clone of the instance (/data/registry), synced at start, inside its own registry
  # edits (app_create) and before each reconcile tick (every 2 minutes): an entry pushed here reaches it at its next tick.
  # Until its own listing has the app, a deploy says "unknown app".
  local listed='' lend=$((SECONDS + 6 * 60))
  until [ "$SECONDS" -ge "$lend" ]; do
    listed=$(in_co 'docker compose exec -T apps-mcp node -e "fetch(\"http://127.0.0.1:8090/internal/status\").then((r) => r.json()).then((a) => console.log(a.map((x) => x.name).join(\" \")))"' 2>/dev/null || true)
    grep -qw -- "$FIXTURE" <<<"$listed" && break
    sleep 10
  done
  if ! grep -qw -- "$FIXTURE" <<<"$listed"; then
    jq -n --arg app "$FIXTURE" '{ok: false, app: $app, note: "harness: apps-mcp did not list it within 6 minutes of its registration"}' >"$GRAD_DIR/fixture.json"; exit 1
  fi
  log "$FIXTURE registered and listed by apps-mcp; deploying"
  # The platform's reconcile pass may have started its first deploy already ("deploy in progress"): wait it out, then deploy
  # (the build is cached by then).
  local end=$((SECONDS + 15 * 60))
  while :; do
    out=$(in_co 'bash ops/app-deploy.sh deploy "$1"' "$FIXTURE" 2>"$GRAD_DIR/fixture-deploy.err") || true
    [ ! -s "$GRAD_DIR/fixture-deploy.err" ] || log "deploy stderr: $(tail -c 400 "$GRAD_DIR/fixture-deploy.err")"
    grep -q "deploy in progress" <<<"$out" && [ "$SECONDS" -lt "$end" ] || break
    sleep 5
  done
  status=$(jq -r '.status // empty' <<<"$out" 2>/dev/null || true)
  log "deploy: $(head -c 600 <<<"$out")"
  jq -n --arg app "$FIXTURE" --arg s "${status:-none}" --arg out "$(head -c 200 <<<"$out")" \
    '{ok: ($s == "healthy"), app: $app, note: "deploy \($s)\(if $s == "healthy" then "" else ": \($out)" end)"}' >"$GRAD_DIR/fixture.json"
  [ "$status" = healthy ]
}

upgrade() {
  : "${TAG:?}" "${KERNEL:?}"
  # The bootstrap: a baseline whose updater can't prepare a named pre-release can't be upgraded this way (select checks it too).
  sudo grep -q AIDENHQ_UPDATE_CANDIDATE "$CO/kernel/src/updates.ts" \
    || { rec upgraded false "baseline predates graduation; graduate one release by hand"; die "baseline predates graduation; graduate one release by hand (README \"Release graduation\")"; }
  local data t=$SECONDS
  data=$(data_dir)
  log "pre-pull: $([ -f "$GRAD_DIR/prepull.done" ] && echo 'done' || echo "still running (the apply pulls the rest)"): $(tail -1 "$GRAD_DIR/prepull.log" 2>/dev/null || echo 'no log')"
  # The instance's own updater, asked for exactly this pre-release: verified and prepared as any release, then filed by the
  # kernel as a kernel.apply that the AI reviewer decides (auto-updates are on for a new install). GitHub's API,
  # unauthenticated from a shared runner address, may be rate-limited (403/429) until its hourly reset: retried for 25
  # minutes. A check still rate-limited at the end is the infrastructure's failure, never the candidate's: no check is
  # recorded, so the result is incomplete and the candidate stays pending (graduate.mjs onFailure). Any other answer is
  # asked again every 30 seconds within the same 25 minutes (a GitHub hiccup).
  local out='' end1=$((SECONDS + 25 * 60))
  while :; do
    out=$(in_co 'AIDENHQ_UPDATE_CANDIDATE="$1" node --disable-warning=ExperimentalWarning kernel/src/updates.ts check "$1" graduate' "$TAG" 2>&1) || true
    log "check: $out"
    grep -q "^release $TAG prepared" <<<"$out" && { touch "$GRAD_DIR/reached-candidate"; break; }
    if [ "$SECONDS" -ge "$end1" ]; then
      grep -qE 'answered (403|429)' <<<"$out" && die "GitHub's API rate-limited the instance's updater for 25 minutes (infrastructure, not $TAG): $out"
      rec upgraded false "the updater didn't prepare $TAG: $out"; exit 1
    fi
    if grep -qE 'answered (403|429)' <<<"$out"; then sleep 120; else sleep 30; fi
  done
  timing upgrade_prepare $((SECONDS - t)); t=$SECONDS
  # The kernel files it at its next updates pass (every 5 minutes) and follows its record to the end: installed, or failed
  # with why (75 minutes), through the AI reviewer or panel ("review"). A record that ends up waiting on the owner (Tier 2 on
  # its merits, e.g. new module authority under a baseline that keeps it the owner's) needs a tap this test doesn't make:
  # the run stops there as the harness's limit, never the candidate's failure.
  local st='{}' rec_state='' shown=0 end=$((SECONDS + 75 * 60)) filed=''
  while [ "$SECONDS" -lt "$end" ]; do
    st=$(sudo cat "$data/updates/state.json" 2>/dev/null || echo '{}')
    [ "$(jq -r '.last.release // ""' <<<"$st")" = "$TAG" ] && break
    if [ -z "$filed" ] && [ -n "$(jq -r '.flight.record // ""' <<<"$st")" ]; then
      filed=1; timing upgrade_filed $((SECONDS - t)); t=$SECONDS
    fi
    rec_state=$(record_state "$data" "$(jq -r '.flight.record // ""' <<<"$st")")
    [ "${rec_state%% *}" != owner ] || harness upgraded "the update's record $(jq -r '.flight.record' <<<"$st") waits on the owner's approval (rule ${rec_state#* }) after the AI review; the baseline $BASELINE makes this move the owner's"
    if [ $((SECONDS - shown)) -ge 120 ]; then log "waiting: $(jq -c '{ready: (.ready.release // null), flight: (.flight | if . then {release, record} else null end), error}' <<<"$st") record: ${rec_state:-none}"; shown=$SECONDS; fi
    sleep 5
  done
  if [ "$(jq -r '.last.release // ""' <<<"$st")" != "$TAG" ]; then rec upgraded false "the update record didn't end within 75 minutes (record: ${rec_state:-none}): $(jq -c '{flight, error}' <<<"$st")"; exit 1; fi
  [ "$(jq -r .last.outcome <<<"$st")" = installed ] || { rec upgraded false "$TAG didn't install: $(jq -r '.last.why // "?"' <<<"$st")"; exit 1; }
  timing upgrade_install $((SECONDS - t)); t=$SECONDS
  # Its apply generation settled good on the candidate's kernel (20 minutes).
  local end2=$((SECONDS + 20 * 60))
  until good_on "$KERNEL" || [ "$SECONDS" -ge "$end2" ]; do sleep 5; done
  timing upgrade_generation $((SECONDS - t))
  if good_on "$KERNEL"; then rec upgraded true "$TAG installed by the updater; generation $(last_gen | jq -r .n) good"
  else rec upgraded false "the apply generation isn't good on ${KERNEL:0:12}: $(last_gen)"; exit 1; fi
}

# After the upgrade (graduate-scenario.mjs smoke runs these beside its own checks, each within its bound).
release_check() {
  : "${TAG:?}" "${TAG_SHA:?}" "${KERNEL:?}"
  # What runs: the instance's main pins the candidate, the checkout is its kernel, every AidenHQ image running is one the
  # candidate's release file names by digest.
  local inst head why='' f
  inst=$(as_svc bash -c 'cd ~/aidenhq-instance && git fetch -q origin main && git show origin/main:instance.yaml')
  head=$(as_svc git -C "$CO" rev-parse HEAD)
  grep -qx "product: $KERNEL" <<<"$inst" || why+="instance.yaml's product isn't ${KERNEL:0:12}; "
  grep -Eq "^release: \{ *name: \"?${TAG//./\\.}\"?,.* sha: $TAG_SHA *\}" <<<"$inst" || why+="instance.yaml's release isn't $TAG at ${TAG_SHA:0:12}; "
  [ "$head" = "$KERNEL" ] || why+="the checkout is at ${head:0:12}; "
  as_svc systemctl --user is-active --quiet aidenhq-kernel || why+="the kernel unit isn't active; "
  f=$(candidate_file)
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
}
verify_security() {
  local out rc=0
  out=$(as_svc bash -c 'cd ~/aidenhq && bash scripts/verify-security.sh' 2>&1) || rc=$?
  printf '%s\n' "$out" | tail -60
  if [ "$rc" = 0 ]; then rec verify_security true; else rec verify_security false "$(grep -m3 FAIL <<<"$out" | tr '\n' ' ')"; fi
}

result() {
  : "${IDENTITY:?}" "${BASELINE:?}"
  node "$here/graduate-checks.mjs" result
}

logs() {
  local out=$1; mkdir -p "$out"
  cp "$GRAD_DIR"/{install.log,baseline.json,fixture.json,prepull.log} "$out/" 2>/dev/null || true
  for d in checks timings; do [ ! -d "$GRAD_DIR/$d" ] || for f in "$GRAD_DIR/$d"/*.json; do cp "$f" "$out/$d-$(basename "$f")" || true; done; done
  cp "$GRAD_DIR/fixture-deploy.err" "$out/" 2>/dev/null || true
  if id "$SVC" >/dev/null 2>&1; then
    for u in aidenhq-kernel aidenhq-runner aidenhq-computers; do as_svc journalctl --user -u "$u" --no-pager -n 3000 >"$out/$u.log" 2>&1 || true; done
    sudo cat "$CO/data/updates/state.json" >"$out/updates-state.json" 2>/dev/null || true
    sudo sh -c "cat '$STATE/generations.jsonl'; ls -t '$STATE'/apply-*.log 2>/dev/null | head -3 | xargs -r tail -n 400" >"$out/generations.log" 2>&1 || true
    sudo docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' >"$out/containers.txt" 2>&1 || true
    for s in paperclip board apps-mcp; do
      sudo docker logs --tail 300 "$(sudo docker ps -aq --filter "label=com.docker.compose.service=$s" | head -1)" >"$out/$s.log" 2>&1 || true
    done
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

# Every phase as the workflow's test job runs them, then the result; exits 0 only when it passed. A fresh VM, once.
run() {
  local v rc=0 me="$here/graduate-instance.sh"
  for v in TAG TAG_SHA KERNEL BASELINE BASELINE_INSTALL_DIGEST CANDIDATE_FILE_DIGEST IDENTITY OPENROUTER_KEY; do
    [ -n "${!v:-}" ] || die "$v is not set (README \"Release graduation\", manual runs)"
  done
  export TAG TAG_SHA KERNEL BASELINE BASELINE_INSTALL_DIGEST CANDIDATE_FILE_DIGEST IDENTITY OPENROUTER_KEY
  export GRADUATE_OPENROUTER_KEY="${GRADUATE_OPENROUTER_KEY:-$OPENROUTER_KEY}"
  { bash "$me" prepare && bash "$me" prepull-start && bash "$me" install && node "$here/graduate-scenario.mjs" baseline \
    && bash "$me" upgrade && node "$here/graduate-scenario.mjs" smoke; } || rc=$?
  bash "$me" result
  [ "$rc" = 0 ] && jq -e .passed "$GRAD_DIR/result.json" >/dev/null
}

cmd=${1:-}
t0=$SECONDS
case "$cmd" in
  prepare|install|fixture|upgrade|release-check|verify-security) trap 'timing "${cmd//-/_}" $((SECONDS - t0))' EXIT ;;
esac
case "$cmd" in
  prepare) prepare ;;
  prepull-start) prepull_start ;;
  prepull) prepull ;;
  install) install_baseline ;;
  fixture) fixture ;;
  upgrade) upgrade ;;
  release-check) release_check ;;
  verify-security) verify_security ;;
  result) result ;;
  logs) logs "${2:?logs <dir>}" ;;
  run) run ;;
  *) echo "usage: graduate-instance.sh prepare | prepull-start | install | fixture | upgrade | release-check | verify-security | result | logs <dir> | run" >&2; exit 2 ;;
esac
