#!/usr/bin/env bash
# Claude Code PostToolUse hook (Edit|Write|MultiEdit): reload the edited Lisp
# file into the running game. Silent when the game is not running or the file
# is not game code. On failure exits 2 so Claude sees the compiler or runtime
# error; the game keeps running the old code.

root="$(cd "$(dirname "$0")/.." && pwd)"
file="$(jq -r '.tool_input.file_path // empty')"

case "$file" in
  "$root"/src/*.lisp)      cmd=(reload "${file#"$root"/}") ;;
  "$root"/hexmaw.asd) cmd=(reload-system) ;;
  *) exit 0 ;;
esac

out="$("$root/tools/hd" "${cmd[@]}" 2>&1)"
case $? in
  0)
    jq -n --arg msg "Hot reload: $out" \
       '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
    ;;
  3) exit 0 ;;
  *)
    printf 'Hot reload of %s failed:\n%s\n' "${file#"$root"/}" "$out" >&2
    exit 2
    ;;
esac
