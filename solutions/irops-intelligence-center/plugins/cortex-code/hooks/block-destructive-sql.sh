#!/usr/bin/env bash
# PreToolUse(Bash) safety guard: block destructive SQL outside the scratch namespace.
# Allows scoped DROP/TRUNCATE/DELETE on the IROP scratch objects (IROP_SCRATCH.*) that
# teardown needs, but blocks any destructive statement not clearly scoped to them.
# Reads hook JSON from stdin. Exit 2 to block; exit 0 to allow. Fail-open if jq is missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
[[ -z "$cmd" ]] && exit 0

upper=$(printf '%s' "$cmd" | tr '[:lower:]' '[:upper:]')

# Is this a destructive statement?
if printf '%s' "$upper" | grep -qE '\b(DROP|TRUNCATE|DELETE)\b'; then
  # Allow only if it is scoped to the scratch namespace.
  if printf '%s' "$upper" | grep -qE 'IROP_SCRATCH'; then
    exit 0
  fi
  jq -n '{decision:"block", systemMessage:"Blocked: destructive SQL (DROP/TRUNCATE/DELETE) must be scoped to the scratch namespace (IROP_SCRATCH.*). Refusing an unscoped destructive statement against IROP_DB or any governed object."}'
  exit 2
fi
exit 0
