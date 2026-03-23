#!/usr/bin/env bash
set -euo pipefail

# Git Bash wrapper for PowerShell runner.
# Usage examples:
#   ./run.sh
#   ./run.sh -ConfigPath ./k6/config.json -NoPrompt

if command -v pwsh >/dev/null 2>&1; then
  PS_CMD="pwsh"
elif command -v powershell.exe >/dev/null 2>&1; then
  PS_CMD="powershell.exe"
else
  echo "PowerShell not found (pwsh or powershell.exe)." >&2
  exit 1
fi

exec "$PS_CMD" -ExecutionPolicy Bypass -File "./run.ps1" "$@"

