#!/usr/bin/env bash
#
# Save the edits sitting in the checkout as a patch.
#
#   ./tools/make-patch.sh bright-teal-sidebar
#   ./tools/make-patch.sh menus src/vs/workbench/browser/parts/
#
# The source at build/vscodium/vscode is disposable: `dev/build.sh` runs `git reset --hard` over
# it, and a build that fetches the source clones it again. A patch in `patches/` is what survives,
# and build.sh puts it back before every build. See patches/README.md.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${SIDCODE_BUILD_DIR:-${ROOT}/build}"
VSCODE="${WORK}/vscodium/vscode"

name="${1:-}"
if [ -z "${name}" ]; then
  echo "usage: $(basename "$0") <name> [paths...]" >&2
  exit 1
fi
shift
paths=("$@")

if [ ! -d "${VSCODE}/.git" ]; then
  echo "no fetched source at ${VSCODE}" >&2
  echo "run ${ROOT}/build.sh once first - fetching it is part of the build" >&2
  exit 1
fi

case "${name}" in
  *.patch) patch_file="${ROOT}/patches/${name}" ;;
  *) patch_file="${ROOT}/patches/${name}.patch" ;;
esac
mkdir -p "${ROOT}/patches"

# --intent-to-add is what makes a file you created show up in the diff. .gitignore still applies,
# so the compiled output and node_modules stay out of the patch.
git -C "${VSCODE}" add --intent-to-add -- .
git -C "${VSCODE}" diff --no-color -- "${paths[@]}" > "${patch_file}"

if [ ! -s "${patch_file}" ]; then
  rm -f "${patch_file}"
  echo "nothing has changed in ${VSCODE}, so there is no patch to make" >&2
  exit 1
fi

echo "wrote patches/$(basename "${patch_file}")"
git -C "${VSCODE}" diff --stat -- "${paths[@]}"

# A patch that cannot be reversed against the tree it came from is one that will not apply to a
# fresh checkout, so say it now rather than at the end of the next long build.
if git -C "${VSCODE}" apply --check --reverse "${patch_file}" 2>/dev/null; then
  echo "  reverses cleanly, so it will apply to a fresh checkout"
else
  echo "  warning: it does not reverse cleanly here - something else is in the checkout" >&2
fi
