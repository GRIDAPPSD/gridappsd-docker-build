#!/bin/bash
export PATH=/gridappsd/services/fncsgossbridge/service:$PATH

cd /gridappsd

java -jar gridappsd-launcher.jar
# &> /tmp/gridappsd/gridappsd.log
