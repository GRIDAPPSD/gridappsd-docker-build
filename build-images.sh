#!/bin/bash
set -euo pipefail

# Make tag configurable via environment variable
GRIDAPPSD_TAG="${GRIDAPPSD_TAG:-:develop}"

# Enable BuildKit for better caching and parallel builds
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

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
  "$PARENT_DIR"

echo ""
echo "================================"
echo "Build Complete!"
echo "================================"
echo "Images built:"
echo "  - gridappsd/gridappsd_base$GRIDAPPSD_TAG"
echo "  - gridappsd/gridappsd$GRIDAPPSD_TAG"
echo ""

# docker build --no-cache \
#   --build-arg GRIDAPPSD_TAG=$GRIDAPPSD_TAG \
#   --network=host \
#   -f Dockerfile.gridappsd_viz \
#   -t gridappsd/viz$GRIDAPPSD_TAG .
