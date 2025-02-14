#! /bin/sh

# This script automates generating changelog with `scripts/github-changelog.cr`,
# editing it into `CHANGELOG.md` and pushing it to a `changelog/$VERSION` branch.
#
# It reads the current (dev-)version from `src/VERSION` and generates the
# changelog entries for all PRs from the respective GitHub milestone via
# `scripts/github-changelog.cr`.
# The section is then inserted into `CHANGELOG.md`, overwriting any previous
# content for this milestone.
# Finally, the changes are commited and pushed to `changelog/$VERSION`.
# If the changelog section is *new*, also creates a draft PR for this branch.
#
# Usage:
#
#   scripts/update-changelog.sh
#
# Requirements:
#
#   - scripts/github-changelog.cr
#   - git
#   - grep
#   - sed
#
# Environment variables:
#   GITHUB_TOKEN: Access token for the GitHub API (required)

set -eu

VERSION=${1:-$(cat src/VERSION)}
VERSION=${VERSION%-dev}

base_branch=$(git rev-parse --abbrev-ref HEAD)
branch="changelog/$VERSION"
current_changelog="CHANGELOG.$VERSION.md"

echo "Generating $current_changelog..."
scripts/github-changelog.cr "$VERSION" > "$current_changelog"

echo "Switching to branch $branch"
git switch "$branch" 2>/dev/null || git switch -c "$branch";

# Write release version into src/VERSION
echo "${VERSION}" > src/VERSION
git add src/VERSION

# Update shard.yml
sed -i -E "s/version: .*/version: ${VERSION}/" shard.yml
git add shard.yml

# Write release date into src/SOURCE_DATE_EPOCH
release_date=$(head -n1 "$current_changelog" | grep -o -P '(?<=\()[^)]+')
date --utc --date="${release_date}" +%s > src/SOURCE_DATE_EPOCH
git add src/SOURCE_DATE_EPOCH

if grep --silent -E "^## \[$VERSION\]" CHANGELOG.md; then
  echo "Replacing section in CHANGELOG"

  sed -i -E "/^## \[$VERSION\]/,/^## /{
    /^## \[$VERSION\]/s/.*/cat $current_changelog/e; /^## /!d
  }" CHANGELOG.md

  git add CHANGELOG.md
  git commit -m "Update changelog for $VERSION"
  git push
else
  echo "Adding new section to CHANGELOG"

  sed -i -E "2r $current_changelog" CHANGELOG.md

  git add CHANGELOG.md
  git commit -m "Add changelog for $VERSION"
  git push -u upstream "$branch"

  gh pr create --draft --base "$base_branch" \
    --body "Preview: https://github.com/crystal-lang/crystal/blob/$branch/CHANGELOG.md" \
    --label "topic:infrastructure" -t "Changelog for $VERSION" --milestone "$VERSION"
fi
