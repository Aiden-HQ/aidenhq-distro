# shellcheck shell=bash
# kinstall <dir>: install a product tree's dependencies the way its own lockfile says. A tree with a
# bun.lock (2026.11.29 on) gets the pinned Bun (install-bun.sh), `bun install --frozen-lockfile`; a tree with only a
# package-lock.json (every older release, immutable) gets `npm ci`. This is the one place both package managers exist.
# Scripts never run. Source it (`. .github/release/kinstall.sh`); it finds install-bun.sh next to itself.
kinstall() {
  local d="$1" self
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$d/bun.lock" ]; then
    local bin
    bin=$(sh "$self/install-bun.sh") || return 1
    PATH="${bin##*$'\n'}:$PATH"
    (cd "$d" && bun install --frozen-lockfile --ignore-scripts >/dev/null)
  else
    npm ci --ignore-scripts --no-audit --no-fund --prefix "$d" >/dev/null
  fi
}
