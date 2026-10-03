# SidCode Defaults

Sid's own colours, settings and keybindings, as the defaults of SidCode.

Four themes, from his colour files: **Sid's Bright Teal**, **Sid's Dark Teal**,
**Sid's Midway Teal** and **Sid's Soft Blue**. Which one SidCode opens with is
`default-theme.txt` in the folder above; the rest are one click away in the theme picker - or
one entry away in **Tools > Themes > Sid's Colours**, which this extension contributes.

The `.json` files here are the ones he keeps - comments and all - and the `.theme.json` files
beside them are what is generated and shipped from those. Run
`node tools/make-defaults.mjs` after changing either.

`extension.js` is what is behind that menu: one command per colour set applies it, and
**Any Others...** opens the list of every other theme the editor has. The command ids are
written by `tools/make-defaults.mjs` into `package.json` and read back out of it here, so the
menu and the runtime cannot drift apart - `node tools/check-themes-menu.mjs` checks that they
have not, before a build rather than in the menu bar.
