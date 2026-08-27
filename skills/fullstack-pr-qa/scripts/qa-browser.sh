#!/usr/bin/env bash
# qa-browser.sh — run agent-browser inside a QA run's session, screenshot dir and base URL.
#
# WHY THIS EXISTS: the agent's Bash tool starts a fresh shell per call, so `export
# AGENT_BROWSER_SESSION=...` never survives to the next command. A bare `agent-browser` call
# would silently land in the "default" session — a different browser, not logged in. This
# wrapper re-applies the run's .qa-env (written by scaffold-qa.sh) on every invocation.
#
# Usage: qa-browser.sh <report-dir> <agent-browser args...>
#   <report-dir>  the qa-analyze/<slug>/ folder printed by scaffold-qa.sh (REPORT's dirname)
#
# Two rewrites keep stories environment-agnostic and evidence in the right folder:
#   1. For navigation commands (open|goto|navigate|read|pushstate) an argument starting with a
#      single "/" is expanded against QA_BASE_URL:
#        qa-browser.sh <dir> open /login   ->  agent-browser open https://staging.app/login
#   2. For screenshot|pdf a bare filename (no "/") is written into the run's screenshots/ dir.
#      This is NOT what agent-browser does on its own: AGENT_BROWSER_SCREENSHOT_DIR applies only
#      when no path is given at all, so a bare `screenshot 01.png` would land in the shell's cwd
#      and pollute the project root.
#   3. For `record start|restart` a bare filename is written into the run's recordings/ dir, and
#      a missing extension becomes .webm. agent-browser has no recordings-dir env var at all, so
#      without this every scenario video would land in the shell's cwd.
#
# Examples:
#   qa-browser.sh qa-analyze/checkout open /login
#   qa-browser.sh qa-analyze/checkout snapshot -i -c
#   qa-browser.sh qa-analyze/checkout screenshot 01-post-login.png     # lands in screenshots/
#   qa-browser.sh qa-analyze/checkout record start US-1-login.webm      # lands in recordings/
#   qa-browser.sh qa-analyze/checkout record restart US-2-filtro.webm   # next scenario
#   qa-browser.sh qa-analyze/checkout record stop
#   qa-browser.sh qa-analyze/checkout network requests --filter /api/
#   qa-browser.sh qa-analyze/checkout close                            # persists state
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[ "$#" -ge 2 ] || die "usage: qa-browser.sh <report-dir> <agent-browser args...>"

report_dir="${1/#\~/$HOME}"
shift

[ -d "$report_dir" ] || die "report dir does not exist: $report_dir (run scaffold-qa.sh first)"

qa_env="$report_dir/.qa-env"
[ -f "$qa_env" ] || die "missing $qa_env — run scaffold-qa.sh for this run first"

# shellcheck disable=SC1090
set -a
source "$qa_env"
set +a

[ -n "${AGENT_BROWSER_SESSION:-}" ] || die "$qa_env has no AGENT_BROWSER_SESSION"

command -v agent-browser >/dev/null 2>&1 || die "agent-browser not on PATH"

# Expand a leading-slash path against the base URL, for navigation commands only.
cmd=""
for a in "$@"; do
  case "$a" in
    -*) ;;
    *)
      cmd="$a"
      break
      ;;
  esac
done

args=()
case "$cmd" in
  open | goto | navigate | read | pushstate)
    for a in "$@"; do
      if [[ "$a" == /* && "$a" != //* ]]; then
        [ -n "${QA_BASE_URL:-}" ] \
          || die "'$a' is a path but QA_BASE_URL is empty in $qa_env; pass a full URL or set the base URL"
        args+=("${QA_BASE_URL%/}$a")
      else
        args+=("$a")
      fi
    done
    ;;
  screenshot | pdf)
    shot_dir="${AGENT_BROWSER_SCREENSHOT_DIR:-$report_dir/screenshots}"
    mkdir -p "$shot_dir"
    seen_cmd=false
    took_path=false
    for a in "$@"; do
      if [ "$seen_cmd" = false ] && [ "$a" = "$cmd" ]; then
        seen_cmd=true
        args+=("$a")
      elif [ "$seen_cmd" = true ] && [ "$took_path" = false ] && [[ "$a" != -* ]] && [[ "$a" != */* ]]; then
        # Bare filename: anchor it in the run's screenshots/ folder.
        took_path=true
        args+=("$shot_dir/$a")
      else
        args+=("$a")
      fi
    done
    ;;
  record)
    # `record start <path.webm> [url]` / `record restart <path.webm> [url]` / `record stop`.
    # Anchor a bare filename in recordings/ so each scenario's video lands with the report.
    rec_dir="${QA_RECORDINGS_DIR:-$report_dir/recordings}"
    seen_cmd=false
    sub=""
    took_path=false
    for a in "$@"; do
      if [ "$seen_cmd" = false ] && [ "$a" = "record" ]; then
        seen_cmd=true
        args+=("$a")
      elif [ "$seen_cmd" = true ] && [ -z "$sub" ] && [[ "$a" != -* ]]; then
        sub="$a"
        args+=("$a")
      elif [ "$took_path" = false ] \
        && { [ "$sub" = "start" ] || [ "$sub" = "restart" ]; } \
        && [[ "$a" != -* ]] && [[ "$a" != */* ]]; then
        took_path=true
        mkdir -p "$rec_dir"
        case "$a" in
          *.webm) args+=("$rec_dir/$a") ;;
          *.*) die "recording filename must end in .webm, got '$a'" ;;
          *) args+=("$rec_dir/$a.webm") ;;
        esac
      else
        args+=("$a")
      fi
    done
    ;;
  *)
    args=("$@")
    ;;
esac

exec agent-browser "${args[@]}"
