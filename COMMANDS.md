# Every SidCode command

One page, by task. Run everything from the top of this folder unless the command says otherwise.

`<app>` below means the built app folder, which is the one with `resources/` and `bin/` in it:

```
build/vscodium/VSCode-linux-x64
```

## First time on a new machine

```bash
sudo apt install -y build-essential pkg-config python3 libx11-dev libxkbfile-dev \
                    libkrb5-dev libsecret-1-dev libasound2-dev librsvg2-bin
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
nvm install 22 && npm install -g yarn
./build.sh
```

The build needs node, yarn, git, jq and python3, and it is the expensive half: 1.5-3 GB of
source, 30-50 GB of disk, an hour or more.

## Building

```bash
./build.sh                              fetch, brand, patch, build, put the built-ins in - an hour
./build.sh --brand-only <app>           re-brand an app already built, seconds
./build.sh --server                     the remote server component, for projects on a host
```

Which one to use is decided by what changed: colours, settings and keybindings are seconds;
anything in `patches/` - the editor's own code - only a full build picks up.

The VSCodium release is pinned in `build.sh` (`VCODIUM_REF=1.135.06055`) so a build can be
repeated. Move it, build from your own fork, or keep the build folder somewhere else:

```bash
VCODIUM_REF=1.135.07000 ./build.sh                              a newer release
VCODIUM_REPO=https://github.com/Sir0Sid/vscodium ./build.sh     from a fork or mirror
SIDCODE_BUILD_DIR=~/sid/build ./build.sh                        more than one build folder
./tools/save-source.sh                                          keep the source you built
./tools/take-the-factory.sh                                     the machinery into factory/ (see below)
```

With the pinned tag already checked out, a rebuild fetches nothing - which is what the saved copy
is for. A branch (`VCODIUM_REF=master`) always fetches.

## Putting this folder on GitHub

The repository *is* this folder: the build script, the patches, the defaults, the tools and the
server definition. `.gitignore` keeps out the two things that must not be committed - `build/`, which
is gigabytes of checkout and built app, and the packed archives - while the VSIX files stay in, since
they are what gets built into the editor.

Create the repository on GitHub first, and **without** a README or a licence: either of those is a
commit of GitHub's, and with one there the first push is refused as non-fast-forward. If it happened
anyway, `--force` on that first push is what settles it - there is nothing else in the repository to
lose.

Git needs to know who is committing, once per machine:

```bash
git config --global user.name "Simon G"
git config --global user.email "321107679+Sir0Sid@users.noreply.github.com"
git config --global init.defaultBranch main
```

That address is GitHub's own private one for the account, so commits link to `Sir0Sid` without a real
email being published. Then, from this folder:

```bash
git init
git add -A
git commit -m "SidCode: the build, the patches, the defaults and the tools"
git remote add origin git@github.com:Sir0Sid/SidCode.git
git push -u origin main --force
```

Two things go wrong on a fresh machine, and neither message says what to do about it:

* **`src refspec main does not match any`** - this git made `master`. Rename it before pushing, since
  the push names a branch that does not exist: `git branch -m master main`. Pushing `master` instead
  leaves the repository's default branch pointing at whatever was there before, with the new branch
  beside it.
* **`Permission denied (publickey)`** - GitHub has no key of this machine's. One key per machine:

  ```bash
  ssh-keygen -t ed25519 -C "321107679+Sir0Sid@users.noreply.github.com" -f ~/.ssh/id_ed25519 -N ""
  cat ~/.ssh/id_ed25519.pub          # this whole line goes to GitHub, not the fingerprint
  ssh -T git@github.com              # should greet the account by name
  ```

  On GitHub: Settings -> SSH and GPG keys -> New SSH key, type **Authentication**, and paste the
  single line of the `.pub` file. GitHub derives the fingerprint and shows it under the box as the
  key is pasted - that is it confirming, not a field to fill in. The key file **without** `.pub`
  never leaves the machine. To avoid keys altogether, use a token over HTTPS instead:
  `git remote set-url origin https://github.com/Sir0Sid/SidCode.git`, then paste a personal access
  token with `contents: write` where a password is asked for.

The name is load-bearing beyond the repository: `branding/product.sidcode.json` points its issue,
feature and licence links at `github.com/Sir0Sid/SidCode`, and `server/artifact.json` points the
server component's download at that repository's releases. `node tools/check-branding.mjs` checks
that those links lead somewhere of Sid's own rather than back to the project this is built from, and
`node tools/check-remote.mjs` that the artifact URL and the artifact name agree. Renaming the
repository later means changing those two files - four URLs between them - and this page.

Repository names are case-insensitive to GitHub, so a repository actually called `sidecode` **is**
`SidCode` as far as every URL above is concerned: they resolve, and only the casing shown in a
browser changes. Rename the repository to `SidCode` if the address bar should read like the product;
nothing in this folder needs to change either way.

## The factory: the machinery in this repository

With `factory/` in place, `build.sh` copies it out to `build/vscodium`, fetches nothing for the
machinery, and the fetch of Microsoft's source comes from Sid's own fork. `factory/FACTORY` records
which VSCodium it was taken from.

```bash
./tools/take-the-factory.sh                              from build/vscodium
SIDCODE_FACTORY_FROM=~/sid/vscodium-source-<commit> ./tools/take-the-factory.sh
SIDCODE_VSCODE_REPO=https://github.com/Sir0Sid/vscode ./tools/take-the-factory.sh
node tools/check-factory.mjs                             is it here, is it Sid's, does the build use it
```

Moving to a newer VS Code is one command - take a newer factory - and then `./build.sh`, which
dry-runs every patch against the source before it compiles: a patch that no longer fits stops the
build in seconds and names itself, instead of at the end of an hour.

## Projects on a host, users on their own PCs

The remote half: whoever has a login on your host installs SidCode and opens the project there.
`server/artifact.json` is the one definition of what the server component is called and where it is
fetched from - every user's settings are generated from it, and the build packs the artifact under
the same name.

```bash
./build.sh --server                     build it, from the same source and the same patches
./tools/publish-server.sh               print where it has to be uploaded, for this build
node tools/check-remote.mjs             check the settings, the artifact and the build agree
```

`README.md` has the host side: one account per person, a shared group and a setgid folder so two
people can write the same project, and the rule that the server component has to be rebuilt for the
same version as the editor, because `remote.SSH.serverVersion` is `match`.

## Starting it

```bash
<app>/bin/sidcode                                                    the build itself
~/.local/share/sidcode/bin/sidcode                                   the installed copy
sidcode                                                             whichever is first on PATH
```

Chromium's sandbox helper has to be owned by root with the setuid bit, and a build or an install
always leaves it undone. Until this is run for the copy you start, SidCode exits immediately and
silently:

```bash
sudo chown root:root <app>/chrome-sandbox
sudo chmod 4755 <app>/chrome-sandbox
```

## Is it the copy I think it is?

```bash
./tools/check-build.sh                  whichever app `sidcode` starts, and the installed one
./tools/check-build.sh <app>            one specific app folder
```

Read-only. It reports the version of the bundled SFTP extension and whether it carries the Tools
entry, whether the Tools patch is compiled into the workbench, anything in the profile that would
stop the extension loading, which copy is actually running, and whether the sandbox is ready. It
ends by saying what to do about whatever it found.

## When a new copy of this folder arrives

Unpack it *over* the folder you have - `build/` is left out of the archive on purpose, so it
survives and you keep the source and the compiled app:

```bash
cd ~/Downloads && tar -xzf "$(ls -t sidcode-*.tar.gz | head -1)" -C ~/sid/sidcode
cat ~/sid/sidcode/VERSION                                 # which one is in the folder now

node tools/make-defaults.mjs && ./build.sh --brand-only <app>       if defaults/ changed
./build.sh                                                          if patches/ changed

./tools/install-sidcode.sh <app>                                    if you run the installed copy
sudo chown root:root ~/.local/share/sidcode/chrome-sandbox
sudo chmod 4755 ~/.local/share/sidcode/chrome-sandbox
```

To pack this folder for whoever downloads it, named with what is inside:

```bash
./tools/pack.sh                          writes sidcode-<sftp-sid>-<defaults>.tar.gz
```

It prints the unpack command on the last two lines, the label as a comment - so copying those two
lines into a shell does what it looks like it does, which is not true of prose followed by a command
on one line.

## Colours, settings and keybindings

Put the files in `defaults/themes/` (a theme, or a `workbench.colorCustomizations` block),
`defaults/settings.json` and `defaults/keybindings.json`, then:

```bash
node tools/make-defaults.mjs            writes defaults/package.json and reports what it found
node tools/check-themes-menu.mjs        checks the Themes menu: every colour set reachable,
                                        every entry a command, the runtime and the manifest agree
node tools/check-branding.mjs           checks the name, the folder, the links, and the services it uses
node tools/check-provenance.mjs         checks every built-in is MIT, recorded and still at its pin
node tools/check-factory.mjs            checks the factory is here, is Sid's, and the build uses it
./build.sh --brand-only <app>           puts the result into an app already built
```

`defaults/default-theme.txt` names the theme SidCode opens with. `--brand-only` is the way to see
a colour change, because the copy it writes into is the one the editor loads - **unless this
extension is also installed into the editor's profile**, which the VSIX below does. A copy in the
profile is loaded *in place of* the built-in one, so an older one there keeps the colours and
hides everything newer in the built-in copy: the Themes menu, for instance, with no sign that
anything is missing. Uninstall it (Extensions view, right-click, Uninstall) and the app's own
copy is used again. The VSIX is for another editor:

```bash
codium --install-extension sidcode-defaults-1.2.1.vsix --force
```

## Icons

`build.sh` runs this for you, against the source, before compiling:

```bash
./tools/apply-icons.sh build/vscodium/vscode
```

It renders `branding/icons/sidcode.svg` to a 512px PNG (the app icon) and copies
`branding/icons/sidcode-mark.svg` over the empty editor's watermark. Both come from the one SVG,
so a change here means a full `./build.sh`. Quick look instead, over the built app - this is the
file the menu entry points at:

```bash
cp <rendered code.png> <app>/resources/app/resources/linux/code.png
```

## Extensions

```bash
./tools/install-extensions.sh                       the list in extensions/install.txt
./tools/install-extensions.sh <app>/bin/sidcode     into a specific editor
./tools/clear-profile-sftp.sh                       quit SidCode first - see below
```

The SFTP extension is built in rather than installed, so updating it is a build:

```bash
mkdir -p extensions && cp ../sids-sftp/sftp-sid-*.vsix extensions/
./build.sh --brand-only <app>
```

`clear-profile-sftp.sh` is for the one mess: if `sir0sid.sftp-sid` is sitting in the profile
(`~/.sidcode/extensions`) from an earlier install, it holds the id, the built-in copy is filtered
out, and you get no SFTP commands and no Tools menu at all. It backs up every file it rewrites.

## The application menu entry

```bash
./tools/install-sidcode.sh <app>                        app into ~/.local/share/sidcode,
                                                        `sidcode` on PATH, and the menu entry
./tools/install-sidcode.sh --in-place <app>              point the command and the menu entry at
                                                        that folder instead of copying it
sudo rm -f ~/.local/share/applications/sidcode.desktop   if it ended up owned by root
```

Never run the installer with `sudo`: it installs into your home folder, and as root it installs
into `/root`, where your desktop never looks.

`--in-place` is the one to use while you are the one rebuilding: the menu entry and the `sidcode`
command then run the build itself, so a `--brand-only` is live the moment you restart, and there
is no second copy to forget. With a copy installed, a rebuilt build changes nothing until this
script is run again - which is the most common way to spend an hour building something the editor
never sees. The sandbox helper still needs sudo, and a full build writes a new one; `--brand-only`
leaves the folder alone and does not.

## Languages

The editor's own language services for JS/TS, CSS, HTML, JSON and Markdown are built in already.
Everything else SidCode has by default comes from two places:

* **`sidcode-languages`** - SidCode's own: nginx, and the place the next language goes. See
  `languages/README.md`.
* **`extensions/builtin.txt`** - the languages and linters built in from the open gallery, one
  `publisher.name@version` per line, MIT only, downloaded at build time and unpacked into the app.
  Python (with pyright and ruff), PHP, systemd, eslint, prettier, stylelint, Tailwind.

```bash
./build.sh --brand-only <app>                   put the list into an app already built, seconds
./build.sh --brand-only <app> --no-download     from what is already in build/vsix/
./tools/check-build.sh <app>                    what each copy has built in, with versions
```

Updating one is changing its version in `extensions/builtin.txt` and rebuilding. Nothing
proprietary can go in there - Intelephense, DevSense PhpTools and Pylance are installed through
`extensions/install.txt` instead, which is for Sid's own machine rather than for everyone's build.

### Claiming a file extension as a language

If the language already exists, this is one line in your own settings
(`Preferences: Open User Settings (JSON)`) and it takes effect immediately, with no build:

```json
"files.associations": {
    "*.sidconf": "nginx",
    "php-fpm.conf": "ini"
}
```

To make it part of every build instead, the same line goes in `defaults/settings.json` and then:
`node tools/make-defaults.mjs && ./build.sh --brand-only <app>`.

Language ids that are always there: `ini`, `properties`, `makefile`, `dockerfile`, `yaml`, `sql`,
`shellscript`, `perl`, `python`, `php`, `ruby`, `go`, `rust`, `java`, `csharp`, `cpp`, `lua`, `r`,
`latex`, `xml`, `css`, `scss`, `less`, `json`, `jsonc`, `markdown`, `diff`, `dockercompose`,
`git-commit`. Added by the built-in extensions: `nginx`; and `systemd-unit`, `systemd-network`,
`systemd-config`, `systemd-udev-rules`, `systemd-tmpfiles`, `systemd-sysusers`, `podman-quadlet`
and `mkosi` from willibrandon.systemd.

If nothing has that language at all, it needs a grammar, and any `.x` becomes a language that way:
add it to `languages/package.json` and a grammar to `languages/syntaxes/`. The recipe is in
`languages/README.md`, and it is four small steps.

## Changing the editor's own code

```bash
./build.sh                              once - this is what compiles the checkout
./tools/dev.sh                          run the checkout, recompiling as you save
./tools/make-patch.sh menus             save the edit as patches/menus.patch
./tools/make-patch.sh menus src/vs/workbench/browser/parts/
./build.sh                              and it is part of the build, not a checkout edit
```

A patch applies by context, so one written against one VS Code release can fail against the next
- and a failed patch aborts the build naming itself, which is what you want to hear instead of an
editor that built with half a change in it.

## Putting this on GitHub

```bash
git init
git add .
git commit -m "SidCode"
git branch -M main
git remote add origin git@github.com:Sir0Sid/SidCode.git
git push -u origin main
```

`build/` is ignored, so the checkouts and the built app stay out of the repository.
