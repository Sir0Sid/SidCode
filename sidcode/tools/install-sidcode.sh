#!/usr/bin/env bash
#
# Install a built SidCode for the current user:
#
#   * the app goes in ~/.local/share/sidcode
#   * a `sidcode` command in ~/.local/bin (which Ubuntu already has on PATH)
#   * an entry in the application menu, so it appears with your other apps
#
#   ./tools/install-sidcode.sh <path to the built app folder>
#   ./tools/install-sidcode.sh build/vscodium/VSCode-linux-x64
#
# No root, no package manager, and nothing outside your home folder is touched. Re-run it
# after a rebuild and it replaces the installed copy.
#
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <path to the built app folder>" >&2
  echo "   eg: $0 build/vscodium/VSCode-linux-x64" >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  cat >&2 <<'TEXT'
This installs into the home folder of whoever runs it, so running it with sudo puts
everything in /root/.local/... , where the desktop of the real user never looks - and the app
is then invisible in the menu and iconless in the dock. Run it as yourself:

  ./tools/install-sidcode.sh <path to the built app folder>

Only Chromium's sandbox helper needs sudo, afterwards, and this script prints those two lines.
TEXT
  exit 1
fi

APP_SRC="$(cd "$1" && pwd)"
APP_DIR="${HOME}/.local/share/sidcode"
BIN_DIR="${HOME}/.local/bin"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/sidcode.desktop"

if [ ! -x "${APP_SRC}/bin/sidcode" ]; then
  echo "there is no bin/sidcode in ${APP_SRC}" >&2
  echo "that is the folder the build produced, the one with resources/ and bin/ in it" >&2
  exit 1
fi

echo "installing from ${APP_SRC}"
echo "            to ${APP_DIR}"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
cp -a "${APP_SRC}/." "${APP_DIR}/"

mkdir -p "${BIN_DIR}" "${DESKTOP_DIR}"
ln -sf "${APP_DIR}/bin/sidcode" "${BIN_DIR}/sidcode"

# A menu entry made earlier with sudo belongs to root, and root's file cannot be replaced by the
# person it is for. Say so plainly rather than letting the shell report "Permission denied" on a
# redirect, which says nothing about which file it was or what to do.
if [ -e "${DESKTOP_FILE}" ] && [ ! -w "${DESKTOP_FILE}" ]; then
  cat >&2 <<TEXT
${DESKTOP_FILE} exists but is not yours to write - it was probably created with sudo.

  sudo rm -f ${DESKTOP_FILE}

then run this again. Everything else is already installed.
TEXT
  exit 1
fi

ICON="$(find "${APP_DIR}/resources/app/resources/linux" -maxdepth 1 -name '*.png' 2>/dev/null | head -1 || true)"

{
  echo '[Desktop Entry]'
  echo 'Type=Application'
  echo 'Name=SidCode'
  echo 'GenericName=Text Editor'
  echo "Comment=Sid's own editor"
  echo "Exec=${APP_DIR}/bin/sidcode %F"
  echo 'Terminal=false'
  echo 'Categories=TextEditor;Development;IDE;'
  echo 'StartupWMClass=sidcode'
  echo 'Actions=new-window;'
  echo ''
  echo '[Desktop Action new-window]'
  echo 'Name=New Window'
  echo "Exec=${APP_DIR}/bin/sidcode --new-window"
} > "${DESKTOP_FILE}"

if [ -n "${ICON}" ]; then
  echo "Icon=${ICON}" >> "${DESKTOP_FILE}"
fi

cat <<TEXT

Installed.

  the app      ${APP_DIR}/bin/sidcode
  the command  sidcode          (open a new terminal first, or: export PATH="\$HOME/.local/bin:\$PATH")
  the menu     SidCode          (in the Activities grid, from where it can be pinned)

To put your extensions in:
  ${BIN_DIR}/sidcode --install-extension ${PWD}/../sids-sftp/sftp-sid-*.vsix

One command is left, and only sudo can do it. Chromium's sandbox helper has to be owned by
root with the setuid bit, and a copy in your home folder cannot be. Without this, SidCode
either starts and immediately closes, or tells you the sandbox helper is not configured:

  sudo chown root:root ${APP_DIR}/chrome-sandbox
  sudo chmod 4755 ${APP_DIR}/chrome-sandbox

You will need it again after re-running this script, since it replaces the folder.
TEXT
