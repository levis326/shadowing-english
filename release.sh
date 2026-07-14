#!/usr/bin/env bash

set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || die "Usage: scripts/release.sh vMAJOR.MINOR.PATCH"

tag="$1"
tag="v${tag#v}"
version="${tag#v}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  die "Version must be vMAJOR.MINOR.PATCH, for example v0.1.5."

[[ -f pubspec.yaml ]] || die "Run this script from the repository root."
[[ -z "$(git status --porcelain)" ]] || die "Working tree must be clean."

version_changed=false
committed=false
cleanup() {
  if [[ "$version_changed" == true && "$committed" == false ]]; then
    git restore -- pubspec.yaml
  fi
}
trap cleanup EXIT

branch="$(git branch --show-current)"
[[ -n "$branch" ]] || die "Cannot release from a detached HEAD."

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "Local tag $tag already exists."
fi
if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  die "Remote tag $tag already exists."
fi

current_version="$(sed -nE 's/^version: ([^[:space:]]+).*/\1/p' pubspec.yaml)"
[[ -n "$current_version" ]] || die "Cannot read the version from pubspec.yaml."
current_name="${current_version%%+*}"
current_build="${current_version#*+}"
[[ "$current_build" != "$current_version" ]] || current_build=0

IFS=. read -r current_major current_minor current_patch <<< "$current_name"
IFS=. read -r next_major next_minor next_patch <<< "$version"
if (( next_major < current_major ||
    (next_major == current_major && next_minor < current_minor) ||
    (next_major == current_major && next_minor == current_minor && next_patch <= current_patch) )); then
  die "Version $tag must be newer than v$current_name."
fi

next_build=$((current_build + 1))
next_version="$version+$next_build"

sed -i.bak -E "s/^version: .*/version: $next_version/" pubspec.yaml
rm pubspec.yaml.bak
version_changed=true

flutter_bin="flutter"
if [[ -x .fvm/flutter_sdk/bin/flutter ]]; then
  flutter_bin=".fvm/flutter_sdk/bin/flutter"
fi

"$flutter_bin" analyze --no-pub
"$flutter_bin" test

git add pubspec.yaml
git commit -m "chore: release $tag"
committed=true
git tag "$tag"
git push origin "$branch" "$tag"

echo "Published $tag with app version $next_version."
