#!/usr/bin/env node

/**
 * Check the Themes menu before it is built, rather than after.
 *
 * Two failures this exists for, both of which look like a finished editor:
 *
 *   * a command that nothing can reach. A command with no menu entry, or a menu entry naming a
 *     command that was never contributed, is only ever noticed in the menu bar - which is the
 *     place the Tools patch was written because the menu bar cannot be trusted to say so.
 *   * the manifest and `extension.js` drifting apart. The runtime reads its command ids back
 *     out of the manifest rather than repeating them, and it names two of them - the menu it
 *     fills and the command that opens the list of every other theme. Those two are the only
 *     ids written twice, so they are the ones compared here.
 *
 * Run it after `tools/make-defaults.mjs`; it runs that itself, so the manifest it checks is the
 * one that would be built.
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import Module, { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// This file is a module; `extension.js` is CommonJS, as an extension has to be.
const require = createRequire(import.meta.url);

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const defaults = path.join(root, 'defaults');

const failures = [];
const notes = [];

function check(what, condition, detail) {
  if (condition) {
    notes.push(what);
  } else {
    failures.push(detail || what);
  }
}

/**
 * `extension.js` is a CommonJS file that starts with `require('vscode')`, which Node has not.
 *
 * The stub is deliberately strict where the editor is strict: the section and the key are
 * joined the way the editor joins them, and a setting that does not come out as
 * `workbench.colorTheme` is refused with the message the editor gives. Writing
 * `workbench.colorTheme` *inside* the `workbench` section asks for a setting of
 * `workbench.workbench.colorTheme`, and the editor answers that by refusing to write anything
 * at all - which is what 1.2.0 shipped, and what the menu bar said instead of changing colour.
 */
function loadExtension(manifest, ownId) {
  const original = Module._load;
  const applied = [];
  const commands = {};
  const errors = [];
  const picks = [];

  const stub = {
    commands: {
      registerCommand: (id, handler) => {
        commands[id] = handler;
        return { dispose() {} };
      },
    },
    workspace: {
      getConfiguration: section => ({
        get: () => applied[applied.length - 1],
        update: (key, value) => {
          const full = section ? `${section}.${key}` : key;

          if (full !== 'workbench.colorTheme') {
            const error = new Error(
              `Unable to write to Workspace Settings because ${full} is not a registered configuration.`
            );
            errors.push(error.message);
            return Promise.reject(error);
          }

          applied.push(value);
          return Promise.resolve();
        },
      }),
    },
    extensions: {
      all: [
        { id: ownId, packageJSON: manifest },
        {
          id: 'someone.else',
          packageJSON: {
            displayName: 'Someone Else',
            contributes: { themes: [{ label: "Sid's Bright Teal" }, { label: 'One Dark Pro' }] },
          },
        },
      ],
    },
    window: {
      createQuickPick: () => {
        const pick = {
          items: [],
          selectedItems: [],
          shown: false,
          onDidChangeActive(handler) {
            pick.changed = handler;
          },
          onDidAccept(handler) {
            pick.accepted = handler;
          },
          onDidHide(handler) {
            pick.hidden = handler;
          },
          show() {
            pick.shown = true;
          },
          hide() {},
          dispose() {},
        };

        picks.push(pick);
        return pick;
      },
      showErrorMessage: message => errors.push(message),
      showInformationMessage: () => {},
    },
    QuickPickItemKind: { Separator: -1 },
    ConfigurationTarget: { GLOBAL: 1 },
  };

  Module._load = function load(request, parent, isMain) {
    if (request === 'vscode') {
      return stub;
    }

    return original.apply(this, arguments);
  };

  try {
    return {
      extension: require(path.join(defaults, 'extension.js')),
      commands,
      applied,
      errors,
      picks,
    };
  } finally {
    Module._load = original;
  }
}

async function main() {
  execFileSync(process.execPath, [path.join(here, 'make-defaults.mjs')], { stdio: 'pipe' });

  const manifest = JSON.parse(fs.readFileSync(path.join(defaults, 'package.json'), 'utf8'));
  const contributes = manifest.contributes || {};
  const themes = contributes.themes || [];
  const commands = contributes.commands || [];
  const submenus = contributes.submenus || [];
  const menus = contributes.menus || {};
  const activationEvents = manifest.activationEvents || [];

  check('there are colour sets to list', themes.length > 0);

  check(
    'the extension has a runtime for the menu',
    manifest.main === './extension.js' && fs.existsSync(path.join(defaults, 'extension.js'))
  );

  // One command per colour set, titled with the theme's own name.
  const themeCommands = commands.filter(command => command.command.indexOf('sidcode.theme.') === 0);
  check(
    'one command per colour set',
    themeCommands.length === themes.length,
    `there are ${themes.length} colour sets and ${themeCommands.length} commands for them`
  );
  themes.forEach(theme => {
    check(
      `"${theme.label}" has a command titled with its name`,
      themeCommands.filter(command => command.title === theme.label).length === 1
    );
  });

  const ids = commands.map(command => command.command);
  check('no command id is used twice', new Set(ids).size === ids.length, 'two commands share an id');

  // Every command is reachable, and every id an entry names is a command that exists.
  commands.forEach(command => {
    check(
      `"${command.command}" starts the extension when it is run`,
      activationEvents.indexOf(`onCommand:${command.command}`) !== -1
    );
  });

  Object.keys(menus).forEach(location => {
    menus[location].forEach(entry => {
      if (entry.command) {
        check(
          `"${entry.command}" in ${location} is a contributed command`,
          ids.indexOf(entry.command) !== -1,
          `${location} names "${entry.command}", which is not contributed`
        );
      }
    });
  });

  // The two submenus have to be declared with a label, or neither can be drawn.
  const submenuIds = submenus.map(submenu => submenu.id);
  ['sidcode.themes', 'sidcode.themes.sids'].forEach(id => {
    const declared = submenus.filter(submenu => submenu.id === id)[0];
    check(`the submenu "${id}" is declared with a label`, Boolean(declared && declared.label));
  });

  // Tools, under SFTP/FTP.
  const tools = menus['menuBar/tools'] || [];
  const inTools = tools.filter(entry => entry.submenu === 'sidcode.themes')[0];
  check('the Themes submenu is in the Tools menu', Boolean(inTools));
  check(
    'it comes after SFTP/FTP',
    Boolean(inTools) && /^navigation@(\d+)$/.test(inTools.group) && Number(inTools.group.split('@')[1]) > 1,
    `Themes sits in Tools at "${inTools && inTools.group}", which does not sort after navigation@1`
  );

  // Every colour set is listed in Sid's Colours, and every entry there is one of them.
  const sidsEntries = menus['sidcode.themes.sids'] || [];
  check(
    "Sid's Colours lists every colour set, once each",
    sidsEntries.length === themes.length &&
      new Set(sidsEntries.map(entry => entry.command)).size === themes.length
  );
  check(
    'Themes holds the list and the way into every other theme',
    (menus['sidcode.themes'] || []).length === 2 &&
      (menus['sidcode.themes'] || []).some(entry => entry.submenu === 'sidcode.themes.sids') &&
      (menus['sidcode.themes'] || []).some(entry => entry.command === 'sidcode.themes.any')
  );

  // The manifest and the runtime, on the two ids the runtime names itself.
  const ownId = `${manifest.publisher}.${manifest.name}`;
  const { extension, commands: runtime, applied, errors, picks } = loadExtension(manifest, ownId);

  check(
    'the runtime knows the submenu the manifest fills',
    extension.SIDS_MENU === 'sidcode.themes.sids' &&
      submenuIds.indexOf(extension.SIDS_MENU) !== -1
  );
  check(
    'the runtime knows the command that opens the list',
    extension.ANY_COMMAND === 'sidcode.themes.any' && ids.indexOf(extension.ANY_COMMAND) !== -1
  );
  check(
    'the runtime reads the colour sets out of the manifest',
    extension.ownThemes(manifest).length === themes.length,
    'the runtime finds a different number of colour sets than the manifest contributes'
  );

  // Run it: activate the way the editor does, then run every command the manifest contributes.
  // A command that throws, or one that asks the editor for a setting that is not there, is an
  // entry in the menu that does nothing - and that is invisible until somebody clicks it, which
  // is how the first version of this was found.
  const context = { extension: { id: ownId, packageJSON: manifest }, subscriptions: [] };

  extension.activate(context);

  const themeHandlers = themeCommands.map(command => ({
    command: command.command,
    title: command.title,
    handler: runtime[command.command],
  }));

  check(
    'activate registers a handler for every colour set',
    themeHandlers.every(entry => typeof entry.handler === 'function'),
    `not registered: ${themeHandlers
      .filter(entry => typeof entry.handler !== 'function')
      .map(entry => entry.command)
      .join(', ')}`
  );
  check(
    'activate registers the command that opens the list',
    typeof runtime[extension.ANY_COMMAND] === 'function'
  );

  for (const entry of themeHandlers) {
    if (typeof entry.handler === 'function') {
      await entry.handler();
    }
  }

  check(
    'every colour set command sets its own theme',
    applied.length === themeHandlers.length &&
      themeHandlers.every((entry, index) => applied[index] === entry.title),
    `${applied.length} of ${themeHandlers.length} set a theme: ${JSON.stringify(applied)}`
  );
  check(
    'no command asks for a setting that does not exist',
    errors.length === 0,
    [...new Set(errors)].join('; ')
  );

  // The list itself, driven through the same code the menu runs.
  if (typeof runtime[extension.ANY_COMMAND] === 'function') {
    await runtime[extension.ANY_COMMAND]();

    const pick = picks[picks.length - 1];
    const labels = pick ? pick.items.map(item => item.label) : [];

    check('the list opens', Boolean(pick && pick.shown));
    check(
      'it lists his colour sets first, under a heading, then every other theme',
      labels[0] === "Sid's Colours" &&
        themes.every(theme => labels.indexOf(theme.label) !== -1) &&
        labels[labels.length - 1] === 'One Dark Pro',
      `the list came out as ${JSON.stringify(labels)}`
    );
    check(
      'it says which theme is in use',
      Boolean(pick) && pick.items.some(item => item.description === 'in use')
    );

    // The three things the picker promises: moving through it previews what is under the
    // cursor, choosing applies it, and leaving without choosing puts back what was on when the
    // list was opened - not what the preview left behind.
    const lastPick = () => picks[picks.length - 1];
    const whenOpened = applied[applied.length - 1];

    const underCursor = lastPick().items.filter(item => item.label === "Sid's Bright Teal")[0];
    lastPick().changed([underCursor]);
    check(
      'moving through the list previews what is under the cursor',
      applied[applied.length - 1] === "Sid's Bright Teal",
      `the preview left ${JSON.stringify(applied[applied.length - 1])}`
    );

    lastPick().hidden();
    check(
      'leaving the list without choosing puts back what was on when it opened',
      applied[applied.length - 1] === whenOpened,
      `it left ${JSON.stringify(applied[applied.length - 1])} instead of ${JSON.stringify(whenOpened)}`
    );

    // A second look, where what was on is a theme from somewhere else.
    await runtime[extension.ANY_COMMAND]();
    lastPick().selectedItems = [{ label: 'One Dark Pro' }];
    lastPick().accepted();
    check('choosing a theme applies it', applied[applied.length - 1] === 'One Dark Pro');

    await runtime[extension.ANY_COMMAND]();
    lastPick().hidden();
    check(
      'and leaving that one without choosing puts One Dark Pro back',
      applied[applied.length - 1] === 'One Dark Pro',
      `it left ${JSON.stringify(applied[applied.length - 1])}`
    );

    check('driving the list reported nothing', errors.length === 0, [...new Set(errors)].join('; '));
  }

  // The grouping, against a window that has his themes and somebody else's.
  const foreign = {
    id: 'someone.else',
    packageJSON: {
      displayName: 'Someone Else',
      contributes: { themes: [{ label: "Sid's Bright Teal" }, { label: 'One Dark Pro' }] },
    },
  };
  const mine = {
    id: ownId,
    packageJSON: { contributes: { themes: themes.map(theme => ({ label: theme.label })) } },
  };
  const grouped = extension.themesFrom([mine, foreign], ownId);

  check(
    'the colour sets are listed first',
    grouped.sids.length === themes.length && grouped.others.length === 1 && grouped.others[0].label === 'One Dark Pro',
    `grouped as ${JSON.stringify(grouped)}`
  );
  check(
    'a theme offered twice is offered once',
    grouped.sids.concat(grouped.others).length === themes.length + 1
  );
  check('every other theme says where it came from', grouped.others[0].from === 'Someone Else');

  // A window that has nothing but his own: the list is his colour sets and no other section,
  // rather than an error about an empty group.
  const alone = extension.themesFrom([mine], ownId);
  check(
    'the list still works with no other theme installed',
    alone.sids.length === themes.length && alone.others.length === 0
  );

  if (failures.length > 0) {
    console.error('the Themes menu is not what it should be:');
    failures.forEach(failure => console.error(`  ${failure}`));
    process.exit(1);
  }

  console.log(`Themes menu OK - ${notes.length} checks, ${themes.length} colour sets:`);
  console.log(`  ${themes.map(theme => theme.label).join(', ')}`);
  console.log(`  plus "Any Others...", which lists every theme in the window (${extension.ANY_COMMAND})`);
}

main().catch(error => {
  console.error(error && error.message ? error.message : error);
  process.exit(1);
});
