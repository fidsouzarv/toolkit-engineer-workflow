#!/usr/bin/env bash
# Read-only. Procura matches de um regex em um arquivo de um branch do GitHub.
# Retorna linhas no formato "linha:conteudo" do arquivo NOVO no branch.
# Uso: find-line.sh OWNER REPO BRANCH FILE_PATH "regex_pattern"
set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "Uso: $0 OWNER REPO BRANCH FILE_PATH 'regex_pattern'" >&2
    exit 2
fi

OWNER="$1"
REPO="$2"
BRANCH="$3"
FILE_PATH="$4"
PATTERN="$5"

if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI nao encontrado." >&2
    exit 3
fi

ENCODED_PATH=$(printf '%s' "$FILE_PATH" | jq -sRr @uri)

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

if ! gh api "repos/$OWNER/$REPO/contents/$ENCODED_PATH?ref=$BRANCH" --jq '.content' 2>/dev/null | base64 -d > "$TMP"; then
    echo "Nao consegui ler $FILE_PATH em $OWNER/$REPO@$BRANCH (404 ou sem acesso)." >&2
    exit 4
fi

LINES=$(wc -l < "$TMP")
echo "# arquivo: $FILE_PATH @ $BRANCH ($LINES linhas)" >&2

if ! grep -nE "$PATTERN" "$TMP"; then
    echo "Nenhum match para padrao: $PATTERN" >&2
    exit 1
fi
