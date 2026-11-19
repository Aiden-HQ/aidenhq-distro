#!/usr/bin/env bash
# The upgrade test (release.yml's test job): every published release older than this one, installed by default, must
# upgrade to it. A release that breaks existing installs (a module they list removed or renamed, a setting or schema the
# new compile refuses) is not cut.
#   bash .github/release/upgrade.sh <new product checkout> <release> <its distro commit> <work dir>
# For each older release tag in this distro checkout (tags are what the updater reads; a release whose run failed has none):
#   1. the instance.yaml that release's own ops/setup.sh writes for a default install from the installer (its heredoc, its
#      modules/marketplace.json bundle and default MODULES, its release: pin), committed in a local instance repo like setup's;
#   2. the pin commit, made as a real update makes it: by the INSTALLED release's own updater (its kernel/src/updates.ts
#      pinText, the function both its updater and its installer-rerun pin step call: one commit moving product: and release:),
#      never by the new kernel's, which migrates what the instance lists (modules renamed or replaced) and so would hide a
#      break a real update meets. The old kernel is that release's kernel sha, read from this checkout's history with the
#      deps its updater needs (yaml) installed; pinText is called as the updater's verify calls it (and resolveRelease,
#      from the old tree, checks the result);
#   3. what the apply of the NEW checkout validates before anything restarts (ops/apply-config-work.sh validate): the staged
#      compile (AIDENHQ_COMPILE_STAGE=1 scripts/compile.mjs) passes and the release resolves (scripts/compiler/release.ts).
# Whatever the new kernel's own pin step (`updates.ts pin`) would add for old installs (its module migration) is not
# credited: only an old updater's pin counts, as it is the one that runs on a real server. An old release's updater
# can't be run as the CLI `pin` (it demands the checkout be the new kernel), so its pinText is called directly.
# Releases from before the one-repo layout (a release file with `marketplace` or `modules`, 2026.11.2 and older: the modules
# came from a separate repo) are skipped: they upgrade once by hand (INSTALL.md). Runs without credentials: every
# repository it reads is public. Old kernels are read from the new checkout's history (the installer's fetch takes main).
# AIDENHQ_UPGRADE_SKIP: release names graduation rejected (graduate.yml), space-separated: no install runs them, so none is
# tested as a starting point.
set -euo pipefail
here=$(cd "$(dirname "$0")/../.." && pwd)
new=$(cd "$1" && pwd) rel=$2 relsha=$3 work=$4
NAME='^[0-9]{4}\.[0-9]{1,2}(\.[0-9]+){0,2}$'
[[ "$rel" =~ $NAME ]] && [[ "$relsha" =~ ^[0-9a-f]{40}$ ]] || { echo "usage: upgrade.sh <product checkout> <release> <distro sha> <work dir>" >&2; exit 2; }
for v in AIDENHQ_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN GIT_CONFIG_COUNT; do
  [ -z "${!v:-}" ] || { echo "refusing: $v is set; the upgrade test runs without credentials" >&2; exit 1; }
done
kernel=$(git -C "$new" rev-parse HEAD)
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
  case " ${AIDENHQ_UPGRADE_SKIP:-} " in *" $R "*) echo "upgrade from $R: skipped (graduation rejected it: no install runs it)"; continue ;; esac
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
    old="$u/product"; mkdir -p "$old"
    if ! { git -C "$new" archive "$RK" kernel scripts | tar -x -C "$old" \
        && for p in scripts kernel; do npm ci --ignore-scripts --no-audit --no-fund --prefix "$old/$p" >/dev/null; done \
        && git -C "$here" show "$relsha:releases/$rel.json" >"$u/new-release.json"; }; then
      echo "::error::upgrade from $R: couldn't set up $R's kernel (${RK:0:12}) in $old"; ok=0
    elif ! out=$(cp "$here/.github/release/pin-as-installed.ts" "$old/kernel/src/pin-as-installed.ts" \
        && cd "$old" && node kernel/src/pin-as-installed.ts "$u/instance/instance.yaml" "$u/new-release.json" "$rel" "$relsha" 2>&1); then
      echo "$out"; echo "::error::upgrade from $R: $R's updater refused to pin $rel"; ok=0
    else
      echo "$out"
      git -C "$u/instance" -c user.name=updater -c user.email=updater@aidenhq.invalid commit -q -am "update: AidenHQ $rel (the updater, from $R)" \
        && git -C "$u/instance" push -q origin HEAD:main && git -C "$u/instance" pull -q --ff-only origin main
      # A pin that left the instance as it was proves nothing.
      if [ "$(sed -n 's/^product: *//p' "$u/instance/instance.yaml")" != "$kernel" ]; then
        echo "::error::upgrade from $R: the pin didn't move product: to $kernel"; ok=0
      elif ! (cd "$new" && AIDENHQ_COMPILE_STAGE=1 node scripts/compile.mjs \
          && { [ ! -f scripts/compiler/release.ts ] || node scripts/compiler/release.ts "$u/instance/instance.yaml"; }); then
        echo "::error::upgrade from $R: the new product's staged compile of the pinned instance failed (above)"; ok=0
      fi
      rm -rf "$new/config.next" "$new/compose.modules.next.yaml"
    fi
  fi
  echo "::endgroup::"
  if [ "$ok" = 1 ]; then echo "upgrade from $R: passed"; tested="$tested $R"; else echo "upgrade from $R: FAILED"; failed="$failed $R"; fi
done
[ -z "$failed" ] || { echo "::error::installs of$failed can't upgrade to $rel: this release isn't cut" >&2; exit 1; }
echo "upgrade: ${tested:- none (no older release since the one-repo layout)}"
