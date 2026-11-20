# shellcheck shell=bash
# kpath <product checkout> <path ending in .mjs>: the file under that checkout, by its .ts name if it has one, else its .mjs name.
# The product renamed its scripts from .mjs to .ts (2026.11.20 and older releases still carry .mjs), and a release is always
# tested with its own scripts, so every kernel-side script is found through this. Prints the path; fails when neither exists.
# Source it (`. .github/release/kpath.sh`); node 24 runs the .ts one as it is.
kpath() {
  local base="${2%.mjs}" ext
  for ext in ts mjs; do
    [ -f "$1/$base.$ext" ] && { printf '%s\n' "$1/$base.$ext"; return 0; }
  done
  return 1
}
