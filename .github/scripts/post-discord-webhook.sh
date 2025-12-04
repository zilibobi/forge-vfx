#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TAG_ARG=""
EXTRA_ARGS=()

for arg in "$@"; do
    if [[ "$arg" == "--debug" || "$arg" == "--dry-run" ]]; then
        EXTRA_ARGS+=("$arg")
    else
        TAG_ARG="$arg"
    fi
done

CMD=(python3 "$SCRIPT_DIR/release_notifier.py")

if [[ -n "$TAG_ARG" ]]; then
    CMD+=(--tag "$TAG_ARG")
fi

if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
    CMD+=(--webhook-url "$DISCORD_WEBHOOK_URL")
fi

CMD+=("${EXTRA_ARGS[@]}")

"${CMD[@]}"
