# aidenhq-distro: guide for coding agents and contributors

How AidenHQ reaches a server: the installer (`curl -fsSL https://get.aidenhq.ai | sh`), the aidenhq.ai site and its
Worker, and the release manifests that pin one tested product commit. The product itself (kernel, runner, board,
official modules) lives in [Aiden-HQ/AidenHQ](https://github.com/Aiden-HQ/AidenHQ); its `CLAUDE.md` "Conventions"
section applies here too.

Start with [README.md](README.md) (layout, releases, nightly, graduation, get.aidenhq.ai) and
[INSTALL.md](INSTALL.md) (what the installer does). Rules: [CONTRIBUTING.md](CONTRIBUTING.md). Put personal notes in a
gitignored `CLAUDE.local.md`, never in this file.

## Layout

- `install.sh`: the installer, one POSIX sh file. A tagged release bakes in its name, its release file's sha256 and the
  distro commit; get.aidenhq.ai serves the latest graduated release's copy, never this one.
- `installer/`: `test.sh` (offline test of the release checks) and `RESEARCH.md` (design notes).
- `releases/<name>.json`: one manifest per release. Cut by the nightly or by hand (README "Cut one by hand").
- `.github/workflows/`: `ci` (installer + site), `nightly` (decide, build, cut), `release` (tag run: verify, test,
  publish as pre-release), `graduate` (upgrade a test instance, promote to latest). Their scripts are in
  `.github/release/`.
- `site/`: the aidenhq.ai pages. Plain HTML with `<!--#include NAME-->` partials from `site/_partials/`; every page has
  a markdown twin (`index.md`) and a sitemap entry.
- `web/`, `wrangler.jsonc`: the Cloudflare Worker serving the site and get.aidenhq.ai. `web/public/` is generated.

## Build and test

Offline, no token or key needed. Node 24 runs the scripts; Bun 1.4.5 (`sh .github/release/install-bun.sh`) runs the tests.

```sh
sh installer/test.sh && dash installer/test.sh   # installer release checks (CI also runs shellcheck on every .sh)
bun test ./.github/release/graduate.test.mjs ./.github/release/image-key.test.mjs
sh web/build.sh && bun test ./web/worker.test.mjs   # site build + web/check-site.mjs (tags, links, twins, sitemap)
```

Run them before a PR that touches what they cover; CI (`.github/workflows/ci.yml`) runs all of them.

## Conventions

- **Releases are cut, not edited.** Never hand-edit a cut `releases/*.json`; a failed release's name is used up.
- **The installer stays POSIX sh**: it must pass `shellcheck` and run under `dash`. It fetches only pinned commits and
  verifies them; it never weakens a check (disk, digest, sha) to make a test pass.
- **Graduation is the gate.** Only `graduate.yml` (or a maintainer by hand) makes a release latest; never move latest
  to an older release.
- **Site changes**: edit `site/`, run `sh web/build.sh`, keep each page's markdown twin and sitemap entry in step. Pages
  deploy by hand (`sh web/build.sh && bunx wrangler@4.160.0 deploy`); releases need no site deploy.
- **Package managers**: Bun is the one (pinned 1.4.5, sha256-checked in `.github/release/install-bun.sh`; the product's
  hosts get theirs from its setup). The one exception is `.github/release/kinstall.sh`: a release tree with a `bun.lock`
  installs with `bun install --frozen-lockfile`, an older one (only `package-lock.json`, immutable) with `npm ci`, so
  upgrade tests from old releases keep working. Keep it until no release before the Bun move can be a baseline.
- **Supply chain**: actions by SHA, tools by version and checksum, nothing under 7 days old unless a security fix.
  Exceptions live in `.github/supply-chain-exceptions.yaml`.
- **Keep in sync with the product**: `site/prompt.md` (its owner MCP tool names and setup steps) and the pages that
  describe the board (`index`, `start/`, `install/`, `workspace/`, `agents/`, `apps/`, `modules/`,
  `_partials/board-mock.html`, `llms.txt`) follow the product's board layout, onboarding and owner MCP tools. What to
  check is in the product `CLAUDE.md` "Keep in sync".
- **Neutral examples** (`acme`, `example.com`); no real names, emails, hostnames or IPs.
- **PRs**: branch, PR against `main`, Conventional Commit title (`fix(installer): …`, `feat(release): …`,
  `docs(site): …`); squash-only. A change spanning both repos lands the product PR first, then the distro one.
