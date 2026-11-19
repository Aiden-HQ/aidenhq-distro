# AidenHQ

**Your agents ship autonomously.**

AidenHQ gives you a whole AI team that runs itself: a chief of staff you talk to, and specialists who plan, build,
ship and follow up around the clock, on your own server.

Not a chatbot. Not a workflow builder. A team that works.

```sh
curl -fsSL https://get.aidenhq.ai | sh
```

One line on a fresh Ubuntu or Debian server; it installs Docker and Node itself. Site: [aidenhq.ai](https://aidenhq.ai) (source in
[`site/`](site/)).

## Hand over real work, in a sentence

- **A chief of staff that follows up for you.** Aiden tracks every commitment made in Slack and email, chases people
  when things slip, and briefs you every morning on what moved.
- **An app from one sentence.** "Build me a roadmap tracker" becomes a live app your team signs in to, maintained
  after launch.
- **A new agent from a description.** "I need an agent that watches our support channel" becomes a working agent. The
  Agent Architect designs it, runs it on trial and graduates it once its work holds up.
- **An engineering team that ships.** A designer, engineers, a reviewer, DevOps and security, each a specialist agent.
  Issues become designed, built, reviewed and deployed work.

## Why it works where other agents stall

- **Stop babysitting your agents.** Talk to Aiden like a chief of staff. The work fans out to specialists who wake on
  schedules and events, and Aiden chases it until it lands.
- **Done means checked.** A grader checks the work before a task counts as done, and an AI reviewer checks every risky
  action before it happens.
- **Apps that look after themselves.** Agents watch every app's health, roll back a bad deploy, raise and fix incidents,
  patch dependencies and security issues with pull requests, and catch visual regressions in UI review.
- **It learns your corrections.** Every correction becomes a rule or an automated check. Agents keep a memory of what
  worked, a coach agent proposes better playbooks, weekly fleet reviews fix the causes of repeat defects, and agents
  propose changes to their own instructions and tools, tested before they land.
- **Plugs into the tools you already use.** Slack, Gmail, Calendar, Drive, Jira, GitHub, Glean, Grafana, ClickHouse,
  Telegram and OpenRouter, connected once and granted tool by tool. Every source feeds one shared warehouse your apps
  can build on.
- **Set the cap. No surprise bills.** Spend caps per agent, per run, per task and per day; fast, efficient models by
  default; and a ledger of every model call.
- **Add, swap or extend any capability.** Engines (Codex, Claude Code, opencode), channels, connections, agents and
  apps are modules. Ours cover most needs, and the marketplace is open for anyone to extend.
- **Yours end to end.** Your server, any OpenRouter model per agent, and every agent, playbook and app in your own git
  repository, ready to review and revert. Under the hood, a small kernel holds the gates, identity, sandbox, metering
  and audit log; everything else is a module on the same public contracts.

## Agents decide. Code approves.

- **AI review of every write.** Each push, merge, deploy and message is checked first. Changes that expand authority
  get a second reviewer from another model family, and every false reject becomes a test case.
- **Rules in code, below the model.** Gates and per-tool permissions are enforced by one proxy that no prompt can
  argue with. You keep the final say on spend, autonomy and what agents may write.
- **Attacked and patched.** A Red Teamer agent probes your system, Security Watch scans images and dependencies for
  known vulnerabilities and opens patch PRs, and every dependency is pinned with a 7-day minimum age, gitleaks secret
  scanning and image scans.
- **Locked down.** Coding jobs run jailed with their own network, no secrets and read-only tokens. Untrusted text is
  fenced as data. Secrets live in an encrypted vault. There are no public ports, and shared apps sit behind your
  company's single sign-on.
- **Every action on the record.** Spend caps, an audit log of gate decisions and tool writes, and every change in git.

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
4. **Test and publish.** The tag run is the same as for a hand cut: install and test on a fresh runner, then publish it
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

  The tag run then tests and publishes it.

The nightly and release workflows use only the built-in `GITHUB_TOKEN`; graduation also needs one secret (below).

### Release graduation

Every cut is published as a GitHub pre-release. Installs' updaters skip pre-releases (they take only published releases
that are not pre-releases, read from the Releases API) and get.aidenhq.ai serves GitHub's latest, which a pre-release never
is. A cut becomes a full release, and latest, only when it graduates: a fresh AidenHQ on a free GitHub-hosted runner moves
to it the way an owner's install would, and still works.

[`graduate.yml`](.github/workflows/graduate.yml) runs after each release run that passed on a tag, every 6 hours to catch
up, and by hand. One run at a time, from main only:

1. **Select** ([`.github/release/graduate.mjs`](.github/release/graduate.mjs) `select`). The baseline is the current
   latest. The candidate is the oldest pre-release newer than it without the rejected mark, so cuts graduate in order and
   each is tested from the release before it. No candidate: the run ends.
2. **Test** (ubuntu-24.04, no token, [`graduate-instance.sh`](.github/release/graduate-instance.sh) and
   [`graduate-scenario.mjs`](.github/release/graduate-scenario.mjs)):
   1. The service user (uid 1000) and the disk: the runner's free space is measured and printed; preinstalled
      toolchains are removed, and Docker's data and the service user's home move to `/mnt`, only when the installer's
      60 GB minimum isn't met otherwise. The installer's own check is never lowered.
   2. The baseline's own published `install.sh` (its digest checked), non-interactive, `--no-tailscale`, the model key
      from the secret `GRADUATE_OPENROUTER_KEY` in its environment (it goes to setup's root-only config file).
   3. A new owner, over HTTP on the runner's loopback: the account, the authenticator, the model key, the welcome with
      every flow skipped, a chat with Aiden that must get a reply, then "a tiny page that says hello". Whether the hello
      app went live is recorded, not required: the candidate may be the release that fixes it.
   4. The upgrade, by the baseline's own installed updater:
      `AIDENHQ_UPDATE_CANDIDATE=<tag> node kernel/src/updates.ts check <tag> graduate`. The kernel files it as a
      `kernel.apply`, which the AI reviewer decides (auto-updates are on for a new install); the run waits for the
      record to end (75 minutes; a record waiting on the owner, e.g. a release adding module authority, fails at once: graduate such a release by hand) and the apply generation to be good.
   5. Smoke checks, each time-bounded: the instance pins the candidate, the checkout is its kernel and every AidenHQ
      image running is one of its digests; the last generation is good; every agent is ready (none `error`,
      `verifying` or `pending_approval`, none gone since the baseline); a new chat gets a fresh reply; the hello app (when
      the baseline had one) is still healthy and answers; a second tiny app deploys; `scripts/verify-security.sh` exits 0.

   It hands promote a small `result.json`; on a failure it uploads its logs with the model key and setup token redacted.
3. **Promote** (`graduate.mjs promote`, `contents: write`, never runs a release's code). The result must name exactly the
   selected release and baseline with every check passed; through the API, this run's test job succeeded and the
   release's tag commit and asset digests are still the ones selected. Then the release is made a full release and
   latest. It refuses to move latest back to an older release; a re-run on a graduated release does nothing.
4. **Reject**, only for the candidate's own failure: the test failed after the upgrade started and one of its checks
   ran and said no. The line `graduation: failed <run url>` is added to the release's notes and one issue is opened. A
   rejected release stays a pre-release for good; the next candidate is tested from the same baseline, and release.yml's
   upgrade test no longer starts from it. Anything else opens one issue and rejects nothing, so the candidate is tried
   again at the next run: a failure before the upgrade (the baseline's install, first run or chat, or the runner), the
   instance's updater rate-limited by GitHub for 25 minutes, a step or the job cut short by its timeout, a cancelled run,
   or promotion failing after a passing test (GitHub API calls there wait out rate limits first). A candidate that keeps
   failing this way is rejected by hand.

Operating it:

- **See what it would do:** `GITHUB_TOKEN=$(gh auth token) node .github/release/graduate.mjs select` (read-only).
- **Retry a rejected release** (e.g. a runner failure): delete the `graduation: failed` line from its notes
  (`gh release edit <tag> -R Aiden-HQ/aidenhq-distro --notes-file <file>`), then
  `gh workflow run graduate.yml -R Aiden-HQ/aidenhq-distro`.
- **Reject one by hand:** add the line `graduation: failed <reason or link>` to its notes.
- **Graduate one by hand** (the bootstrap, below, or an emergency fix): check it yourself, then
  `gh release edit <tag> -R Aiden-HQ/aidenhq-distro --prerelease=false --latest`. Never graduate a release older than
  the current latest.
- **The secret:** `GRADUATE_OPENROUTER_KEY`, an OpenRouter key with a low spend limit. The test runs the candidate's
  code with it, so it must be a key whose leak costs at most its limit.
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
