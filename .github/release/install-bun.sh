#!/bin/sh
# install-bun.sh: the pinned Bun (what the product's own hosts pin: ops/lib/bun.sh (ensureBun)), checked by sha256, on this runner.
# Bun 1.4.5 (released 2026-11-19), the official release zips. No-op when that version is already on PATH.
# Always prints the bin dir holding the right bun as its last line (prepend it to PATH); with GITHUB_PATH set (Actions) it is added to PATH for later steps too.
set -eu
V=1.4.5
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) f=bun-linux-x64.zip sum=94559b3b528995a49452f9f2404cec74f2efd7d06e0a000a8cd214b02c3666eb ;;
  Linux-aarch64|Linux-arm64) f=bun-linux-aarch64.zip sum=18656a3bf0ea5641f5796ae4213b75255579a70a0fded2f337933785568cdf84 ;;
  Darwin-x86_64) f=bun-darwin-x64.zip sum=a4972e778cce4b6a194d7d289f326aa61576d71d80b7a53e9da2f3739566e5fd ;;
  Darwin-arm64) f=bun-darwin-aarch64.zip sum=b5d6bc2e13caf14e57c89661e89efd073ff16165b41bfe43882616410609cd10 ;;
  *) echo "install-bun: no pinned Bun for $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac
if [ "$(bun --version 2>/dev/null || true)" = "$V" ]; then dirname "$(command -v bun)"; exit 0; fi
# RUNNER_TEMP is private to the job; anywhere else gets a fresh private directory (nothing shared is trusted).
dir="${RUNNER_TEMP:-$(mktemp -d)}/bun-$V"
if [ ! -x "$dir/bin/bun" ]; then
  rm -rf "$dir"; mkdir -p "$dir/bin"
  curl -fsSL -o "$dir/$f" "https://github.com/oven-sh/bun/releases/download/bun-v$V/$f"
  got=$(if command -v sha256sum >/dev/null; then sha256sum "$dir/$f"; else shasum -a 256 "$dir/$f"; fi | cut -d' ' -f1)
  [ "$got" = "$sum" ] || { echo "install-bun: $f sha256 is $got, not the pinned $sum" >&2; exit 1; }
  # The zip holds <name>/bun; Python's zipfile unpacks it (the runner image has no guaranteed unzip).
  python3 -c 'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); open(sys.argv[2], "wb").write(z.read(z.namelist()[-1]))' "$dir/$f" "$dir/bin/bun"
  chmod +x "$dir/bin/bun"
fi
[ -z "${GITHUB_PATH:-}" ] || echo "$dir/bin" >> "$GITHUB_PATH"
echo "$dir/bin"
