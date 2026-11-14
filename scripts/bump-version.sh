#!/bin/bash
# Bumps CFBundleShortVersionString, commits it, and tags the commit.
#
# Usage: scripts/bump-version.sh {major|minor|patch} [--push]
#
# With --push, sends main and the new tag to origin in one atomic push,
# which triggers the release workflow.
set -euo pipefail

readonly VERSION_FILE="Resources/Info.plist"
readonly RELEASE_BRANCH="main"

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    echo "usage: $0 {major|minor|patch} [--push]" >&2
    exit 2
}

cd "$(dirname "$0")/.."

[[ $# -eq 1 || $# -eq 2 ]] || usage
bump_type="$1"
push=false
if [[ $# -eq 2 ]]; then
    [[ "$2" == "--push" ]] || usage
    push=true
fi

current_version="$(python3 -I -c 'import plistlib, sys
with open(sys.argv[1], "rb") as f:
    print(plistlib.load(f)["CFBundleShortVersionString"])' "$VERSION_FILE")"
[[ "$current_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
    || die "unexpected CFBundleShortVersionString in $VERSION_FILE: '$current_version'"
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$bump_type" in
    major) new_version="$((major + 1)).0.0" ;;
    minor) new_version="$major.$((minor + 1)).0" ;;
    patch) new_version="$major.$minor.$((patch + 1))" ;;
    *) usage ;;
esac
readonly tag="v$new_version"

# Refuse to release anything but a clean, pushed main, so the release commit
# contains only the version change and the tag points at published history.
[[ -z "$(git status --porcelain)" ]] \
    || die "the working tree has uncommitted or untracked files"
[[ "$(git symbolic-ref --quiet --short HEAD || true)" == "$RELEASE_BRANCH" ]] \
    || die "releases must be made from $RELEASE_BRANCH"
git fetch --quiet origin "$RELEASE_BRANCH"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$RELEASE_BRANCH")" ]] \
    || die "$RELEASE_BRANCH is not in sync with origin/$RELEASE_BRANCH"
! git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null \
    || die "tag $tag already exists locally"
[[ -z "$(git ls-remote --tags origin "refs/tags/$tag")" ]] \
    || die "tag $tag already exists on origin"

echo "Bumping the version from $current_version to $new_version"
# Edit the string in place so the rest of the file keeps its formatting.
perl -0pi -e \
    's{(<key>CFBundleShortVersionString</key>\s*<string>)\Q'"$current_version"'\E(</string>)}{${1}'"$new_version"'${2}}' \
    "$VERSION_FILE"
scripts/check-tag-version.sh "$tag" "$VERSION_FILE"

git commit --quiet -m "chore: bump version to $new_version" -- "$VERSION_FILE"
git tag "$tag"
echo "Created the commit and tag $tag"

if [[ "$push" == true ]]; then
    git push --atomic origin "$RELEASE_BRANCH" "refs/tags/$tag"
else
    echo "Run 'git push --atomic origin $RELEASE_BRANCH refs/tags/$tag' to publish"
fi
