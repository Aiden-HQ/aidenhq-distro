#!/bin/sh
# Assemble what the Worker serves: the site plus the installer.
# Each page's `<!--#include NAME-->` line is replaced by site/_partials/NAME.html (the shared header, footer and
# blocks), so pages stay plain HTML with no framework. A marker with no partial fails the build.
set -eu
cd "$(dirname "$0")/.."
rm -rf web/public && mkdir -p web/public
cp -R site/. web/public/
rm -rf web/public/_partials
find web/public -name '*.html' | while IFS= read -r page; do
  awk '
    /^[ \t]*<!--#include [a-z0-9-]+-->[ \t]*$/ {
      name = $0; sub(/^[ \t]*<!--#include /, "", name); sub(/-->[ \t]*$/, "", name)
      file = "site/_partials/" name ".html"
      if ((getline line < file) <= 0) { print "build.sh: missing partial " file > "/dev/stderr"; exit 1 }
      print line
      while ((getline line < file) > 0) print line
      close(file); next
    }
    { print }
  ' "$page" > "$page.tmp"
  mv "$page.tmp" "$page"
done
if grep -rl '<!--#include' web/public --include='*.html'; then echo "build.sh: unresolved include" >&2; exit 1; fi
# llms-full.txt: every page's markdown twin and the agent install guide in one file, so it never drifts from the pages.
{
  printf '# AidenHQ: the full site as markdown\n\n> Every page of https://aidenhq.ai as markdown, then the agent install guide (https://aidenhq.ai/prompt.md). The index is https://aidenhq.ai/llms.txt.\n'
  for md in index.md start/index.md install/index.md workspace/index.md agents/index.md apps/index.md safety/index.md integrations/index.md modules/index.md prompt.md; do
    printf '\n\n---\n\nSource: https://aidenhq.ai/%s\n\n' "$md"
    cat "site/$md"
  done
} > web/public/llms-full.txt
# get.aidenhq.ai serves the latest tagged release's install.sh (web/worker.js), not this copy.
cp web/_headers web/public/_headers
# Fail the build on a page that would share or index badly (missing tags, a broken og:image, sitemap gaps).
node web/check-site.mjs
