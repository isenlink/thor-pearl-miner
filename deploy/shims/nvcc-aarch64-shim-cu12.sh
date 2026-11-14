#!/bin/bash
exec /usr/local/cuda-12.8/bin/nvcc -ccbin /usr/bin/aarch64-linux-gnu-g++ "$@"
