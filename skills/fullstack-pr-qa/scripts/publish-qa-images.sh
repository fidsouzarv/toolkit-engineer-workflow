#!/usr/bin/env bash
# publish-qa-images.sh — host QA screenshots by SHA, without polluting the repo.
#
# Uploads image files to the repository's git object store as an ORPHAN commit
# (parented to nothing, so it is on no branch), anchored by a hidden ref
# refs/qa/<slug> so GitHub will not garbage-collect the objects. Prints
# ready-to-paste markdown image embeds that reference each image by the commit
# SHA. The images never enter the PR branch diff or the default branch, so CI
# (prettier/lint/format) never scans them and `main` stays clean.
#
# This is the delivery path for embedding screenshots in a PR description when
# the user does NOT want QA artifacts committed to the repo. `gh` has no
# user-attachments upload API (that is a github.com web-session flow), so the
# git data API + SHA reference is the only automatable route.
#
# Usage: publish-qa-images.sh <screenshots-dir> <task-slug> [owner/repo]
#   arg1  directory containing the .png/.jpg/.jpeg/.webp screenshots
#   arg2  task slug (used for the hidden ref name refs/qa/<slug>)
#   arg3  repo (owner/repo); defaults to `gh repo view` for the current repo
#
# Requires: gh (authenticated), jq, base64.
#
# Stdout:
#   COMMIT_SHA=<sha>
#   REF=refs/qa/<slug>
#   ![<name>](https://github.com/<repo>/blob/<sha>/qa/<file>?raw=true)   (one per image)
set -euo pipefail

dir="${1:?screenshots dir required}"
slug="${2:?task slug required}"
repo="${3:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

[ -d "$dir" ] || {
  echo "ERROR: not a directory: $dir" >&2
  exit 1
}

shopt -s nullglob
files=("$dir"/*.png "$dir"/*.jpg "$dir"/*.jpeg "$dir"/*.webp)
[ "${#files[@]}" -gt 0 ] || {
  echo "ERROR: no image files in $dir" >&2
  exit 1
}

# 1) One git blob per image.
tree_items=()
for f in "${files[@]}"; do
  name=$(basename "$f")
  b64=$(base64 < "$f" | tr -d '\n')
  bsha=$(jq -n --arg c "$b64" '{content:$c, encoding:"base64"}' \
    | gh api -X POST "/repos/$repo/git/blobs" --input - -q .sha)
  tree_items+=("$(jq -n --arg p "qa/$name" --arg s "$bsha" \
    '{path:$p, mode:"100644", type:"blob", sha:$s}')")
done

# 2) A tree holding every blob under qa/.
tree_sha=$(printf '%s\n' "${tree_items[@]}" | jq -s '{tree: .}' \
  | gh api -X POST "/repos/$repo/git/trees" --input - -q .sha)

# 3) An orphan commit (no parents) — exists in the object store, on no branch.
commit_sha=$(jq -n --arg t "$tree_sha" \
  --arg m "QA screenshots for $slug (orphan commit; referenced by SHA in the PR)" \
  '{message:$m, tree:$t}' \
  | gh api -X POST "/repos/$repo/git/commits" --input - -q .sha)

# 4) Anchor with a hidden ref so the objects survive GC. Custom refs/qa/*
#    namespace does not appear in the branch/tag UI. Create, else force-update.
ref="refs/qa/$slug"
if ! jq -n --arg r "$ref" --arg s "$commit_sha" '{ref:$r, sha:$s}' \
  | gh api -X POST "/repos/$repo/git/refs" --input - -q .ref >/dev/null 2>&1; then
  jq -n --arg s "$commit_sha" '{sha:$s, force:true}' \
    | gh api -X PATCH "/repos/$repo/git/$ref" --input - -q .ref >/dev/null
fi

# 5) Emit markdown embeds referencing each image by the commit SHA.
echo "COMMIT_SHA=$commit_sha"
echo "REF=$ref"
for f in "${files[@]}"; do
  name=$(basename "$f")
  echo "![${name%.*}](https://github.com/$repo/blob/$commit_sha/qa/$name?raw=true)"
done
