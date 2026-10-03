#!/usr/bin/env bash
#
# Which SidCode am I running, and has it got the Tools menu?
#
#   ./tools/check-build.sh [path to an app folder]
#
# Read-only; it changes nothing. It prints, for the built app and for the installed copy:
#
#   * the version of the bundled SFTP extension, and whether that copy carries the
#     `menuBar/tools` entry the Tools menu is filled from
#   * whether the Tools menu patch is compiled into the workbench
#   * any SFTP extension installed in the editor's own profile, which is loaded ahead of a
#     built-in one of the same id and can therefore hide the built-in copy
#   * which of those copies is actually running
#
# Why it is worth a script: the app is *built* into build/vscodium/, but `sidcode` on PATH is
# a *copy* of it in ~/.local/share/sidcode, put there by tools/install-sidcode.sh. Rebuilding
# changes the first and not the second, so "I rebuilt it and nothing changed" is the normal
# result of running the old copy - and nothing in the editor says which one it is.
#
# It ends with what to do about whatever it found. Nothing in the editor's menu bar is a
# coincidence: with no items in it, the Tools menu is left out of the bar entirely, so "no
# Tools" and "SFTP is not in the editor" are the same fault seen twice.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
INSTALLED="${HOME}/.local/share/sidcode"
PROFILE="${HOME}/.sidcode/extensions"

info() { printf '   %s\n' "$*"; }
head_() { printf '\n== %s\n' "$*"; }

# A built app folder, whichever name VSCodium gave it this time.
find_built_app() {
  local candidate
  for candidate in "${ROOT}/build/vscodium/VSCode-linux-x64" "${ROOT}/build/vscodium/VSCodium-linux-x64" \
                   "${ROOT}/build/vscodium/VSCode-linux-arm64" "${ROOT}/build/vscodium/VSCodium-linux-arm64"; do
    if [ -d "${candidate}/resources/app/extensions" ]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

# The bundled SFTP extension of one app folder: its version, and whether it has the entry
# that the Tools menu is filled from. `node` because that is what a build machine already has.
report_builtin() {
  local dir="$1"
  local manifest="${dir}/resources/app/extensions/sftp-sid/package.json"

  if [ ! -f "${manifest}" ]; then
    info "sftp-sid is not built in - Tools would be empty, and an empty Tools is left out"
    return 1
  fi

  node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const has = !!(p.contributes && p.contributes.menus && p.contributes.menus["menuBar/tools"]);
console.log(`   sftp-sid ${p.publisher}.${p.name}@${p.version} - ` + (has
  ? "carries the SFTP/FTP entry for the Tools menu"
  : "NO menuBar/tools entry, so this copy is older than the Tools menu"));
' "${manifest}"
}

# Sid's own defaults extension carries the Themes menu as well as the colours, and a copy of it
# that predates that has the themes and none of the menu - which looks exactly like a build that
# did not pick the change up.
report_defaults() {
  local dir="$1"
  local extension="${dir}/resources/app/extensions/sidcode-defaults"
  local manifest="${extension}/package.json"

  if [ ! -f "${manifest}" ]; then
    info "sidcode-defaults is not built in - no Themes menu in Tools, and no Sid's colours"
    return 0
  fi

  node -e '
const fs = require("fs");
const path = require("path");
const dir = process.argv[2];
const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const c = p.contributes || {};
const menus = c.menus || {};
const themes = (c.themes || []).length;
const inTools = (menus["menuBar/tools"] || []).some(e => e.submenu === "sidcode.themes");
const runtime = Boolean(p.main) && fs.existsSync(path.join(dir, p.main));
console.log(`   sidcode-defaults ${p.publisher}.${p.name}@${p.version} - ${themes} colour set(s), ` +
  (inTools ? "Themes in Tools" : "NO Themes menu") + ", " +
  (runtime ? `runtime ${p.main} there` : `no ${p.main || "main"} beside it`));
if (!inTools || !runtime) {
  console.log("     that copy predates the Themes menu: it colours the editor and cannot put a menu in Tools");
}
' "${manifest}" "${extension}"
}

# The version of the SFTP extension inside one copy of the app, or nothing when there is no copy
# there. This is the fact that says whether the extension a window loads can contain the change that
# was just made: a copy of the app is a copy, so its built-in extensions stay as they were until the
# copy itself is replaced - and a version number is the whole difference between "the fix went in"
# and "the window is still running yesterday's extension".
builtin_sftp_version() {
  local manifest="$1/resources/app/extensions/sftp-sid/package.json"

  [ -f "${manifest}" ] || return 0

  node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "${manifest}" 2>/dev/null || true
}

# The one fact the verdict turns on, asked of any copy of the app: is its bundled SFTP the
# one that carries the Tools entry? Printed as yes / no / missing.
builtin_tools() {
  local manifest="$1/resources/app/extensions/sftp-sid/package.json"

  if [ ! -f "${manifest}" ]; then
    echo "missing"
    return 0
  fi

  node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const has = !!(p.contributes && p.contributes.menus && p.contributes.menus["menuBar/tools"]);
console.log(has ? "yes" : "no");
' "${manifest}"
}

# How many times a word appears in one of the app's compiled files. `grep -c` counts lines,
# and the workbench is minified onto a handful of very long ones, so this counts matches.
count_in() {
  local word="$1"
  local file="$2"

  if [ ! -f "${file}" ]; then
    echo 0
    return 0
  fi

  grep -o "${word}" "${file}" 2>/dev/null | wc -l | tr -d ' ' || true
}

# Is the Tools menu in this app's own code at all? Both halves of the patch have to be there:
# the menu id (MenubarToolsMenu, declared in the editor and used to register the entry) and
# the name the patch publishes it to extensions under (menuBar/tools, which the SFTP
# extension's manifest is written against). Either missing is a build from before the patch.
compiled_patch_count() {
  count_in 'MenubarToolsMenu' "$1/resources/app/out/vs/workbench/workbench.desktop.main.js"
}

compiled_published_key_count() {
  count_in 'menuBar/tools' "$1/resources/app/out/vs/workbench/workbench.desktop.main.js"
}

# The menus the main process draws, read out of the compiled Electron main bundle. This is the
# half that catches people out: the renderer can register a top level menu, publish it to
# extensions and fill it, and the bar still comes up without it, because the menu bar itself is
# assembled in platform/menubar/electron-main/menubar.ts from a list of menu names - File, Edit,
# Selection, View, Go, Run, Terminal, Window, Help. A menu that is not named there is never drawn.
main_menus() {
  local bundle="$1/resources/app/out/main.js"

  if [ ! -f "${bundle}" ]; then
    echo "no main bundle"
    return 0
  fi

  local drawn
  drawn="$(grep -oE 'shouldDrawMenu\(["'"'"'][a-zA-Z]+["'"'"']\)' "${bundle}" 2>/dev/null \
    | sed -E "s/shouldDrawMenu\([\"']//; s/[\"']\)//" | paste -sd' ' - || true)"

  if [ -z "${drawn}" ]; then
    echo "none found"
  else
    echo "${drawn}"
  fi
}

# The app folder a launcher belongs to. What VSCodium ships is `<app>/bin/sidcode`, so the app
# itself is the folder above `bin` - and getting that wrong points the checks at files that do
# not exist, which is worse than not checking.
app_dir_of_launcher() {
  local dir
  dir="$(dirname "$1")"

  if [ "$(basename "${dir}")" = "bin" ]; then
    dir="$(dirname "${dir}")"
  fi

  printf '%s' "${dir}"
}

# Chromium's sandbox helper is setuid root, and only sudo can make it so. Nothing that copies or
# rebuilds an app folder can carry that across, so after every build or install it is wrong again
# - and the editor then starts and immediately exits, with the error hidden by its own launcher.
# `ok` or `<owner> <mode>` or `missing`.
sandbox_state() {
  local file="$1/chrome-sandbox"

  if [ ! -e "${file}" ]; then
    echo "missing"
    return 0
  fi

  local owner mode
  owner="$(stat -c '%U' "${file}" 2>/dev/null || echo '?')"
  mode="$(stat -c '%a' "${file}" 2>/dev/null || echo '?')"

  if [ "${owner}" = "root" ] && [ "${mode}" = "4755" ]; then
    echo "ok"
  else
    echo "${owner} ${mode}"
  fi
}

draws_tools() {
  case " $(main_menus "$1") " in
    *" Tools "*) echo "yes" ;;
    *) echo "no" ;;
  esac
}

# A disabled or half-removed extension contributes nothing: no commands, no views, and nothing
# in Tools. Both places that can say so are cheap to read.
suppressed_in_profile() {
  local hits=0
  local id="sftp-sid"

  if [ -f "${PROFILE}/.obsolete" ] && grep -qi "${id}" "${PROFILE}/.obsolete" 2>/dev/null; then
    echo "  listed in ${PROFILE}/.obsolete - the editor treats it as uninstalled"
    hits=$((hits + 1))
  fi

  local state="${HOME}/.config/SidCode/User/globalStorage/storage.json"
  if [ -f "${state}" ] && grep -qi "${id}" "${state}" 2>/dev/null; then
    echo "  named in ${state}"
    grep -o "\"[^\"]*[Dd]isable[^\"]*\":\[[^]]*\]" "${state}" 2>/dev/null | head -3 | sed 's/^/    /'
    hits=$((hits + 1))
  fi

  return 0
}

# What the build put in: SidCode's own languages extension, and everything extensions/builtin.txt
# asks for. Read against that list rather than against the folder, because the question is whether
# what the build asks for is actually in the app - a language that quietly did not go in looks
# exactly like one the editor has no support for, which is the same fault seen twice.
report_builtins() {
  local dir="$1"
  local extensions="${dir}/resources/app/extensions"
  local list="${ROOT}/extensions/builtin.txt"
  local line id version missing=0 total=0

  if [ -f "${extensions}/sidcode-languages/package.json" ]; then
    version="$(node -e 'console.log(require(process.argv[1]).version)' "${extensions}/sidcode-languages/package.json" 2>/dev/null || echo '?')"
    if [ -f "${extensions}/sidcode-languages/syntaxes/nginx.tmLanguage.json" ]; then
      info "sidcode-languages@${version}: nginx, with its grammar"
    else
      info "sidcode-languages@${version}: no nginx grammar in it - nginx files will not colour"
      missing=$((missing + 1))
    fi
  else
    info "sidcode-languages: NOT in that copy - nginx is plain text there, and the .conf"
    info "  associations in its settings point at a language nothing provides"
    missing=$((missing + 1))
  fi

  if [ ! -f "${list}" ]; then
    info "no extensions/builtin.txt to compare against"
    return 0
  fi

  while read -r line; do
    case "${line}" in ''|'#'*) continue ;; esac
    id="${line%%[[:space:]]*}"
    id="${id%@*}"
    total=$((total + 1))
    if [ -f "${extensions}/${id}/package.json" ]; then
      version="$(node -e 'console.log(require(process.argv[1]).version)' "${extensions}/${id}/package.json" 2>/dev/null || echo '?')"
      info "built in: ${id}@${version}"
    else
      info "NOT built in: ${id} - put it in with: ${ROOT}/build.sh --brand-only ${dir}"
      missing=$((missing + 1))
    fi
  done < "${list}"

  if [ "${missing}" -eq 0 ]; then
    info "every language and linter this build asks for is in that copy"
  fi
}

report_copy() {
  local label="$1"
  local dir="$2"

  head_ "${label}: ${dir}"
  if [ ! -d "${dir}/resources/app/extensions" ]; then
    info "no resources/app/extensions there - that is not a built app"
    return 0
  fi

  report_builtin "${dir}" || true
  report_defaults "${dir}" || true
  report_builtins "${dir}" || true

  local bundle="${dir}/resources/app/out/vs/workbench/workbench.desktop.main.js"
  if [ -f "${bundle}" ]; then
    info "in the compiled workbench, MenubarToolsMenu: $(count_in 'MenubarToolsMenu' "${bundle}") (5 in a build with the patch, 4 with one that predates the menu-service hunk)"
    info "                            menuBar/tools: $(count_in 'menuBar/tools' "${bundle}") (1 in a build with the patch)"
    info "  a 0 on either line is a build from before the patch was in place"
  else
    info "no compiled workbench at ${bundle}"
  fi

  # The half that decides whether the menu is drawn at all, whatever the renderer registered.
  info "menus the main process draws: $(main_menus "${dir}")"
  if [ "$(draws_tools "${dir}")" = "no" ]; then
    info "  Tools is not among them, so no rebuild of the extension or the profile can make it"
    info "  appear: this app predates the main-process half of patches/tools-menu.patch"
  fi

  local sandbox
  sandbox="$(sandbox_state "${dir}")"
  if [ "${sandbox}" = "ok" ]; then
    info "chrome-sandbox: root-owned with the setuid bit, so this copy can start"
  elif [ "${sandbox}" = "missing" ]; then
    info "chrome-sandbox: not there at all, which is not an app folder"
  else
    info "chrome-sandbox: owned by ${sandbox} - this copy starts and immediately exits until:"
    info "  sudo chown root:root ${dir}/chrome-sandbox && sudo chmod 4755 ${dir}/chrome-sandbox"
  fi

  info "that folder was last written $(date -r "${dir}" '+%Y-%m-%d %H:%M')"
}

head_ "where SidCode is"

# Which app the command starts, before anything else: `sidcode` can be a launcher somewhere on
# PATH pointing at either copy, and the interesting question is not whether a copy is correct
# but whether that copy is the one being started.
launcher="$(command -v sidcode 2>/dev/null || true)"
launcher_is_installed="no"
launcher_dir=""
if [ -z "${launcher}" ]; then
  info "no \`sidcode\` on PATH - start one of the copies below by its path"
else
  resolved="$(readlink -f "${launcher}" 2>/dev/null || echo "${launcher}")"
  info "\`sidcode\` is ${launcher}"
  info "  which is ${resolved}"
  case "$(app_dir_of_launcher "${resolved}")" in
    "${INSTALLED}") launcher_is_installed="yes"; info "  so it starts the installed copy" ;;
    "${ROOT}"/*) info "  so it starts the app under ${ROOT}" ;;
    *) info "  which is not one of the two copies below" ;;
  esac

  # Whichever copy it is, that copy has to be able to start before any of the rest matters.
  if [ -d "$(app_dir_of_launcher "${resolved}")/resources/app" ]; then
    launcher_dir="$(app_dir_of_launcher "${resolved}")"
  fi
fi

if [ $# -ge 1 ]; then
  if [ ! -d "$1" ]; then
    echo "no app folder at $1" >&2
    exit 1
  fi
  BUILT="$(cd "$1" && pwd)"
else
  BUILT="$(find_built_app || true)"
fi

if [ -n "${BUILT}" ]; then
  report_copy "the build" "${BUILT}"
else
  head_ "the build"
  info "nothing built under ${ROOT}/build/vscodium - pass the app folder as an argument"
fi

if [ -d "${INSTALLED}" ]; then
  report_copy "the installed copy (what ~/.local/bin/sidcode starts)" "${INSTALLED}"
else
  head_ "the installed copy"
  info "nothing at ${INSTALLED} - ${HOME}/.local/bin/sidcode does not point at anything"
fi

# An extension installed into the profile is loaded in place of a built-in with the same id,
# so an older SFTP in here hides a current one in the app.
head_ "SFTP installed in the editor's profile (${PROFILE})"
profile_hits=0
profile_missing_tools=0
shopt -s nullglob
for manifest in "${PROFILE}"/*sftp*/package.json; do
  profile_hits=$((profile_hits + 1))
  info "${manifest}"
  node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const has = !!(p.contributes && p.contributes.menus && p.contributes.menus["menuBar/tools"]);
console.log(`     ${p.publisher}.${p.name}@${p.version} - ` + (has
  ? "has the Tools entry; it is loaded in place of the built-in copy, which is only a problem if the two differ"
  : "NO menuBar/tools entry, and being in the profile it hides the built-in copy"));
' "${manifest}" || true
  if ! grep -q '"menuBar/tools"' "${manifest}" 2>/dev/null; then
    profile_missing_tools=$((profile_missing_tools + 1))
  fi
done
shopt -u nullglob
if [ "${profile_hits}" -eq 0 ]; then
  info "none - the app's own copy is the one the editor loads"
fi

# The same rule for Sid's colours: the VSIX is the way to try them in another editor, and the
# README says so - which leaves a copy in here that is loaded instead of the app's own. A 1.1.x
# one colours the editor exactly as it always did and has no Themes menu, so the change looks
# like it never went in.
head_ "SidCode Defaults installed in the editor's profile (${PROFILE})"
defaults_hits=0
defaults_old=0
shopt -s nullglob
for manifest in "${PROFILE}"/*sidcode-defaults*/package.json; do
  defaults_hits=$((defaults_hits + 1))
  info "${manifest}"
  node -e '
const fs = require("fs");
const path = require("path");
const dir = path.dirname(process.argv[1]);
const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const c = p.contributes || {};
const inTools = ((c.menus || {})["menuBar/tools"] || []).some(e => e.submenu === "sidcode.themes");
const runtime = Boolean(p.main) && fs.existsSync(path.join(dir, p.main));
console.log(`     ${p.publisher}.${p.name}@${p.version} - ` + (inTools && runtime
  ? "has the Themes menu; being in the profile it is loaded in place of the built-in copy"
  : "NO Themes menu, and being in the profile it hides the built-in copy that has one"));
' "${manifest}" || true
  if ! grep -q '"sidcode.themes"' "${manifest}" 2>/dev/null; then
    defaults_old=$((defaults_old + 1))
  fi
done
shopt -u nullglob
if [ "${defaults_hits}" -eq 0 ]; then
  info "none - the app's own copy is the one the editor loads, so --brand-only reaches it"
fi

# Records that stop it loading, whatever the extension folder itself says.
head_ "anything in the profile that would stop it loading"
suppressed="$(suppressed_in_profile)"
profile_records="no"
if [ -n "${suppressed}" ]; then
  printf '%s\n' "${suppressed}"
  profile_records="yes"
else
  info "nothing - no disabled or obsolete record for it"
fi

# Which copy is it, actually? `sidcode` on PATH is a symlink into the install, so the command
# that was typed says nothing about it; /proc/<pid>/exe is the binary that is really running.
head_ "running now"
running_copy="none"
running_dir=""
running_found="no"
unreadable_found="no"
running_deleted="no"
seen_dirs=""
for pid in $(pgrep -f sidcode 2>/dev/null | grep -v -e "^$$\$" -e "^${PPID}\$" || true); do
  exe="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"

  # The kernel adds " (deleted)" to the target once the file the process was started from has
  # been unlinked - and an install or a rebuild does exactly that: `rm -rf` over the app
  # folder, then a fresh copy. The process carries on running the copy it started with, which
  # is not the one on disk, so every check below that reads the folder describes a window that
  # is not the one being looked at. That is "I rebuilt it and nothing changed" again.
  exe_deleted="no"
  case "${exe}" in
    *" (deleted)")
      exe_deleted="yes"
      running_deleted="yes"
      exe="${exe% (deleted)}"
      ;;
  esac

  if [ -z "${exe}" ]; then
    # A /proc that cannot be read (a sandbox, or another user's editor) still leaves the
    # command line, which is enough to say which copy was started.
    exe="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null | awk '{print $1}' || true)"
  fi
  if [ -z "${exe}" ]; then
    unreadable_found="yes"
    info "pid ${pid} - a process with sidcode in its command line, but not one this can read"
    continue
  fi

  dir="$(dirname "${exe}")"

  # Something else that merely mentions sidcode (this script, an editor open on the folder)
  # is not the editor: the binary is called sidcode, and an app folder has resources/app in it.
  if [ "$(basename "${exe}")" != "sidcode" ] && [ ! -d "${dir}/resources/app" ]; then
    continue
  fi

  running_found="yes"
  case " ${seen_dirs} " in
    *" ${dir} "*) ;;
    *)
      seen_dirs="${seen_dirs} ${dir}"
      if [ "${exe_deleted}" = "yes" ]; then
        info "pid ${pid} -> ${exe}"
        info "  that file is gone from disk - this SidCode was started before the last install"
        info "  or rebuild, so it is still running the copy from before it"
      else
        info "pid ${pid} -> ${exe} (and any other processes of the same editor)"
      fi
      ;;
  esac

  case "${dir}" in
    "${INSTALLED}") running_copy="installed"; running_dir="${INSTALLED}" ;;
    "${ROOT}"/*) running_copy="build"; running_dir="${dir}" ;;
    *) running_copy="somewhere else"; running_dir="${dir}" ;;
  esac
done
if [ "${running_found}" = "no" ] && [ "${unreadable_found}" = "no" ]; then
  info "nothing - SidCode is not running"
fi

head_ "what this means"

# The order is deliberate, most decisive first. Nothing matters as much as *which copy runs*:
# `sidcode` on PATH starts the installed copy, which is a copy and not a link, so a build that
# has everything can sit there while the editor keeps starting the older one - no Tools menu,
# no bundled SFTP, and no sign of either fault inside the editor.
installed_is_old="no"
installed_version="$(builtin_sftp_version "${INSTALLED}" || true)"
built_version="$(builtin_sftp_version "${BUILT}" || true)"
if [ -d "${INSTALLED}" ] && [ -n "${BUILT}" ] && [ "${launcher_is_installed}" = "yes" ]; then
  if [ "$(compiled_patch_count "${BUILT}")" -gt 0 ] && [ "$(builtin_tools "${BUILT}")" = "yes" ] &&
     { [ "$(compiled_patch_count "${INSTALLED}")" -eq 0 ] ||
       [ "$(builtin_tools "${INSTALLED}")" != "yes" ] ||
       { [ -n "${built_version}" ] && [ "${installed_version}" != "${built_version}" ]; }; }; then
    installed_is_old="yes"
  fi
fi

if [ "${installed_is_old}" = "yes" ]; then
  info "The copy you start is older than the build, and that is the whole fault."
  info "  built:   ${BUILT} (sftp-sid ${built_version:-no copy})"
  info "  started: ${INSTALLED} - Tools menu patch $(compiled_patch_count "${INSTALLED}") time(s), SFTP $(builtin_tools "${INSTALLED}") (sftp-sid ${installed_version:-no copy})"
  info "Nothing reaches that copy on its own - it is a copy, not a link - so the build has to be"
  info "put there. Quit SidCode completely first, then:"
  info "  ${ROOT}/tools/install-sidcode.sh ${BUILT}"
  info "It prints the two chrome-sandbox lines to run with sudo afterwards; run those, then"
  info "start SidCode again."
elif [ -n "${BUILT}" ] && [ "$(draws_tools "${BUILT}")" = "no" ]; then
  info "That build's main process does not draw a Tools menu, so nothing can appear in it - not"
  info "the extension, not the renderer's registration. The bar can only ever show the menus"
  info "named in platform/menubar/electron-main/menubar.ts, and Tools is not one of them in that"
  info "app: it predates the main-process half of patches/tools-menu.patch. This is the fault"
  info "that looks like everything else being wrong. Rebuild the editor:"
  info "  ${ROOT}/build.sh"
elif [ -n "${launcher_dir}" ] && [ "$(sandbox_state "${launcher_dir}")" != "ok" ]; then
  info "The app \`sidcode\` starts cannot run yet, and nothing about the menu matters until it"
  info "can: its chrome-sandbox is $(sandbox_state "${launcher_dir}"). Chromium will not start"
  info "without that helper owned by root with the setuid bit, and neither a rebuild nor an"
  info "install can carry that across, so it is wrong again after each one. SidCode then exits"
  info "immediately and silently, because its launcher throws the error away:"
  info "  sudo chown root:root ${launcher_dir}/chrome-sandbox"
  info "  sudo chmod 4755 ${launcher_dir}/chrome-sandbox"
  info "then start it again. To see the error yourself, run the binary in the foreground:"
  info "  ${launcher_dir}/sidcode 2>&1 | head -20"
elif [ "${profile_records}" = "yes" ]; then
  info "Something in the profile is holding the SFTP extension back - see the section above."
  info "Clear it, quit SidCode completely, and start it again:"
  info "  ${ROOT}/tools/clear-profile-sftp.sh"
elif [ "${profile_missing_tools}" -gt 0 ]; then
  info "There is an SFTP extension in the profile above that has no Tools entry, and a copy in"
  info "the profile is loaded in place of the app's own. Remove it, restart, and run this again:"
  info "  sidcode --uninstall-extension sir0sid.sftp-sid"
elif [ "${defaults_old}" -gt 0 ]; then
  info "There is a SidCode Defaults in the profile above with no Themes menu in it, and a copy in"
  info "the profile is loaded in place of the app's own - so the colours are still his, and the"
  info "Themes menu in Tools is the one thing that is not there. No build and no --brand-only"
  info "can reach it: the app's copy is not the one the editor loads. Remove it, restart, and run"
  info "this again:"
  info "  sidcode --uninstall-extension Sir0Sid.sidcode-defaults"
  info "Its four colour sets are built in, so uninstalling it costs nothing: the app's own copy"
  info "has them, and the Themes menu with them."
elif [ "${running_deleted}" = "yes" ]; then
  info "The SidCode that is open started from a file that is no longer on disk: it is the copy"
  info "from before the last install or rebuild, still running in memory while the folder holds"
  info "the new one. Nothing read above describes that window, so quit it completely and start"
  info "it again - no rebuild and no reinstall, just a fresh start:"
  info "  quit SidCode, then start it again"
  info "Tools belongs between Terminal and Help."
elif [ "${running_copy}" = "build" ]; then
  info "The running editor is the build folder itself, and nothing is rebuilt into an editor"
  info "that is already running: quit SidCode completely and start it again."
elif [ -n "${running_dir}" ] && [ "$(builtin_tools "${running_dir}")" != "yes" ]; then
  info "The copy that is running has no SFTP with the Tools entry built into it, so nothing"
  info "fills the Tools menu - and a build from before the menu-service hunk leaves an empty"
  info "Tools out of the menu bar altogether."
  info "That is the whole fault. Package a current VSIX and put it back in the app:"
  info "  cd $(cd "${ROOT}/../sids-sftp" && pwd) && npm install && npm run compile && npx @vscode/vsce package"
  info "  mkdir -p ${ROOT}/extensions && cp ../sids-sftp/sftp-sid-*.vsix ${ROOT}/extensions/"
  info "  ${ROOT}/build.sh --brand-only ${BUILT:-<app folder>}"
elif [ -n "${BUILT}" ] && [ "$(builtin_tools "${BUILT}")" != "yes" ]; then
  info "The app's bundled SFTP has no Tools entry, so nothing fills the Tools menu - and a build"
  info "from before the menu-service hunk leaves an empty Tools out of the menu bar altogether."
  info "That is the whole fault, and it is fixed by putting a current SFTP into the app rather"
  info "than by rebuilding the editor:"
  info "  mkdir -p ${ROOT}/extensions && cp ../sids-sftp/sftp-sid-*.vsix ${ROOT}/extensions/"
  info "  ${ROOT}/build.sh --brand-only ${BUILT}"
elif [ -n "${BUILT}" ] && { [ "$(compiled_patch_count "${BUILT}")" -eq 0 ] || [ "$(compiled_published_key_count "${BUILT}")" -eq 0 ]; }; then
  info "The Tools menu patch is not all there in that app's compiled workbench:"
  info "  MenubarToolsMenu $(compiled_patch_count "${BUILT}") (5 with the patch, 4 with an older one), menuBar/tools $(compiled_published_key_count "${BUILT}") (1 with it)"
  info "so that app was built before the patch was in place. Rebuild it: ${ROOT}/build.sh"
elif [ -z "${BUILT}" ]; then
  info "No built app was found, so there is nothing to judge yet. Pass the folder:"
  info "  ${ROOT}/tools/check-build.sh <app folder>"
elif [ "${running_copy}" = "none" ]; then
  info "Everything in ${BUILT} looks right: the patch is compiled in and the bundled SFTP has"
  info "the Tools entry. Start SidCode - or, if you start it from ~/.local/bin, make sure the"
  info "installed copy is this build first, with:"
  info "  ${ROOT}/tools/install-sidcode.sh ${BUILT}"
  info "Tools belongs between Terminal and Help."
else
  info "Both halves look right in the copy that is running: the Tools menu patch is in its"
  info "code and its bundled SFTP carries the Tools entry."
  info "Tools should be in the bar on the first frame, empty for a moment and then holding the"
  info "SFTP items, so nothing needs doing. If it is only there after the menu bar is hidden and"
  info "shown again, this copy predates the menu-service hunk - the one that keeps an empty"
  info "Tools in the bar - and that ritual is rebuilding the bar. It costs no rebuild:"
  info "  View > Appearance > Toggle Menu Bar, twice - or Ctrl+R to reload the window"
  info "Then click Tools > SFTP/FTP > Create Connection..., which opens the form and writes"
  info "what you type into the folder's .vscode/sftp.json."
fi
