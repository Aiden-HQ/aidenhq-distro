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

The installer checks your server, fetches a tested release of the kernel and the essential modules pinned by commit,
verifies every commit, and hands you to setup. Aiden says hello on your board when it's ready.

## About this repo

This repo is the distribution of AidenHQ: how you get a tested set of the kernel and modules onto a server.

| Repo | What it holds |
|---|---|
| [AidenHQ](https://github.com/Aiden-HQ/AidenHQ) | The kernel, runner, board and setup scripts. |
| [aidenhq-modules](https://github.com/Aiden-HQ/aidenhq-modules) | The official modules and the `aidenhq` marketplace. |
| aidenhq-distro (this repo) | The installer, the website and the release manifests. |

| Path | What it is |
|---|---|
| `install.sh` | The installer `curl -fsSL https://get.aidenhq.ai \| sh` runs. See [INSTALL.md](INSTALL.md). |
| `installer/` | `test.sh`, an offline test of the installer's release checks (`sh installer/test.sh`, needs only POSIX sh and git). `RESEARCH.md` has the design notes. |
| `releases/` | One manifest per release, for example `releases/2026.11.json`. |
| `site/` | The aidenhq.ai website (static files, `llms.txt`, `prompt.md`). |
| `web/`, `wrangler.jsonc` | The Cloudflare Worker that serves `install.sh` at get.aidenhq.ai and the site. |

### Releases

A release manifest pins three things by commit sha: the kernel (`kernel`, from AidenHQ), the modules marketplace
(`marketplace.sha`, from aidenhq-modules) and each essential module (`modules.<name>`). The installer fetches those
exact commits, checks that each module sha is in the marketplace history, and refuses a manifest whose sha256 does not
match the one baked into the tagged `install.sh`. A manifest that still has `TODO-` placeholders is not cut yet and the
installer refuses it.

After install, an instance moves on its own: its owner bumps the `product:` sha in `instance.yaml` (kernel) and the
`aidenhq` marketplace sha (modules). A new release does not change a running instance.

### Nightly releases

Releases are named by their cut date (`2026.11.18`, UTC). A second cut on the same day is `2026.11.18.1`, then `.2`.
Names compare part by part as numbers, so `2026.11.2` < `2026.11.18` < `2026.11.18.1` < `2026.11.19`. A kernel that
predates four-part names ignores a day's second cut and takes the next day's release.

Every day at 18:00 UTC, [`nightly.yml`](.github/workflows/nightly.yml) does the following:

1. **Decide.** [`.github/release/nightly.mjs`](.github/release/nightly.mjs) reads product main's sha and its
   `modules-pin.json`. If both equal the newest published release's, it stops. Otherwise it waits up to 45 minutes for
   product main's `ci-required` check and skips the night unless that check passed. The release file pins the kernel,
   the modules sha and the marketplace's `bundle` at that sha. Its `notes` come from the `feat`, `fix` and `perf`
   commit subjects since the last release: features first, deduplicated, at most 20. The notes start with a flag when a
   release may add module authority, read approximately from `module.yaml` diffs. They end with a flag when it touches
   host setup (`ops/setup.sh` or `ops/vm/`). A day's second cut waits until product main's kernel accepts four-part
   names.
2. **Build.** It calls [`release.yml`](.github/workflows/release.yml)'s plan, images and collect jobs. They build and
   push every image for amd64 and arm64.
3. **Cut.** It commits `releases/<name>.json` with its `images` to main, tags that commit and dispatches `release.yml`
   on the tag. It does all three with the built-in `GITHUB_TOKEN`; the main ruleset only blocks deletion and force-push.
   A tag pushed with that token starts no workflow, so the run is a dispatch on the tag. Installs' updaters accept a
   `release.yml` run on the tag, whether a push or a dispatch.
4. **Test and publish.** The tag run is the same as for a hand cut: install and test on a fresh runner, then publish.
   Installs' updaters pick up the release that night, between 02:00 and 05:00 in their own timezone. get.aidenhq.ai
   serves it within minutes (below).

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

No setup: the workflows use only the built-in `GITHUB_TOKEN`.

### get.aidenhq.ai

The Worker ([`web/worker.js`](web/worker.js)) serves GitHub's `releases/latest/download/install.sh` as `text/plain`. It
caches that file for five minutes and keeps the last good copy, which it serves when GitHub fails. A release changes
nothing on the site, and the site needs no deploy for it. Pages and styles are still deployed by hand when they change
(`sh web/build.sh && npx -y wrangler@4.160.0 deploy`).

What it serves is exactly the asset GitHub published for the latest release:

- GitHub's "latest" is the newest release that is neither a draft nor a prerelease.
- `release.yml` keeps a release a draft until its install-and-test has passed and its uploaded assets match what was
  tested and baked. If a release fails, it deletes the draft and the tag.
- `release.yml` marks a release latest only when no published release has a newer name. A re-run of an older tag never
  moves the site back.
- The Worker serves only a cut installer: one with a release name, its release file's sha256 and the distro commit
  baked in. The installer then refuses any release file whose sha256 differs from the baked one.

The trust is in this repository and its release workflow, the same as for the release assets themselves. There is no
separate pin in the Worker.

### Test locally

```sh
sh installer/test.sh
```

### Licence

MIT, see [LICENSE](LICENSE). The kernel is AGPL-3.0-only and the modules are MIT or AGPL-3.0-only per module; see their
repos.

### Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
