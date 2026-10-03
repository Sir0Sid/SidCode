#!/usr/bin/env bash
#
# Install Sid's extension set into a SidCode - or any VS Code-shaped - editor.
#
#   ./tools/install-extensions.sh [path to the editor CLI]
#
# Without an argument it calls `sidcode`, so it works from the built app's own bin folder or
# from the CLI on PATH. The list is extensions/install.txt; anything that gallery does not
# have is reported at the end rather than passing for installed.
#
set -euo pipefail

BIN="${1:-sidcode}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="${HERE}/../extensions/install.txt"

if ! command -v "${BIN}" >/dev/null 2>&1 && [ ! -x "${BIN}" ]; then
  echo "no editor CLI at \"${BIN}\" - pass its path, e.g. ./build/VSCode-linux-x64/bin/sidcode" >&2
  exit 1
fi

installed=0
missing=()

while read -r id; do
  case "${id}" in ''|'#'*) continue;; esac

  printf '  %-45s' "${id}"
  if "${BIN}" --install-extension "${id}" --force >/dev/null 2>&1; then
    echo 'installed'
    installed=$((installed + 1))
  else
    echo 'not in this gallery'
    missing+=("${id}")
  fi
done < "${LIST}"

echo
echo "${installed} installed"

if [ ${#missing[@]} -gt 0 ]; then
  echo "${#missing[@]} not available from this gallery:"
  printf '  %s\n' "${missing[@]}"
  echo
  echo "Pylance and the other Microsoft-only extensions are not something a non-Microsoft"
  echo "build may redistribute; pyright or basedpyright is the open stand-in for Pylance."
fi
