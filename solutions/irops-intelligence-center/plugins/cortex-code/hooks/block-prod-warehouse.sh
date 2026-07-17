#!/usr/bin/env bash
# PreToolUse(Bash) safety guard: block SQL that could target a production warehouse or use ACCOUNTADMIN.
# The lifecycle skills (setup/deploy/teardown) must only touch the scratch warehouses
# IROP_OTP_WH / IROP_ML_WH / IROP_OCC_WH. Reads hook JSON from stdin. Exit 2 to block; exit 0 to allow.
# Fail-open if jq is missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
[[ -z "$cmd" ]] && exit 0

upper=$(printf '%s' "$cmd" | tr '[:lower:]' '[:upper:]')

# Never allow ACCOUNTADMIN.
if printf '%s' "$upper" | grep -q 'ACCOUNTADMIN'; then
  jq -n '{decision:"block", systemMessage:"Blocked: ACCOUNTADMIN must never be used. Use SYSADMIN + the scoped IROP_OCC_ROLE / IROP_AI_ROLE."}'
  exit 2
fi

# If the command names a warehouse, it must be one of the scratch warehouses.
if printf '%s' "$upper" | grep -qE 'WAREHOUSE'; then
  if ! printf '%s' "$upper" | grep -qE 'IROP_OTP_WH|IROP_ML_WH|IROP_OCC_WH'; then
    jq -n '{decision:"block", systemMessage:"Blocked: lifecycle skills may only target the scratch warehouses IROP_OTP_WH / IROP_ML_WH / IROP_OCC_WH, not a production warehouse."}'
    exit 2
  fi
fi
exit 0
