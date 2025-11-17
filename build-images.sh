#!/bin/bash

# Note this does not export this and it is not
# set into the context of the container without passing as an argument
GRIDAPPSD_TAG=":rc2"

docker build --no-cache \
  --build-arg GRIDAPPSD_TAG=$GRIDAPPSD_TAG \
  --network=host \
  -f Dockerfile.gridappsd_base \
  -t gridappsd/gridappsd_base$GRIDAPPSD_TAG .

docker build --no-cache \
  --build-arg GRIDAPPSD_TAG=$GRIDAPPSD_TAG \
  --network=host \
  -f Dockerfile.gridappsd \
  -t gridappsd/gridappsd$GRIDAPPSD_TAG .

# docker build --no-cache \
#   --build-arg GRIDAPPSD_TAG=$GRIDAPPSD_TAG \
#   --network=host \
#   -f Dockerfile.gridappsd_viz \
#   -t gridappsd/viz$GRIDAPPSD_TAG .
