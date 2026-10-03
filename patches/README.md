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
  to the editor's own source — seven hunks in six files — and it needs a rebuild rather than a
  settings change.

  **The bar is built in two places, and a new top level menu has to be added to both.** Which
  menus exist is decided in the main process: `platform/menubar/electron-main/menubar.ts` names
  every one of them, File through Help, one at a time. The items inside them come from the
  renderer as data, but a menu the renderer registers and that file does not name is silently
  never drawn — the bar comes up as the eight it knows, and everything else looks correct. That
  is what the last hunk is: Tools, named there, before Help. On macOS the same list is the
  application menu, so Tools appears there too, between Window and Help.

  The hunk before it is about what an empty menu would do. The bar is sent to the main process as
  one snapshot, and a top level menu that is not File or Window, with nothing in it, is read as a
  broken menu bar — and then nothing is sent at all, File and Edit included. A menu that only
  extensions put items in is empty until one is loaded, so an empty Tools is sent and drawn as an
  empty menu rather than being taken for a fault. It fills in as soon as the extension's items
  arrive, which is why Tools can appear a moment after the window opens rather than on its first
  frame.

  **The bar a window draws for itself is built from one list, and a menu that is empty when that
  list is read is not in the list.** `platform/actions/common/menuService.ts` drops a submenu with
  nothing in it rather than carrying it through as a menu with nothing in it — right everywhere
  else, wrong here: Tools is empty until an extension puts something in it, so when the window
  assembled its bar there was usually no Tools to assemble, and the bar came up File, Edit, ...,
  Terminal, Help. It could not turn up later either, because the Tools submenu's own change event
  can fill in a menu the bar already has but cannot add one it has not got. The only thing that
  ever brought it in was throwing the bar away and building it again, which is exactly what hiding
  and showing the menu bar does — hence a Tools menu that needed a ritual to appear. Tools is now
  kept while it is empty, so it is in the bar with the window and the extension's items are in it
  a moment later.

  It was written against the VS Code release `VCODIUM_REF` resolves to, and checked with
  `git apply --check --ignore-whitespace` against that release's own files, so it applies today. A
  release that moves those lines will break it, and a failed patch aborts the build naming itself
  — which is what you want to hear rather than an editor that built with half a change in it.

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
