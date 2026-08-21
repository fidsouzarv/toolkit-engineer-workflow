#!/usr/bin/env bash
# qa-auth.sh — turn the skill's $3 credentials parameter into an agent-browser auth profile.
#
# Credentials always end up in the agent-browser auth vault (AES-256-GCM under
# ~/.agent-browser), never in the project, never in the QA report, never in a log line.
# The password is passed to the vault over stdin, so it does not appear in `ps` output.
#
# Usage: qa-auth.sh <projeto> <ambiente> "<spec>" [login-url] [--username-selector <s>]
#                   [--password-selector <s>] [--submit-selector <s>]
#
# <spec> accepts four forms:
#   @<perfil>              an existing vault profile — verified and reused as-is
#   env:<VAR_USER>,<VAR_PASS>   read both from the environment (nothing enters the transcript)
#   <user>:<senha>         saved to the vault as qa-<projeto>-<ambiente>; requires [login-url]
#   none                   the app under test needs no login
#
# Stdout: exactly one line, AUTH_PROFILE=<name|none>. Everything else goes to stderr.
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[ "$#" -ge 3 ] || die "usage: qa-auth.sh <projeto> <ambiente> \"<spec>\" [login-url] [selector overrides]"

raw_project="$1"
env_label="$2"
spec="$3"
shift 3
login_url="${1:-}"
[ "$#" -gt 0 ] && shift || true
# Remaining args are passed straight through (--username-selector, etc.).
# Expanded as ${extra[@]+"${extra[@]}"} everywhere: macOS ships bash 3.2, where an empty array
# under `set -u` is an "unbound variable" error rather than an empty expansion.
extra=("$@")

command -v agent-browser >/dev/null 2>&1 || die "agent-browser not on PATH"

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//'
}

expanded="${raw_project/#\~/$HOME}"
project_name="$(basename "${expanded%/}")"
profile="qa-$(slugify "$project_name")-$(slugify "$env_label")"

save_profile() {
  local user="$1" pass="$2"
  [ -n "$user" ] || die "username is empty in the credentials spec"
  [ -n "$pass" ] || die "password is empty in the credentials spec"
  [ -n "$login_url" ] \
    || die "saving a new vault profile needs the login URL as arg 4 (e.g. https://staging.app/login)"
  printf '%s' "$pass" | agent-browser auth save "$profile" \
    --url "$login_url" --username "$user" --password-stdin ${extra[@]+"${extra[@]}"} >&2
  echo "AUTH_PROFILE=$profile"
}

case "$spec" in
  none | NONE | "")
    echo "AUTH_PROFILE=none"
    ;;
  @*)
    name="${spec#@}"
    [ -n "$name" ] || die "'@' with no profile name"
    agent-browser auth show "$name" >/dev/null 2>&1 \
      || die "vault profile '$name' not found — 'agent-browser auth list' shows the saved ones"
    echo "AUTH_PROFILE=$name"
    ;;
  env:*)
    pair="${spec#env:}"
    user_var="${pair%%,*}"
    pass_var="${pair#*,}"
    [ -n "$user_var" ] && [ -n "$pass_var" ] && [ "$user_var" != "$pass_var" ] \
      || die "expected env:<VAR_USER>,<VAR_PASS>, got '$spec'"
    user="${!user_var:-}"
    pass="${!pass_var:-}"
    [ -n "$user" ] || die "environment variable \$$user_var is unset or empty"
    [ -n "$pass" ] || die "environment variable \$$pass_var is unset or empty"
    save_profile "$user" "$pass"
    ;;
  *:*)
    save_profile "${spec%%:*}" "${spec#*:}"
    ;;
  *)
    die "unrecognized credentials spec '$spec'; expected @<perfil>, env:<VAR_USER>,<VAR_PASS>, <user>:<senha> or none"
    ;;
esac
