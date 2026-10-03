#!/usr/bin/env bash
#
# Where the remote server component has to be uploaded to, for the build sitting beside this folder.
#
# `build.sh --server` packs an artifact named from `server/artifact.json`; the editor's settings
# were generated from the same file, and the URL they carry is the only place a user's editor learns
# where to fetch a server from. So this prints the address that URL resolves to for a given build -
# and if the artifact is here, says so; if it is not, says that instead.
#
#   ./tools/publish-server.sh                        the build in build/vscodium
#   ./tools/publish-server.sh --version 1.135.06 --commit a1b2c3d --arch arm64
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${SIDCODE_BUILD_DIR:-${ROOT}/build}"
VSCODIUM="${WORK}/vscodium"

VERSION=""
COMMIT=""
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) ARCH=x64 ;;
  aarch64) ARCH=arm64 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --commit) COMMIT="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; echo "usage: $0 [--version v] [--commit c] [--arch a]" >&2; exit 2 ;;
  esac
done

if [ -z "${VERSION}" ]; then
  VERSION="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "${VSCODIUM}/package.json" 2>/dev/null || echo '')"
  [ -n "${VERSION}" ] || { echo "no version given, and no checkout at ${VSCODIUM} to read one from." >&2; exit 1; }
fi

if [ -z "${COMMIT}" ]; then
  COMMIT="$(git -C "${VSCODIUM}" rev-parse --short HEAD 2>/dev/null || echo '')"
  [ -n "${COMMIT}" ] || { echo "no commit given, and ${VSCODIUM} is not a git checkout." >&2; exit 1; }
fi

NAME="$(node "${ROOT}/tools/artifact-name.mjs" name "${VERSION}" "${COMMIT}" "${ARCH}")"
URL="$(node "${ROOT}/tools/artifact-name.mjs" url "${VERSION}" "${COMMIT}" "${ARCH}")"

LOCAL="$(dirname "${ROOT}")/${NAME}"

echo "the build:  VSCodium ${VERSION} (${COMMIT}), linux ${ARCH}"
echo "the artifact: ${NAME}"
if [ -f "${LOCAL}" ]; then
  echo "  it is here: $(du -h "${LOCAL}" | cut -f1)  ${LOCAL}"
else
  echo "  it is not here yet - build it with ${ROOT}/build.sh --server"
fi
echo
echo "where every user's editor will look for it:"
echo "  ${URL}"
echo
echo "so it has to be uploaded there. For a GitHub release, that is:"
echo "  gh release create server-${VERSION} --title 'SidCode server ${VERSION}' \\"
echo "     '${LOCAL}'"
