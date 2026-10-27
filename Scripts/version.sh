#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 <major|minor|patch>" >&2
    exit 1
fi
case "$1" in
    major|minor|patch) ;;
    *) echo 'Usage: just version <major|minor|patch>' >&2; exit 1 ;;
esac

if [[ $(git branch --show-current) != main || -n $(git status --porcelain --untracked-files=all) ]]; then
    echo 'Release from a clean main checkout with all changes committed.' >&2
    exit 1
fi
git fetch --tags origin refs/heads/main:refs/remotes/origin/main
source=$(git rev-parse HEAD)
if [[ "$source" != $(git rev-parse refs/remotes/origin/main) ]]; then
    echo 'Push or synchronize main with origin/main before releasing.' >&2
    exit 1
fi

current=$(cat VERSION)
if [[ ! "$current" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo 'VERSION must contain a semantic version such as 0.1.0.' >&2
    exit 1
fi
major=${BASH_REMATCH[1]}; minor=${BASH_REMATCH[2]}; patch=${BASH_REMATCH[3]}
case "$1" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
esac
next="$major.$minor.$patch"
tag="v$next"
if git show-ref --verify --quiet "refs/tags/$tag"; then
    echo "Tag $tag already exists." >&2
    exit 1
fi

read -r -p "Release $current → $next, commit VERSION, and push main + $tag to origin? [y/N] " answer || answer=
case "$answer" in
    y|Y|yes|YES|Yes) ;;
    *) echo 'Cancelled.'; exit 0 ;;
esac
if [[ $(git branch --show-current) != main || $(git rev-parse HEAD) != "$source" || -n $(git status --porcelain --untracked-files=all) ]]; then
    echo 'Checkout changed; retry the release.' >&2
    exit 1
fi
printf '%s\n' "$next" > VERSION
git commit --only -m "chore: release $tag" -- VERSION
commit=$(git rev-parse HEAD)
git tag -a "$tag" -m "chore: release $tag" "$commit"
if ! git push --atomic origin "$commit:refs/heads/main" "refs/tags/$tag:refs/tags/$tag"; then
    echo 'Push failed; the local release commit and tag have been retained. Resolve the failure and retry:' >&2
    printf 'git push --atomic origin %s:refs/heads/main refs/tags/%s:refs/tags/%s\n' "$commit" "$tag" "$tag" >&2
    exit 1
fi
