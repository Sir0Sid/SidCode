#!/usr/bin/env bash
#
# Clear a stranded SFTP extension out of the editor's profile.
#
#   ./tools/clear-profile-sftp.sh
#
# Quit SidCode first - this edits files the editor keeps open.
#
# Why this is needed: sir0sid.sftp-sid is *built into* the app by build.sh, but it can also
# be sitting in the profile (~/.sidcode/extensions) from an earlier `--install-extension`.
# SidCode refuses to update or uninstall that copy - "Extension 'sir0sid.sftp-sid' is a
# built-in extension and not allowed to be updated in the current product quality 'stable'" -
# so it stays there, and while it holds the id, the extension's contributions are filtered
# out instead of loaded: no SFTP commands, no SFTP view, and no entry in the Tools menu (an
# empty Tools is left out of the menu bar by patches/tools-menu.patch). Removing the copy and
# the records that describe it leaves the app's own copy as the only one, which is the one
# that works.
#
# Nothing here touches the app itself, and every file it rewrites is backed up beside the
# original first.
#
set -euo pipefail

PROFILE_DIR="${HOME}/.sidcode/extensions"
STATE_FILE="${HOME}/.config/SidCode/User/globalStorage/storage.json"
ID_PATTERN="sftp-sid"

say() { printf '\n== %s\n' "$*"; }

if pgrep -f 'sidcode' >/dev/null 2>&1; then
  echo "SidCode is running - quit it first, then run this again." >&2
  exit 1
fi

say "the copy in the profile"
shopt -s nullglob
found=("${PROFILE_DIR}"/*"${ID_PATTERN}"*)
shopt -u nullglob
if [ ${#found[@]} -eq 0 ]; then
  echo "  none - the app's own copy is the only one"
else
  for dir in "${found[@]}"; do
    echo "  removing ${dir}"
    rm -rf "${dir}"
  done
fi

# The manifest of installed extensions, and the list of ids VS Code remembers as uninstalled.
# Both are derived state: the editor rewrites them on the next scan. Entries for this id are
# dropped here so that neither can keep the extension in limbo.
say "the records of it"
node - "${PROFILE_DIR}" "${ID_PATTERN}" <<'NODE'
const fs = require('fs');
const path = require('path');
const [profileDir, pattern] = process.argv.slice(2);
const hit = (v) => JSON.stringify(v).toLowerCase().includes(pattern);

for (const name of ['extensions.json', '.obsolete']) {
	const file = path.join(profileDir, name);
	if (!fs.existsSync(file)) {
		console.log(`  no ${name}`);
		continue;
	}
	const value = JSON.parse(fs.readFileSync(file, 'utf8'));
	const kept = Array.isArray(value) ? value.filter(entry => !hit(entry)) : value;
	if (Array.isArray(value)) {
		fs.copyFileSync(file, `${file}.bak`);
		fs.writeFileSync(file, JSON.stringify(kept));
		console.log(`  ${name}: ${value.length} -> ${kept.length} entries`);
	} else {
		console.log(`  ${name}: not an array, left alone`);
	}
}
NODE

# Disabled and obsolete ids also live in the editor's global state.
say "the editor's global state"
node - "${STATE_FILE}" "${ID_PATTERN}" <<'NODE'
const fs = require('fs');
const [stateFile, pattern] = process.argv.slice(2);
if (!fs.existsSync(stateFile)) {
	console.log(`  no ${stateFile}`);
	process.exit(0);
}
const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
let changed = false;
for (const key of Object.keys(state)) {
	const value = state[key];
	if (!Array.isArray(value)) {
		continue;
	}
	if (!value.some(entry => typeof entry === 'string' && entry.toLowerCase().includes(pattern))) {
		continue;
	}
	const kept = value.filter(entry => !(typeof entry === 'string' && entry.toLowerCase().includes(pattern)));
	console.log(`  ${key}: ${value.join(', ')} -> ${kept.length ? kept.join(', ') : '(nothing)'}`);
	state[key] = kept;
	changed = true;
}
if (changed) {
	fs.copyFileSync(stateFile, `${stateFile}.bak`);
	fs.writeFileSync(stateFile, JSON.stringify(state));
	console.log('  written back, original kept as storage.json.bak');
} else {
	console.log('  nothing there refers to it');
}
NODE

cat <<'TEXT'

== done

Start SidCode again. The SFTP extension is then the app's own copy - the one build.sh
installs and checks. Tools should be in the menu bar between Terminal and Help, with
SFTP/FTP > Create Connection... in it, and Ctrl+Shift+P should find SFTP: Create Connection...

If the Extensions view still lists a stale "not allowed in a stable version" entry, run
"Developer: Reload Window" once, which makes the editor rescan what is actually on disk.
TEXT
