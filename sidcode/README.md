# SidCode

Sid's own editor: VSCodium's build pipeline, with SidCode's name on it and Sid's own things
built in rather than installed afterwards.

VSCodium is not a fork - it is a set of scripts that build Microsoft's `vscode` into
freely-licensed binaries. SidCode wraps those scripts and adds two steps of its own: branding,
and extensions that ship with the editor instead of being added to it.

```
branding/product.sidcode.json   the fields SidCode overrides: name, CLI command, data folder
defaults/                       the SidCode Defaults extension - colours, settings, keys
  themes/                       colour files go here
  settings.json keybindings.json  optional: copies of Sid's user files
tools/make-defaults.mjs         turns the files above into that extension
tools/apply-branding.mjs        puts SidCode's name on a prepared product.json
patches/                        SidCode's own patches to the editor's source
tools/dev.sh                    runs the checkout, recompiling as you save
tools/make-patch.sh             saves edits made there as one of those patches
build.sh                        the build itself
```

## Colours, settings and keybindings

Drop the colour files into `defaults/themes/`, then run:

```
node tools/make-defaults.mjs
```

It writes `defaults/package.json`, which is what makes them an extension, and reports what it
found. Two shapes of colour file are accepted:

* a **theme** (`name`, `type`, `colors`, `tokenColors`) - shipped as it is;
* a **customisations block** (`workbench.colorCustomizations`,
  `editor.tokenColorCustomizations`) - wrapped into a real theme file beside it, leaving the
  original untouched.

`settings.json` and `keybindings.json` are read as VS Code writes them, comments and all, and
become `configurationDefaults` and default keybindings - so a fresh SidCode opens with them,
and any of them can still be overridden.

The same extension is both things: package it and install it into the editor in use today to
see the colours, and `build.sh` copies it into the build so it is built in.

## Building

```
./build.sh
```

The heavy lifting is VSCodium's own development entry point, `dev/build.sh`: it clones
Microsoft's `vscode` at the tag this VSCodium is built from, de-brands it, applies its patches
and builds. Two things are wrapped around it:

* **The branding.** VSCodium brands itself by merging *its* `product.json` over the upstream one
  while preparing, so `tools/merge-product.mjs` writes a `product.json` that is VSCodium's own
  with SidCode's fields on top, and that is what the checkout gets. The name therefore survives
  every prepare step rather than being overwritten by the next one.
* **The built-in extensions.** `sidcode-defaults` and the SFTP VSIX are copied into the built
  app's `resources/app/extensions` afterwards.

The build is the expensive half: Microsoft's `vscode` source (1.5-3 GB), 30-50 GB of free disk
and an hour or more. Dependencies are VSCodium's own: node (their `.nvmrc`), `jq`, `git`,
python3, `rustup`, `yarn`, and on Linux `gcc`, `g++`, `make`, `pkg-config`, `libx11-dev`,
`libxkbfile-dev`, `libsecret-1-dev`, `libkrb5-dev`. Pin `VCODIUM_REF` to a release tag for a
build that can be repeated.

`./build.sh --brand-only <app dir>` re-brands an app that is already built and re-installs the
built-ins in seconds, which is the quick loop while shaping colours.

## Changing the editor itself

The colours and the name are the shallow end. `patches/` is the deep one: anything dropped in
there is applied to Microsoft's `vscode` source during the build, after VSCodium's own patches,
so the editor's own behaviour - a menu entry, a keybinding's default, a feature switched off, a
command that is not there yet - can be changed, and the change kept.

```
./build.sh                      once, to fetch the source and build it
./tools/dev.sh                  run the checkout, recompiling as you save
./tools/make-patch.sh my-change save the edit as a patch, then build again
```

`patches/README.md` has the detail, including the one thing to remember: the checkout is
disposable and only the patch survives it.

The first patch in there is `tools-menu.patch`, and it is the shape of thing this layer is for:
a **Tools** menu in the top level menu bar, and with it the id `menuBar/tools`, so an extension
can put its own items in that menu. The SFTP extension's **Tools > SFTP/FTP > Create** — a form
for a new connection, saved into the project's `sftp.json` — is the first thing in it. The menu
bar belongs to the editor and not to an extension, which is exactly why this one is a patch.

### On a fresh Ubuntu Desktop

```
sudo apt install -y build-essential pkg-config python3 libx11-dev libxkbfile-dev \
                    libkrb5-dev libsecret-1-dev libasound2-dev
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
nvm install 22 && npm install -g yarn
./build.sh
```

The result runs from `build/VSCode-linux-x64/bin/sidcode`. Then, to put Sid's extensions in:

```
./tools/install-extensions.sh build/VSCode-linux-x64/bin/sidcode
```

And to have it in the application menu, as yourself - never with `sudo`, since it installs into
your own home folder:

```
./tools/install-sidcode.sh build/VSCodium-linux-x64
```

To try the colours before any of that, install `sidcode-defaults-1.1.1.vsix` into the editor in
use now (Extensions → ⋯ → Install from VSIX), or from a shell:
`codium --install-extension sidcode-defaults-1.1.1.vsix`.

## What SidCode is made of

The application **is** VS Code: VSCodium's scripts build Microsoft's own source, so the editor,
search, source control, terminal, debugger, tasks, the extension host and every language feature
shipped with VS Code are in SidCode by construction. Extensions are additions on top of that,
not the editor itself.

Three groups, and the middle one is the interesting one:

* **Built in** - `sir0sid.sftp-sid` and `sidcode-defaults` (Sid's four colour sets, defaults and
  keybindings). His old `sir0sid.sids-colours` extension is deliberately not among them: those
  colour files now live inside `sidcode-defaults`.
* **Installed from the gallery** - `extensions/install.txt`, through
  `tools/install-extensions.sh`. One command after the first run, and it reports what the
  gallery does not have instead of leaving a silent gap.
* **Not ours to give** - Microsoft's own extensions. Pylance has never left Microsoft's
  marketplace, and the terms on Pylance, the C# pack and the Remote Development packs allow them
  only in Microsoft's builds. That is the premise VSCodium is built on, and SidCode inherits it.
  `pyright` or `basedpyright` is the open stand-in for Pylance; the Microsoft marketplace,
  Copilot, IntelliCode and Microsoft's settings sync are likewise absent by design.

So: a complete editor, with Sid's toolchain on top, minus the pieces that are Microsoft's to
distribute.

## Putting this on GitHub

The build has to run on a real machine, so this folder travels first - as an archive, or by
dragging it into the repository page with **Add file → Upload files**. From a shell:

```
git init
git add .
git commit -m "SidCode"
git branch -M main
git remote add origin git@github.com:Sir0Sid/SidCode.git
git push -u origin main
```

`README.md`, `LICENSE` and the folder layout are already what a repository wants. `build/` is
ignored, so the checkouts and the built app stay out of it.

## Still to come

* **Icons** - SidCode's mark is in place (`branding/icons/`), rendered into the build by
  `tools/apply-icons.sh`: a heart on a plate for the app icon, and the bare mark for the empty
  editor's watermark. Changing it means editing that SVG and rebuilding - every size comes from
  the one file.
* **Other extensions** - `build.sh` installs `sidcode-defaults` and the SFTP extension; the
  list is one place to extend.

## What Sid's settings brought with them

`defaults/settings.json` holds the settings from his own editor that belong to a default set -
auto save, the nginx/sid file associations, the icon theme, the title bar, the auto-lock
behaviour, the Java telemetry opt-out, and `sftp.downloadWhenOpenInRemoteExplorer` so the SFTP
extension behaves the way he wants without being told twice.

Four things in his file were deliberately **not** taken:

* `workbench.colorTheme` — it names a theme from the extension he has installed now
  (`Sids Colours: Bright Teal`). SidCode's own copy of that colour set is a theme *inside* the
  defaults extension, so `make-defaults.mjs` sets the name of the bundled one instead.
* `sshfs.configs` — the name of one server on one machine. That belongs to the SSHFS extension
  and to him, not to everyone's editor.
* `extensions.allowed: { "*": true }` — a security-shaped switch, and not one to switch on for
  other people by default.
* `json.schemas` with `"url": null` for `.vscode/sftp.json` — that *disables* the schema for
  those files, and it looks like a workaround for the schema complaint this fork has since
  fixed. Leaving it in SidCode would turn our own schema off.

His colours also confirm the default theme: `"workbench.colorTheme": "Sids Colours: Bright
Teal"` is the theme he is actually using, which is why `default-theme.txt` names
**Sid's Bright Teal**.

One default in there is not from his file at all. `workbench.editor.enablePreview` is off, so a
file opened from the Explorer or a tab adds a tab of its own instead of being shown in the one
placeholder tab VS Code keeps for previews - opening a second file no longer takes the first one
off the screen. `workbench.editor.enablePreviewFromQuickOpen` does the same for files opened with
Ctrl+P. Both are defaults, so any of them can still be turned back on in your own settings.
