#!/bin/bash

set -e

gcc -O0 main_bnn.c helpers.c layer0.c layer1_uint32.c samples_bnn.c -o bnn

echo "Build successful: ./bnn"
