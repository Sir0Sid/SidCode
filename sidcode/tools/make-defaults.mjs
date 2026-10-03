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
const EXTENSION_VERSION = '1.1.1';

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

  const manifest = {
    name: EXTENSION_NAME,
    displayName: 'SidCode Defaults',
    description: "Sid's colours, settings and keybindings, as the defaults of SidCode.",
    publisher: PUBLISHER,
    version: EXTENSION_VERSION,
    engines: { vscode: '^1.64.2' },
    categories: themes.length ? ['Themes'] : [],
    contributes: {
      themes: themes.map(({ label, uiTheme, path: themePath }) => ({
        label,
        uiTheme,
        path: themePath,
      })),
      configurationDefaults,
      keybindings,
    },
  };

  fs.writeFileSync(path.join(defaults, 'package.json'), JSON.stringify(manifest, null, 2) + '\n');

  const wrapped = themes.filter(theme => theme.wrapped).map(theme => theme.label);

  console.log('SidCode Defaults written to defaults/package.json');
  console.log(
    `  themes:   ${themes.length}${themes.length ? ` (${themes.map(t => t.label).join(', ')})` : ''}`
  );
  console.log(`  default:  ${wanted || 'none - no theme files in defaults/themes yet'}`);
  console.log(`  settings: ${Object.keys(settings).length}`);
  console.log(`  keybindings: ${Array.isArray(keybindings) ? keybindings.length : 0}`);

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
