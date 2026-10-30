#!/usr/bin/env bash
# Start the game with the dev eval server on 127.0.0.1:${HEXMAW_EVAL_PORT:-7171}.
# Set HEXMAW_SWANK_PORT=4005 to also start Swank for an editor to connect to.
cd "$(dirname "$0")" || exit 1
# A checkout's .eval-port (gitignored) picks its port, as it does for tools/hd.
[ -z "$HEXMAW_EVAL_PORT" ] && [ -f .eval-port ] && export HEXMAW_EVAL_PORT="$(cat .eval-port)"
exec sbcl --dynamic-space-size 4096 --noinform --no-userinit --disable-debugger \
     --load boot.lisp \
     --eval '(hexmaw::dev-launch)'
