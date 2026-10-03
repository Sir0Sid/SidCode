#!/usr/bin/env bash
#
# Build SidCode.
#
#   ./build.sh                          fetch VSCodium, brand it, build it, install the built-ins
#   ./build.sh --brand-only <app dir>   re-brand an app that is already built
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
# Pin this to a VSCodium release tag for a build that can be repeated.
VCODIUM_REF="${VCODIUM_REF:-master}"

say() { printf '\n== %s\n' "$*"; }

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
      echo "  $(basename "${patch}")"
      found="yes"
    fi
  done

  if [ "${found}" = "no" ]; then
    echo "  none - see patches/README.md to change the editor's own code"
  fi
}

install_builtins() {
  local app_dir="$1"
  local extensions_dir="${app_dir}/resources/app/extensions"

  if [ ! -d "${extensions_dir}" ]; then
    echo "no ${extensions_dir} - is that a built app?" >&2
    return 1
  fi

  say "installing the built-in extensions"
  node "${ROOT}/tools/make-defaults.mjs"
  rm -rf "${extensions_dir}/sidcode-defaults"
  mkdir -p "${extensions_dir}/sidcode-defaults"
  cp -R "${ROOT}/defaults/." "${extensions_dir}/sidcode-defaults/"
  echo "  sidcode-defaults"

  local vsix
  vsix="$(ls -1t "${ROOT}"/../sids-sftp/sftp-sid-*.vsix 2>/dev/null | head -1 || true)"
  if [ -n "${vsix}" ]; then
    # A VSIX keeps its extension under `extension/`, and a built-in extension is the *contents*
    # of that folder - unzipping it straight in gives `sftp-sid/extension/package.json`, which is
    # a directory with no package.json and is therefore skipped, leaving SFTP silently absent.
    rm -rf "${extensions_dir}/sftp-sid" "${extensions_dir}/sftp-sid.unpacked"
    mkdir -p "${extensions_dir}/sftp-sid" "${extensions_dir}/sftp-sid.unpacked"
    unzip -q "${vsix}" -d "${extensions_dir}/sftp-sid.unpacked"
    mv "${extensions_dir}/sftp-sid.unpacked/extension/." "${extensions_dir}/sftp-sid/"
    rm -rf "${extensions_dir}/sftp-sid.unpacked"
    echo "  sftp-sid from $(basename "${vsix}")"
  else
    echo "  no sftp-sid-*.vsix beside this folder, so SFTP is not built in" >&2
  fi
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

if [ "${1:-}" = "--brand-only" ]; then
  APP_DIR="${2:-}"
  if [ -z "${APP_DIR}" ]; then
    APP_DIR="$(find_app_dir || true)"
  fi
  [ -n "${APP_DIR}" ] || { echo "usage: ./build.sh --brand-only <app dir>" >&2; exit 1; }

  say "branding ${APP_DIR}"
  node "${ROOT}/tools/apply-branding.mjs" "${APP_DIR}/resources/app/product.json"
  install_builtins "${APP_DIR}"
  exit 0
fi

for tool in git node yarn; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "SidCode's build needs ${tool}, which is not on PATH" >&2; exit 1; }
done

say "fetching VSCodium (${VCODIUM_REF})"
if [ -d "${VSCODIUM}/.git" ]; then
  git -C "${VSCODIUM}" fetch --tags --depth 1 origin "${VCODIUM_REF}"
  git -C "${VSCODIUM}" checkout FETCH_HEAD
else
  mkdir -p "${WORK}"
  git clone --depth 1 --branch "${VCODIUM_REF}" https://github.com/VSCodium/vscodium.git "${VSCODIUM}"
fi

say "branding it as SidCode"
node "${ROOT}/tools/merge-product.mjs" "${VSCODIUM}"
cp "${ROOT}/branding/product.json" "${VSCODIUM}/product.json"
"${ROOT}/tools/apply-icons.sh" "${VSCODIUM}"

say "our own patches"
apply_own_patches

say "building - this is the long part"
(cd "${VSCODIUM}" && ./dev/build.sh)

if APP_DIR="$(find_app_dir)"; then
  install_builtins "${APP_DIR}"
  cat <<TEXT

== done

The app is at ${APP_DIR}
Run it with: ${APP_DIR}/bin/sidcode

Then, to put Sid's own extensions in:
  ${ROOT}/tools/install-extensions.sh ${APP_DIR}/bin/sidcode
TEXT
else
  cat <<TEXT

== the build finished but no built app was found under ${VSCODIUM}
Look for a VSCode-*-x64 folder there and pass it to:
  ${ROOT}/build.sh --brand-only <that folder>
TEXT
fi
