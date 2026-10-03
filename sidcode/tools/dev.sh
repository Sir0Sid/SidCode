#!/usr/bin/env bash
#
# Run the editor from the checkout, with the TypeScript recompiling as you save.
#
#   ./tools/dev.sh
#
# For changing the editor's own code. `build.sh` re-fetches the source and rebuilds the lot;
# this starts what is already compiled and watches for changes, so an edit is visible in seconds.
#
# It needs one full `./build.sh` first: that is what installs the dependencies and produces the
# compiled output this starts from. `./tools/make-patch.sh` saves what you end up with.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${SIDCODE_BUILD_DIR:-${ROOT}/build}"
VSCODE="${WORK}/vscodium/vscode"

if [ ! -d "${VSCODE}/node_modules" ] || [ ! -d "${VSCODE}/out" ]; then
  cat >&2 <<TEXT
${VSCODE} has not been built yet - dev mode starts from a build:
  ${ROOT}/build.sh          the long one, once
TEXT
  exit 1
fi

# Patches in patches/ are applied by the build, so a checkout that has not been through one since
# a patch was written is missing that change. git apply is all or nothing, and it simply fails
# where the change is already there.
for patch in "${ROOT}"/patches/*.patch; do
  if [ -f "${patch}" ]; then
    if git -C "${VSCODE}" apply --check "${patch}" >/dev/null 2>&1; then
      git -C "${VSCODE}" apply "${patch}"
      echo "applied $(basename "${patch}")"
    fi
  fi
done

launcher=""
for candidate in script/code.sh scripts/code.sh; do
  if [ -x "${VSCODE}/${candidate}" ]; then
    launcher="${candidate}"
    break
  fi
done
if [ -z "${launcher}" ]; then
  echo "no code.sh launcher under ${VSCODE} - that is not the checkout this expects" >&2
  exit 1
fi

cd "${VSCODE}"

watch_pid=""
if [ "${SIDCODE_NO_WATCH:-}" != "1" ]; then
  echo "watching for changes - saving a file is enough"
  npm run watch &
  watch_pid="$!"
  trap 'if [ -n "${watch_pid}" ]; then kill "${watch_pid}" 2>/dev/null || true; fi' EXIT
  # let the first compile get ahead of the window opening
  sleep 5
fi

echo "starting ${launcher}"
"./${launcher}" "$@"
