#!/usr/bin/env bash
# ensure-ffmpeg.sh — guarantee the scenario recordings can actually be encoded.
#
# agent-browser encodes every `record` through ffmpeg, and without it the failure is silent and
# late: `record start` prints "✓ Recording started", the whole scenario runs, and only
# `record stop` reports "✗ ffmpeg not found" — with no file written at all. `agent-browser
# doctor` does not check for it either, so it reports 0 fail on a machine where every recording
# will be lost. This script is the preflight that closes that gap, and it installs ffmpeg when
# it can do so unattended and without privilege escalation.
#
# Usage: ensure-ffmpeg.sh [--no-install]
#   --no-install   report only; never install. Same as QA_NO_INSTALL=1 in the environment.
#
# Stdout, exactly one KEY=VALUE line:
#   FFMPEG=<path>              already present, nothing done                        (exit 0)
#   FFMPEG_INSTALLED=<path>    installed just now by this script                    (exit 0)
#   FFMPEG_MISSING=<reason>    unavailable; recordings are impossible this run      (exit 4)
#
# Exit 4 is a soft failure by design: a QA run without video is still worth doing on screenshots
# plus network evidence. The caller decides, reports the degradation, and never silently starts
# recordings that cannot be encoded.
set -euo pipefail

no_install="${QA_NO_INSTALL:-}"
[ "${1:-}" = "--no-install" ] && no_install=1

found() {
  echo "$1=$(command -v ffmpeg)"
  exit 0
}

command -v ffmpeg >/dev/null 2>&1 && found FFMPEG

if [ -n "$no_install" ]; then
  echo "FFMPEG_MISSING=not installed and installation was disabled (--no-install / QA_NO_INSTALL)"
  exit 4
fi

# Pick an installer that needs no sudo and no interaction. Anything requiring privilege
# escalation is reported for a human to run, never attempted from inside a QA run.
install_cmd=""
case "$(uname -s)" in
  Darwin)
    if command -v brew >/dev/null 2>&1; then
      install_cmd="brew install ffmpeg"
    else
      echo "FFMPEG_MISSING=Homebrew not found; install ffmpeg manually (https://brew.sh then 'brew install ffmpeg')"
      exit 4
    fi
    ;;
  Linux)
    if command -v brew >/dev/null 2>&1; then
      install_cmd="brew install ffmpeg"
    elif [ "$(id -u)" = "0" ] && command -v apt-get >/dev/null 2>&1; then
      install_cmd="apt-get update && apt-get install -y ffmpeg"
    elif [ "$(id -u)" = "0" ] && command -v dnf >/dev/null 2>&1; then
      install_cmd="dnf install -y ffmpeg"
    else
      echo "FFMPEG_MISSING=no unattended installer available; run 'sudo apt-get install ffmpeg' (or the distro equivalent) yourself"
      exit 4
    fi
    ;;
  *)
    echo "FFMPEG_MISSING=unsupported platform $(uname -s); install ffmpeg manually"
    exit 4
    ;;
esac

echo "installing ffmpeg: $install_cmd" >&2
echo "(first install pulls a large dependency tree and can take several minutes)" >&2

# Progress and errors go to stderr so stdout stays a single parseable KEY=VALUE line.
# HOMEBREW_NO_AUTO_UPDATE keeps a QA run from silently upgrading unrelated formulae.
if ! HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
  DEBIAN_FRONTEND=noninteractive \
  bash -c "$install_cmd" >&2; then
  echo "FFMPEG_MISSING=installation failed: $install_cmd"
  exit 4
fi

# hash -r: the shell may have cached a negative lookup for ffmpeg before the install.
hash -r 2>/dev/null || true
command -v ffmpeg >/dev/null 2>&1 && found FFMPEG_INSTALLED

echo "FFMPEG_MISSING=install reported success but ffmpeg is still not on PATH"
exit 4
