#!/usr/bin/env sh
#
# This helper updates the reference of [distribution-scripts](https://github.com/crystal-lang/distribution-scripts),
# pushes the change to GitHub and creates a pull request.
#
# Usage:
#
#    scripts/update-distribution_scripts.sh [REF [BRANCH]]
#
# Parameters:
# * REF: Git commit SHA in distribution-scripts (default: HEAD)
# * BRANCH: Branch name for CI branch in crystal (default: ci/update-distribution-scripts)
#
# Requirements:
# * packages: git gh sed
# * Working directory should be in a checked out work tree of `crystal-lang/crystal`.
#
# * The default value for reference is the current HEAD of https://github.com/crystal-lang/distribution-scripts.

set -eu

DISTRIBUTION_SCRIPTS_WORK_DIR=${DISTRIBUTION_SCRIPTS_WORK_DIR:-../distribution-scripts/.git}
GIT_DS="git --git-dir=$DISTRIBUTION_SCRIPTS_WORK_DIR"

$GIT_DS fetch origin master

if [ "${1:-"HEAD"}" = "HEAD" ]; then
  reference=$($GIT_DS rev-list origin/master | head -1)
else
  reference=${1}
fi

branch="${2:-"ci/update-distribution-scripts"}"

git switch -C "$branch" master

old_reference=$(sed -n "/distribution-scripts-version:/{n;n;n;p}" .circleci/config.yml | grep -o -P '(?<=default: ")[^"]+')
echo "$old_reference".."$reference"

sed -i -E "/distribution-scripts-version:/{n;n;n;s/default: \".*\"/default: \"$reference\"/}" .circleci/config.yml

git add .circleci/config.yml

message="Updates \`distribution-scripts\` dependency to https://github.com/crystal-lang/distribution-scripts/commit/$reference"
log=$($GIT_DS log "$old_reference".."$reference" --format="%s" | sed "s/.*(/crystal-lang\/distribution-scripts/;s/^/* /;s/)$//")
message=$(printf "%s\n\nThis includes the following changes:\n\n%s" "$message" "$log")

git commit -m "Update distribution-scripts" -m "$message"

git show

git push -u upstream "$branch"

# Confirm creating pull request
echo "Create pull request for branch $branch? [y/N]"
read -r REPLY

if [ "$REPLY" = "y" ]; then
  gh pr create -R crystal-lang/crystal --fill --label "topic:infrastructure" --assignee "@me"
fi
