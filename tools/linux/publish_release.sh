#!/bin/bash
# tools/linux/publish_release.sh: creates the GitHub release and uploads the packages.
#
#   GITHUB_TOKEN=<a personal access token with the repo scope> \
#     tools/linux/publish_release.sh v0.6.1 "Let's Go Recomp 0.6.1" docs/RELEASE-0.6.1.md \
#       build/dist/letsgo-recomp_0.6.1-1_amd64.deb build/dist/LetsGoRecomp_0.6.1_x86_64.AppImage
#
# The release is a pre-release (the game itself has not been played through on Linux yet: it needs the player's own
# game files). With PRERELEASE=0 it is a normal one.
#
# The token: github.com/settings/tokens (classic, with the repo scope), or a fine-grained one with "Contents: write".
set -euo pipefail
cd "$(dirname "$0")/../.."

REPO=${REPO:-TetradogOther/letsgo-recomp}
TAG=${1:?the tag}
NAME=${2:?the name of the release}
NOTES=${3:?the notes (a file)}
shift 3
ASSETS=("$@")

[ -n "${GITHUB_TOKEN:-}" ] || { echo "publish_release: GITHUB_TOKEN is needed"; exit 1; }
[ -f "$NOTES" ] || { echo "publish_release: $NOTES is not there"; exit 1; }
command -v curl >/dev/null || { echo "publish_release: curl is needed"; exit 1; }
command -v jq >/dev/null || { echo "publish_release: jq is needed (apt install jq)"; exit 1; }

api() {  # api <method> <path> [body file]
    local method=$1 path=$2 body=${3:-}
    if [ -n "$body" ]; then
        curl -sS -X "$method" -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
            -H "Content-Type: application/json" --data-binary "@$body" "https://api.github.com$path"
    else
        curl -sS -X "$method" -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
            "https://api.github.com$path"
    fi
}

# the release (if it is already there, it is updated)
printf '{"tag_name":"%s","name":"%s","body":%s,"prerelease":%s,"draft":false}\n' \
    "$TAG" "$NAME" "$(jq -Rs . < "$NOTES")" "${PRERELEASE:-1}" > /tmp/release.json

ID=$(api GET "/repos/$REPO/releases/tags/$TAG" | jq -r '.id // empty')
if [ -n "$ID" ]; then
    echo "==> the release $TAG is already there ($ID): it is updated"
    api PATCH "/repos/$REPO/releases/$ID" /tmp/release.json | jq -r '.html_url'
else
    echo "==> the release $TAG"
    ID=$(api POST "/repos/$REPO/releases" /tmp/release.json | jq -r '.id // empty')
    [ -n "$ID" ] || { echo "publish_release: the release was not created"; exit 1; }
    api GET "/repos/$REPO/releases/$ID" | jq -r '.html_url'
fi

for a in "${ASSETS[@]}"; do
    [ -f "$a" ] || { echo "publish_release: $a is not there"; exit 1; }
    name=$(basename "$a")
    echo "==> $name ($(du -h "$a" | cut -f1))"
    # an asset with that name (from a previous run) is replaced
    old=$(api GET "/repos/$REPO/releases/$ID/assets" | jq -r --arg n "$name" '.[] | select(.name == $n) | .id')
    for o in $old; do api DELETE "/repos/$REPO/releases/assets/$o" >/dev/null; done
    curl -sS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$a" \
        "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=$name" \
        | jq -r 'if .id then "    ok: \(.browser_download_url)" else "    FAILED: \(.message // .)" end'
done

echo "publish_release: done"
