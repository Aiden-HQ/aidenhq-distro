#!/usr/bin/env bash
# The upgrade test (release.yml's test job): every published release older than this one, installed by default, must
# upgrade to it. A release that breaks existing installs (a module they list removed or renamed, a setting or schema the
# new compile refuses) is not cut.
#   bash .github/release/upgrade.sh <new product checkout> <release> <its distro commit> <work dir>
# For each older release tag in this distro checkout (tags are what the updater reads; a release whose run failed has none):
#   1. the instance.yaml that release's own ops/setup.sh writes for a default install from the installer (its heredoc, its
#      modules/marketplace.json bundle and default MODULES, its release: pin), committed in a local instance repo like setup's;
#   2. the new product's pin step, `node kernel/src/updates.ts pin` (the installer run again and the updater move the pin
#      the same way): the one commit that moves product: and release: and migrates what the instance lists;
#   3. what the apply validates before anything restarts: the release resolves (scripts/compiler/release.ts) and the
#      staged compile (AIDENHQ_COMPILE_STAGE=1 scripts/compile.mjs) passes.
# Releases from before the one-repo layout (a release file with `marketplace` or `modules`, 2026.11.2 and older: the modules
# came from a separate repo) are skipped: they upgrade once by hand (INSTALL.md). Runs without credentials: every
# repository it reads is public. Old kernels are read from the new checkout's history (the installer's fetch takes main).
set -euo pipefail
here=$(cd "$(dirname "$0")/../.." && pwd)
new=$(cd "$1" && pwd) rel=$2 relsha=$3 work=$4
NAME='^[0-9]{4}\.[0-9]{1,2}(\.[0-9]+){0,2}$'
[[ "$rel" =~ $NAME ]] && [[ "$relsha" =~ ^[0-9a-f]{40}$ ]] || { echo "usage: upgrade.sh <product checkout> <release> <distro sha> <work dir>" >&2; exit 2; }
for v in AIDENHQ_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN GIT_CONFIG_COUNT; do
  [ -z "${!v:-}" ] || { echo "refusing: $v is set; the upgrade test runs without credentials" >&2; exit 1; }
done
kernel=$(git -C "$new" rev-parse HEAD)
if ! command grep -qs 'cmd === "pin"' "$new/kernel/src/updates.ts"; then
  echo "::error::$rel's kernel has no pin step (kernel/src/updates.ts pin): an install can't upgrade to it"; exit 1
fi
for p in scripts kernel; do [ -d "$new/$p/node_modules" ] || npm ci --ignore-scripts --no-audit --no-fund --prefix "$new/$p" >/dev/null; done
mkdir -p "$work"
export AIDENHQ_SOURCES_DIR="$work/sources" AIDENHQ_STATE_DIR="$work/state" AIDENHQ_DATA_DIR="$work/data"

# The older releases, newest first: release tags this checkout has, sorted as the publish job sorts names.
older=$(git -C "$here" tag -l | command grep -E "$NAME" | { cat; echo "$rel"; } | sort -u -t. -k1,1n -k2,2n -k3,3n -k4,4n \
  | sed -n "/^$(printf '%s' "$rel" | sed 's/\./\\./g')\$/q;p" | awk '{l[NR]=$0} END {for (i = NR; i > 0; i--) print l[i]}')

json() { local s="${1//\\/\\\\}"; printf '"%s"' "${s//\"/\\\"}"; }   # ops/setup.sh's own
# The instance.yaml release $1 (distro commit $2, kernel $3) writes on a default install, from its own ops/setup.sh.
old_instance() {
  local R=$1 RSHA=$2 RK=$3 setup tmpl bundle def mods
  setup=$(git -C "$new" show "$RK:ops/setup.sh")
  # shellcheck disable=SC2016  # literal $ in the patterns
  tmpl=$(printf '%s\n' "$setup" | sed -n '/write_user_file "\$INST\/instance.yaml" 644 <<EOF$/,/^EOF$/p' | sed '1d;$d')
  [ -n "$tmpl" ] || { echo "::error::$R's ops/setup.sh has no instance.yaml heredoc (write_user_file \"\$INST/instance.yaml\" 644 <<EOF): update upgrade.sh"; return 1; }
  bundle=$(git -C "$new" show "$RK:modules/marketplace.json" | jq -er '.bundle | map("\"\(.)\"") | join(",")')
  # shellcheck disable=SC2016
  def=$(printf '%s\n' "$setup" | sed -n 's/.*MODULES="$(cfg MODULES \([A-Za-z0-9,_-]*\))".*/\1/p' | head -1)
  mods=$bundle
  for m in ${def//,/ }; do case ",$mods," in *",\"$m\","*) ;; *) mods="$mods,\"$m\"" ;; esac; done
  # The installer's environment for setup, and setup's own values for a default unattended install.
  # shellcheck disable=SC2034  # read by the heredoc
  local OWNER_NAME=owner OWNER_EMAIL=owner@example.com TIMEZONE=UTC COMPANY=work EXPOSURE=tailscale AGENTS_ORG='' \
    PRODUCT=$RK ENVF="$work/env" AUTO_UPDATE='  auto_update: "on"' \
    RELEASE_LINE="release: { name: \"$R\", source: { source: github, repo: Aiden-HQ/aidenhq-distro }, sha: $RSHA }"
  printf 'AIDENHQ_PRODUCT_REPO=Aiden-HQ/AidenHQ\n' >"$work/env"
  eval "cat <<EOF
$tmpl
EOF"
}

failed='' tested=''
for R in $older; do
  f=$(git -C "$here" show "$R:releases/$R.json" 2>/dev/null) || { echo "::warning::tag $R has no releases/$R.json: skipped"; continue; }
  if jq -e 'has("marketplace") or has("modules")' <<<"$f" >/dev/null; then
    echo "upgrade from $R: skipped (it predates the one-repo layout; such installs upgrade once by hand)"; continue
  fi
  RK=$(jq -er .kernel <<<"$f") RSHA=$(git -C "$here" rev-list -n1 "$R")
  echo "::group::upgrade from $R (kernel ${RK:0:12}) to $rel (kernel ${kernel:0:12})"
  u="$work/$R"; rm -rf "$u"; mkdir -p "$u"
  ok=1
  {
    git init -q --bare -b main "$u/instance.git" && git clone -q "$u/instance.git" "$u/instance" 2>/dev/null \
      && old_instance "$R" "$RSHA" "$RK" >"$u/instance/instance.yaml" \
      && echo "apps: []" >"$u/instance/apps.yaml" && mkdir -p "$u/instance/agents" \
      && git -C "$u/instance" add -A && git -C "$u/instance" -c user.name=setup -c user.email=setup@aidenhq.invalid commit -q -m "instance (as $R's setup writes it)" \
      && git -C "$u/instance" push -q origin HEAD:main
  } || { echo "::error::upgrade from $R: couldn't make its default instance"; ok=0; }
  if [ "$ok" = 1 ]; then
    echo "$R's default instance.yaml:"; sed 's/^/  /' "$u/instance/instance.yaml"
    export AIDENHQ_INSTANCE_DIR="$u/instance"
    if ! out=$(cd "$new" && node kernel/src/updates.ts pin "$rel" "$relsha" 2>&1); then
      echo "$out"; echo "::error::upgrade from $R: the pin step failed"; ok=0
    else
      echo "$out"
      git -C "$u/instance" pull -q --ff-only origin main
      # A pin step that left the instance as it was proves nothing: it must now run this release's kernel.
      if [ "$(sed -n 's/^product: *//p' "$u/instance/instance.yaml")" != "$kernel" ]; then
        echo "::error::upgrade from $R: the pin step didn't move product: to $kernel"; ok=0
      elif ! (cd "$new" && { [ ! -f scripts/compiler/release.ts ] || node scripts/compiler/release.ts "$u/instance/instance.yaml"; } \
          && AIDENHQ_COMPILE_STAGE=1 node scripts/compile.mjs); then
        echo "::error::upgrade from $R: the staged compile of the upgraded instance failed (above)"; ok=0
      fi
      rm -rf "$new/config.next" "$new/compose.modules.next.yaml"
    fi
  fi
  echo "::endgroup::"
  if [ "$ok" = 1 ]; then echo "upgrade from $R: passed"; tested="$tested $R"; else echo "upgrade from $R: FAILED"; failed="$failed $R"; fi
done
[ -z "$failed" ] || { echo "::error::installs of$failed can't upgrade to $rel: this release isn't cut" >&2; exit 1; }
echo "upgrade: ${tested:- none (no older release since the one-repo layout)}"
