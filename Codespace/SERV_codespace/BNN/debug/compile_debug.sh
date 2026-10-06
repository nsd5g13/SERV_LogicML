#!/bin/bash

set -e

gcc -O0 debug_bnn_gcc.c helpers.c layer0.c layer1_uint32.c samples_bnn.c -o BNN

echo "Build successful: ./BNN"
