#!/bin/bash
set -euo pipefail

# Make tag configurable via environment variable
GRIDAPPSD_TAG="${GRIDAPPSD_TAG:-:develop}"

# Repository URIs (optional, with defaults)
GOSS_URI="${GOSS_URI:-https://github.com/GRIDAPPSD/GOSS.git}"
GRIDAPPSD_URI="${GRIDAPPSD_URI:-https://github.com/GRIDAPPSD/GOSS-GridAPPS-D.git}"

# Branch variables for cloning (required)
if [ -z "${GOSS_BRANCH:-}" ]; then
  echo "ERROR: GOSS_BRANCH is not set. Please set GOSS_BRANCH environment variable."
  exit 1
fi

if [ -z "${GRIDAPPSD_BRANCH:-}" ]; then
  echo "ERROR: GRIDAPPSD_BRANCH is not set. Please set GRIDAPPSD_BRANCH environment variable."
  exit 1
fi

# Enable BuildKit for better caching and parallel builds
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Clone or update GOSS repository
echo "================================"
echo "Cloning/Updating GOSS"
echo "  URI: $GOSS_URI"
echo "  Branch: $GOSS_BRANCH"
echo "================================"
if [ -d "$SCRIPT_DIR/GOSS" ]; then
  cd "$SCRIPT_DIR/GOSS"
  git fetch origin
  git reset --hard
  git checkout "$GOSS_BRANCH"
  git reset --hard "origin/$GOSS_BRANCH"
  cd "$SCRIPT_DIR"
else
  git clone -b "$GOSS_BRANCH" "$GOSS_URI" "$SCRIPT_DIR/GOSS"
fi

# Clone or update GOSS-GridAPPS-D repository
echo ""
echo "================================"
echo "Cloning/Updating GOSS-GridAPPS-D"
echo "  URI: $GRIDAPPSD_URI"
echo "  Branch: $GRIDAPPSD_BRANCH"
echo "================================"
if [ -d "$SCRIPT_DIR/GOSS-GridAPPS-D" ]; then
  cd "$SCRIPT_DIR/GOSS-GridAPPS-D"
  git fetch origin
  git reset --hard
  git checkout "$GRIDAPPSD_BRANCH"
  git reset --hard "origin/$GRIDAPPSD_BRANCH"
  cd "$SCRIPT_DIR"
else
  git clone -b "$GRIDAPPSD_BRANCH" "$GRIDAPPSD_URI" "$SCRIPT_DIR/GOSS-GridAPPS-D"
fi

echo ""

echo "================================"
echo "Building GridAPPS-D Base Image"
echo "Tag: $GRIDAPPSD_TAG"
echo "================================"

docker build \
  --build-arg GRIDAPPSD_TAG=$GRIDAPPSD_TAG \
  --network=host \
  -f "$SCRIPT_DIR/Dockerfile.gridappsd_base" \
  -t gridappsd/gridappsd_base$GRIDAPPSD_TAG \
  "$SCRIPT_DIR"

echo ""
echo "================================"
echo "Building GridAPPS-D Application Image"
echo "Tag: $GRIDAPPSD_TAG"
echo "================================"

docker build \
  --build-arg GRIDAPPSD_VERSION_LABEL=$GRIDAPPSD_TAG \
  --network=host \
  -f "$SCRIPT_DIR/Dockerfile.gridappsd" \
  -t gridappsd/gridappsd$GRIDAPPSD_TAG \
  "$SCRIPT_DIR"

echo ""
echo "================================"
echo "Build Complete!"
echo "================================"
echo "Images built:"
echo "  - gridappsd/gridappsd_base$GRIDAPPSD_TAG"
echo "  - gridappsd/gridappsd$GRIDAPPSD_TAG"
echo ""

docker build --no-cache \
  --build-arg GRIDAPPSD_TAG=$GRIDAPPSD_TAG \
  --network=host \
  -f Dockerfile.gridappsd_viz \
  -t gridappsd/viz$GRIDAPPSD_TAG .
