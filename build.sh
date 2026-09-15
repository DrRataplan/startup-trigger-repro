#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build
rm -f build/startup-trigger-repro.xar
( cd pkg && jar cfM0 ../build/startup-trigger-repro.xar . )
echo "built build/startup-trigger-repro.xar"
