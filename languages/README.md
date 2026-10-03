# SidCode Languages

The languages SidCode provides itself, rather than the ones it builds in from the open gallery.

## What is in here

**nginx** - a grammar, the file patterns, comments and brackets. It is here rather than fetched
from the gallery because the only real nginx syntax extension on Open VSX is GPL-3.0: a licence to
install on your own machine, not one to build into an editor you hand to anyone. This one is MIT
and it is ours.

`build.sh` copies this folder into the app's `resources/app/extensions/`, so it is on with no
install step, and `./build.sh --brand-only <app dir>` puts a change into an app already built.

## Claiming a file extension as a language

Two routes, and the first is nearly always the one you want.

**For yourself, now, with no build.** If a language already exists for what you are looking at -
and there are 83 of them in the editor before anything is added - it is one line in your own
settings (`Preferences: Open User Settings (JSON)`):

```json
"files.associations": {
    "*.sidconf": "nginx"
}
```

The language ids that are always there include `ini`, `properties`, `makefile`, `dockerfile`,
`yaml`, `sql`, `shellscript`, `perl`, `python`, `php`, `ruby`, `go`, `rust`, `java`, `csharp`,
`cpp`, `lua`, `r`, `latex`, `xml`, and the web ones. What the built-in extensions add is on top of
that: `nginx` (this one), and from `willibrandon.systemd` - `systemd-unit`, `systemd-network`,
`systemd-config`, `systemd-udev-rules`, `systemd-tmpfiles`, `systemd-sysusers`, `podman-quadlet`,
`mkosi` and the rest of the systemd family.

`COMMANDS.md` has the same list with the commands around it.

**For everyone who builds SidCode.** If nothing has a grammar for it, the language has to be
declared, and that is this extension:

1. Add the language to `package.json` under `contributes.languages`:

```json
{
    "id": "myconf",
    "aliases": ["MyConf"],
    "extensions": [".myconf"],
    "configuration": "./language-configuration.json"
}
```

2. Add its grammar to `contributes.grammars`, pointing at a file in `syntaxes/`. A TextMate
   grammar is JSON: `patterns` at the top, `repository` below with the rules, and each rule names
   a scope (`keyword.other.myconf`) that the theme then colours. `syntaxes/nginx.tmLanguage.json`
   is small enough to copy and rename - the shape it uses is a comment rule, a quoted-string rule,
   a `begin`/`end` rule for blocks, and a `begin`/`end` rule for a directive that ends in `;`.

3. Put the file patterns that are globs (a path, not an extension) in `defaults/settings.json`
   under `files.associations` instead - `**/sites-available/*` is not something an extension's
   `languages` entry can express, and that is why nginx names them there.

4. `./build.sh --brand-only <app dir>` and it is in.

## Changing nginx itself

The grammar colours by shape, not by a list of nginx directives: the first word on a line is the
directive, everything after it is its values, `{` opens a block and `;` ends a directive. Adding a
directive to nginx therefore needs nothing here. What is worth knowing if you edit the file: every
regex was checked by compiling it, and the grammar was run over a real config with
`vscode-textmate` before it was built in - both are cheap to repeat.
