#!/usr/bin/env bash
#
# Build SidCode.
#
#   ./build.sh                          fetch VSCodium, brand it, build it, install the built-ins
#   ./build.sh --brand-only <app dir>   re-brand an app that is already built
#   ./build.sh --server                 build the remote server component, not the desktop app
#   ./build.sh --no-download [...]      build from the extensions already downloaded
#
# The heavy work is VSCodium's own development entry point, `dev/build.sh`: it clones
# Microsoft's vscode at the tag this VSCodium is built from, de-brands it, applies its patches
# and builds. Two things are wrapped around it:
#
#   * our product.json. VSCodium brands itself by merging *its* product.json over the upstream
#     one during prepare, so giving it ours - VSCodium's own with SidCode's fields on top -
#     means the branding survives every prepare step instead of being overwritten by one.
#   * our own patches, from patches/, copied into the checkout's patches/user/ - the folder
#     VSCodium reserves for patches that are not theirs and applies last of all. That is how a
#     change to the editor's own code survives a rebuild. See patches/README.md.
#   * the built-in extensions, copied into the built app afterwards.
#
# The build is the expensive half: Microsoft's vscode source (1.5-3 GB), 30-50 GB of free disk
# and an hour or more. Dependencies are VSCodium's: node (see their .nvmrc), jq, git, python3,
# rustup, yarn, and on Linux gcc, g++, make, pkg-config, libx11-dev, libxkbfile-dev,
# libsecret-1-dev, libkrb5-dev.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${SIDCODE_BUILD_DIR:-${ROOT}/build}"
VSCODIUM="${WORK}/vscodium"

# What SidCode is built from, and the two things worth knowing about it.
#
# It is VSCodium's source with our patches on top, and VSCodium's build fetches Microsoft's own
# `vscode` at the tag it pins - so the supply is three things: that repository, Microsoft's, and the
# npm packages. None of them is needed to *run* an editor that is already built; they are needed to
# build a new one. That is why the reference is pinned and not `master`: `master` moves, and a
# rebuild six months from now would fetch a different VS Code, apply our patches to code they were
# never written against, and fail - or, worse, come up missing a menu our own checks then have to
# catch.
#
# Set VCODIUM_REF to a release tag for a build that can be repeated:
#
#   git ls-remote --tags https://github.com/VSCodium/vscodium 'refs/tags/1.135.*' | tail -5
#   git -C build/vscodium rev-parse HEAD        # the commit you are actually running now
#
# and VCODIUM_REPO to your own fork or mirror if you would rather build from a copy you own:
#
#   VCODIUM_REPO=https://github.com/Sir0Sid/vscodium ./build.sh
VCODIUM_REPO="${VCODIUM_REPO:-https://github.com/VSCodium/vscodium.git}"
VCODIUM_REF="${VCODIUM_REF:-1.135.06055}"

# The extensions built into the editor from the open gallery, and where their downloads are kept
# between builds so that a rebuild does not fetch them again.
BUILTIN_LIST="${ROOT}/extensions/builtin.txt"
VSIX_CACHE="${WORK}/vsix"

say() { printf '\n== %s\n' "$*"; }

# What a patch covers, said out loud as it is copied in. A patch that is missing a file - an
# older copy of it, say - otherwise applies perfectly happily and builds an editor that is
# quietly half patched, which then takes an hour to discover. The Tools menu is that shape of
# fault exactly: registered in the renderer, never drawn, and nothing in the build looks wrong.
summarise_patch() {
  local patch="$1"
  local files hunks
  files="$(grep -c '^diff --git' "${patch}" 2>/dev/null || true)"
  hunks="$(grep -c '^@@' "${patch}" 2>/dev/null || true)"
    printf '  %s - %s hunks in %s files\n' "$(basename "${patch}")" "${hunks:-0}" "${files:-0}"
}

# An older copy of the Tools menu patch is the same change with one hunk missing - the one that
# names Tools in the main process - and it applies perfectly happily. The editor it builds comes
# up with File, Edit, Selection, View, Go, Run, Terminal, Help and no Tools, by which point the
# hour has gone. So the copy about to be built with is checked here, before the build.
check_tools_patch() {
  local patch="$1"

  if [ "$(basename "${patch}")" != "tools-menu.patch" ]; then
    return 0
  fi

  if grep -q 'platform/menubar/electron-main/menubar.ts' "${patch}"; then
    return 0
  fi

  cat >&2 <<'TEXT'
  That is an older copy of tools-menu.patch: it has no hunk for
  src/vs/platform/menubar/electron-main/menubar.ts, which is what names Tools in the main
  process, so this build would come up without a Tools menu. The current copy is 7 hunks in
  6 files and includes that file. Replace the one in patches/ and run this again.
TEXT
  return 1
}

# sidcode/patches/*.patch -> the checkout's patches/user/, which VSCodium applies after its own
# patches and after the OS-specific ones, and which is therefore the place a change to the
# editor's own code belongs.
apply_own_patches() {
  local dest="${VSCODIUM}/patches/user"
  local patch
  local found="no"

  mkdir -p "${dest}"
  for patch in "${ROOT}"/patches/*.patch; do
    if [ -f "${patch}" ]; then
      cp "${patch}" "${dest}/$(basename "${patch}")"
      summarise_patch "${patch}"
      check_tools_patch "${patch}"
      found="yes"
    fi
  done

  if [ "${found}" = "no" ]; then
    echo "  none - see patches/README.md to change the editor's own code"
  fi
}

# Is the Tools menu in the app that was just built? Two halves have to be there, and both are
# silent when they are not: the renderer's registration and the id it publishes to extensions,
# and the main process naming the menu, without which the bar is drawn as the eight menus it
# knows and Tools never appears however right everything else is.
check_tools_menu() {
  local app_dir="$1"
  local renderer="${app_dir}/resources/app/out/vs/workbench/workbench.desktop.main.js"
  local main="${app_dir}/resources/app/out/main.js"
  local drawn verdict

  say "checking the Tools menu"
  drawn="$(grep -oE 'shouldDrawMenu\(["'"'"'][a-zA-Z]+["'"'"']\)' "${main}" 2>/dev/null | sed -E "s/shouldDrawMenu\([\"']//; s/[\"']\)//" | paste -sd' ' - || true)"

  if [ -z "${drawn}" ]; then
    echo "  could not read the menu names out of ${main}" >&2
  else
    verdict="no"
    case " ${drawn} " in *" Tools "*) verdict="yes" ;; esac
    if [ "${verdict}" = "yes" ]; then
      echo "  the main process draws: ${drawn}"
    else
      echo "  THIS APP HAS NO TOOLS MENU - the main process draws: ${drawn}" >&2
      echo "  Tools has to be named in src/vs/platform/menubar/electron-main/menubar.ts, and it" >&2
      echo "  is not in this build, so that app predates that part of the patch. Check the patch" >&2
      echo "  you are building with: patches/tools-menu.patch is 7 hunks in 6 files, and one of" >&2
      echo "  them is that file. An older copy of it builds an editor that looks finished." >&2
    fi
  fi

  if grep -q 'menuBar/tools' "${renderer}" 2>/dev/null; then
    echo "  the renderer publishes menuBar/tools, so extensions can add items to it"
  else
    echo "  THIS APP DOES NOT PUBLISH menuBar/tools - extension items have nowhere to go" >&2
  fi
}

# The SFTP extension is not built here - it is Sid's own fork, kept beside this folder - so
# this finds the VSIX it was packaged into. Newest first, in the two places it is kept:
# shipped beside SidCode's own files (extensions/), then beside this folder (../sids-sftp/).
find_sftp_vsix() {
  local candidate
  for candidate in "${ROOT}"/extensions "${ROOT}"/../sids-sftp; do
    local found
    found="$(ls -1t "${candidate}"/sftp-sid-*.vsix 2>/dev/null | head -1 || true)"
    if [ -n "${found}" ]; then
      echo "${found}"
      return 0
    fi
  done
  return 1
}

# What has just been copied in has to be the copy that knows about the Tools menu.
#
# An older sftp-sid has no `menuBar/tools` in its manifest, so nothing is ever put in Tools,
# and an empty Tools is skipped by our own patch - so the menu bar comes up with File, Edit,
# Selection, View, Go, Run, Terminal, Help and no Tools, on a build where every piece is
# otherwise in place. That is a build that looks finished and is not, so it is checked here,
# at build time, with the version that was installed printed either way.
verify_sftp_builtin() {
  local extension_dir="$1"

  if [ ! -f "${extension_dir}/package.json" ]; then
    echo "  sftp-sid has no package.json in it - the folder is not an extension" >&2
    return 1
  fi

  if ! node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const id = `${p.publisher}.${p.name}@${p.version}`;
const menus = (p.contributes && p.contributes.menus) || {};
if (!menus["menuBar/tools"]) {
  console.error(`  ${id} - no menuBar/tools contribution in that copy`);
  process.exit(1);
}
console.log(`  ${id}, with its entry for the Tools menu`);
process.exit(0);
' "${extension_dir}/package.json" 2>/dev/null; then
    return 1
  fi
}

# sidcode-defaults is no longer only colour files: the Themes menu in Tools is contributed by
# it, and the commands behind it are in its extension.js. A copy that has lost either - an older
# VSIX in its place, a folder copied without the runtime - builds an editor with no Themes menu,
# which is the same shape of failure as the SFTP entry: everything else in place and one menu
# quietly missing. The version that went in is printed either way.
verify_defaults_builtin() {
  local extension_dir="$1"

  if [ ! -f "${extension_dir}/package.json" ]; then
    echo "  sidcode-defaults has no package.json in it - the folder is not an extension" >&2
    return 1
  fi

  if ! node -e '
const fs = require("fs");
const path = require("path");
const dir = process.argv[2];
const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const id = `${p.publisher}.${p.name}@${p.version}`;
const menus = (p.contributes && p.contributes.menus) || {};
const inTools = (menus["menuBar/tools"] || []).some(entry => entry.submenu === "sidcode.themes");
const runtime = Boolean(p.main) && fs.existsSync(path.join(dir, p.main));
const problems = [];
if (!inTools) {
  problems.push("the Themes menu is not in its Tools entry");
}
if (!runtime) {
  problems.push(`there is no ${p.main || "main"} beside it`);
}
if (problems.length > 0) {
  console.error(`  ${id} - ${problems.join(", and ")}`);
  process.exit(1);
}
console.log(`  ${id}, with the Themes menu in Tools`);
' "${extension_dir}/package.json" "${extension_dir}" 2>&1; then
    return 1
  fi
}

# SidCode's own languages extension: the languages nothing in the gallery provides, or provides
# under a licence that cannot ship inside an editor. nginx is the first - the only real nginx
# syntax extension on the open gallery is GPL, which is a licence to install, not to build in.
install_languages_builtin() {
  local extensions_dir="$1"

  rm -rf "${extensions_dir}/sidcode-languages"
  mkdir -p "${extensions_dir}/sidcode-languages"
  cp -R "${ROOT}/languages/." "${extensions_dir}/sidcode-languages/"
  echo "  sidcode-languages"
}

# A built-in that needs another extension will not work without it, and a dependency the gallery
# does not have is exactly how a language ends up looking built in and doing nothing: the Python
# extension ships as a pack that wants Pylance, and Pylance is not on the open gallery. Hard
# requirements are faults; a missing *pack* member is what it is, an absent convenience.
check_builtin_dependencies() {
  local extensions_dir="$1"

  node - "${extensions_dir}" "${BUILTIN_LIST}" <<'JS'
const fs = require('fs');
const path = require('path');
const [dir, listFile] = process.argv.slice(2);

const present = new Map();
for (const entry of fs.readdirSync(dir)) {
  const manifest = path.join(dir, entry, 'package.json');
  if (!fs.existsSync(manifest)) continue;
  try {
    const p = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    if (p.publisher && p.name) present.set(`${p.publisher}.${p.name}`, p.version);
  } catch {
    // a built-in the editor ships rather than one of ours
  }
}

let faults = 0;
let absent = 0;
for (const raw of fs.readFileSync(listFile, 'utf8').split('\n')) {
  const line = raw.trim();
  if (!line || line.startsWith('#')) continue;
  const id = line.split(/\s+/)[0].split('@')[0];
  const manifest = path.join(dir, id, 'package.json');
  if (!fs.existsSync(manifest)) {
    console.log(`  ${id}: NOT in the app`);
    faults++;
    continue;
  }
  const p = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  for (const dep of p.extensionDependencies || []) {
    if (!present.has(dep)) {
      console.log(`  ${id} needs ${dep}, which is not in the app - it will not start`);
      faults++;
    }
  }
  for (const dep of p.extensionPack || []) {
    if (!present.has(dep)) {
      console.log(`  ${id} also bundles ${dep}, which this gallery does not have - that part is simply absent`);
      absent++;
    }
  }
}

if (!faults && !absent) {
  console.log('  every built-in is in the app and has what it needs');
}
JS
}

# What to download for one entry, asked of the registry rather than guessed. Some extensions ship
# a build per platform - a debugger, a linter carrying its own binary - and have no plain file at
# all, so the plain URL is a 404 for them. Prints "<target> <url>", with "-" for the target when
# the extension is one build for everything. Nothing printed means it could not be read.
builtin_download() {
  curl -fsSL --max-time 90 "https://open-vsx.org/api/$1/$2/$3" \
    | node -e '
let body = "";
process.stdin.on("data", chunk => body += chunk);
process.stdin.on("end", () => {
  let release;
  try { release = JSON.parse(body); } catch { process.exit(1); }
  const targets = Object.keys(release.downloads || {});
  const preferred = ["linux-x64", "linux-arm64", "universal"];
  const target = preferred.find(t => targets.includes(t)) || targets[0] || "";
  const url = target ? release.downloads[target] : (release.files || {}).download;
  if (!url) process.exit(1);
  process.stdout.write(`${target || "-"} ${url}`);
});
' || true
}

# extensions/builtin.txt -> the app's own extensions. One `publisher.name@version` per line,
# fetched from the open gallery and unpacked, so the list is the record and changing a version is
# the whole of an update. The VSIXes are cached under build/vsix/, which is what makes a rebuild
# cheap and --no-download possible.
install_gallery_builtins() {
  local extensions_dir="$1"

  if [ ! -f "${BUILTIN_LIST}" ]; then
    echo "  no extensions/builtin.txt - nothing built in from the gallery"
    return 0
  fi

  local total=0 failed=0
  local line id ns name version vsix unpacked pick target url

  while read -r line; do
    case "${line}" in ''|'#'*) continue ;; esac
    id="${line%%[[:space:]]*}"
    total=$((total + 1))

    case "${id}" in
      *.*@*) ;;
      *)
        echo "  ${id}: not publisher.name@version - skipped" >&2
        failed=$((failed + 1))
        continue
        ;;
    esac

    ns="${id%%.*}"
    name="${id#*.}"; name="${name%%@*}"
    version="${id##*@}"

    if [ -n "${NO_DOWNLOAD}" ]; then
      # Offline: whatever is already in the cache for that version, target and all.
      vsix="$(ls -1 "${VSIX_CACHE}/${ns}.${name}-${version}"*.vsix 2>/dev/null | head -1 || true)"
      if [ -z "${vsix}" ]; then
        echo "  ${ns}.${name}@${version}: not downloaded, and --no-download is set" >&2
        failed=$((failed + 1))
        continue
      fi
    else
      pick="$(builtin_download "${ns}" "${name}" "${version}")"
      if [ -z "${pick}" ]; then
        echo "  ${ns}.${name}@${version}: could not be read from the gallery - no such name and" >&2
        echo "    version, or no network" >&2
        failed=$((failed + 1))
        continue
      fi
      target="${pick%% *}"
      url="${pick#* }"
      if [ "${target}" = "-" ]; then
        vsix="${VSIX_CACHE}/${ns}.${name}-${version}.vsix"
      else
        vsix="${VSIX_CACHE}/${ns}.${name}-${version}@${target}.vsix"
      fi

      if [ ! -f "${vsix}" ]; then
        mkdir -p "${VSIX_CACHE}"
        if [ "${target}" = "-" ]; then
          echo "  ${ns}.${name}@${version}: downloading"
        else
          echo "  ${ns}.${name}@${version}: downloading (${target})"
        fi
        if ! curl -fsSL --max-time 300 -o "${vsix}.part" "${url}"; then
          rm -f "${vsix}.part"
          echo "  ${ns}.${name}@${version}: download failed" >&2
          failed=$((failed + 1))
          continue
        fi
        mv "${vsix}.part" "${vsix}"
      fi
    fi

    # A VSIX keeps the extension under `extension/`, and a built-in is the *contents* of that
    # folder - the same shape the SFTP one is unpacked in, for the same reason.
    unpacked="$(mktemp -d)"
    if ! unzip -q "${vsix}" -d "${unpacked}" 2>/dev/null || [ ! -f "${unpacked}/extension/package.json" ]; then
      echo "  ${ns}.${name}@${version}: no extension/package.json in that file" >&2
      rm -rf "${unpacked}"
      failed=$((failed + 1))
      continue
    fi

    rm -rf "${extensions_dir}/${ns}.${name}"
    mkdir -p "${extensions_dir}/${ns}.${name}"
    cp -R "${unpacked}/extension/." "${extensions_dir}/${ns}.${name}/"
    rm -rf "${unpacked}"
    echo "  ${ns}.${name}@${version}"
  done < "${BUILTIN_LIST}"

  if [ "${total}" -eq 0 ]; then
    echo "  extensions/builtin.txt has nothing in it"
    return 0
  fi

  if [ "${failed}" -gt 0 ]; then
    echo "  ${failed} of ${total} did not go in - the editor is still built, just without them" >&2
  fi

  check_builtin_dependencies "${extensions_dir}" || true
  return 0
}

install_builtins() {
  local app_dir="$1"
  local extensions_dir="${app_dir}/resources/app/extensions"

  if [ ! -d "${extensions_dir}" ]; then
    echo "no ${extensions_dir} - is that a built app?" >&2
    return 1
  fi

  # Every built-in here comes out of a .vsix, which is a zip.
  if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip is missing, and the built-in extensions are unpacked with it:" >&2
    echo "  sudo apt install -y unzip" >&2
    return 1
  fi

  say "installing the built-in extensions"
  node "${ROOT}/tools/make-defaults.mjs"
  rm -rf "${extensions_dir}/sidcode-defaults"
  mkdir -p "${extensions_dir}/sidcode-defaults"
  cp -R "${ROOT}/defaults/." "${extensions_dir}/sidcode-defaults/"
  echo "  sidcode-defaults"

  if ! verify_defaults_builtin "${extensions_dir}/sidcode-defaults"; then
    cat >&2 <<'TEXT'
  sidcode-defaults went in without the Themes menu, so Tools would come up with SFTP/FTP in it
  and nothing else. It is written by node tools/make-defaults.mjs from defaults/ - run that, and
  check that defaults/extension.js is there, then run this script again.
TEXT
    return 1
  fi

  local vsix
  if ! vsix="$(find_sftp_vsix)"; then
    cat >&2 <<'TEXT'
  no sftp-sid-*.vsix found, so SFTP cannot be built in - and with nothing in it the Tools
  menu is empty and is left out of the menu bar entirely.

  Package it from Sid's fork:
    cd ../sids-sftp && npm install && npm run compile && npx @vscode/vsce package
  then run this script again, or drop the .vsix in sidcode/extensions/ and run:
    ./build.sh --brand-only <app dir>
TEXT
    return 1
  fi

  # A VSIX keeps its extension under `extension/`, and a built-in extension is the *contents*
  # of that folder - unzipping it straight in gives `sftp-sid/extension/package.json`, which is
  # a directory with no package.json and is therefore skipped, leaving SFTP silently absent.
  #
  # Unpacked outside the app and copied in rather than moved in: an editor that is running
  # holds that folder open, and renaming into it fails with "Device or resource busy" - which
  # abandons the rest of this script half done. Copying cannot fail that way. Same as the
  # defaults above, which are copied for exactly this reason.
  local unpacked
  unpacked="$(mktemp -d)"
  unzip -q "${vsix}" -d "${unpacked}"
  rm -rf "${extensions_dir}/sftp-sid"
  mkdir -p "${extensions_dir}/sftp-sid"
  cp -R "${unpacked}/extension/." "${extensions_dir}/sftp-sid/"
  rm -rf "${unpacked}" "${extensions_dir}/sftp-sid.unpacked"
  echo "  sftp-sid from $(basename "${vsix}")"

  if ! verify_sftp_builtin "${extensions_dir}/sftp-sid"; then
    cat >&2 <<TEXT

  That VSIX is older than the Tools menu (it was packaged before the SFTP/FTP entry was
  added), so this build would come up without a Tools menu. Package a current one:
    cd "$(cd "${ROOT}/../sids-sftp" && pwd)" && npm install && npm run compile && npx @vscode/vsce package
  copy the new sftp-sid-*.vsix into ${ROOT}/extensions and run this script again.
  (Delete the old .vsix there, or this picks it up again - newest by date wins.)
TEXT
    return 1
  fi

  install_languages_builtin "${extensions_dir}"
  install_gallery_builtins "${extensions_dir}"
}

find_app_dir() {
  local candidate
  for candidate in "${VSCODIUM}/VSCode-linux-x64" "${VSCODIUM}/VSCodium-linux-x64"; do
    if [ -d "${candidate}/resources/app/extensions" ]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

# The remote server component: what a Remote-SSH session runs on the host, so that the project and
# everything that touches it stay there and the editor on somebody's PC is only the front of it.
#
# It is the same source, the same patches and the same branding as the desktop app - VSCodium builds
# one for its own releases, with a switch of its own. That switch is the part belonging to them and
# it can change between releases, so the *artifact* is what decides whether this worked: a build that
# leaves no server directory behind says so and packages nothing, rather than packing a desktop
# build under a server's name and failing later, on somebody's connection.
find_reh_dir() {
  local candidate
  for candidate in "${WORK}"/vscode-reh-linux-* "${WORK}"/vscodium-reh-linux-* "${VSCODIUM}"/../vscode-reh-linux-*; do
    if [ -d "${candidate}" ]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

build_server_component() {
  local reh_dir version commit arch artifact destination

  say "building the server component"
  (cd "${VSCODIUM}" && SHOULD_BUILD_REH=yes ./dev/build.sh) || {
    echo "VSCodium's build failed - see above" >&2
    return 1
  }

  reh_dir="$(find_reh_dir || true)"
  if [ -z "${reh_dir}" ]; then
    cat >&2 <<'TEXT'
  VSCodium's build finished without leaving a server build behind, so nothing was packaged.
  It builds one for its own releases, so the switch exists - but the variable is theirs and can
  change between releases. Look in the checkout's dev/build.sh for SHOULD_BUILD_REH (or whatever
  that file now calls its server target) and set it in build_server_component() in this script.
TEXT
    return 1
  fi

  version="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "${VSCODIUM}/package.json" 2>/dev/null || echo unknown)"
  commit="$(git -C "${VSCODIUM}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  arch="$(uname -m)"
  case "${arch}" in
    x86_64) arch=x64 ;;
    aarch64) arch=arm64 ;;
  esac

  # The name comes from `tools/artifact-name.mjs`, which reads server/artifact.json - the same file
  # the editor's settings were generated from, so the artifact and the URL it is fetched from are
  # the same definition.
  artifact="$(node "${ROOT}/tools/artifact-name.mjs" name "${version}" "${commit}" "${arch}")"
  destination="$(dirname "${ROOT}")/${artifact}"

  echo "  packing $(basename "${reh_dir}") as ${artifact}"
  tar --warning=no-file-changed -czf "/tmp/${artifact}" -C "$(dirname "${reh_dir}")" "$(basename "${reh_dir}")"
  mv "/tmp/${artifact}" "${destination}"

  echo
  echo "${destination}"
  du -h "${destination}" | sed 's/^/  /'
  echo "  upload it where server/artifact.json says it is fetched from; ${ROOT}/tools/publish-server.sh"
  echo "  prints that URL for this build."
}

# Our patches, checked against the source before the compile rather than in the middle of it.
#
# Their build applies them from `patches/user/` after it has fetched and de-branded Microsoft's
# source, so the tree they are meant for is `vscode/` inside the checkout - and that only exists once
# their prepare step has run. When it does exist, this is the same `git apply` they will do, a
# second earlier: a patch that no longer fits says so in seconds, naming the patch, instead of at the
# end of an hour. When it does not exist yet there is nothing to check against, and the Tools-menu
# check after the build is the backstop it already is.
preflight_own_patches() {
  local patch
  local failed="no"

  if [ ! -d "${VSCODIUM}/vscode" ]; then
    say "our patches: no prepared source here to check them against yet"
    echo "  their build fetches it during this run, and check_tools_menu runs after the build"
    return 0
  fi

  say "checking our patches against the source"

  for patch in "${ROOT}"/patches/*.patch; do
    if [ ! -f "${patch}" ]; then
      continue
    fi

    if git -C "${VSCODIUM}/vscode" apply --check "${patch}" 2>/dev/null; then
      echo "  fits: $(basename "${patch}")"
    else
      echo "  DOES NOT FIT: $(basename "${patch}")" >&2
      failed="yes"
    fi
  done

  if [ "${failed}" = "yes" ]; then
    echo >&2
    echo "  The patches above no longer apply to this source, so this build would fail - or worse," >&2
    echo "  succeed without them. The source is at VSCodium ${VCODIUM_REF}; run" >&2
    echo "  ${ROOT}/tools/make-patch.sh against an editor built from it to make them fit again." >&2
    return 1
  fi
}

usage_text() {
  echo "usage: ./build.sh [--brand-only <app dir>] [--server] [--no-download]" >&2
  echo "  an app folder is one holding resources/app/ - usually build/vscodium/VSCode-linux-x64," >&2
  echo "  and \`--brand-only\` on its own finds it" >&2
  echo "  \`--server\` builds the remote server component instead of the desktop app" >&2
}

# Flags, in any order: --brand-only [app folder], --server, --no-download.
BRAND_ONLY=""
SERVER_MODE=""
NO_DOWNLOAD="${SIDCODE_NO_DOWNLOAD:-}"
APP_ARG=""
for arg in "$@"; do
  case "${arg}" in
    --brand-only) BRAND_ONLY="yes" ;;
    --server) SERVER_MODE="yes" ;;
    --no-download) NO_DOWNLOAD="yes" ;;
    --*) echo "unknown option: ${arg}" >&2; usage_text; exit 1 ;;
    *)
      # A second folder used to overwrite the first without a word, which is how
      # `--brand-only <app> Quick` - a pasted comment, a stray word - brands nothing and says
      # nothing: the folder that is checked is the stray one, and it is not an app folder.
      if [ -n "${APP_ARG}" ]; then
        echo "two app folders were given: ${APP_ARG} and ${arg}" >&2
        echo "only one is used, so which one that is should not be a guess:" >&2
        usage_text
        exit 1
      fi
      APP_ARG="${arg}" ;;
  esac
done

if [ -n "${BRAND_ONLY}" ] && [ -n "${SERVER_MODE}" ]; then
  echo "--brand-only re-brands an app that is already built; --server builds the server component." >&2
  echo "They are different errands - run them one at a time." >&2
  exit 1
fi

if [ -n "${BRAND_ONLY}" ]; then
  APP_DIR="${APP_ARG}"
  if [ -z "${APP_DIR}" ]; then
    APP_DIR="$(find_app_dir || true)"
  fi
  [ -n "${APP_DIR}" ] || { usage_text; exit 1; }
  if [ ! -d "${APP_DIR}" ]; then
    echo "no app folder at ${APP_DIR}" >&2
    found="$(find_app_dir || true)"
    if [ -n "${found}" ]; then
      echo "there is one at ${found} - is that the folder you meant?" >&2
    else
      usage_text
    fi
    exit 1
  fi
  APP_DIR="$(cd "${APP_DIR}" && pwd)"

  say "branding ${APP_DIR}"
  node "${ROOT}/tools/apply-branding.mjs" "${APP_DIR}/resources/app/product.json"
  install_builtins "${APP_DIR}"
  check_tools_menu "${APP_DIR}"

  # Which copy was changed, said out loud, and the two things that can still keep the change out
  # of the editor that is started. `--brand-only` writes into an app *folder*: the app that runs
  # is not always the app that was built (the installer puts a copy in ~/.local/share/sidcode),
  # and an extension of the same id sitting in the editor's profile is loaded in place of the
  # built-in one. Either of them turns a finished branding into "it did not go in", which is a
  # puzzle worth answering here rather than in the menu bar.
  cat <<TEXT

== branded ${APP_DIR}

That is the copy that changed. Two things can still keep the change out of the editor you start:
TEXT

  said="no"

  if [ -d "${HOME}/.local/share/sidcode/resources/app" ] && [ "${HOME}/.local/share/sidcode" != "${APP_DIR}" ]; then
    echo "  * ${HOME}/.local/share/sidcode is a copy, not a link, so it still holds the old files."
    echo "    Put this build there - quitting SidCode first - and run the sudo lines it prints:"
    echo "      ${ROOT}/tools/install-sidcode.sh ${APP_DIR}"
    said="yes"
  fi

  for id in sftp-sid sidcode-defaults; do
    for copy in "${HOME}/.sidcode/extensions"/*"${id}"*; do
      [ -d "${copy}" ] || continue
      echo "  * ${id} is installed in the editor's profile as well:"
      echo "      ${copy}"
      echo "    A copy in the profile is loaded in place of the app's own, so an older one there"
      echo "    hides what was just branded. Remove it in the Extensions view, then start SidCode."
      said="yes"
    done
  done

  if [ "${said}" = "no" ]; then
    echo "  nothing - the copy that is started is the one just branded"
  fi

  exit 0
fi

for tool in git node yarn; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "SidCode's build needs ${tool}, which is not on PATH" >&2; exit 1; }
done

# The factory first. When the machinery is in this repo - taken there by
# `tools/take-the-factory.sh` - it is copied out and used, and nothing is fetched for it: the same
# idea as the pinned ref below, extended from the checkout to the scripts that make it.
FACTORY="${ROOT}/factory"
if [ -d "${FACTORY}/dev" ]; then
  say "the factory in this repo (${FACTORY}) - nothing fetched for the machinery"
  mkdir -p "${VSCODIUM}"
  # Copied over whatever is already here rather than replacing the folder: a built app sits beside
  # this checkout, and taking an hour of building away to copy some scripts is a poor trade.
  tar --warning=no-file-changed -czf - -C "${FACTORY}" . | tar -xzf - -C "${VSCODIUM}"
  sed -n '1p' "${FACTORY}/FACTORY" 2>/dev/null | sed 's/^/  /'
else
say "VSCodium source (${VCODIUM_REF} from ${VCODIUM_REPO})"
if [ -d "${VSCODIUM}/.git" ]; then
  # A pinned tag or commit that is already checked out needs nothing from the network, and that is
  # what makes a saved copy of the source worth keeping (`tools/save-source.sh`). A *branch* always
  # fetches: a branch is a moving target, and skipping that would quietly build the same old code
  # for ever while looking like it had updated.
  here="$(git -C "${VSCODIUM}" rev-parse HEAD 2>/dev/null || true)"
  wanted="$(git -C "${VSCODIUM}" rev-parse --verify --quiet "${VCODIUM_REF}^{commit}" 2>/dev/null || true)"
  is_branch="no"
  if git -C "${VSCODIUM}" show-ref --verify --quiet "refs/heads/${VCODIUM_REF}"; then
    is_branch="yes"
  fi

  if [ "${is_branch}" = "no" ] && [ -n "${wanted}" ] && [ "${wanted}" = "${here}" ]; then
    echo "  already at ${VCODIUM_REF} (${here:0:12}) - nothing to fetch"
  else
    git -C "${VSCODIUM}" fetch --tags --depth 1 origin "${VCODIUM_REF}"
    git -C "${VSCODIUM}" checkout FETCH_HEAD
    echo "  now at $(git -C "${VSCODIUM}" rev-parse --short HEAD)"
  fi
else
  mkdir -p "${WORK}"
  git clone --depth 1 --branch "${VCODIUM_REF}" "${VCODIUM_REPO}" "${VSCODIUM}"
fi
fi

say "branding it as SidCode"
node "${ROOT}/tools/merge-product.mjs" "${VSCODIUM}"
cp "${ROOT}/branding/product.json" "${VSCODIUM}/product.json"
"${ROOT}/tools/apply-icons.sh" "${VSCODIUM}"

say "our own patches"
apply_own_patches

preflight_own_patches || exit 1

if [ -n "${SERVER_MODE}" ]; then
  build_server_component
  exit $?
fi

# VSCodium's dependency list includes rustup, and without it the build stops at the very
# end: the CLI (the tunnel client) is built with rust at a point where the editor itself
# has already been assembled. That is the wrong half to lose - and the wrong end of an
# hour-long build to find out at. `SHOULD_BUILD_CLI=no` is VSCodium's own switch for
# leaving the CLI out, which is what this does when rustup is not there.
if ! command -v rustup >/dev/null 2>&1; then
  echo
  echo "no rustup on PATH - building without the CLI; https://rustup.rs adds it"
  export SHOULD_BUILD_CLI=no
fi

say "building - this is the long part"
BUILD_STATUS=0
(cd "${VSCODIUM}" && ./dev/build.sh) || BUILD_STATUS=$?

# The built-ins go in whether or not VSCodium got to the end of its own build. The app
# folder is assembled minutes before its last steps - its tunnel CLI, which is what stops
# when rust is not installed - so a build that ends there has still produced the whole
# editor, and leaving it without Sid's extensions (and, with an empty Tools menu, without
# the menu bar on Linux) is the one thing that must not happen. A failed build is
# reported again at the end; this only decides that the app is finished first.
if APP_DIR="$(find_app_dir)"; then
  APP_DIR="$(cd "${APP_DIR}" && pwd)"
  install_builtins "${APP_DIR}"
  check_tools_menu "${APP_DIR}"

  if [ "${BUILD_STATUS}" -ne 0 ]; then
    DONE_NOTE=" - VSCodium's own build ended with status ${BUILD_STATUS}; see above"
  else
    DONE_NOTE=""
  fi

BUILT_FROM="It was built from VSCodium ${VCODIUM_REF} (${VCODIUM_REPO}) at $(git -C "${VSCODIUM}" rev-parse --short HEAD 2>/dev/null || echo 'an unknown commit')."

if [ -d "${FACTORY}/dev" ]; then
  BUILT_FROM="It was built from the factory in this repo: $(sed -n '1p' "${FACTORY}/FACTORY" | tr -s ' ')"
fi

  cat <<TEXT

== done${DONE_NOTE}

The app is at ${APP_DIR}
Run it with: ${APP_DIR}/bin/sidcode

${BUILT_FROM}
To keep that source, so that a rebuild never depends on it still being there:

  ${ROOT}/tools/save-source.sh

One command is left, and a rebuild resets it every time. Chromium's sandbox helper has to be
owned by root with the setuid bit, and a build cannot do that to its own output - so without
this SidCode starts and immediately exits, saying nothing, because its launcher discards the
error:

  sudo chown root:root ${APP_DIR}/chrome-sandbox
  sudo chmod 4755 ${APP_DIR}/chrome-sandbox

Then, to put Sid's own extensions in:
  ${ROOT}/tools/install-extensions.sh ${APP_DIR}/bin/sidcode

To start it, and to check that this build has the Tools menu and that the copy you start is
the one that was just built:
  ${ROOT}/tools/install-sidcode.sh ${APP_DIR}
  ${ROOT}/tools/check-build.sh ${APP_DIR}
TEXT
else
  cat <<TEXT

== no built app was found under ${VSCODIUM}
Look for a VSCode-*-x64 folder there and pass it to:
  ${ROOT}/build.sh --brand-only <that folder>
TEXT
fi

exit "${BUILD_STATUS}"
