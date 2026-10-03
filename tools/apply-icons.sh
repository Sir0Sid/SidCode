#!/usr/bin/env bash
#
# Put SidCode's mark into a VSCodium checkout, so the editor carries it.
#
#   ./tools/apply-icons.sh <path to a VSCodium checkout>
#
# Two files matter on Linux, and VSCodium's own `icons/build_icons.sh` leaves both alone if
# they already exist - which is the hook this uses:
#
#   src/stable/resources/linux/code.png                       the app icon: the dock, the
#                                                            window, the .desktop entry
#   src/stable/src/vs/workbench/browser/media/code-icon.svg    the watermark on an empty editor
#
# The icon is a PNG because Linux wants one; it is rendered from the SVG here with
# `rsvg-convert`, which is the one renderer that keeps the transparency the plate needs.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONS="${ROOT}/branding/icons"

if [ $# -lt 1 ]; then
  echo "usage: $0 <path to a VSCodium checkout>" >&2
  exit 1
fi

CHECKOUT="$(cd "$1" && pwd)"
LINUX_DIR="${CHECKOUT}/src/stable/resources/linux"
MEDIA_DIR="${CHECKOUT}/src/stable/src/vs/workbench/browser/media"

if [ ! -d "${CHECKOUT}/src/stable" ]; then
  echo "no src/stable in ${CHECKOUT} - is that a VSCodium checkout?" >&2
  exit 1
fi

if ! command -v rsvg-convert >/dev/null 2>&1; then
  cat >&2 <<'TEXT'
rsvg-convert is missing, and it is what turns the SVG into the PNG Linux wants:

  sudo apt install -y librsvg2-bin

TEXT
  exit 1
fi

mkdir -p "${LINUX_DIR}" "${MEDIA_DIR}"

# 512px is what VS Code's Linux builds ship, and what a 256px dock icon scales up from.
rsvg-convert -w 512 -h 512 "${ICONS}/sidcode.svg" -o "${LINUX_DIR}/code.png"
echo "  app icon    ${LINUX_DIR}/code.png"

cp "${ICONS}/sidcode-mark.svg" "${MEDIA_DIR}/code-icon.svg"
echo "  watermark   ${MEDIA_DIR}/code-icon.svg"

# The rpm packaging derives its .xpm from the PNG; it is only needed if that is built.
if command -v convert >/dev/null 2>&1; then
  mkdir -p "${LINUX_DIR}/rpm"
  convert "${LINUX_DIR}/code.png" "${LINUX_DIR}/rpm/code.xpm"
  echo "  rpm icon    ${LINUX_DIR}/rpm/code.xpm"
fi

echo "SidCode's mark is in place."
