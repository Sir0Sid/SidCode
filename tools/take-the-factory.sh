#!/usr/bin/env bash
#
# Take the factory: copy the build machinery out of a VSCodium checkout into this repository.
#
# The point is that cloning SidCode and running `build.sh` then builds SidCode with nothing fetched
# from anybody else's repository. What that needs is not the editor's source - that is fetched, and
# it is two gigabytes - but the scripts that know how to *build* it, their patch set, their
# product.json, and the fetch of Microsoft's source pointed at Sid's own fork rather than at
# Microsoft's repository.
#
# Run it against a checkout, once per VSCodium version:
#
#   ./tools/take-the-factory.sh                        build/vscodium
#   SIDCODE_FACTORY_FROM=~/sid/vscodium ./tools/take-the-factory.sh
#   SIDCODE_VSCODE_REPO=https://github.com/Sir0Sid/vscode ./tools/take-the-factory.sh
#
# It prints what it took, the size, and the line it rewrote.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${SIDCODE_BUILD_DIR:-${ROOT}/build}"
FROM="${SIDCODE_FACTORY_FROM:-${WORK}/vscodium}"
FACTORY="${ROOT}/factory"

# Sid's own fork of Microsoft's source. Rename the fork on GitHub and pass the new URL here; nothing
# else in this folder names it, and `tools/check-factory.mjs` fails if the factory still points at
# Microsoft's repository.
VSCODE_REPO="${SIDCODE_VSCODE_REPO:-https://github.com/Sir0Sid/sidecode-1}"

if [ ! -d "${FROM}" ]; then
  cat >&2 <<TEXT
There is no checkout at ${FROM} to take a factory from.

Build once first (./build.sh), or point at a copy you kept:
  SIDCODE_FACTORY_FROM=~/sid/vscodium-source-<commit> ./tools/take-the-factory.sh
TEXT
  exit 1
fi

version_of() {
  node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "$1" 2>/dev/null || echo unknown
}

VERSION="$(version_of "${FROM}/package.json")"
COMMIT="$(git -C "${FROM}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
TAKEN="$(date -u '+%Y-%m-%d %H:%M UTC')"

say() {
  echo "$@"
}

say "taking the factory from ${FROM}"
say "  VSCodium ${VERSION} (${COMMIT})"

rm -rf "${FACTORY}"
mkdir -p "${FACTORY}"

# Generous on purpose: their build reads parts of their repository that are not obvious from the
# outside, and a file left behind fails the build in the middle rather than at the start. What is
# left out is the enormous and the re-creatable: Microsoft's source (their build fetches it), the
# installed packages, the built app, git history and any archives.
tar --warning=no-file-changed \
  --exclude='./vscode' \
  --exclude='./node_modules' --exclude='*/node_modules' \
  --exclude='./VSCode-linux-*' --exclude='./VSCodium-linux-*' \
  --exclude='./VSCode-darwin*' --exclude='./VSCode-win32*' \
  --exclude='./.git' \
  --exclude='*.tar.gz' \
  -czf /tmp/sidcode-factory.tar.gz -C "${FROM}" .

tar -xzf /tmp/sidcode-factory.tar.gz -C "${FACTORY}"
rm -f /tmp/sidcode-factory.tar.gz

if [ ! -f "${FACTORY}/dev/build.sh" ]; then
  echo "  the copy has no dev/build.sh in it - this does not look like a VSCodium checkout" >&2
  exit 1
fi

# The fetch of Microsoft's source, pointed at Sid's fork. Their build clones it itself, so the URL
# lives in their scripts: every file under dev/ is searched, the lines are printed, and the record
# below says which repository the factory now fetches from.
CHANGED_LINES=""
# The file list goes through a temporary file rather than process substitution or a plain `find` in
# the loop: one requires /dev/fd, the other splits on spaces in a path, and this has to run on
# whatever machine Sid happens to be on.
find "${FACTORY}" -type f \
  \( -name '*.sh' -o -name '*.js' -o -name '*.json' -o -name '*.mjs' \) \
  -not -path '*/node_modules/*' > /tmp/sidcode-factory-files.txt

while IFS= read -r file; do
  if grep -q 'microsoft/vscode' "${file}"; then
    say "  rewriting the source fetch in ${file#${FACTORY}/}:"
    grep -n 'microsoft/vscode' "${file}" | sed 's/^/    /'
    sed -i 's#https://github\.com/microsoft/vscode#__SIDCODE_VSCODE_REPO__#g; s#microsoft/vscode\.git#__SIDCODE_VSCODE_REPO__#g; s#microsoft/vscode#__SIDCODE_VSCODE_REPO__#g' "${file}"
    sed -i "s#__SIDCODE_VSCODE_REPO__#${VSCODE_REPO}#g" "${file}"
    CHANGED_LINES="${CHANGED_LINES}${file#${FACTORY}/}
"
  fi
done < /tmp/sidcode-factory-files.txt

rm -f /tmp/sidcode-factory-files.txt

# Whether their build can be run up to the point where the source is prepared but not compiled, which
# is where the patches can be checked against it. Recorded rather than guessed: `build.sh` reads it.
PREPARE_HINT="$(grep -n 'prepare_vscode\|SHOULD_BUILD' "${FACTORY}/dev/build.sh" | head -5 || true)"

# No apostrophe in this default: bash reads a quote inside ${...:-...} as a quote, and the
# expansion fails with "unexpected EOF" - which `bash -n` does not catch, because it happens when
# the line runs rather than when it is parsed.
REWRITTEN="${CHANGED_LINES:-nothing found - no line naming the Microsoft repository was in the copy}"

{
  echo "taken-from   VSCodium ${VERSION} (${COMMIT})"
  echo "taken-on     ${TAKEN}"
  echo "vscode-from  ${VSCODE_REPO}"
  echo "rewritten    ${REWRITTEN}"
} > "${FACTORY}/FACTORY"

SIZE="$(du -sh "${FACTORY}" | cut -f1)"
COUNT="$(find "${FACTORY}" -type f | wc -l | tr -d ' ')"

say
say "  ${FACTORY}"
say "  ${SIZE}, ${COUNT} files"
say
cat "${FACTORY}/FACTORY" | sed 's/^/  /'

if [ -z "${CHANGED_LINES}" ]; then
  cat >&2 <<'TEXT'

  Nothing in the copy named Microsoft's repository, so the fetch of the source is still theirs and
  the goal is not met yet. Look in dev/ for where their build clones vscode (a variable, or a
  REPO= line) and tell me what it says; the rewriting above is the one place it happens.
TEXT
fi

say
say "  the patches can be dry-run against a prepared source when one is here; build.sh says so."
say "  next: ./build.sh - it uses this factory and fetches nothing for the machinery."
