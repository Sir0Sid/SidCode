#!/usr/bin/env bash
#
# Pack this folder as the archive Sid downloads, named with what is in it.
#
# It used to be `sidcode.tar.gz` every time, which says nothing about which one it is: two
# downloads a day apart look identical in a Downloads folder, and unpacking the older one over a
# build is a mistake that shows up later as "the fix did not go in". So the name carries the two
# versions that change - the SFTP extension and Sid's colours - and a `VERSION` file inside says
# the same thing to anyone who has already unpacked it.
#
#   ./tools/pack.sh          writes sidcode-<sftp-sid>-<defaults>-<packed>.tar.gz beside this folder
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

version_of() {
  node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "$1" 2>/dev/null || echo unknown
}

SFTP_VERSION="$(version_of ../sids-sftp/package.json)"
DEFAULTS_VERSION="$(version_of defaults/package.json)"
LANGUAGES_VERSION="$(version_of languages/package.json)"

# The versions first, because they are what changes and what people say out loud - and the time as
# well, because the folder changes without them: two archives packed an hour apart, with the same
# two extensions in them, are otherwise the same name and not the same archive.
PACKED="$(date -u '+%Y%m%d-%H%M')"
NAME="sidcode-${SFTP_VERSION}-${DEFAULTS_VERSION}-${PACKED}.tar.gz"
STAMP="$(date -u '+%Y-%m-%d %H:%M UTC')"

cat > VERSION <<TEXT
${NAME%.tar.gz}

sftp-sid          ${SFTP_VERSION}
sidcode-defaults  ${DEFAULTS_VERSION}
sidcode-languages ${LANGUAGES_VERSION}

packed ${STAMP}
TEXT

rm -f "${NAME}" sidcode.tar.gz
# `build/` is the VSCodium checkout and the built app: the expensive part, and not what this is
# for. Any older archive beside this one is left alone - it has its own version in its name now.
#
# Written outside the folder and moved in: an archive written into the folder it is reading makes
# tar read its own output, which it reports as `. changed as we read it`. That warning also arrives
# when something else writes to the folder while tar is reading it - an editor, a git snapshot -
# and an archive with one directory entry read a moment late is not a broken archive, so only a
# real failure (2 and up) stops this.
tar --warning=no-file-changed --exclude='./build' --exclude='./sidcode*.tar.gz' -czf "/tmp/${NAME}" .
STATUS=$?

if [ "${STATUS}" -gt 1 ]; then
  echo "tar failed with status ${STATUS}" >&2
  exit "${STATUS}"
fi

mv "/tmp/${NAME}" "${NAME}"

echo "${ROOT}/${NAME}"
tar tzf "${NAME}" | grep -c . | sed 's/^/  /;s/$/ files/'
cat VERSION | sed 's/^/  /'
# The label is a comment and the command is on its own line, so both of the last two lines can be
# pasted into a shell exactly as they are printed. Printing "unpack with: tar -xzf ..." on one line
# did not survive that: "unpack with:" at the start of a line is a command the shell looks for, and
# `unpack` is not one.
echo "# to unpack it, exactly as printed:"
echo "tar -xzf ~/Downloads/${NAME} -C ~/sid/sidcode"
