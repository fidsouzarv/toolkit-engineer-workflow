# Publishing QA results to the PR (screenshots without repo pollution)

How to attach the QA summary and screenshots to a pull request **after the user
confirms**, without committing binaries to the branch or the default branch.

Paths below are relative to the project root resolved from the skill's `$1`
parameter: the report lives at `<projeto>/qa-analyze/<slug>/`. Run the helper
from inside `<projeto>` (or pass absolute paths), since it resolves the repo
with `gh repo view` in the current directory. This whole step is opt-in and
only applies when the project is a GitHub repo with an open PR.

## The constraint

GitHub renders inline images in a PR body from only two sources:

1. Files committed to the repo (pollutes the branch diff and `main`; the report
   `.md` also becomes subject to CI `prettier --check`).
2. The `user-attachments` CDN — populated only by the github.com **web-session**
   upload (drag/paste in the editor). There is **no `gh`/REST/GraphQL API** for
   it, so it cannot be automated with a token.

When the user wants the screenshots in the PR **but not committed**, use the
git-data-API path below: it hosts the images by **commit SHA** on an orphan
commit that lives on no branch.

## The SHA-hosted delivery (default when not committing)

Run the bundled helper after capturing screenshots and confirming delivery:

```
cd <projeto> && bash <skill-dir>/scripts/publish-qa-images.sh \
  qa-analyze/<slug>/screenshots <slug> [owner/repo]
```

It:

1. Creates one git **blob** per image (`POST /repos/:o/:r/git/blobs`).
2. Builds a **tree** with the blobs under `qa/` (`POST .../git/trees`).
3. Creates an **orphan commit** (no parents) holding that tree
   (`POST .../git/commits`) — the objects exist in the store but are on no
   branch, so they never appear in the PR "Files changed" or in `main`.
4. Anchors the commit with a hidden ref `refs/qa/<slug>` (`POST .../git/refs`,
   force-updates if it exists) so GitHub will not garbage-collect the objects.
   Custom `refs/qa/*` refs do not show in the branches/tags UI.
5. Prints `COMMIT_SHA=…`, `REF=…`, and one markdown embed per image:
   `![name](https://github.com/<repo>/blob/<sha>/qa/<file>?raw=true)`.

Paste those `![…]` lines into the PR body (`gh pr edit <n> --body-file …`).
Because CI never sees the images (not on the PR branch), the Format/lint jobs
are unaffected, and `main` stays clean.

Verify before wiring into the body (optional but cheap):

```
gh api -H "Accept: application/vnd.github.raw" \
  "/repos/<repo>/contents/qa/<file>.png?ref=<COMMIT_SHA>" | wc -c
```

The byte count should match the local file.

## Alternatives (pick per the user's choice)

- **Commit the artifacts** — only if the user explicitly wants them in the repo.
  Commit `qa-analyze/<slug>/` and reference images by their normal repo path.
  Note the report `.md` will then be format-gated: run `prettier --write` on it
  before pushing, or the Format check fails.
- **Manual web upload** — the user drags the local
  `qa-analyze/<slug>/screenshots/*.png` into the PR editor themselves; GitHub
  hosts them on `user-attachments`. Use when neither committing nor SHA-hosting
  is wanted.

## Notes

- Keep the local `qa-analyze/<slug>/` report + screenshots as the durable record
  regardless of hosting choice; SHA-hosting does not require committing them.
- Do not upload company screenshots to third-party image hosts — hosting stays
  within the repo's own object store (SHA path) or GitHub's attachment CDN.
