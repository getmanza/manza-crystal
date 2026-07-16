#!/usr/bin/env bash
# Downloads the cassette tarball published by zazu-ruby's release workflow.
# CI calls this before running tests so we don't have to commit cassettes
# into both repos.
#
#   scripts/fetch-cassettes.sh            # latest release
#   scripts/fetch-cassettes.sh v0.2.1     # specific tag
#
# Cassettes land under spec/fixtures/cassettes/.
set -euo pipefail

REPO="getzazu/zazu-ruby"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/spec/fixtures/cassettes"

TAG="${1:-}"
AUTH=()
if [[ -n "${GH_TOKEN:-}" ]]; then
  AUTH=(-H "Authorization: Bearer $GH_TOKEN")
fi

if [[ -z "$TAG" ]]; then
  # Resolve the latest release tag over the git transport rather than
  # api.github.com — the REST API's 503 storms have failed release runs,
  # while the git endpoints ride separate infrastructure.
  TAG=$(git ls-remote --tags --refs "https://github.com/$REPO.git" 'v*' |
    awk -F/ '{print $NF}' | sort -V | tail -1)
  [[ -n "$TAG" ]] || { echo "Could not resolve latest tag for $REPO" >&2; exit 1; }
fi

URL="https://github.com/$REPO/releases/download/$TAG/cassettes-$TAG.tar.gz"
echo "Fetching cassettes from $URL"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 8 --retry-all-errors --retry-delay 10 "${AUTH[@]}" -H "Accept: application/octet-stream" -o "$TMP/cassettes.tar.gz" "$URL"

mkdir -p "$DEST"
tar -xzf "$TMP/cassettes.tar.gz" -C "$(dirname "$DEST")"
echo "Cassettes extracted to $DEST"
