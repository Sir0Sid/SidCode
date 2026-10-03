#!/usr/bin/env bash
#
# Keep a copy of the source SidCode was built from.
#
# The editor that is installed needs none of this to run: it is an app folder and a data folder, and
# neither looks at the network. What needs the network is a *rebuild* - VSCodium's repository,
# Microsoft's `vscode` inside it (VSCodium's build fetches it at a tag of its own), and the npm
# packages. Any of those can move, be renamed, or go away, and a copy you hold is the only thing that
# answers that.
#
# Copying is also the honest alternative to a fork: a fork is for changing the base, this is for
# keeping it. Neither is needed to *change* SidCode - `patches/` is applied on top of VSCodium's own
# patches, which is where a change to the editor's code belongs, and it is how the Tools menu exists.
#
#   ./tools/save-source.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${SIDCODE_BUILD_DIR:-${ROOT}/build}"
VSCODIUM="${WORK}/vscodium"

if [ ! -d "${VSCODIUM}" ]; then
  echo "no checkout at ${VSCODIUM}: there is no source here to save." >&2
  echo "Set SIDCODE_BUILD_DIR if your build folder is somewhere else." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is not on PATH, so the commit being saved cannot be named." >&2
  exit 1
fi

REF="$(git -C "${VSCODIUM}" rev-parse --short HEAD 2>/dev/null || echo no-git)"
NAME="vscodium-source-${REF}-$(date -u '+%Y-%m-%d').tar.gz"

# Beside this folder and not inside it: `tools/pack.sh` packs the whole folder, and half a gigabyte
# of source does not belong in what Sid downloads.
DEST="$(dirname "${ROOT}")/${NAME}"

echo "packing ${VSCODIUM}"
echo "  VSCodium's source, and Microsoft's vscode inside it, at ${REF}"

# node_modules and the built app are left out: both are reproduced by building, and both are the
# bulk of the folder. Everything that could vanish upstream is in.
#
# The patterns start with `*/` because the members are `vscodium/...` - tar matches its exclusions
# against the names *in the archive*, not against the paths on disk, so `--exclude='./vscodium/...'`
# would exclude nothing at all and quietly pack the built app and every node_modules with it.
tar --warning=no-file-changed \
  --exclude='*/node_modules' \
  --exclude='*/VSCode-linux-x64' --exclude='*/VSCodium-linux-x64' \
  --exclude='*/VSCode-darwin*' --exclude='*/VSCode-win32*' \
  -czf "/tmp/${NAME}" -C "${WORK}" vscodium

STATUS=$?
if [ "${STATUS}" -gt 1 ]; then
  echo "tar failed with status ${STATUS}" >&2
  exit "${STATUS}"
fi

mv "/tmp/${NAME}" "${DEST}"

echo
echo "${DEST}"
du -h "${DEST}" | sed 's/^/  /'
echo "  the source, at ${REF}, in a copy of your own - unpack it wherever you keep builds"
echo "  (VSCodium's checkout is inside it, Microsoft's vscode inside that, and patches/user)"
