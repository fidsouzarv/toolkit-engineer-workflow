#!/usr/bin/env bash
# Read-only. Baixa metadados, diff e file-list de um PR para um diretorio.
# Uso: fetch-pr.sh OWNER REPO NUMBER OUT_DIR
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "Uso: $0 OWNER REPO NUMBER OUT_DIR" >&2
    exit 2
fi

OWNER="$1"
REPO="$2"
NUMBER="$3"
OUT_DIR="$4"

mkdir -p "$OUT_DIR"

if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI nao encontrado. Instale o GitHub CLI." >&2
    exit 3
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "gh nao autenticado. Rode 'gh auth login'." >&2
    exit 4
fi

META_FIELDS="title,body,state,baseRefName,headRefName,author,additions,deletions,changedFiles,commits,reviews,statusCheckRollup,files,mergeable,reviewDecision"

gh pr view "$NUMBER" --repo "$OWNER/$REPO" --json "$META_FIELDS" > "$OUT_DIR/metadata.json" &
META_PID=$!

gh pr diff "$NUMBER" --repo "$OWNER/$REPO" > "$OUT_DIR/diff.patch" &
DIFF_PID=$!

wait "$META_PID" || { echo "Falha ao buscar metadata do PR $OWNER/$REPO#$NUMBER" >&2; exit 5; }
wait "$DIFF_PID" || { echo "Falha ao buscar diff do PR $OWNER/$REPO#$NUMBER" >&2; exit 6; }

jq '.files' "$OUT_DIR/metadata.json" > "$OUT_DIR/file-list.json"

META_SIZE=$(wc -c < "$OUT_DIR/metadata.json")
DIFF_SIZE=$(wc -c < "$OUT_DIR/diff.patch")
FILES_COUNT=$(jq 'length' "$OUT_DIR/file-list.json")

echo "OK: $OUT_DIR/metadata.json (${META_SIZE}B), $OUT_DIR/diff.patch (${DIFF_SIZE}B), arquivos=$FILES_COUNT"
