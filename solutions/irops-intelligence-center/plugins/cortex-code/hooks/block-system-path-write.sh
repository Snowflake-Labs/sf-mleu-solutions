#!/usr/bin/env bash
# PreToolUse(Write|Edit) safety guard: block writes to system / out-of-project paths.
# The plugin lifecycle skills should only write inside the plugin package and a scratch
# working area — never to system locations. Reads hook JSON from stdin.
# Exit 2 to block; exit 0 to allow. Fail-open if jq is missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // ""')
[[ -z "$path" ]] && exit 0

case "$path" in
  /etc/*|/usr/*|/bin/*|/sbin/*|/System/*|/Library/*|/boot/*|/var/root/*|/root/*)
    jq -n '{decision:"block", systemMessage:"Blocked: refusing to write to a system path. Writes must stay within the plugin package or the scratch working directory."}'
    exit 2
    ;;
  *.ssh/*|*/.aws/*|*/.config/gcloud/*)
    jq -n '{decision:"block", systemMessage:"Blocked: refusing to write to a credentials/config path."}'
    exit 2
    ;;
esac
exit 0
