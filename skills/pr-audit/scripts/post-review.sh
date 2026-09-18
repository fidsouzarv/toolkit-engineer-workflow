#!/usr/bin/env bash
# Mutating. Posta uma review (com comments inline) no PR via gh api.
# Uso: post-review.sh OWNER REPO NUMBER PAYLOAD_JSON
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "Uso: $0 OWNER REPO NUMBER PAYLOAD_JSON" >&2
    exit 2
fi

OWNER="$1"
REPO="$2"
NUMBER="$3"
PAYLOAD="$4"

if [ ! -f "$PAYLOAD" ]; then
    echo "Payload nao encontrado: $PAYLOAD" >&2
    exit 3
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI nao encontrado." >&2
    exit 4
fi

if ! jq -e '.event and (.comments | type == "array")' "$PAYLOAD" >/dev/null 2>&1; then
    echo "Payload invalido. Precisa ter 'event' e 'comments' (array)." >&2
    exit 5
fi

COMMENTS_COUNT=$(jq '.comments | length' "$PAYLOAD")
EVENT=$(jq -r '.event' "$PAYLOAD")

echo "# postando review: event=$EVENT, comments=$COMMENTS_COUNT" >&2

gh api "repos/$OWNER/$REPO/pulls/$NUMBER/reviews" \
    --method POST \
    --input "$PAYLOAD" \
    --jq '{id, state, html_url}'
