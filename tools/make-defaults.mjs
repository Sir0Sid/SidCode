#!/usr/bin/env node

/**
 * Build the `sidcode-defaults` extension from the files Sid keeps in this folder.
 *
 * Drop colour files into `defaults/themes/`, settings into `defaults/settings.json` and
 * keybindings into `defaults/keybindings.json`, then run this. It writes
 * `defaults/package.json` - the manifest that turns those files into an extension - and says
 * what it found. Nothing here edits the files that were put in: a theme that is only a
 * `workbench.colorCustomizations` block is wrapped into a real theme file beside it.
 *
 * The same extension serves both halves of SidCode: install it as a VSIX into the editor he
 * uses today, and copy the folder into the build's `extensions/` to have it built in.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const defaults = path.join(root, 'defaults');
const themesDir = path.join(defaults, 'themes');

const PUBLISHER = 'Sir0Sid';
const EXTENSION_NAME = 'sidcode-defaults';
// Bumped here rather than in the generated manifest, which is rewritten every run.
const EXTENSION_VERSION = '1.3.1';

/**
 * The Themes menu. `sidcode.themes` is what goes in Tools, `sidcode.themes.sids` is the list
 * of Sid's own colour sets inside it; "Any Others..." is a command rather than a list, because
 * an extension's menu entries are fixed when it is packaged and the other themes on a machine
 * are not known until it runs. `defaults/extension.js` opens that list and knows these two ids -
 * `tools/check-themes-menu.mjs` fails if the two ever stop agreeing.
 */
const THEME_MENU = 'sidcode.themes';
const SIDS_MENU = 'sidcode.themes.sids';
const ANY_COMMAND = 'sidcode.themes.any';

/**
 * VS Code's own user files are JSON with comments and trailing commas. `JSON.parse` refuses
 * both, and refusing them here would mean refusing the very files this is for.
 */
function parseJsonc(text, file) {
  const withoutComments = text
    .replace(/\\"|"(?:\\"|[^"])*"|(\/\/.*|\/\*[\s\S]*?\*\/)/g, (match, comment) =>
      comment ? '' : match
    )
    .replace(/,(\s*[}\]])/g, '$1');

  try {
    return JSON.parse(withoutComments);
  } catch (error) {
    throw new Error(`${file} is not valid JSON: ${error.message}`);
  }
}

function readJsonc(file) {
  return parseJsonc(fs.readFileSync(file, 'utf8'), path.basename(file));
}

function listJson(dir) {
  if (!fs.existsSync(dir)) {
    return [];
  }

  return fs
    .readdirSync(dir)
    .filter(name => name.toLowerCase().endsWith('.json'))
    .sort();
}

function isFullTheme(json) {
  return Array.isArray(json.tokenColors) || (!!json.colors && !json.workbench);
}

function uiThemeFor(json) {
  if (json.type === 'light') {
    return 'vs';
  }
  if (json.type === 'hc') {
    return 'hc-black';
  }

  return 'vs-dark';
}

/**
 * A theme can arrive in either of the two shapes people keep colours in: a theme file, or the
 * `workbench.colorCustomizations` part of a settings file. The second is wrapped rather than
 * refused, because that is what most hand-made colour sets are.
 */
function themeFrom(file) {
  const json = readJsonc(file);
  const base = path.basename(file, '.json');
  const from = path.basename(file);

  if (isFullTheme(json)) {
    const themePath = writeTheme(base, json);
    return {
      label: typeof json.name === 'string' && json.name ? json.name : base,
      uiTheme: uiThemeFor(json),
      path: themePath,
      file: from,
      wrapped: false,
    };
  }

  const tokens = json['editor.tokenColorCustomizations'];
  const wrapped = {
    name: typeof json.name === 'string' && json.name ? json.name : `${base} (SidCode)`,
    type: json.type || 'dark',
    colors: json['workbench.colorCustomizations'] || json,
  };

  if (tokens) {
    wrapped.tokenColors =
      typeof tokens === 'object' && Array.isArray(tokens.textMateRules)
        ? tokens.textMateRules
        : Array.isArray(tokens)
        ? tokens
        : [];
  }

  return {
    label: wrapped.name,
    uiTheme: uiThemeFor(wrapped),
    path: writeTheme(base, wrapped),
    file: from,
    wrapped: true,
  };
}

/**
 * The theme that actually ships, written as plain JSON beside the file it came from.
 *
 * Two reasons it is a copy rather than the file itself: colour files are hand-kept, so they
 * carry comments and notes that a shipped artefact should not, and a theme that is written out
 * from what was parsed is a theme that cannot be broken by a stray trailing comma later.
 */
function writeTheme(base, theme) {
  const name = `${base}.theme.json`;
  const { name: themeName, type, colors, tokenColors } = theme;
  const normalised = { name: themeName || base, type: type || 'dark', colors: colors || {} };

  if (Array.isArray(tokenColors)) {
    normalised.tokenColors = tokenColors;
  }

  fs.writeFileSync(path.join(themesDir, name), JSON.stringify(normalised, null, 2) + '\n');

  return `./themes/${name}`;
}

/**
 * `server/artifact.json`: the one definition of what the remote server component is called and
 * where it is fetched from. `build.sh --server` names the tarball from `name`; this writes
 * `urlTemplate` into the settings. Two readers, one file, so a mismatch cannot be silent.
 */
function readArtifact() {
  const file = path.join(root, 'server', 'artifact.json');

  if (!fs.existsSync(file)) {
    throw new Error(`there is no ${path.relative(root, file)} to read the server artifact from`);
  }

  const artifact = JSON.parse(fs.readFileSync(file, 'utf8'));

  if (!artifact.name || !artifact.urlTemplate) {
    throw new Error(`${path.relative(root, file)} needs both a name and a urlTemplate`);
  }

  return artifact;
}

/** A theme's label as a command id: "Sid's Bright Teal" becomes sidcode.theme.sid-s-bright-teal. */
function commandIdFor(label) {
  const slug = String(label)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

  return `sidcode.theme.${slug || 'theme'}`;
}

/**
 * One command per colour set, each titled with the theme's own name so that it reads the same
 * in the menu, in the palette and in the list of what is installed. Two themes whose names slug
 * the same way get ids that differ: a duplicate id would make one of them unselectable.
 */
function themeCommandsFor(themes) {
  const used = {};

  return themes.map(theme => {
    let id = commandIdFor(theme.label);

    for (let n = 2; used[id]; n += 1) {
      id = `${commandIdFor(theme.label)}-${n}`;
    }

    used[id] = true;

    return { command: id, title: theme.label, category: 'Themes' };
  });
}

/**
 * The Themes menu, or nothing at all when there are no colour files: an empty submenu is
 * dropped from the menu bar by the editor itself, so contributing one would only be litter.
 */
function themesMenuContribution(themes) {
  if (themes.length === 0) {
    return undefined;
  }

  const themeCommands = themeCommandsFor(themes);

  return {
    commands: [{ command: ANY_COMMAND, title: 'Any Others...', category: 'Themes' }].concat(themeCommands),
    submenus: [
      { id: THEME_MENU, label: 'Themes' },
      { id: SIDS_MENU, label: "Sid's Colours" },
    ],
    menus: {
      // Under SFTP/FTP, which the SFTP extension puts in at navigation@1.
      'menuBar/tools': [{ submenu: THEME_MENU, group: 'navigation@2' }],
      [THEME_MENU]: [
        { submenu: SIDS_MENU, group: '1_sids@1' },
        { command: ANY_COMMAND, group: '2_any@1' },
      ],
      [SIDS_MENU]: themeCommands.map((entry, index) => ({
        command: entry.command,
        group: `1@${index + 1}`,
      })),
    },
  };
}

function main() {
  if (!fs.existsSync(themesDir)) {
    console.error(`there is no ${path.relative(root, themesDir)} folder to read themes from`);
    process.exit(1);
  }

  const themeFiles = listJson(themesDir).filter(name => !name.endsWith('.theme.json'));
  const themes = themeFiles.map(name => themeFrom(path.join(themesDir, name)));

  const settingsFile = path.join(defaults, 'settings.json');
  const settings = fs.existsSync(settingsFile) ? readJsonc(settingsFile) : {};

  const keybindingsFile = path.join(defaults, 'keybindings.json');
  const keybindings = fs.existsSync(keybindingsFile) ? readJsonc(keybindingsFile) : [];

  // Which theme SidCode opens with: `defaults/default-theme.txt`, holding a theme's name or
  // the file it came from. Falling back to a label with "default" in it, then to the first.
  const defaultFile = path.join(defaults, 'default-theme.txt');
  const named = fs.existsSync(defaultFile)
    ? fs.readFileSync(defaultFile, 'utf8').trim()
    : '';

  const wanted = (
    (named &&
      (themes.find(theme => theme.label === named) ||
        themes.find(theme => theme.label.toLowerCase() === named.toLowerCase()) ||
        themes.find(theme => theme.file === named))) ||
    themes.find(theme => /default/i.test(theme.label)) ||
    themes[0] ||
    {}
  ).label;

  if (named && !wanted) {
    console.log(`  note: default-theme.txt names "${named}", which no colour file matches`);
  }

  const configurationDefaults = Object.assign({}, settings);
  if (wanted) {
    configurationDefaults['workbench.colorTheme'] = wanted;
  }

  // The remote half. The server component a Remote-SSH session needs is fetched from a URL, and
  // that URL is the one place this product could still be pointing at somebody else's build - so it
  // is written from `server/artifact.json`, the same file `build.sh --server` names the tarball
  // from. Read from one place, written here, checked by `tools/check-remote.mjs`: the name in the
  // URL and the name of the artefact cannot drift apart without something failing first.
  const artifact = readArtifact();
  configurationDefaults['remote.SSH.serverDownloadUrlTemplate'] = artifact.urlTemplate;
  // Left as the extension's own default on purpose, and written out so it is visible: the client
  // and the server component have to be the same build, and `match` is what enforces it. The
  // symptom of getting this wrong is a connection that fails with a version mismatch.
  configurationDefaults['remote.SSH.serverVersion'] = 'match';

  const themesMenu = themesMenuContribution(themes);

  const manifest = {
    name: EXTENSION_NAME,
    displayName: 'SidCode Defaults',
    description: "Sid's colours, settings and keybindings, as the defaults of SidCode.",
    publisher: PUBLISHER,
    version: EXTENSION_VERSION,
    engines: { vscode: '^1.64.2' },
    // The Themes menu lives in this extension, so it is no longer only a set of colour files:
    // `extension.js` applies a theme from the menu and opens the list of every other one.
    main: './extension.js',
    activationEvents: themesMenu
      ? themesMenu.commands.map(entry => `onCommand:${entry.command}`)
      : [],
    categories: themes.length ? ['Themes'] : [],
    contributes: Object.assign(
      {
        themes: themes.map(({ label, uiTheme, path: themePath }) => ({
          label,
          uiTheme,
          path: themePath,
        })),
      },
      themesMenu || {},
      {
        configurationDefaults,
        keybindings,
      }
    ),
  };

  fs.writeFileSync(path.join(defaults, 'package.json'), JSON.stringify(manifest, null, 2) + '\n');

  const wrapped = themes.filter(theme => theme.wrapped).map(theme => theme.label);

  console.log('SidCode Defaults written to defaults/package.json');
  console.log(
    `  themes:   ${themes.length}${themes.length ? ` (${themes.map(t => t.label).join(', ')})` : ''}`
  );
  console.log(`  default:  ${wanted || 'none - no theme files in defaults/themes yet'}`);
  console.log(`  settings: ${Object.keys(settings).length}`);
  console.log(`  remote:   server from ${artifact.urlTemplate}`);
  console.log(`  keybindings: ${Array.isArray(keybindings) ? keybindings.length : 0}`);
  if (themesMenu) {
    console.log(
      `  Themes menu: ${themesMenu.commands.length} commands (${themesMenu.commands
        .map(entry => entry.title)
        .join(', ')})`
    );
  }

  if (wrapped.length) {
    console.log(`  wrapped from colour customisations: ${wrapped.join(', ')}`);
  }
  if (settings['workbench.colorTheme'] && wanted && settings['workbench.colorTheme'] !== wanted) {
    console.log(
      `  note: settings.json asks for "${settings['workbench.colorTheme']}", overridden with "${wanted}"`
    );
  }
}

main();
