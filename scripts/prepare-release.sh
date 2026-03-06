#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/prepare-release.sh patch|minor|major

Bumps the semantic version and build number, updates CHANGELOG.md,
creates a release commit, and creates an annotated git tag.
EOF
}

if (($# != 1)); then
  usage >&2
  exit 1
fi

BUMP_KIND="$1"

case "$BUMP_KIND" in
  patch|minor|major) ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to prepare a release." >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Run this command from inside the Nomad Dashboard git repository." >&2
  exit 1
}

cd "$REPO_ROOT"

VERSION_FILE="Config/Version.xcconfig"
CHANGELOG_FILE="CHANGELOG.md"
RELEASE_DATE="$(date +%F)"

default_changelog_header() {
  cat <<'EOF'
# Changelog

All notable changes to Nomad Dashboard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/).
EOF
}

empty_unreleased_body() {
  cat <<'EOF'
### Added

- _Nothing yet_

### Changed

- _Nothing yet_

### Fixed

- _Nothing yet_
EOF
}

read_xcconfig_value() {
  local key="$1"
  sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" "$VERSION_FILE" | head -n 1
}

assert_clean_worktree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Release preparation requires a clean git working tree." >&2
    echo "Commit, stash, or discard your changes, then run the command again." >&2
    exit 1
  fi
}

extract_header() {
  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    default_changelog_header
    return
  fi

  awk '
    /^## \[Unreleased\]/ {exit}
    {print}
  ' "$CHANGELOG_FILE"
}

extract_unreleased_body() {
  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    empty_unreleased_body
    return
  fi

  awk '
    /^## \[Unreleased\]/ {in_section=1; next}
    /^## \[/ && in_section {exit}
    in_section {print}
  ' "$CHANGELOG_FILE"
}

extract_released_sections() {
  [[ -f "$CHANGELOG_FILE" ]] || return

  awk '
    /^## \[Unreleased\]/ {in_unreleased=1; next}
    in_unreleased && /^## \[/ {in_unreleased=0; printing=1}
    printing {print}
  ' "$CHANGELOG_FILE"
}

sanitize_release_body() {
  sed '/^[[:space:]]*-[[:space:]]*_Nothing yet_[[:space:]]*$/d'
}

unreleased_has_content() {
  local body="$1"
  local normalized

  normalized="$(
    printf '%s\n' "$body" |
      sed \
        -e '/^[[:space:]]*$/d' \
        -e '/^[[:space:]]*###[[:space:]].*$/d' \
        -e '/^[[:space:]]*-[[:space:]]*_Nothing yet_[[:space:]]*$/d'
  )"

  [[ -n "$normalized" ]]
}

draft_release_body_from_git() {
  local latest_tag
  local -a commit_subjects

  latest_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"

  if [[ -n "$latest_tag" ]]; then
    commit_subjects=("${(@f)$(git log --format='%s' --reverse "${latest_tag}..HEAD")}")
  else
    commit_subjects=("${(@f)$(git log --format='%s' --reverse)}")
  fi

  printf '### Changed\n\n'

  if ((${#commit_subjects[@]} == 0)); then
    printf '%s\n' "- Maintenance release."
    return
  fi

  local subject
  for subject in "${commit_subjects[@]}"; do
    [[ -n "$subject" ]] || continue
    printf -- '- %s\n' "$subject"
  done
}

write_version_file() {
  local version="$1"
  local build="$2"

  cat > "$VERSION_FILE" <<EOF
MARKETING_VERSION = $version
CURRENT_PROJECT_VERSION = $build
EOF
}

write_changelog() {
  local version="$1"
  local body="$2"
  local header="$3"
  local released_sections="$4"

  {
    printf '%s\n\n' "$header"
    printf '## [Unreleased]\n\n'
    empty_unreleased_body
    printf '\n\n'
    printf '## [%s] - %s\n\n' "$version" "$RELEASE_DATE"
    printf '%s\n' "$body"

    if [[ -n "$released_sections" ]]; then
      printf '\n%s\n' "$released_sections"
    fi
  } > "$CHANGELOG_FILE"
}

assert_clean_worktree

[[ -f "$VERSION_FILE" ]] || {
  echo "Missing $VERSION_FILE." >&2
  exit 1
}

CURRENT_VERSION="$(read_xcconfig_value MARKETING_VERSION)"
CURRENT_BUILD="$(read_xcconfig_value CURRENT_PROJECT_VERSION)"

if [[ "$CURRENT_VERSION" != <->.<->.<-> ]]; then
  echo "Expected MARKETING_VERSION in semantic version form, found '$CURRENT_VERSION'." >&2
  exit 1
fi

if [[ "$CURRENT_BUILD" != <-> ]]; then
  echo "Expected CURRENT_PROJECT_VERSION to be an integer, found '$CURRENT_BUILD'." >&2
  exit 1
fi

IFS='.' read -r CURRENT_MAJOR CURRENT_MINOR CURRENT_PATCH <<< "$CURRENT_VERSION"

case "$BUMP_KIND" in
  patch)
    NEXT_MAJOR="$CURRENT_MAJOR"
    NEXT_MINOR="$CURRENT_MINOR"
    NEXT_PATCH="$((CURRENT_PATCH + 1))"
    ;;
  minor)
    NEXT_MAJOR="$CURRENT_MAJOR"
    NEXT_MINOR="$((CURRENT_MINOR + 1))"
    NEXT_PATCH=0
    ;;
  major)
    NEXT_MAJOR="$((CURRENT_MAJOR + 1))"
    NEXT_MINOR=0
    NEXT_PATCH=0
    ;;
esac

NEXT_VERSION="${NEXT_MAJOR}.${NEXT_MINOR}.${NEXT_PATCH}"
NEXT_BUILD="$((CURRENT_BUILD + 1))"
NEXT_TAG="v${NEXT_VERSION}"

if git rev-parse -q --verify "refs/tags/${NEXT_TAG}" >/dev/null 2>&1; then
  echo "Tag ${NEXT_TAG} already exists." >&2
  exit 1
fi

CHANGELOG_HEADER="$(extract_header)"
UNRELEASED_BODY="$(extract_unreleased_body)"
RELEASED_SECTIONS="$(extract_released_sections)"

if unreleased_has_content "$UNRELEASED_BODY"; then
  RELEASE_BODY="$(printf '%s\n' "$UNRELEASED_BODY" | sanitize_release_body)"
else
  RELEASE_BODY="$(draft_release_body_from_git)"
fi

[[ -n "${RELEASE_BODY//[$'\n\r\t ']}" ]] || RELEASE_BODY=$'### Changed\n\n- Maintenance release.'

write_version_file "$NEXT_VERSION" "$NEXT_BUILD"
write_changelog "$NEXT_VERSION" "$RELEASE_BODY" "$CHANGELOG_HEADER" "$RELEASED_SECTIONS"

git add -- "$VERSION_FILE" "$CHANGELOG_FILE"
git commit -m "Release ${NEXT_TAG}"
git tag -a "$NEXT_TAG" -m "Release ${NEXT_TAG}"

cat <<EOF
Prepared ${NEXT_TAG}

Next steps:
  git push
  git push --tags
  make archive
  make dmg
  make release-dry-run
EOF

