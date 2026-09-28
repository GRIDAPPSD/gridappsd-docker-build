#!/usr/bin/env bash
#
# Create GitHub releases (tag v<VERSION>) across the GridAPPS-D repositories.
#
# Runs as a DRY RUN by default: it checks every repo and prints the release
# notes that would be published. Pass --execute to create the releases.
#
# No release branches are created: merge develop into each repo's release
# branch (master/main) first. The dry run warns when develop has commits that
# are not in the release branch.
#
# Each release is created on the head of the given branch, and its notes are
# GitHub's generated summary of changes since that repo's previous release,
# prefixed with a link to the readthedocs release notes. A repo with no
# previous release gets only the link and a "first release" line.
#
# Docker images: each repo's GitHub workflow builds and pushes its image as
# :v<VERSION> when the release tag is created (gridappsd, viz, sample_app,
# proven, gridappsd_base, ...). The gridappsd/blazegraph image has no workflow,
# so this script copies gridappsd/blazegraph:<from> to :v<VERSION>, :latest,
# :master and :main on Docker Hub (the image is copied by digest, not pulled).
#
# Requires: gh (authenticated with repo write access: `gh auth login`), and
# for blazegraph, docker buildx logged in to Docker Hub (`docker login`).
#
# Usage:
#   create_release.sh [options] VERSION [repo[:branch] ...]
#
# Options:
#   -x, --execute     Create the releases (default is a dry run)
#   -y, --yes         With --execute, do not prompt for confirmation
#   -o, --owner NAME  GitHub owner/organization (default: GRIDAPPSD)
#   --blazegraph-from TAG  Blazegraph image tag to release (default: develop)
#   --no-blazegraph   Do not tag the blazegraph image
#   -h, --help        Show this help
#
# Repos where tag v<VERSION> already exists are skipped, and so is blazegraph
# if gridappsd/blazegraph:v<VERSION> already exists.
#
# If no repos are given, DEFAULT_REPOS below is used. A repo without ":branch"
# is released from its GitHub default branch.
#
# Examples:
#   create_release.sh 2026.09.0                     # dry run, all repos
#   create_release.sh --execute 2026.09.0           # create all releases
#   create_release.sh 2026.09.0 gridappsd-viz gridappsd-docker:main

set -euo pipefail

OWNER="GRIDAPPSD"

DEFAULT_REPOS=(
  GOSS-GridAPPS-D:master
  gridappsd-viz:master
  gridappsd-sample-app:master
  proven-docker:master
  gridappsd-docker-build:master
  gridappsd-data:master
  Powergrid-Models:gridappsd
  gridappsd-sensor-simulator:master
  gridappsd-testing:master
  gridappsd-docker:main
  gridappsd-sample-distributed-app:main
  GLIMPSE:master
)

EXECUTE=false
ASSUME_YES=false
BLAZEGRAPH=true
BG_IMAGE="gridappsd/blazegraph"
BG_FROM="develop"

usage() {
  sed -n '3,/^$/{s/^# \{0,1\}//;p}' "$0"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

row() {
  printf '%-34s %-12s %-9s %-14s %s\n' "$@"
}

# Number of commits in HEAD_REF that are not in BASE_REF, or "?" when GitHub
# cannot compare them (for example, a diff too large to generate).
commits_ahead() {
  local slug=$1 base=$2 head=$3 n
  n=$(gh api "repos/$slug/compare/$base...$head" -q .ahead_by 2>/dev/null || true)
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo "?"
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    -x|--execute) EXECUTE=true ;;
    -y|--yes)     ASSUME_YES=true ;;
    -o|--owner)   [ $# -ge 2 ] || die "$1 needs a value"; OWNER="$2"; shift ;;
    --blazegraph-from) [ $# -ge 2 ] || die "$1 needs a value"; BG_FROM="$2"; shift ;;
    --no-blazegraph)   BLAZEGRAPH=false ;;
    -h|--help)    usage; exit 0 ;;
    -*)           die "unknown option: $1 (see --help)" ;;
    *)            POSITIONAL+=("$1") ;;
  esac
  shift
done

[ ${#POSITIONAL[@]} -ge 1 ] || { usage; exit 1; }

VERSION="${POSITIONAL[0]#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || die "version '$VERSION' should look like 2026.09.0"
TAG="v$VERSION"
TITLE="$VERSION release"
BG_TAGS=("$TAG" latest master main)

if [ ${#POSITIONAL[@]} -gt 1 ]; then
  REPOS=("${POSITIONAL[@]:1}")
else
  REPOS=("${DEFAULT_REPOS[@]}")
fi

command -v gh >/dev/null || die "gh (GitHub CLI) is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login'"

# readthedocs anchor: 2026.09.0 -> version-2026-09-0
DOCS_URL="https://gridappsd.readthedocs.io/en/master/overview/index.html#version-${VERSION//./-}"

# ---------------------------------------------------------------------------
# Preflight: validate every repo before anything is created
# ---------------------------------------------------------------------------
# Parallel arrays, one entry per repo to release
P_REPO=(); P_BRANCH=(); P_SHA=(); P_PREV=()
SKIPPED=()
ERRORS=()

echo "Release $TAG for $OWNER ($([ "$EXECUTE" = true ] && echo "EXECUTE" || echo "dry run"))"
echo
row REPO BRANCH COMMIT PREVIOUS STATUS
row ---- ------ ------ -------- ------

for entry in "${REPOS[@]}"; do
  repo="${entry%%:*}"
  slug="$OWNER/$repo"
  branch=""
  [ "$entry" != "$repo" ] && branch="${entry#*:}"

  if ! default_branch=$(gh repo view "$slug" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null); then
    ERRORS+=("$repo: repository not found or not accessible")
    row "$repo" "${branch:--}" - - "ERROR: not found"
    continue
  fi
  branch="${branch:-$default_branch}"

  if ! sha=$(gh api "repos/$slug/branches/$branch" -q .commit.sha 2>/dev/null); then
    ERRORS+=("$repo: branch '$branch' does not exist")
    row "$repo" "$branch" - - "ERROR: no branch"
    continue
  fi

  # Skip if the tag already exists (released or not), or a draft release
  # already claims it.
  if gh api "repos/$slug/git/ref/tags/$TAG" >/dev/null 2>&1; then
    SKIPPED+=("$repo")
    row "$repo" "$branch" "${sha:0:7}" - "skip: tag $TAG already exists"
    continue
  fi
  if gh release view "$TAG" -R "$slug" >/dev/null 2>&1; then
    SKIPPED+=("$repo")
    row "$repo" "$branch" "${sha:0:7}" - "skip: release $TAG already exists"
    continue
  fi

  prev=$(gh release view -R "$slug" --json tagName -q .tagName 2>/dev/null || true)
  if [ -n "$prev" ]; then
    ahead=$(commits_ahead "$slug" "$prev" "$sha")
    status="ok, $ahead commits since $prev"
    [ "$ahead" = "0" ] && status="ok (warning: no commits since $prev)"
  else
    status="ok (no previous GitHub release)"
  fi

  # Releases are cut from the branch directly (no release branches), so
  # develop should already be merged into it.
  if [ "$branch" != "develop" ]; then
    if gh api "repos/$slug/branches/develop" >/dev/null 2>&1; then
      unmerged=$(commits_ahead "$slug" "$sha" develop)
      if [ "$unmerged" = "?" ]; then
        status="$status; warning: could not compare develop with $branch"
      elif [ "$unmerged" != "0" ]; then
        status="$status; warning: develop has $unmerged commits not in $branch"
      fi
    fi
  fi

  P_REPO+=("$repo"); P_BRANCH+=("$branch"); P_SHA+=("$sha"); P_PREV+=("$prev")
  row "$repo" "$branch" "${sha:0:7}" "${prev:--}" "$status"
done

# Blazegraph: resolve the source image to a digest so the image tagged at
# release time is the one checked here.
BG_TODO=false
BG_DIGEST=""
if [ "$BLAZEGRAPH" = true ]; then
  if ! docker buildx version >/dev/null 2>&1; then
    ERRORS+=("$BG_IMAGE: docker buildx is not available (use --no-blazegraph to skip)")
    row "$BG_IMAGE" "$BG_FROM" - - "ERROR: no docker buildx"
  elif docker buildx imagetools inspect "$BG_IMAGE:$TAG" >/dev/null 2>&1; then
    SKIPPED+=("$BG_IMAGE")
    row "$BG_IMAGE" "$BG_FROM" - - "skip: $BG_IMAGE:$TAG already exists"
  elif ! BG_DIGEST=$(docker buildx imagetools inspect "$BG_IMAGE:$BG_FROM" 2>/dev/null \
                       | awk '/^Digest:/ {print $2; exit}') || [ -z "$BG_DIGEST" ]; then
    ERRORS+=("$BG_IMAGE: source image $BG_IMAGE:$BG_FROM not found")
    row "$BG_IMAGE" "$BG_FROM" - - "ERROR: source image not found"
  else
    BG_TODO=true
    bg_digest_short="${BG_DIGEST#sha256:}"
    row "$BG_IMAGE" "$BG_FROM" "${bg_digest_short:0:7}" - "ok, tag as ${BG_TAGS[*]}"
  fi
fi

echo
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "Preflight failed; nothing was created:" >&2
  printf '  - %s\n' "${ERRORS[@]}" >&2
  exit 1
fi

if [ ${#P_REPO[@]} -eq 0 ] && [ "$BG_TODO" != true ]; then
  echo "Nothing to do: $TAG already exists everywhere."
  exit 0
fi

# ---------------------------------------------------------------------------
# Release notes: generated once and used for both the dry run and the release,
# so the dry run shows exactly what will be published.
# ---------------------------------------------------------------------------
release_notes() {
  local repo=$1 sha=$2 prev=$3
  # With no previous release in this repo, GitHub would compare against any
  # older tag (for a fork, one copied from upstream), so skip the summary.
  if [ -z "$prev" ]; then
    printf 'See %s for release notes.\n\nFirst GridAPPS-D release of %s.\n' "$DOCS_URL" "$repo"
    return
  fi
  local generated
  generated=$(gh api "repos/$OWNER/$repo/releases/generate-notes" \
    -f "tag_name=$TAG" -f "target_commitish=$sha" -f "previous_tag_name=$prev" -q .body)
  printf 'See %s for release notes.\n\n%s\n' "$DOCS_URL" "$generated"
}

if [ "$EXECUTE" != true ]; then
  for i in "${!P_REPO[@]}"; do
    echo "================================================================"
    echo "$OWNER/${P_REPO[$i]}  $TAG  at ${P_BRANCH[$i]} (${P_SHA[$i]:0:7})"
    echo "Title: $TITLE"
    echo "----------------------------------------------------------------"
    release_notes "${P_REPO[$i]}" "${P_SHA[$i]}" "${P_PREV[$i]}"
  done
  if [ "$BG_TODO" = true ]; then
    echo "================================================================"
    echo "Docker Hub: $BG_IMAGE:$BG_FROM ($BG_DIGEST)"
    echo "  would be tagged as: ${BG_TAGS[*]}"
  fi
  echo "================================================================"
  echo "Dry run: ${#P_REPO[@]} release(s) would be created$([ "$BG_TODO" = true ] && echo " and blazegraph tagged"), ${#SKIPPED[@]} skipped."
  echo "Rerun with --execute to create them."
  exit 0
fi

# ---------------------------------------------------------------------------
# Create releases
# ---------------------------------------------------------------------------
if [ "$ASSUME_YES" != true ]; then
  prompt="Create ${#P_REPO[@]} release(s) tagged $TAG"
  [ "$BG_TODO" = true ] && prompt="$prompt and push $BG_IMAGE tags (${BG_TAGS[*]})"
  read -r -p "$prompt? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted; nothing was created."; exit 1; }
fi

CREATED=(); FAILED=()
for i in "${!P_REPO[@]}"; do
  repo="${P_REPO[$i]}"
  # Release the exact commit checked in preflight, not whatever the branch
  # points to now.
  if notes=$(release_notes "$repo" "${P_SHA[$i]}" "${P_PREV[$i]}") \
     && url=$(printf '%s' "$notes" | gh release create "$TAG" \
                -R "$OWNER/$repo" \
                --target "${P_SHA[$i]}" \
                --title "$TITLE" \
                --notes-file -); then
    CREATED+=("$url")
    echo "created  $url"
  else
    FAILED+=("$repo")
    echo "FAILED   $OWNER/$repo" >&2
  fi
done

if [ "$BG_TODO" = true ]; then
  bg_args=()
  for t in "${BG_TAGS[@]}"; do bg_args+=(-t "$BG_IMAGE:$t"); done
  if docker buildx imagetools create "${bg_args[@]}" "$BG_IMAGE@$BG_DIGEST"; then
    CREATED+=("$BG_IMAGE")
    echo "tagged   $BG_IMAGE@$BG_DIGEST as ${BG_TAGS[*]}"
  else
    FAILED+=("$BG_IMAGE")
    echo "FAILED   $BG_IMAGE (is docker logged in to Docker Hub?)" >&2
  fi
fi

echo
echo "Created ${#CREATED[@]}, skipped ${#SKIPPED[@]}, failed ${#FAILED[@]}."
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "Fix the failures and rerun the same command; completed items are skipped." >&2
  exit 1
fi
