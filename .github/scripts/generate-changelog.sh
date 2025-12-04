#!/usr/bin/env bash
set -e

REPO="zilibobi/forge-vfx"

if [[ $# -gt 1 ]]; then
    TO_TAG="$2"
else
    TO_TAG=$(git describe --tags --abbrev=0)
fi

if [[ $# -gt 0 ]]; then
    FROM_TAG="$1"
else
    FROM_TAG=$(git tag --sort=-version:refname | grep -v "^${TO_TAG}$" | head -1)
    if [[ -z "$FROM_TAG" ]]; then
        FROM_TAG=$(git rev-list --max-parents=0 HEAD)
    fi
fi

echo "## Commits"
echo ""

git log "${FROM_TAG}..${TO_TAG}^" \
    --pretty=format:"- %s ([%h](https://github.com/${REPO}/commit/%H))" \
    --no-merges

echo ""
echo ""
echo "[**Full Changelog**](https://github.com/${REPO}/compare/${FROM_TAG}...${TO_TAG})"
