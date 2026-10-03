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
languages/                      SidCode's own languages extension - nginx, and the next one
extensions/install.txt          what is installed into the editor after a build
extensions/builtin.txt          the languages and linters built in from the open gallery
patches/                        SidCode's own patches to the editor's source
tools/make-defaults.mjs         turns the files above into that extension
tools/apply-branding.mjs        puts SidCode's name on a prepared product.json
tools/dev.sh                    runs the checkout, recompiling as you save
tools/make-patch.sh             saves edits made there as one of those patches
build.sh                        the build itself
COMMANDS.md                     every command, by task
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

* **The name and the links.** `branding/product.sidcode.json` sets the name, the data folder
  (`.sidcode`), the protocol and the four links a customer can click - documentation at
  **sidcode.dev**, issues and licence at his GitHub. `node tools/check-branding.mjs` fails if any of
  them leads back to the project this is built from, or if the folder or the protocol is one another
  editor already uses.
* **The branding.** VSCodium brands itself by merging *its* `product.json` over the upstream one
  while preparing, so `tools/merge-product.mjs` writes a `product.json` that is VSCodium's own
  with SidCode's fields on top, and that is what the checkout gets. The name therefore survives
  every prepare step rather than being overwritten by the next one.
* **The built-in extensions.** `sidcode-defaults` and the SFTP VSIX are copied into the built
  app's `resources/app/extensions` afterwards.

The build is the expensive half: Microsoft's `vscode` source (1.5-3 GB), 30-50 GB of free disk
and an hour or more. Dependencies are VSCodium's own: node (their `.nvmrc`), `jq`, `git`,
python3, `rustup`, `yarn`, and on Linux `gcc`, `g++`, `make`, `pkg-config`, `libx11-dev`,
`libxkbfile-dev`, `libsecret-1-dev`, `libkrb5-dev`.

**`VCODIUM_REF` is pinned to a release tag** (`1.135.06055`), not to `master`, so a rebuild is the
build you already made rather than whatever landed upstream since. Move it with
`git ls-remote --tags https://github.com/VSCodium/vscodium 'refs/tags/1.135.*'`, and use
`git -C build/vscodium rev-parse HEAD` to see the commit you are actually running. VSCodium's build
then fetches Microsoft's `vscode` at the tag *it* pins - so there are two repositories and a set of
npm packages between you and a new build, and none of them between you and the one you have.

**`VCODIUM_REPO`** points at that repository, and takes your own fork or mirror instead:
`VCODIUM_REPO=https://github.com/Sir0Sid/vscodium ./build.sh`. A fork is worth having to *change*
VSCodium's own side, or as a frozen copy; it is not needed to change the editor - `patches/` does
that, and is how the Tools menu exists.

`./build.sh --brand-only <app dir>` re-brands an app that is already built and re-installs the
built-ins in seconds, which is the quick loop while shaping colours.

Three checks, one per half of the product, and each of them catches a failure that is invisible in
the editor until somebody clicks the thing that does not work:

```bash
node tools/check-branding.mjs           the name, the folder, the links, and which services it uses
node tools/check-themes-menu.mjs         the Themes menu: every colour set reachable, the runtime agrees
node tools/check-remote.mjs              the remote half: the settings and the server artifact agree
```

The update check is **off** (`update.mode: none`), and that is deliberate: this build would otherwise
ask VSCodium's update service, which could deliver a VSCodium build over SidCode. Extension updates
are separate and still on, from Open VSX. When there is an update channel of its own, that setting
goes away and `updateUrl` in the branding names it.

## Keeping what it is built from

Running SidCode needs none of this: it is an app folder and a data folder, and neither looks at
the network. A *rebuild* is what needs the two repositories and the npm packages, and any of those
can move, be renamed or go away.

```bash
./tools/save-source.sh
```

keeps a copy of the checkout - VSCodium's source with Microsoft's `vscode` inside it and `patches/user`
alongside - beside this folder, named with the commit it is at. With that copy unpacked as
`build/vscodium`, a rebuild of the same pinned tag fetches **nothing** and says so; a copy you hold
is the only thing that answers "what if it is not there any more".

## Everyone on their own PC, one project on your host

The arrangement: each person installs SidCode on their own machine, and the project lives on **your**
host. The editor is only the front of it - the files, the terminals and the language servers stay on
the host, and nothing is copied to anybody's disk.

Three pieces make that work, and only one of them is new work:

* **The extension.** `jeanp413.open-remote-ssh` is built in (`extensions/builtin.txt`). It is the
  only Remote-SSH a non-Microsoft build may have: Microsoft's own is not on the open gallery at all
  and its licence keeps it to their builds. This one is MIT, with its `LICENSE.txt` inside the VSIX,
  and it does the same job.
* **Your server component.** A Remote-SSH session runs a *server* build on the host, which the
  extension fetches from a URL it is given. `server/artifact.json` holds that URL and the name of the
  artifact; `node tools/make-defaults.mjs` writes the URL into the settings every user gets, and
  `./build.sh --server` packs the artifact under the same name. One definition, three readers - and
  `node tools/check-remote.mjs` fails if they ever disagree, because a mismatch is a connection that
  fetches nothing and says so badly.
* **The host recipe**, below.

```bash
./build.sh --server                     the remote server component, from the same source and patches
./tools/publish-server.sh               where it has to be uploaded, for the build beside this folder
node tools/check-remote.mjs             that the settings, the artifact and the build agree
```

### On the host

* **One account per person.** Each gets their own `~/.vscode-server` (or whatever
  `remote.SSH.serverInstallPath` says), their own git identity, and can be removed without touching
  anyone else's. A single shared account is simpler and loses all three.
* **One group for the project, and a setgid folder:**

  ```bash
  sudo groupadd sidsite
  sudo usermod -aG sidsite alice && sudo usermod -aG sidsite bob
  sudo mkdir -p /srv/site && sudo chgrp sidsite /srv/site && sudo chmod 2775 /srv/site
  ```

  `2775` is the bit that makes this work: new files inherit the group, so two people can write the
  same project without fighting over ownership.
* **SSH and nothing else** open to them. That one port is what the editor talks over.
* **The update rule**: when the editor moves to a new build, build the server component for that same
  version and upload it. `remote.SSH.serverVersion` is `match`, so a client and a host that differ
  are refused - and the symptom, if you skip this, is a connection that fails on a version mismatch
  rather than a wrong edit.

### What the users do

They install SidCode, and the first time they connect to the host the extension puts the server
component there and keeps it there. After that, opening the project is opening a remote folder - and
the editor's own features are all in place, because the same `patches/` apply to the server build.

If they would rather have no install at all, that is the *browser* shape: `openvscode-server` or
`code-server`, both MIT, serving the same upstream editor from the host. It is the same server
component story and a different front - a second build target rather than a second product.

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
can put its own items in that menu. The SFTP extension puts two there: **Tools > SFTP/FTP >
Connections** — every connection this project has together with the ones saved for every
project, to add, change, test or remove — and **Tools > SFTP/FTP > Create**, the shorter form
for a new one. Both are saved into the project's `sftp.json`, or into the extension's own user
area when a connection is kept for every project. `sidcode-defaults` puts **Tools > Themes** in
beside them: **Sid's Colours** is a list of his four colour sets, and **Any Others…** opens the
list of every other theme the editor has. That second one is a list rather than a menu of its
own for a reason worth writing down: an extension's menu entries are fixed when it is packaged,
so his colour sets can be entries and the themes of extensions installed later cannot. The menu
bar belongs to the editor and not to an extension, which is exactly why this one is a patch.

### On a fresh Ubuntu Desktop

```
sudo apt install -y build-essential pkg-config python3 libx11-dev libxkbfile-dev \
                    libkrb5-dev libsecret-1-dev libasound2-dev
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
nvm install 22 && npm install -g yarn
./build.sh
```

The result runs from `build/vscodium/VSCode-linux-x64/bin/sidcode`. Then, to put Sid's extensions in:

```
./tools/install-extensions.sh build/vscodium/VSCode-linux-x64/bin/sidcode
```

And to have it in the application menu, as yourself - never with `sudo`, since it installs into
your own home folder:

```
./tools/install-sidcode.sh build/vscodium/VSCode-linux-x64
```

To try the colours before any of that, install `sidcode-defaults-1.2.1.vsix` into the editor in
use now (Extensions → ⋯ → Install from VSIX), or from a shell:
`codium --install-extension sidcode-defaults-1.2.1.vsix`.

## When a new copy of this folder arrives

It comes as an archive named after what is in it - `sidcode-<sftp-sid>-<defaults>-<packed>.tar.gz`,
so `sidcode-1.30.3-1.2.1-20261003-0923.tar.gz` today - and it carries a `VERSION` file inside saying
the same thing, with `sidcode-languages` alongside. The versions come first because they are what
changes; the time is there because the tools and docs change without them, and two such archives an
hour apart are otherwise the same name and not the same archive. The archive leaves `build/` out on purpose - the VSCodium
checkout and the built app are the expensive part, and unpacking into a fresh folder would mean
cloning Microsoft's source and building it from nothing. So unpack it *over* the folder that is
already there:

```bash
mkdir -p ~/sid
cd ~/Downloads && tar -xzf "$(ls -t sidcode-*.tar.gz | head -1)" -C ~/sid/sidcode
cat ~/sid/sidcode/VERSION            # which one did I just unpack
```

Name the archive rather than passing a glob: a Downloads folder holding several of them turns
`sidcode-*.tar.gz` into *several* arguments, and tar reads the first as the archive and every one
after it as a member to extract - so it fails with "Not found in archive" once per file, and the
unpacking it did do is the one you asked for by accident.

`tools/pack.sh` writes it, and the version in the name is read from the two extensions inside it,
so it cannot say something the archive does not hold.

What to run next depends on which half changed, and the two are very different sizes:

| what changed | what to run | how long |
| --- | --- | --- |
| `defaults/` - colours, settings, keybindings | `node tools/make-defaults.mjs`, then `./build.sh --brand-only build/vscodium/VSCode-linux-x64` | seconds |
| `patches/` - the editor's own code | `./build.sh` | an hour or more |

Either way, the app that was *built* is not the app that *runs*: `sidcode` on PATH is a copy in
`~/.local/share/sidcode`, put there by the installer. Put the new build in place, and repeat the
one step only sudo can do - it is needed every time, because the installer replaces the folder:

```
./tools/install-sidcode.sh build/vscodium/VSCode-linux-x64
sudo chown root:root ~/.local/share/sidcode/chrome-sandbox
sudo chmod 4755 ~/.local/share/sidcode/chrome-sandbox
```

There is a second one, and it is quieter. An extension installed **into the editor's profile** -
`~/.sidcode/extensions` - is loaded *in place of* a built-in with the same id. So a
`sidcode-defaults` or `sftp-sid` sitting in there keeps whatever it has and hides everything
newer in the app: the Themes menu, the SFTP/FTP entries, with nothing to say they are gone.
`--brand-only` prints both of these at the end, and does nothing else about them.

`./tools/check-build.sh` afterwards says which copy is running, and whether the build just made is
the one that was started.

If your `sidcode` command points straight at the build instead - `/usr/local/bin/sidcode` onto
`build/vscodium/VSCode-linux-x64/bin/sidcode` - then there is no install step, and the build is
what runs. The sandbox helper still needs those two lines, on that folder, because a fresh build
always leaves them undone and the app then starts and immediately exits:

```
sudo chown root:root build/vscodium/VSCode-linux-x64/chrome-sandbox
sudo chmod 4755 build/vscodium/VSCode-linux-x64/chrome-sandbox
```

That arrangement is worth making deliberate, because the two routes are otherwise easy to mix up:
a menu entry pointing at a copy will keep starting the older editor while the build sits there
current, and nothing in the editor says so. `--in-place` settles it for good -

```
./tools/install-sidcode.sh --in-place build/vscodium/VSCode-linux-x64
```

- after which the menu, the `sidcode` command and the build are the same SidCode.

## What SidCode is made of

The application **is** VS Code: VSCodium's scripts build Microsoft's own source, so the editor,
search, source control, terminal, debugger, tasks, the extension host and every language feature
shipped with VS Code are in SidCode by construction. Extensions are additions on top of that,
not the editor itself.

Three groups, and the middle one is the interesting one:

* **Built in** - `sir0sid.sftp-sid`, `sidcode-defaults` (Sid's four colour sets, the **Themes**
  menu in Tools, the defaults and the keybindings) and `sidcode-languages` (nginx, and the place
  the next language goes). His old `sir0sid.sids-colours` extension is deliberately not among
  them: those colour files now live inside `sidcode-defaults`.

  The languages and linters that are neither his nor the editor's own - Python with pyright and
  ruff, PHP with phpactor, systemd, eslint, prettier, stylelint, Tailwind - are built in from the
  open gallery the same way, from `extensions/builtin.txt`: one `publisher.name@version` per line,
  MIT only, downloaded during the build and unpacked into the app, and cached under `build/vsix/`
  so a rebuild does not fetch them again. Pylance is not there to have - it exists only in
  Microsoft's marketplace - which is why the type checker is pyright. Anything proprietary is
  installed for Sid himself through `extensions/install.txt` instead, never built in.
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
