#!/usr/bin/env sh

# Update shards release.
#
# Usage:
#
#    scripts/update-shards.sh [<version>]
#
# This helper script pulls the latest Shards release from GitHub and updates all
# references to the shards release in this repository.
#
# See Crystal release checklist: https://github.com/crystal-lang/distribution-scripts/blob/master/processes/shards-release.md#post-release

set -eux

SHARDS_VERSION=${1:-}
if [ -z "$SHARDS_VERSION" ]; then
  # fetch latest release from GitHub
  SHARDS_VERSION=$(gh release view --repo crystal-lang/shards --json tagName --jq .tagName | cut -c 2-)
fi

# Update shards ref in mingw64 and win-msvc build actions
sed -i "/repository: crystal-lang\/shards/{n;s/ref: .*/ref: ${shards_version}/}" .github/workflows/mingw-w64.yml .github/workflows/win_build_portable.yml
