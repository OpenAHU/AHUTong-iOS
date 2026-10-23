#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: upload-sentry-symbols.sh <dSYM directory>" >&2
  exit 2
fi

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "::warning::SENTRY_AUTH_TOKEN is not configured; debug symbols remain in the build artifact."
  exit 0
fi

if [[ ! -d "$1" ]]; then
  echo "Debug symbol directory is missing." >&2
  exit 2
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "sentry-cli must be installed before uploading debug symbols." >&2
  exit 2
fi

shopt -s nullglob
symbols=("$1"/*.dSYM)
if [[ ${#symbols[@]} -eq 0 ]]; then
  echo "No dSYM bundles were produced for this build." >&2
  exit 2
fi

# The credential is read from the environment, never a command-line argument.
# Upload symbol files only; do not bundle source files with --include-sources.
sentry-cli debug-files upload \
  --org "${SENTRY_ORG:-ratatoskr}" \
  --project "${SENTRY_PROJECT:-ahutong-ios}" \
  --wait "${symbols[@]}"
