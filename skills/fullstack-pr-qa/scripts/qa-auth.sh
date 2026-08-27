#!/usr/bin/env bash
# qa-auth.sh — resolve a QA run's credentials to an agent-browser auth vault profile.
#
# THE VAULT IS ALWAYS THE SOURCE OF TRUTH. Every run starts by looking for the conventional
# profile for this project+environment pair, so a first run that was given a user/password
# saves it once and every later run finds it with no credentials in the invocation at all.
# When no profile exists and no credentials were supplied, the script does NOT guess and does
# NOT run without a login: it exits 3 with AUTH_MISSING= so the caller stops and asks the user.
#
# Credentials always end up in the vault (AES-256-GCM under ~/.agent-browser), never in the
# project, never in the QA report, never in a log line. The password reaches the vault over
# stdin, so it does not appear in `ps` output.
#
# Usage: qa-auth.sh <projeto> <ambiente> "<spec>" [login-url] [--username-selector <s>]
#                   [--password-selector <s>] [--submit-selector <s>]
#
# <spec> accepts:
#   ""  | auto | vault      look the vault up for qa-<projeto>-<ambiente>; never create
#   @<perfil>               use this existing vault profile — verified, never created
#   env:<VAR_USER>,<VAR_PASS>   read both from the environment, then SAVE to the vault
#   <user>:<senha>          SAVE to the vault as qa-<projeto>-<ambiente>; requires [login-url]
#   none                    the app under test genuinely needs no login (explicit opt-out)
#
# Stdout, exactly one KEY=VALUE line plus optional CANDIDATE= lines. Everything else to stderr.
#   AUTH_PROFILE=<name>     ready to use with `agent-browser auth login <name>`
#   AUTH_PROFILE=none       explicit no-login run
#   AUTH_MISSING=<name>     nothing in the vault; caller must ask the user   (exit 3)
#   CANDIDATE=<name> <username> <url>   other profiles saved for this project, if any
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[ "$#" -ge 3 ] || die "usage: qa-auth.sh <projeto> <ambiente> \"<spec>\" [login-url] [selector overrides]"

raw_project="$1"
raw_env="$2"
spec="$3"

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
project_slug="$(slugify "$project_name")"
profile="qa-$project_slug-$(slugify "$env_label")"

profile_exists() {
  agent-browser auth show "$1" >/dev/null 2>&1
}

# Every other profile saved for this project, so the caller can offer the user a real choice
# (a different role, a neighbouring environment) instead of asking for a password blindly.
print_candidates() {
  agent-browser auth list 2>/dev/null \
    | awk -v pfx="qa-$project_slug-" 'index($1, pfx) == 1 { print "CANDIDATE=" $1 " " $2 " " $3 }' || true
}

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
  "" | auto | AUTO | vault | VAULT)
    if profile_exists "$profile"; then
      echo "AUTH_PROFILE=$profile"
    else
      echo "AUTH_MISSING=$profile"
      print_candidates
      echo "no vault profile '$profile' — ask the user for an existing profile name, or for" >&2
      echo "user+password to create it once; do NOT run the QA without a login." >&2
      exit 3
    fi
    ;;
  none | NONE)
    echo "AUTH_PROFILE=none"
    ;;
  @*)
    name="${spec#@}"
    [ -n "$name" ] || die "'@' with no profile name"
    if profile_exists "$name"; then
      echo "AUTH_PROFILE=$name"
    else
      echo "AUTH_MISSING=$name"
      print_candidates
      echo "vault profile '$name' not found — 'agent-browser auth list' shows the saved ones" >&2
      exit 3
    fi
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
    die "unrecognized credentials spec '$spec'; expected @<perfil>, env:<VAR_USER>,<VAR_PASS>, <user>:<senha>, auto or none"
    ;;
esac
