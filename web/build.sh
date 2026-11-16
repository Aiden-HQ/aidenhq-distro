#!/bin/sh
# Assemble what the Worker serves: the site plus the installer.
set -eu
cd "$(dirname "$0")/.."
rm -rf web/public && mkdir -p web/public
cp -R site/. web/public/
cp install.sh web/public/install.sh
