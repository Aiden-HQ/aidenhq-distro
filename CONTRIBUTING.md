# Contributing

The full rules live in the product repo's
[CONTRIBUTING.md](https://github.com/Aiden-HQ/AidenHQ/blob/main/CONTRIBUTING.md). They apply here too. In short:

- Fork, branch, open a PR against `main`. Never push to `main`.
- Sign the [CLA](https://github.com/Aiden-HQ/AidenHQ/blob/main/CLA.md).
- The PR title is a Conventional Commit (`fix(installer): ...`, `docs: ...`). The repo is squash-only, so the title
  becomes the commit. The body says why.
- Supply chain: unless it is a security fix, do not adopt a dependency, package, image or action published less than 7
  days ago. Pin versions exactly and state the release date of any pin you bump.
- Do not edit a cut release manifest by hand. The nightly (README "Nightly releases") cuts releases and fills the shas.
- Use neutral examples (`acme`, `example.com`). No real names, emails, hostnames or IPs.

Run `sh installer/test.sh` before opening a PR that touches `install.sh`.
