# AidenHQ

**Cut the noise. Focus on what matters.**

AidenHQ is an open-source AI chief of staff and agent team that runs on your own server. Website:
**[aidenhq.ai](https://aidenhq.ai)**.

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

One line on a fresh Ubuntu or Debian server, or a Mac; it installs Docker and Node itself. Using Claude Code, Codex or
another coding agent? Paste: `Set up AidenHQ on my server by following https://aidenhq.ai/prompt.md`.

## What it does for you

- **Your work life, on autopilot.** Aiden reads your Slack, the email you hand it and your meeting notes, turns what
  needs you into one action item each, follows up with people until it's done, and sends you a morning brief.
- **An agent for anything else.** Describe it in a sentence ("chase anyone who hasn't answered me in two days") and
  Aiden designs the agent, gives it tools, tries it on real work and adds it to your team.
- **Apps that keep themselves running.** Ask for a tracker or a dashboard; agents build it, watch it and fix it when it
  breaks.
- **Autonomous, and still yours.** A second AI reviews every message, merge and deploy, and anything that matters waits
  for one tap from your phone. Your server, any model, spend capped per agent, task and day.

More on [aidenhq.ai](https://aidenhq.ai): [agents](https://aidenhq.ai/agents/), [apps](https://aidenhq.ai/apps/),
[approvals and safety](https://aidenhq.ai/safety/), [integrations](https://aidenhq.ai/integrations/) and the
[install guide](https://aidenhq.ai/install/). The product itself lives in
[Aiden-HQ/AidenHQ](https://github.com/Aiden-HQ/AidenHQ); this repo is how it reaches a server: the installer, the
website (source in [`site/`](site/)) and the release manifests.

## One line to install

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

The installer checks your server, fetches a tested release of AidenHQ (the kernel and its official modules) pinned by
one commit, verifies it, and hands you to setup. Aiden says hello on your board when it's ready.

## About this repo

This repo is the distribution of AidenHQ: how you get a tested set of the kernel and modules onto a server.

| Repo | What it holds |
|---|---|
| [AidenHQ](https://github.com/Aiden-HQ/AidenHQ) | The kernel, runner, board, setup scripts and, in `modules/`, the official modules. |
| aidenhq-distro (this repo) | The installer, the website and the release manifests. |

| Path | What it is |
|---|---|
| `install.sh` | The installer `curl -fsSL https://get.aidenhq.ai \| sh` runs. See [INSTALL.md](INSTALL.md). |
| `installer/` | `test.sh`, an offline test of the installer's release checks (`sh installer/test.sh`, needs only POSIX sh and git). `RESEARCH.md` has the design notes. |
| `releases/` | One manifest per release, for example `releases/2026.11.json`. |
| `site/` | The aidenhq.ai website (static files, `llms.txt`, `prompt.md`). |
| `web/`, `wrangler.jsonc` | The Cloudflare Worker that serves `install.sh` at get.aidenhq.ai and the site. |

### Releases

A release manifest pins one product commit, `kernel`: a commit of AidenHQ on its `main`, holding the kernel and the
official modules (`modules/`). Beside it are the prebuilt `images` by digest, the `notes` and, once published, the
`tested` stamp. There is no `marketplace` or `modules` entry: third-party modules stay the instance's own marketplaces in
`instance.yaml`. The installer fetches that exact commit, verifies it, and refuses a manifest whose sha256 does not
match the one baked into the tagged `install.sh`. A manifest without a real sha is not cut yet and the installer refuses
it. The 2026.11 to 2026.11.2 manifests are the older two-repo shape and stay as they were cut.

After install, an instance updates itself to each new graduated release (the product's `kernel/src/updates.ts`, below):
one instance commit moves `product:` and `release:`. Running the installer again on an existing install does the same through setup,
and drops the instance's obsolete `aidenhq` marketplace entry in that commit; other marketplaces stay.

### Nightly releases

Releases are named by their cut date (`2026.11.18`, UTC). A second cut on the same day is `2026.11.18.1`, then `.2`.
Names compare part by part as numbers, so `2026.11.2` < `2026.11.18` < `2026.11.18.1` < `2026.11.19`. A kernel that
predates four-part names ignores a day's second cut and takes the next day's release.

Every day at 18:00 UTC, [`nightly.yml`](.github/workflows/nightly.yml) does the following:

1. **Decide.** [`.github/release/nightly.mjs`](.github/release/nightly.mjs) reads product main's sha.
   If it equals the newest published release's `kernel`, it stops. It also skips while product main has no
   `modules/marketplace.json` (the official modules not yet in the product). Otherwise it waits up to 45 minutes for
   product main's `ci-required` check and skips the night unless that check passed. The release file pins that one
   product sha. Its `notes` come from the product's `feat`, `fix` and `perf` commit subjects since the last release's
   kernel sha: features first, deduplicated, at most 20. The notes start with a flag when a release may add module
   authority, read approximately from `modules/<name>/module.yaml` diffs. They end with a flag when it touches
   host setup (`ops/setup.sh` or `ops/vm/`). A day's second cut waits until product main's kernel accepts four-part
   names.
2. **Build.** It calls [`release.yml`](.github/workflows/release.yml)'s plan, images and collect jobs. They build and
   push every image the product checkout builds (its kernel and its `modules/`) for amd64 and arm64.
3. **Cut.** It commits `releases/<name>.json` with its `images` to main, tags that commit and dispatches `release.yml`
   on the tag. It does all three with the built-in `GITHUB_TOKEN`; the main ruleset only blocks deletion and force-push.
   A tag pushed with that token starts no workflow, so the run is a dispatch on the tag. Installs' updaters accept a
   `release.yml` run on the tag, whether a push or a dispatch.
4. **Check and publish.** The tag run is the same as for a hand cut: fetch, verify and check it on a fresh runner, then publish it
   as a pre-release. Nothing takes it yet.
5. **Graduate.** [`graduate.yml`](.github/workflows/graduate.yml) upgrades a test instance to it (below). Once it
   graduates, installs' updaters pick it up that night, between 02:00 and 05:00 in their own timezone, and get.aidenhq.ai
   serves it within minutes.

A tag run that doesn't publish deletes its tag and any draft release, then opens an issue, so nothing untested is ever
offered. A failed nightly before the tag only opens an issue. A failed release leaves its file on main, and its name is
used up: the next cut that day takes the next `.N`.

- **Preview tonight's cut:** `GITHUB_TOKEN=$(gh auth token) node .github/release/nightly.mjs`, or run `nightly` with
  `dry_run` from the Actions tab.
- **Skip one night:** cancel that night's `nightly` run.
- **Hold nightlies:** `gh workflow disable nightly.yml -R Aiden-HQ/aidenhq-distro`. Use `gh workflow enable` to resume.
- **Cut one now:** `gh workflow run nightly.yml -R Aiden-HQ/aidenhq-distro`. It makes the same checks as the
  scheduled run.
- **Cut one by hand,** e.g. pinning shas other than main's:
  1. Write `releases/<name>.json` with no `images` (copy the nightly's shape, `notes` included).
  2. Run `release` by hand with `release=<name>`.
  3. Merge the `images.json` artifact into the file and land it on main.
  4. Push the tag `<name>` on that commit, or run `release` on the tag.

  The tag run then checks and publishes it: the kernel sha must be on product main with its `ci-required` check green
  there (product CI already ran every suite on it), the set fetches and verifies, the last release's install must still
  upgrade to it (staged compile), and every image digest must be there for amd64 and arm64. The last release's AI
  reviewer judges the update too, but only advisorily: a rejection prints a warning and doesn't block publish. When the
  last release's updater can't land this one, the owner may set `"upgrade_from_previous": "manual"` in the file, with
  a first note telling installs to run the installer again (INSTALL.md "Releases"): the review is skipped up front and
  graduation upgrades its test instance by running the candidate's installer again.

The nightly and release workflows use the built-in `GITHUB_TOKEN`, plus one secret: graduation's model key (below), which
the tag run's `review` job also uses so the last release's own AI reviewer judges the update.

### Release graduation

Every cut is published as a GitHub pre-release. Installs' updaters skip pre-releases (they take only published releases
that are not pre-releases, read from the Releases API) and get.aidenhq.ai serves GitHub's latest, which a pre-release never
is. A cut becomes a full release, and latest, only when it graduates: a fresh AidenHQ on a free GitHub-hosted runner moves
to it the way an owner's install would, and still works.

[`graduate.yml`](.github/workflows/graduate.yml) is dispatched by `release.yml` once it publishes a cut (a `workflow_run` trigger never fires for a
release the nightly started with `GITHUB_TOKEN`), and runs every 6 hours to catch up and by hand. One run at a time, from main only:

1. **Select** ([`.github/release/graduate.mjs`](.github/release/graduate.mjs) `select`). The baseline is the current
   latest. The candidate is the oldest pre-release newer than it without the rejected mark, so cuts graduate in order and
   each is tested from the release before it. No candidate: the run ends.
2. **Test** (ubuntu-24.04, no token, [`graduate-instance.sh`](.github/release/graduate-instance.sh),
   [`graduate-scenario.mjs`](.github/release/graduate-scenario.mjs) and
   [`graduate-checks.mjs`](.github/release/graduate-checks.mjs)), about 15-20 minutes:
   1. The service user (uid 1000) and the disk: the runner's free space is measured and printed; preinstalled
      toolchains are removed, and Docker's data and the service user's home move to `/mnt`, only when the installer's
      60 GB minimum isn't met otherwise. The installer's own check is never lowered.
   2. The baseline's own published `install.sh` (its digest checked), non-interactive, `--no-tailscale`, the model key
      from the secret `GRADUATE_OPENROUTER_KEY` in its environment (it goes to setup's root-only config file). Beside it,
      in the background, the candidate's images (its release file, digest checked) of every repository the baseline has
      pulled, so the upgrade's apply mostly restarts. That pull starts only once the installer has pulled a repository
      (never before its disk check), never records a check, and anything it misses the apply pulls itself.
   3. A new owner, over HTTP on the runner's loopback: the account, the authenticator, the model key, the welcome with
      every flow skipped, and a chat with Aiden that must get a reply. Beside them, without a model, the hello app: the
      baseline's own app starter in a repository on the server (`local/grad-hello`), registered in the instance's
      `apps.yaml` as `app_create` does (pushed to the instance's main, then waited for until apps-mcp, which reads its own
      clone at its next reconcile tick, lists it) and deployed through the apps platform's host path (`ops/app-deploy.sh`: build,
      health, the post-deploy checks). Whether it went live is recorded, not required: the candidate may be the release
      that fixes it. When it didn't, the job log and summary say so, since the hello check after the upgrade then has
      nothing to test.
   4. The upgrade, by the baseline's own installed updater:
      `AIDENHQ_UPDATE_CANDIDATE=<tag> node kernel/src/updates.ts check <tag> graduate`. The kernel files it as a
      `kernel.apply`, which the AI reviewer decides (auto-updates are on for a new install); the run waits for the
      record to end through the AI reviewer or panel (75 minutes) and the apply generation to be good. A record that ends
      up waiting on the owner (Tier 2 on its merits under the baseline's rules, e.g. new module authority) needs a tap this
      test doesn't make: the run stops there with the verdict `harness`, which opens an issue and neither rejects the
      candidate nor counts toward its incomplete runs. The owner decides that release (graduate it by hand).
   5. Smoke checks, side by side, each within its own bound: the instance pins the candidate, the checkout is its kernel
      and every AidenHQ image running is one of its digests; the last generation is good; every agent is ready (none
      `error`, `verifying` or `pending_approval`, none gone since the baseline); a new chat gets a fresh reply; the hello
      app (when the baseline had one) is still healthy and answers; `scripts/verify-security.sh` exits 0. A check that
      says no fails the candidate; one cut off at its bound stays missing (incomplete, below).

   It hands promote a small `result.json` (the checks, notes and each phase's seconds; the job log prints `timing:
   <phase> <s>s` lines and the summary a table); on a failure it uploads its logs with the model key and setup token
   redacted. Expected: install 8-12 minutes, scenario 3-5, upgrade 4-8 (0-5 of it the kernel's next updates pass, which
   files the prepared release), smoke 1-3.

   Aiden building an app end to end (a model-built app through an Engineer) is not part of this per-release gate: it is
   slow and varies run to run. It belongs in a separate, less frequent check (not built yet).
3. **Promote** (`graduate.mjs promote`, `contents: write`, never runs a release's code). The result must name exactly the
   selected release and baseline with every check passed; through the API, this run's test job succeeded and the
   release's tag commit and asset digests are still the ones selected. Then the release is made a full release and
   latest. It refuses to move latest back to an older release; a re-run on a graduated release does nothing.
4. **Reject**, only for the candidate's own failure: the test failed after the upgrade started and one of its checks
   ran and said no. The line `graduation: failed <run url>` is added to the release's notes and one issue is opened. A
   rejected release stays a pre-release for good; the next candidate is tested from the same baseline, and release.yml's
   upgrade test no longer starts from it. Anything else opens one issue and rejects nothing, so the candidate is tried
   again at the next run: a failure before the upgrade (the baseline's install, first run or chat, or the runner), the
   instance's updater rate-limited by GitHub for 25 minutes, the test's own limit (verdict `harness`, e.g. the update
   waiting on an owner's tap), a step or the job cut short by its timeout, a cancelled run,
   or promotion failing after a passing test (GitHub API calls there wait out rate limits first). A run that reached the
   candidate (its updater prepared it) but ended without a verdict (it hung, a step timed out, its checks never wrote)
   adds a `graduation: incomplete <run url>` line to its notes; at the third such line it is rejected as never
   completed, so one release can't hold back every later cut.

   A candidate that has waited over 24 hours without graduating also gets one `Graduation stalled: <tag> waiting since <time>`
   issue (opened by `select`, kept open once, closed when that cut or a newer one graduates). It names the baseline and
   the last runs, and whether each failed in the baseline stage (before the candidate was touched) or the candidate stage.

Operating it:

- **See what it would do:** `GITHUB_TOKEN=$(gh auth token) node .github/release/graduate.mjs select` (read-only).
- **Run it by hand on a VM** (the same scripts, outside GitHub; nothing is promoted or rejected). A fresh Ubuntu 24.04
  VM (it creates the `aidenhq` user, installs AidenHQ and changes the host: never one you use), 8 GB RAM or more, 70 GB
  free, a sudoer with passwordless sudo, and `git`, `curl`, `jq` and Node 24 on the PATH. On a cloud image whose uid
  1000 is taken (`ubuntu`), the service user gets another uid and the script warns. Then:

  ```sh
  git clone https://github.com/Aiden-HQ/aidenhq-distro && cd aidenhq-distro
  # TAG, TAG_SHA, KERNEL, BASELINE and the digests select would name: candidate and baseline named, or omitted for
  # select's own pick (the oldest pending pre-release, from latest). GITHUB_TOKEN is optional (rate limits).
  eval "$(node .github/release/graduate.mjs env <candidate> <baseline>)"   # e.g. 2026.11.20 2026.11.19.2
  export OPENROUTER_KEY=sk-or-...        # a spend-capped key, as GRADUATE_OPENROUTER_KEY
  export GRAD_DIR=$HOME/graduate-run     # the default; the run's account, authenticator key and results (0700)
  bash .github/release/graduate-instance.sh run
  ```

  `run` does what the test job does, in order (prepare, prepull-start, install, `graduate-scenario.mjs baseline`,
  upgrade, `graduate-scenario.mjs smoke`), then `result`: `$GRAD_DIR/result.json` and the verdict, exit 0 only when it
  passed. Each phase also runs alone with the same env (`bash .github/release/graduate-instance.sh <phase>`, `node
  .github/release/graduate-scenario.mjs baseline|smoke`), e.g. to rerun the smoke checks after a fix.
- **Retry a rejected release** (e.g. a runner failure): delete the `graduation: failed` line from its notes
  (`gh release edit <tag> -R Aiden-HQ/aidenhq-distro --notes-file <file>`), then
  `gh workflow run graduate.yml -R Aiden-HQ/aidenhq-distro`.
- **Reject one by hand:** add the line `graduation: failed <reason or link>` to its notes.
- **Graduate one by hand** (the bootstrap, below, or an emergency fix): check it yourself, then
  `gh release edit <tag> -R Aiden-HQ/aidenhq-distro --prerelease=false --latest`. Never graduate a release older than
  the current latest.
- **The secret:** `GRADUATE_OPENROUTER_KEY`, an OpenRouter key with a low spend limit. The test runs the candidate's
  code with it, so it must be a key whose leak costs at most its limit. `release.yml`'s `review` job (its only user there, on a fresh runner that runs no code of the release) uses it too: there
  the last graduated release's own kernel files the update and its AI reviewer judges it, as on an install.
- **The bootstrap:** a baseline whose updater predates graduation (no `AIDENHQ_UPDATE_CANDIDATE` in its
  `kernel/src/updates.ts`) can't be upgraded this way, and select fails with "baseline ... predates graduation;
  graduate one release by hand". Graduate by hand the first release that has it; from then on graduation runs itself.
  Releases published before graduation as full releases but newer than latest (select warns about them) count as
  graduated for updaters that have the filter: make them pre-releases (`gh release edit <tag> --prerelease`) to have
  them tested, or leave them.

An install whose updater predates the graduated filter ignores the pre-release flag and takes a cut as soon as its
release run passes. The gate holds for an install once it runs a release with the filter.

### get.aidenhq.ai

The Worker ([`web/worker.js`](web/worker.js)) serves GitHub's `releases/latest/download/install.sh` as `text/plain`. It
caches that file for five minutes and keeps the last good copy, which it serves when GitHub fails. A release changes
nothing on the site, and the site needs no deploy for it. Pages and styles are still deployed by hand when they change
(`sh web/build.sh && npx -y wrangler@4.160.0 deploy`).

What it serves is exactly the asset GitHub published for the latest graduated release:

- GitHub's "latest" is the newest release that is neither a draft nor a prerelease.
- `release.yml` keeps a release a draft until its install-and-test has passed and its uploaded assets match what was
  tested and baked. If a release fails, it deletes the draft and the tag.
- `release.yml` publishes every release as a pre-release, never latest. Only `graduate.yml` makes a release latest, after
  its test instance passed, and it never moves latest back to an older release.
- The Worker serves only a cut installer: one with a release name, its release file's sha256 and the distro commit
  baked in. The installer then refuses any release file whose sha256 differs from the baked one.

The trust is in this repository and its release workflow, the same as for the release assets themselves. There is no
separate pin in the Worker.

### Test locally

```sh
sh installer/test.sh
```

### Licence

MIT, see [LICENSE](LICENSE). The kernel is AGPL-3.0-only; the kernel's and the official modules' licences are in
[AidenHQ](https://github.com/Aiden-HQ/AidenHQ).

### Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
