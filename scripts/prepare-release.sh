#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/prepare-release.sh [--push] patch|minor|major

Bumps the semantic version and build number, updates CHANGELOG.md,
creates a release commit, and creates an annotated git tag.
Pass --push to also push the current branch and the new tag to origin.
EOF
}

if (($# < 1 || $# > 2)); then
  usage >&2
  exit 1
fi

BUMP_KIND=""
PUSH_TO_REMOTE="false"

for arg in "$@"; do
  case "$arg" in
    patch|minor|major)
      if [[ -n "$BUMP_KIND" ]]; then
        usage >&2
        exit 1
      fi
      BUMP_KIND="$arg"
      ;;
    --push)
      PUSH_TO_REMOTE="true"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$BUMP_KIND" ]]; then
  usage >&2
  exit 1
fi

assert_push_remote_ready() {
  git remote get-url origin >/dev/null 2>&1 || {
    echo "Cannot push release: git remote 'origin' is not configured." >&2
    exit 1
  }

  CURRENT_BRANCH="$(git branch --show-current)"
  [[ -n "$CURRENT_BRANCH" ]] || {
    echo "Cannot push release from a detached HEAD. Check out the target branch and try again." >&2
    exit 1
  }
}

push_release_refs() {
  git push origin "$CURRENT_BRANCH"
  git push origin "$NEXT_TAG"
}

case "$BUMP_KIND" in
  patch|minor|major) ;;
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
  local dirty_status
  dirty_status="$(git status --short)"

  if [[ -n "$dirty_status" ]]; then
    echo "Release preparation requires a clean git working tree." >&2
    echo "Dirty paths:" >&2
    printf '%s\n' "$dirty_status" >&2
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

extract_section_items() {
  local heading="$1"
  local body="$2"

  printf '%s\n' "$body" |
    awk -v heading="$heading" '
      $0 == "### " heading {in_section=1; next}
      /^### / && in_section {exit}
      in_section {print}
    ' |
    sanitize_release_body |
    sed '/^[[:space:]]*$/d'
}

normalize_note_line() {
  local line="$1"

  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "$line" ]] || return 0

  if [[ "$line" != -\ * ]]; then
    line="- $line"
  fi

  printf '%s\n' "$line"
}

canonicalize_note() {
  printf '%s' "$1" |
    sed -E \
      -e 's/^[[:space:]]*-[[:space:]]*//' \
      -e 's/[[:space:]]+$//' \
      -e 's/[[:punct:]]+$//' |
    tr '[:upper:]' '[:lower:]'
}

dedupe_note_lines() {
  local note_lines="$1"
  local line normalized canonical
  local -A seen=()

  while IFS= read -r line; do
    normalized="$(normalize_note_line "$line")"
    [[ -n "$normalized" ]] || continue

    canonical="$(canonicalize_note "$normalized")"
    [[ -n "$canonical" ]] || continue

    if [[ -z "${seen[$canonical]-}" ]]; then
      seen[$canonical]=1
      printf '%s\n' "$normalized"
    fi
  done <<< "$note_lines"
}

section_for_commit_subject() {
  local subject="$1"

  case "$subject" in
    feat:*|feat\(*\):*)
      printf 'Added\n'
      ;;
    fix:*|fix\(*\):*)
      printf 'Fixed\n'
      ;;
    *)
      printf 'Changed\n'
      ;;
  esac
}

format_commit_subject() {
  local subject="$1"

  subject="$(
    printf '%s' "$subject" |
      sed -E 's/^(feat|fix|docs|chore|refactor|perf|test|ci|build|style)(\([^)]+\))?!?:[[:space:]]*//'
  )"

  printf '%s\n' "$subject"
}

draft_release_sections_from_git() {
  local latest_tag
  local -a commit_subjects
  local subject section note

  GIT_ADDED_ITEMS=""
  GIT_CHANGED_ITEMS=""
  GIT_FIXED_ITEMS=""

  latest_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"

  if [[ -n "$latest_tag" ]]; then
    commit_subjects=("${(@f)$(git log --format='%s' --reverse "${latest_tag}..HEAD")}")
  else
    commit_subjects=("${(@f)$(git log --format='%s' --reverse)}")
  fi

  if ((${#commit_subjects[@]} == 0)); then
    GIT_CHANGED_ITEMS="- Maintenance release."
    return
  fi

  for subject in "${commit_subjects[@]}"; do
    [[ -n "$subject" ]] || continue

    note="$(format_commit_subject "$subject")"
    section="$(section_for_commit_subject "$subject")"

    case "$section" in
      Added)
        if [[ -n "$GIT_ADDED_ITEMS" ]]; then
          GIT_ADDED_ITEMS+=$'\n'
        fi
        GIT_ADDED_ITEMS+="$note"
        ;;
      Changed)
        if [[ -n "$GIT_CHANGED_ITEMS" ]]; then
          GIT_CHANGED_ITEMS+=$'\n'
        fi
        GIT_CHANGED_ITEMS+="$note"
        ;;
      Fixed)
        if [[ -n "$GIT_FIXED_ITEMS" ]]; then
          GIT_FIXED_ITEMS+=$'\n'
        fi
        GIT_FIXED_ITEMS+="$note"
        ;;
    esac
  done
}

build_release_body() {
  local unreleased_body="$1"
  local manual_added manual_changed manual_fixed
  local combined_added combined_changed combined_fixed

  draft_release_sections_from_git

  manual_added="$(extract_section_items "Added" "$unreleased_body")"
  manual_changed="$(extract_section_items "Changed" "$unreleased_body")"
  manual_fixed="$(extract_section_items "Fixed" "$unreleased_body")"

  combined_added="$(dedupe_note_lines "$(printf '%s\n%s\n' "$manual_added" "$GIT_ADDED_ITEMS")")"
  combined_changed="$(dedupe_note_lines "$(printf '%s\n%s\n' "$manual_changed" "$GIT_CHANGED_ITEMS")")"
  combined_fixed="$(dedupe_note_lines "$(printf '%s\n%s\n' "$manual_fixed" "$GIT_FIXED_ITEMS")")"

  if [[ -n "$combined_added" ]]; then
    printf '### Added\n\n%s\n' "$combined_added"
  fi

  if [[ -n "$combined_changed" ]]; then
    if [[ -n "$combined_added" ]]; then
      printf '\n'
    fi
    printf '### Changed\n\n%s\n' "$combined_changed"
  fi

  if [[ -n "$combined_fixed" ]]; then
    if [[ -n "$combined_added$combined_changed" ]]; then
      printf '\n'
    fi
    printf '### Fixed\n\n%s\n' "$combined_fixed"
  fi

  if [[ -z "$combined_added$combined_changed$combined_fixed" ]]; then
    printf '### Changed\n\n- Maintenance release.\n'
  fi
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

if [[ "$PUSH_TO_REMOTE" == "true" ]]; then
  assert_push_remote_ready
fi

CHANGELOG_HEADER="$(extract_header)"
UNRELEASED_BODY="$(extract_unreleased_body)"
RELEASED_SECTIONS="$(extract_released_sections)"
RELEASE_BODY="$(build_release_body "$UNRELEASED_BODY")"

[[ -n "${RELEASE_BODY//[$'\n\r\t ']}" ]] || RELEASE_BODY=$'### Changed\n\n- Maintenance release.'

write_version_file "$NEXT_VERSION" "$NEXT_BUILD"
write_changelog "$NEXT_VERSION" "$RELEASE_BODY" "$CHANGELOG_HEADER" "$RELEASED_SECTIONS"

git add -- "$VERSION_FILE" "$CHANGELOG_FILE"
git commit -m "Release ${NEXT_TAG}"
git tag -a "$NEXT_TAG" -m "Release ${NEXT_TAG}"

if [[ "$PUSH_TO_REMOTE" == "true" ]]; then
  push_release_refs
fi

if [[ "$PUSH_TO_REMOTE" == "true" ]]; then
  cat <<EOF
Prepared ${NEXT_TAG} and pushed it to origin

Pushed:
  branch: ${CURRENT_BRANCH}
  tag: ${NEXT_TAG}

Next steps:
  make release-dry-run
  make release
EOF
  exit 0
fi

cat <<EOF
Prepared ${NEXT_TAG}

Next steps:
  git push
  git push --tags
  make archive
  make dmg
  make release-dry-run
EOF
