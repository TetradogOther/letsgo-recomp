#!/bin/bash
# tools/linux/lintian.sh: the checks on the built package (lintian), with the tags the package is allowed to keep
# (debian/source.lintian-overrides: each line is a tag and why it is there).
#
#   tools/linux/lintian.sh                    # the last .deb built
#   tools/linux/lintian.sh build/dist/x.deb
#
# Needs lintian (apt install lintian) and the package to be built (tools/linux/build_deb.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."

command -v lintian >/dev/null || { echo "lintian: not installed (apt install lintian)"; exit 1; }
DEB=${1:-$(ls -t build/dist/*_amd64.deb 2>/dev/null | head -1)}
[ -n "$DEB" ] && [ -f "$DEB" ] || { echo "lintian: no package to check (tools/linux/build_deb.sh)"; exit 1; }

# the tags the package is allowed to keep
TAGS=$(sed -n 's/^\([a-z0-9-]\{1,\}\):.*/\1/p' debian/source.lintian-overrides | paste -sd,)

echo "==> lintian ($DEB)"
lintian --tag-display-limit 0 ${TAGS:+--suppress-tags "$TAGS"} "$DEB"
