# SidCode's own patches

Anything in here is applied to Microsoft's `vscode` source during the build, after VSCodium's own
patches. That is how a change to the editor itself - not to its name, its colours or its settings,
but to what it *does* - survives a rebuild.

`build.sh` copies these into `patches/user/` in the checkout, which is the folder VSCodium already
reserves for patches that are not theirs and applies last of all.

## What is in here

* **`tools-menu.patch`** — a **Tools** menu in the top level menu bar, between Terminal and Help,
  and the id `menuBar/tools` published so an extension can put its own items inside it. The SFTP
  extension's **SFTP/FTP > Create** is the first thing in that menu.

  An extension cannot add a top level menu: `menusExtensionPoint.ts` lists the menus the editor
  lets extensions reach, and the top of the bar is not among them. So the entry itself is a change
  to the editor's own source — four hunks in three files — and it needs a rebuild rather than a
  settings change.

  It was written against the VS Code release `VCODIUM_REF` resolves to, and checked with
  `git apply --check` against that release's own files, so it applies today. A release that moves
  those lines will break it, and a failed patch aborts the build naming itself — which is what
  you want to hear rather than an editor that built with half a change in it.

  On macOS the native menu bar is assembled separately (`platform/menubar`) and will not show
  Tools. Nothing breaks there: it is simply a Linux and Windows menu.

## Making one

1. Run `./build.sh` once. It fetches the source to `build/vscodium/vscode` and leaves it patched,
   so what you edit there is the editor as SidCode builds it.
2. Edit the source in that folder - the editor is TypeScript, and the file you want is almost
   always going to be found by name under `src/vs/`. Then run it straight from the checkout,
   recompiling as you save:

   ```
   ./tools/dev.sh
   ```

3. When it does what you want, save the edit as a patch:

   ```
   ./tools/make-patch.sh my-change                     the whole tree
   ./tools/make-patch.sh menus src/vs/workbench/browser/parts/
   ```

4. `./build.sh` again, and it is part of the build rather than something sitting in a checkout.

## What the checkout forgets

`build/vscodium/vscode` is disposable. `dev/build.sh` runs `git reset --hard` over it before it
builds, and a build that fetches the source clones it again from nothing. Edits living only in
that folder are gone after either. The patch file is the copy that stays.

## One change, one name

Keep the same name for the same change and overwrite the file when it changes. Patches apply by
context, so a patch written against one VS Code release can fail against the next - and a failed
patch aborts the build, naming the patch it was. That is VSCodium's own way of working: their
patches break every month or so and are rebuilt by hand. Fewer, larger patches are easier to keep
than many small ones.
