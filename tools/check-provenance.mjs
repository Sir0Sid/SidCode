#!/usr/bin/env node

/**
 * Check that everything built into SidCode is MIT, and that the record says where it came from.
 *
 * `extensions/builtin.txt` says "MIT only" in a comment, and a comment cannot fail a build. This is
 * the same rule as something that can: every entry in that list has to have a record in
 * `extensions/provenance.json` - the licence and the upstream it came from - the licence has to be
 * one this product may ship, and the pinned version has to be the version the record names. So a
 * new built-in fails the check until somebody writes down where it came from, and a licence that
 * cannot be shipped fails it outright.
 *
 * No network: it compares two files in this folder. `tools/check-remote.mjs` and
 * `tools/check-branding.mjs` are the other two halves of the same idea.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');

/** The licences this product may build in. Anything else needs a decision, not a default. */
const SHIPPABLE = ['MIT'];

const failures = [];
const notes = [];

function check(what, condition, detail) {
  if (condition) {
    notes.push(what);
  } else {
    failures.push(detail || what);
  }
}

/** `publisher.name@version`, one per line, comments and blank lines ignored. */
function builtIns() {
  return fs
    .readFileSync(path.join(root, 'extensions', 'builtin.txt'), 'utf8')
    .split('\n')
    .map(line => line.split('#')[0].trim())
    .filter(line => line.includes('@'))
    .map(line => {
      const id = line.slice(0, line.lastIndexOf('@'));
      const version = line.slice(line.lastIndexOf('@') + 1);
      return { id, version };
    });
}

function main() {
  const entries = builtIns();
  const record = JSON.parse(fs.readFileSync(path.join(root, 'extensions', 'provenance.json'), 'utf8'));
  const recorded = Object.keys(record).filter(key => key !== '//');

  check('there are built-ins to account for', entries.length > 0);

  entries.forEach(({ id, version }) => {
    const row = record[id];

    check(`${id} has a record`, Boolean(row), `${id} is built in with no entry in extensions/provenance.json`);

    if (!row) {
      return;
    }

    check(
      `${id} is recorded as ${SHIPPABLE.join(' or ')}`,
      SHIPPABLE.includes(row.licence),
      `${id} is recorded as ${JSON.stringify(row.licence)}, which this product may not ship - the list's rule is ${SHIPPABLE.join(' or ')} only`
    );
    check(
      `${id} records the version it is pinned to`,
      row.version === version,
      `${id} is pinned to ${version} in builtin.txt and recorded as ${JSON.stringify(row.version)} - the record did not follow the pin`
    );
    check(`${id} records where it came from`, Boolean(row.upstream), `${id} has no upstream in its record`);

    // A licence that is real but undeclared - the registry and the manifest say nothing - is worth
    // saying so, because the next person to check will look there first and find nothing.
    if (row.licence === 'MIT' && !row.evidence) {
      notes.push(`${id}: declared MIT`);
    }
  });

  recorded.forEach(id => {
    check(
      `${id} is still built in`,
      entries.some(entry => entry.id === id),
      `${id} has a record but is no longer in extensions/builtin.txt - the record is the list's shadow and should not outlive it`
    );
  });

  if (failures.length > 0) {
    console.error('the built-in extensions are not accounted for:');
    failures.forEach(failure => console.error(`  ${failure}`));
    process.exit(1);
  }

  console.log(`Built-ins OK - ${notes.length} checks, ${entries.length} extensions, all ${SHIPPABLE.join('/')}.`);
  console.log('  where they come from, as recorded:');
  entries.forEach(({ id }) => {
    const row = record[id];
    console.log(`    ${id}@${row.version}  ${row.licence}  ${row.upstream.replace('https://github.com/', '')}`);
  });
  const withEvidence = entries.filter(({ id }) => record[id].evidence);
  if (withEvidence.length > 0) {
    console.log(`  told apart by hand: ${withEvidence.map(({ id }) => id).join(', ')} - the licence is real but not declared where the registry looks`);
  }
}

main();
