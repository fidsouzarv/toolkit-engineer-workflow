#!/usr/bin/env bash
# scaffold-qa.sh — bootstrap the QA output folder and the agent-browser session for a run.
#
# Creates <projeto>/qa-analyze/<slug>/{screenshots,recordings}/, seeds qa-results.md from the
# skill's template, derives a STABLE agent-browser session id for the project+environment pair,
# and writes <slug>/.qa-env so scripts/qa-browser.sh can re-apply that environment on every call
# (agent hosts may not keep environment variables between shell calls).
#
# recordings/ holds ONE WebM per test scenario, never one video for the whole run — see
# references/agent-browser-playbook.md.
#
# Usage: scaffold-qa.sh <project> "<title>" <environment> [base-url]
#   $1  project: absolute path, ~-path, relative path, or a bare name looked up under
#       ./<name> then ~/dev/<name>. ALL output is written under this directory.
#   $2  run title (slugified into the folder name).
#   $3  environment: "<label>=<url>" (preferred: staging=https://staging.app), a bare URL, or a
#       bare label (localhost | staging | prod | <free label>). This argument is required.
#       The LABEL is what keeps the session id and the vault profile stable across runs, so
#       prefer the "label=url" form for anything remote.
#   $4  base URL, when not embedded in $3, e.g. http://localhost:3002 (default: empty)
#       REQUIRED for any remote environment: the skill must never invent a staging/prod host.
#
# Read-only with respect to the application: it only creates the qa-analyze/ tree.
#
# Stdout (KEY=VALUE, one per line):
#   PROJECT_ROOT SLUG ENV BASE_URL REPORT_DIR REPORT SHOTS RECORDINGS SESSION QA_ENV
# REPORT_DIR is the <report-dir> argument every qa-browser.sh call takes.
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[ "$#" -ge 3 ] || die "usage: scaffold-qa.sh <project> \"<title>\" <environment> [base-url]"

raw_project="$1"
raw_title="$2"
raw_env="$3"
base_url="${4:-}"

[ -n "$raw_project" ] || die "project (arg 1) is empty; expected a path or a project name"
[ -n "$raw_title" ] || die "title (arg 2) is empty; expected the run title"
[ -n "$raw_env" ] || die "environment (arg 3) is empty; expected a local label, <label>=<url>, or URL"

# --- split the environment argument into a stable LABEL and a base URL ----------------------
# Accepted forms, in order:
#   staging=https://staging.app   label + URL, the form Gate A asks the user to re-invoke with.
#                                 Keeps the label (and therefore the vault profile and the
#                                 session id) stable no matter which host is passed.
#   https://staging.app           bare URL; the label is derived from the host.
#   staging                       bare label; the URL must come from the next positional arg.
parse_env_spec() {
  local spec="$1" host
  env_label=""
  env_url=""
  case "$spec" in
    *=http://* | *=https://*)
      env_label="${spec%%=*}"
      env_url="${spec#*=}"
      ;;
    http://* | https://*)
      env_url="$spec"
      host="${spec#*://}"
      host="${host%%/*}"
      case "$host" in
        localhost* | 127.0.0.1* | 0.0.0.0* | "[::1]"*) env_label="localhost" ;;
        *) env_label="${host%%:*}" ;;
      esac
      ;;
    *)
      env_label="$spec"
      ;;
  esac
}

parse_env_spec "$raw_env"
# An explicit arg 4 wins over a URL embedded in arg 3; otherwise the embedded one is the URL.
[ -n "$base_url" ] || base_url="$env_url"

# A remote environment must arrive with its base URL already resolved and confirmed. Labels
# like staging/prod name no host on their own, and guessing one is how a QA run ends up
# driving the wrong deployment. See SKILL.md Step 0.
case "$(printf '%s' "$env_label" | tr '[:upper:]' '[:lower:]')" in
  localhost | local | dev | development)
    ;;
  *)
    if [ -z "$base_url" ]; then
      die "environment '$env_label' is remote but no base URL was given as arg 4 — ask the user for the full https:// URL; never infer a host from the label"
    fi
    ;;
esac

case "$base_url" in
  "" | http://* | https://*) ;;
  *) die "base URL (arg 4) must start with http:// or https://, got '$base_url'" ;;
esac

# --- resolve the project directory --------------------------------------------------------
expanded="${raw_project/#\~/$HOME}"
if [ -d "$expanded" ]; then
  project_root="$(cd "$expanded" && pwd -P)"
elif [ -d "./$expanded" ]; then
  project_root="$(cd "./$expanded" && pwd -P)"
elif [ -d "$HOME/dev/$expanded" ]; then
  project_root="$(cd "$HOME/dev/$expanded" && pwd -P)"
else
  die "project not found: '$raw_project' (tried '$expanded', './$expanded', '$HOME/dev/$expanded')"
fi

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//'
}

slug="$(slugify "$raw_title")"
[ -n "$slug" ] || die "title slugified to an empty string: '$raw_title'"

env_slug="$(slugify "$env_label")"
[ -n "$env_slug" ] || die "environment slugified to an empty string: '$env_label'"

project_slug="$(slugify "$(basename "$project_root")")"

# --- create the report tree ---------------------------------------------------------------
out_dir="$project_root/qa-analyze/$slug"
shots_dir="$out_dir/screenshots"
recordings_dir="$out_dir/recordings"
mkdir -p "$shots_dir" "$recordings_dir"

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
template="$skill_dir/assets/qa-results.template.md"
report="$out_dir/qa-results.md"
if [ ! -f "$report" ]; then
  if [ -f "$template" ]; then
    cp "$template" "$report"
  else
    printf '# QA Results: %s\n' "$raw_title" > "$report"
  fi
fi

# --- derive a stable session id -------------------------------------------------------------
# Stable across runs for the same project+environment, so --restore can reuse the login.
# Session names accept only [A-Za-z0-9_-]; `session id` guarantees a valid one.
command -v agent-browser >/dev/null 2>&1 \
  || die "agent-browser not on PATH — install with 'brew install agent-browser' (or 'npm i -g agent-browser'), then 'agent-browser install'"

prefix="qa-${project_slug}-${env_slug}"
scope="git-root"
git -C "$project_root" rev-parse --show-toplevel >/dev/null 2>&1 || scope="cwd"
session="$(cd "$project_root" && agent-browser session id --scope "$scope" --prefix "$prefix")"
[ -n "$session" ] || die "agent-browser session id returned empty for prefix '$prefix'"

# --- write .qa-env (consumed by qa-browser.sh) ----------------------------------------------
qa_env="$out_dir/.qa-env"
{
  echo "# generated by scaffold-qa.sh — consumed by qa-browser.sh; safe to delete"
  echo "AGENT_BROWSER_SESSION=$session"
  echo "AGENT_BROWSER_RESTORE=$session"
  echo "AGENT_BROWSER_SCREENSHOT_DIR=$shots_dir"
  echo "QA_RECORDINGS_DIR=$recordings_dir"
  echo "QA_BASE_URL=$base_url"
  echo "QA_ENV=$env_label"
  echo "QA_PROJECT_ROOT=$project_root"
} > "$qa_env"

echo "PROJECT_ROOT=$project_root"
echo "SLUG=$slug"
echo "ENV=$env_label"
echo "BASE_URL=$base_url"
echo "REPORT_DIR=$out_dir"
echo "REPORT=$report"
echo "SHOTS=$shots_dir"
echo "RECORDINGS=$recordings_dir"
echo "SESSION=$session"
echo "QA_ENV=$qa_env"
