#!/usr/bin/env bash
# Build the standalone game into dist/ (tools/build-dist); run it with dist/hexmaw.
exec "$(dirname "$0")/tools/build-dist" "$@"
