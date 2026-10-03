'use strict';

/**
 * The Themes menu: Sid's own colour sets as a list, and a way into every other theme the
 * editor has.
 *
 * The menu itself is in `package.json`, written by `tools/make-defaults.mjs` - one command per
 * colour set, plus "Any Others...". An extension's menu entries cannot be added while it runs,
 * so the colour sets, which are known when this is packaged, are entries; the other themes on
 * the machine are not, and what cannot be an entry is a list instead, opened by the one command
 * that is.
 *
 * The command ids are not repeated here. They are read back out of this extension's own
 * manifest, which is the only place they are written, and `tools/check-themes-menu.mjs` fails
 * if the two ever stop agreeing.
 */

const vscode = require('vscode');

/** The command `package.json` puts in Themes beside "Sid's Colours". */
const ANY_COMMAND = 'sidcode.themes.any';
/** The submenu whose entries are one command per colour set. */
const SIDS_MENU = 'sidcode.themes.sids';
/** The section the chosen theme lives in, and the key inside it. */
const WORKBENCH = 'workbench';
/**
 * Just the key, never "workbench.colorTheme": `getConfiguration(WORKBENCH)` carries the
 * section already, so the full name here asks the editor for the setting
 * `workbench.workbench.colorTheme`, which does not exist - and it answers by refusing to write
 * it at all. That is what 1.2.0 shipped with, which is why the menu said
 * "Unable to write to Workspace Settings because workbench.workbench.colorTheme is not a
 * registered configuration" instead of changing a colour.
 */
const THEME_SETTING = 'colorTheme';

/** Older editors have no separator kind; -1 is what it is. */
const SEPARATOR = vscode.QuickPickItemKind ? vscode.QuickPickItemKind.Separator : -1;

function text(value) {
  return typeof value === 'string' ? value.trim() : '';
}

/**
 * Every theme the editor has, its own colour sets first and where each one came from.
 *
 * Pure on purpose - it is handed the extensions rather than reading them, so the grouping can
 * be tested without an editor. A label offered twice is offered once, by the first extension
 * to claim it: that is the one the editor would use for it.
 */
function themesFrom(extensions, ownId) {
  const sids = [];
  const others = [];
  const seen = {};

  (extensions || []).forEach(extension => {
    const packageJSON = (extension && extension.packageJSON) || {};
    const contributes = packageJSON.contributes || {};
    const themes = Array.isArray(contributes.themes) ? contributes.themes : [];
    const from = text(packageJSON.displayName) || text(packageJSON.name) || text(packageJSON.id);

    themes.forEach(theme => {
      const label = text(theme && theme.label);

      if (!label || seen[label]) {
        return;
      }

      seen[label] = true;

      const entry = { label, from };

      if (extension.id === ownId) {
        sids.push(entry);
      } else {
        others.push(entry);
      }
    });
  });

  return { sids, others };
}

/** The colour sets this extension ships, in the order its own submenu lists them. */
function ownThemes(packageJSON) {
  const menu = ((packageJSON.contributes || {}).menus || {})[SIDS_MENU] || [];
  const titles = {};

  ((packageJSON.contributes || {}).commands || []).forEach(command => {
    titles[command.command] = command.title;
  });

  return menu
    .map(entry => ({ command: entry.command, label: titles[entry.command] }))
    .filter(entry => entry.command && entry.label);
}

function applyTheme(label) {
  return Promise.resolve(
    vscode.workspace.getConfiguration(WORKBENCH).update(THEME_SETTING, label, vscode.ConfigurationTarget.GLOBAL)
  ).catch(error => {
    vscode.window.showErrorMessage(`The colour theme could not be set: ${error && error.message ? error.message : error}`);
  });
}

function currentTheme() {
  return vscode.workspace.getConfiguration(WORKBENCH).get(THEME_SETTING);
}

/**
 * The list of every theme, opened by "Any Others...".
 *
 * One list rather than only the other extensions' themes: the menu already has his four, and a
 * list that a person opens to change theme is the place they would look for any of them. Moving
 * through it applies what is under the cursor, and leaving it without choosing puts back what
 * was on - the editor's own picker behaves this way, and a preview that cannot be undone is
 * worse than none.
 */
async function chooseTheme(context) {
  const { sids, others } = themesFrom(vscode.extensions.all, context.extension.id);
  const inUse = currentTheme();
  const items = [];

  if (sids.length > 0) {
    items.push({ label: "Sid's Colours", kind: SEPARATOR });
    sids.forEach(theme => {
      items.push({ label: theme.label, description: theme.label === inUse ? 'in use' : undefined });
    });
  }

  if (others.length > 0) {
    items.push({ label: 'Other Extensions', kind: SEPARATOR });
    others.forEach(theme => {
      items.push({
        label: theme.label,
        description: theme.label === inUse ? `in use - ${theme.from}` : theme.from,
      });
    });
  }

  if (items.length === 0) {
    vscode.window.showInformationMessage('No colour themes are installed.');
    return;
  }

  const before = text(inUse);
  const pick = vscode.window.createQuickPick();

  pick.title = 'Colour Theme';
  pick.placeholder = 'The theme is applied as you move through the list; Escape puts the last one back';
  pick.items = items;

  let chosen = false;

  pick.onDidChangeActive(selected => {
    const item = selected[0];

    if (item && !item.kind) {
      applyTheme(item.label);
    }
  });

  pick.onDidAccept(() => {
    chosen = true;
    const item = pick.selectedItems[0];

    if (item) {
      applyTheme(item.label);
    }

    pick.hide();
  });

  pick.onDidHide(() => {
    if (!chosen && before) {
      applyTheme(before);
    }

    pick.dispose();
  });

  pick.show();
}

function activate(context) {
  ownThemes(context.extension.packageJSON).forEach(theme => {
    context.subscriptions.push(
      vscode.commands.registerCommand(theme.command, () => applyTheme(theme.label))
    );
  });

  context.subscriptions.push(
    vscode.commands.registerCommand(ANY_COMMAND, () => chooseTheme(context))
  );
}

function deactivate() {
  // Nothing to put back: the theme is a setting, not a resource this holds open.
}

module.exports = { activate, deactivate, themesFrom, ownThemes, ANY_COMMAND, SIDS_MENU };
