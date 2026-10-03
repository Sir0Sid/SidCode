#!/usr/bin/env node

/**
 * Check the product's own identity: the name, the folder, the links, and which services it talks to.
 *
 * This is the half of a product that cannot be seen by looking at the code, and it fails quietly in
 * exactly the way that costs money later: a link that still points at somebody else's repository, a
 * data folder that shares its name with another editor's, or an update check still aimed at the
 * build SidCode is derived from - which would deliver *their* editor over this one.
 *
 * Run it after touching branding/product.sidcode.json or the settings that go with it.
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');

const failures = [];
const notes = [];

function check(what, condition, detail) {
  if (condition) {
    notes.push(what);
  } else {
    failures.push(detail || what);
  }
}

function main() {
  execFileSync(process.execPath, [path.join(here, 'make-defaults.mjs')], { stdio: 'pipe' });

  const branding = JSON.parse(fs.readFileSync(path.join(root, 'branding', 'product.sidcode.json'), 'utf8'));
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'defaults', 'package.json'), 'utf8'));
  const defaults = manifest.contributes.configurationDefaults || {};

  // The name and the folder it keeps its own things in.
  check('the product is called SidCode', branding.nameLong === 'SidCode' && branding.nameShort === 'SidCode');
  check('its data folder is its own', branding.dataFolderName === '.sidcode', `dataFolderName is ${JSON.stringify(branding.dataFolderName)}, which another editor may also be using`);
  check('and so is its server side', branding.serverDataFolderName === '.sidcode-server');
  check('its url protocol is its own', branding.urlProtocol === 'sidcode');
  check('people run it by a name of its own', branding.applicationName === 'sidcode');

  // The links. Every one of these is somewhere a customer clicks, so every one of them has to lead
  // to Sid rather than to the project this is built from.
  const urls = ['documentationUrl', 'reportIssueUrl', 'requestFeatureUrl', 'licenseUrl'];
  urls.forEach(key => {
    const value = branding[key] || '';
    check(`${key} is set`, value.length > 0);
    check(
      `${key} does not lead to Microsoft's or VSCodium's`,
      !/vscode|vscodium|visualstudio|microsoft/i.test(value),
      `${key} is ${JSON.stringify(value)}`
    );
    check(
      `${key} leads to Sid's own`,
      /sidcode\.dev|github\.com\/Sir0Sid/i.test(value),
      `${key} is ${JSON.stringify(value)}, which is neither sidcode.dev nor his GitHub`
    );
  });
  check('the documentation link is the site itself', /sidcode\.dev/.test(branding.documentationUrl || ''));

  // Which services the editor talks to. It may not name an update service of its own and leave the
  // check on - that combination means it is asking somebody else's, and would take their build.
  const updateMode = defaults['update.mode'];
  const updateUrl = branding.updateUrl;

  check(
    'there is no update service of somebody else\u2019s behind the update check',
    Boolean(updateUrl) || updateMode === 'none',
    updateUrl
      ? `the branding names ${updateUrl}: that is yours to run, which this does not check`
      : `no updateUrl is set, so the editor would use the inherited one, and update.mode is ${JSON.stringify(updateMode)} instead of "none"`
  );
  check(
    'the extension gallery is the open one, unless Sid runs his own',
    !branding.extensionsGallery || !/marketplace\.visualstudio/i.test(JSON.stringify(branding.extensionsGallery)),
    'the branding points the Extensions view at Microsoft\u2019s marketplace, which may not serve a build that is not theirs'
  );

  if (failures.length > 0) {
    console.error('the product is not presented as its own:');
    failures.forEach(failure => console.error(`  ${failure}`));
    process.exit(1);
  }

  console.log(`Product identity OK - ${notes.length} checks.`);
  console.log(`  ${branding.nameLong}, ${branding.dataFolderName}/, run as \`${branding.applicationName}\``);
  console.log(`  documentation: ${branding.documentationUrl}`);
  console.log(`  updates: ${updateUrl ? `from ${updateUrl}` : `off (update.mode: ${updateMode})`}`);
}

main();
