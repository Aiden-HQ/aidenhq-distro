#!/usr/bin/env bash
# The upgrade test (release.yml's test job): the last graduated release (GitHub's latest, non-prerelease one: what installs
# run, as every cut stays a pre-release until it graduates), installed by default, must upgrade to this one. A release that breaks existing installs (a module they list removed or renamed, a setting or schema the
# new compile refuses) is not cut.
#   bash .github/release/upgrade.sh compile <new product checkout> <release> <its distro commit> <work dir>   (steps 1-3)
#   bash .github/release/upgrade.sh review <product clone> <release> <its distro commit> <work dir>           (steps 1, 2, 4)
# compile runs this release's code (its npm ci, compile, release.ts) and never sees a model key. review, the only mode given
# OPENROUTER_API_KEY, runs in its own job on a fresh runner and runs no code of this release: the product repository is
# only read with git (the old setup.sh and the manifests), and only the old release's checkout and this repo's scripts run.
# For that release (its tag is in this distro checkout: tags are what the updater reads):
#   1. the instance.yaml that release's own ops/setup.sh writes for a default install from the installer (its heredoc, its
#      modules/marketplace.json bundle and default MODULES, its release: pin), committed in a local instance repo like setup's;
#   2. the pin commit, made as a real update makes it: by the INSTALLED release's own updater (its kernel/src/updates.ts
#      pinText, the function both its updater and its installer-rerun pin step call: one commit moving product: and release:),
#      never by the new kernel's, which migrates what the instance lists (modules renamed or replaced) and so would hide a
#      break a real update meets. The old kernel is that release's kernel sha, read from this checkout's history with the
#      deps its updater needs (yaml) installed; pinText is called as the updater's verify calls it (and resolveRelease,
#      from the old tree, checks the result);
#   3. what the apply of the NEW checkout validates before anything restarts (ops/apply-config-work.sh validate): the staged
#      compile (AIDENHQ_COMPILE_STAGE=1 scripts/compile.mjs) passes and the release resolves (scripts/compiler/release.ts);
#   4. the review an install runs before it lands the pin (review-as-installed.ts, in the old release's own product checkout
#      at its exact kernel sha, checked clean first; its config compiled for that instance): the pin commit, on release/<name> as the updater's prepare commits it, filed
#      as the kernel.apply that release's kernel files for it and judged by that release's own AI reviewer on the model,
#      the authority diff and the "Release update" line included. Only an approval passes: a rejection, an escalation to the
#      owner's tap or a failed review fails the test, with the reviewers' notes and every authority line they judged.
# Whatever the new kernel's own pin step (`updates.ts pin`) would add for old installs (its module migration) is not
# credited: only an old updater's pin counts, as it is the one that runs on a real server. An old release's updater
# can't be run as the CLI `pin` (it demands the checkout be the new kernel), so its pinText is called directly.
# A last release from before the one-repo layout (a release file with `marketplace` or `modules`, 2026.11.2 and older: the modules
# came from a separate repo) is skipped: it upgrades once by hand (INSTALL.md). Runs without GitHub credentials: every
# repository it reads is public. review needs OPENROUTER_API_KEY (graduation's spend-capped key): the reviewer is never
# skipped. Old kernels are read from the new checkout's history (the installer's fetch takes main).
set -euo pipefail
here=$(cd "$(dirname "$0")/../.." && pwd)
mode=$1 new=$(cd "$2" && pwd) rel=$3 relsha=$4 work=$5
NAME='^[0-9]{4}\.[0-9]{1,2}(\.[0-9]+){0,2}$'
[[ "$mode" =~ ^(compile|review)$ ]] && [[ "$rel" =~ $NAME ]] && [[ "$relsha" =~ ^[0-9a-f]{40}$ ]] || { echo "usage: upgrade.sh compile|review <product checkout> <release> <distro sha> <work dir>" >&2; exit 2; }
for v in AIDENHQ_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN GIT_CONFIG_COUNT; do
  [ -z "${!v:-}" ] || { echo "refusing: $v is set; the upgrade test runs without GitHub credentials" >&2; exit 1; }
done
# The model key: review's alone, and handed to the review command only (never the old release's npm ci or compile).
review_key=${OPENROUTER_API_KEY:-}; unset OPENROUTER_API_KEY
if [ "$mode" = review ]; then
  [ -n "$review_key" ] || { echo "::error::OPENROUTER_API_KEY is not set: the last release's AI reviewer judges the update (GRADUATE_OPENROUTER_KEY)" >&2; exit 1; }
else
  [ -z "$review_key" ] || { echo "refusing: OPENROUTER_API_KEY is set; compile runs this release's code and never gets the model key" >&2; exit 1; }
fi
kernel=$(git -C "$here" show "$relsha:releases/$rel.json" | jq -er .kernel)
git -C "$new" cat-file -e "$kernel^{commit}" || { echo "::error::$new has no commit $kernel ($rel's kernel)"; exit 1; }
if [ "$mode" = compile ]; then
  [ "$(git -C "$new" rev-parse HEAD)" = "$kernel" ] || { echo "::error::$new isn't at $rel's kernel $kernel"; exit 1; }
  for p in scripts kernel; do [ -d "$new/$p/node_modules" ] || npm ci --ignore-scripts --no-audit --no-fund --prefix "$new/$p" >/dev/null; done
fi
mkdir -p "$work"
export AIDENHQ_SOURCES_DIR="$work/sources" AIDENHQ_STATE_DIR="$work/state" AIDENHQ_DATA_DIR="$work/data"

# The baseline: the repository's latest (non-prerelease) release. Read from github.com's releases/latest redirect, not the
# REST API: this job has no token, and the API's unauthenticated limit is shared by every job on a runner's IP (403s).
R=$(curl -fsS -o /dev/null -w '%{redirect_url}' --retry 3 --retry-all-errors "https://github.com/Aiden-HQ/aidenhq-distro/releases/latest") \
  && R=${R##*/tag/} && [[ "$R" =~ $NAME ]] || { echo "::error::couldn't read the latest release"; exit 1; }

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

f=$(git -C "$here" show "$R:releases/$R.json" 2>/dev/null) || { echo "::error::tag $R has no releases/$R.json"; exit 1; }
if jq -e 'has("marketplace") or has("modules")' <<<"$f" >/dev/null; then
  echo "upgrade from $R: skipped (it predates the one-repo layout; such installs upgrade once by hand)"; exit 0
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
  # $R's product checkout as a real update finds it: at its kernel, with this release's kernel on its origin's main (what the
  # updater's landKernel does to a local mirror), its config compiled for the instance its setup wrote.
  old="$u/product"
  if ! { git init -q --bare -b main "$u/product.git" && git -C "$new" push -q "$u/product.git" "$kernel:refs/heads/main" \
      && git clone -q "$u/product.git" "$old" && git -C "$old" checkout -q --detach "$RK" \
      && for p in scripts kernel; do npm ci --ignore-scripts --no-audit --no-fund --prefix "$old/$p" >/dev/null; done \
      && { [ "$mode" = compile ] || (cd "$old" && node scripts/compile.mjs >"$u/compile.log" 2>&1); } \
      && git -C "$here" show "$relsha:releases/$rel.json" >"$u/new-release.json"; }; then
    tail -20 "$u/compile.log" 2>/dev/null || true; echo "::error::upgrade from $R: couldn't set up $R's product (${RK:0:12}) in $old"; ok=0
  elif ! out=$(git -C "$u/instance" checkout -q -b "release/$rel" && cp "$here/.github/release/pin-as-installed.ts" "$old/kernel/src/pin-as-installed.ts" \
      && cd "$old" && node kernel/src/pin-as-installed.ts "$u/instance/instance.yaml" "$u/new-release.json" "$rel" "$relsha" 2>&1); then
    echo "$out"; echo "::error::upgrade from $R: $R's updater refused to pin $rel"; ok=0
  else
    echo "$out"; rm -f "$old/kernel/src/pin-as-installed.ts"
    # The pin commit on release/<name>, as the updater's prepare commits it, then filed as the kernel.apply $R's kernel files
    # and reviewed by $R's own AI reviewer (review-as-installed.ts): a release an install would reject never ships.
    git -C "$u/instance" -c user.name=updater -c user.email=updater@aidenhq.invalid commit -q -am "update: AidenHQ $rel (the updater, from $R)" \
      && git -C "$u/instance" push -q origin "release/$rel"
    # A pin that left the instance as it was proves nothing.
    if [ "$(sed -n 's/^product: *//p' "$u/instance/instance.yaml")" != "$kernel" ]; then
      echo "::error::upgrade from $R: the pin didn't move product: to $kernel"; ok=0
    elif [ "$mode" = compile ]; then
      if ! (cd "$new" && AIDENHQ_COMPILE_STAGE=1 node scripts/compile.mjs \
          && { [ ! -f scripts/compiler/release.ts ] || node scripts/compiler/release.ts "$u/instance/instance.yaml"; }); then
        echo "::error::upgrade from $R: the new product's staged compile of the pinned instance failed (above)"; ok=0
      fi
      rm -rf "$new/config.next" "$new/compose.modules.next.yaml"
    # The old checkout is exactly $R's kernel with no tracked file changed, before its kernel judges the update (its compile
    # adds untracked config, e.g. config/engines.json, which the kernel reads as on a real install).
    elif [ "$(git -C "$old" rev-parse HEAD)" != "$RK" ] || [ -n "$(git -C "$old" status --porcelain --untracked-files=no)" ]; then
      git -C "$old" status --porcelain --untracked-files=no | head -20; echo "::error::upgrade from $R: its checkout isn't clean at ${RK:0:12}"; ok=0
    elif ! { cp "$here/.github/release/review-as-installed.ts" "$old/kernel/src/review-as-installed.ts" \
        && (cd "$old" && mkdir -p "$u/secrets" && AIDENHQ_SECRETS_DIR="$u/secrets" AIDENHQ_PRODUCT_REPO=Aiden-HQ/AidenHQ OPENROUTER_API_KEY="$review_key" node --disable-warning=ExperimentalWarning kernel/src/review-as-installed.ts \
          "$u/instance.git" local/aidenhq-instance "release/$rel" "$(git -C "$u/instance" rev-parse HEAD)" "$R" "$rel" "$relsha" "$u/kernel.db"); }; then
      echo "::error::upgrade from $R: $R's AI reviewer didn't approve the update to $rel (its note and the authority lines above): an install of $R wouldn't auto-update to it"; ok=0
    fi
  fi
fi
echo "::endgroup::"
[ "$ok" = 1 ] || { echo "upgrade from $R: FAILED"; echo "::error::an install of $R can't upgrade to $rel: this release isn't cut" >&2; exit 1; }
echo "upgrade from $R: passed"
