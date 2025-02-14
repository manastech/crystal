#!/usr/bin/env sh
#
# This helper updates all references to the previous Crystal release as bootstrap version with a new release.
#
# Usage:
#
#    scripts/release-update.sh 1.3.0
#
# See Crystal release checklist: https://github.com/crystal-lang/distribution-scripts/blob/master/processes/crystal-release.md#post-release
set -eu

CRYSTAL_VERSION=$1

# Write dev version for next minor release into src/VERSION
minor_branch="${CRYSTAL_VERSION%.*}"
next_minor="$((${minor_branch#*.} + 1))"
echo "${CRYSTAL_VERSION%%.*}.${next_minor}.0-dev" > src/VERSION

# Update shard.yml
sed -i -E "s/version: .*/version: $(cat src/VERSION)/" shard.yml

# Remove SOURCE_DATE_EPOCH (only used in source tree of a release)
rm -f src/SOURCE_DATE_EPOCH

# Edit PREVIOUS_CRYSTAL_BASE_URL in .circleci/config.yml
sed -i -E "s|[0-9.]+/crystal-[0-9.]+-[0-9]|$CRYSTAL_VERSION/crystal-$CRYSTAL_VERSION-1|g" .circleci/config.yml

# Edit DOCKER_TEST_PREFIX in bin/ci
sed -i -E "s|crystallang/crystal:[0-9.]+|crystallang/crystal:$CRYSTAL_VERSION|" bin/ci

# Edit prepare_build on_osx download package and folder
sed -i -E "s|[0-9.]+/crystal-[0-9.]+-[0-9]|$CRYSTAL_VERSION/crystal-$CRYSTAL_VERSION-1|g" bin/ci
sed -i -E "s|crystal-[0-9.]+-[0-9]|crystal-$CRYSTAL_VERSION-1|g" bin/ci

# Edit .github/workflows/*.yml to point to docker image
# Update the patch version of the latest entry if same minor version to have only one item per minor version
previous_release=$(grep -o -P '(?<=crystal_bootstrap_version: ).*(?= # LATEST RELEASE)' .github/workflows/linux.yml)
sed -i -E "s/crystal_bootstrap_version: .+ # LATEST RELEASE/crystal_bootstrap_version: $CRYSTAL_VERSION # LATEST RELEASE/" .github/workflows/linux.yml
sed -i -E "/crystal_bootstrap_version:/ s/(, ${previous_release%.*}\.[0-9]*)?\]\$/, $previous_release]/" .github/workflows/forward-compatibility.yml
sed -i -E "s|crystallang/crystal:[0-9.]+|crystallang/crystal:$CRYSTAL_VERSION|g" .github/workflows/*.yml

# Edit .github/workflows/*.yml to update version for install-crystal action
sed -i -E "s|crystal: \"[0-9.]+\"|crystal: \"$CRYSTAL_VERSION\"|g" .github/workflows/*.yml

# Edit shell.nix latestCrystalBinary using nix-prefetch-url --unpack <url>
darwin_url="https://github.com/crystal-lang/crystal/releases/download/$CRYSTAL_VERSION/crystal-$CRYSTAL_VERSION-1-darwin-universal.tar.gz"
darwin_sha=$(nix-prefetch-url --unpack "$darwin_url")

sed -i -E "s|https://github.com/crystal-lang/crystal/releases/download/[0-9.]+/crystal-[0-9.]+-[0-9]-darwin-universal.tar.gz|$darwin_url|" shell.nix
sed -i -E "/darwin-universal\.tar\.gz/ {n;s|sha256:[^\"]+|sha256:$darwin_sha|}" shell.nix

linux_url="https://github.com/crystal-lang/crystal/releases/download/$CRYSTAL_VERSION/crystal-$CRYSTAL_VERSION-1-linux-x86_64.tar.gz"
linux_sha=$(nix-prefetch-url --unpack "$linux_url")

sed -i -E "s|https://github.com/crystal-lang/crystal/releases/download/[0-9.]+/crystal-[0-9.]+-[0-9]-linux-x86_64.tar.gz|$linux_url|" shell.nix
sed -i -E "/linux-x86_64\.tar\.gz/ {n;s|sha256:[^\"]+|sha256:$linux_sha|}" shell.nix
