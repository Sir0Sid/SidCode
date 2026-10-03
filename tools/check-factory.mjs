#!/usr/bin/env node

/**
 * Check that the factory is here, that it is Sid's, and that the build uses it.
 *
 * The goal this check exists for: cloning SidCode and running `build.sh` builds SidCode, with
 * nothing fetched from anybody else's repository. Three things make that true, and all three are
 * invisible until one of them is false - so they are asked rather than assumed:
 *
 *   * the machinery is in `factory/`, with a record of which VSCodium it was taken from;
 *   * the fetch of Microsoft's source names Sid's own fork, not Microsoft's repository;
 *   * `build.sh` prefers the factory when it is there, instead of fetching a VSCodium checkout.
 *
 * No network. It reads files, like the other four checks.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const factory = path.join(root, 'factory');

const failures = [];
const notes = [];

function check(what, condition, detail) {
  if (condition) {
    notes.push(what);
  } else {
    failures.push(detail || what);
  }
}

function source(relative) {
  return fs.readFileSync(path.join(root, relative), 'utf8');
}

/** Every file under factory/ that could name a repository. */
function factorySources() {
  const found = [];

  const walk = dir => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);

      if (entry.isDirectory()) {
        if (entry.name !== 'node_modules') {
          walk(full);
        }
        continue;
      }

      if (/\.(sh|js|mjs|json|yml|yaml)$/.test(entry.name)) {
        found.push(full);
      }
    }
  };

  walk(factory);
  return found;
}

function main() {
  if (!fs.existsSync(path.join(factory, 'dev', 'build.sh'))) {
    console.error('the factory is not in this repo yet.');
    console.error('  Take it from a checkout, once per VSCodium version:');
    console.error('    ./tools/take-the-factory.sh');
    console.error(`  (nothing else in ${path.relative(process.cwd(), path.join(root, 'tools'))} needs it, and no other check waits for it)`);
    process.exit(1);
  }

  const recordFile = path.join(factory, 'FACTORY');
  check('the factory carries its record', fs.existsSync(recordFile), 'factory/FACTORY is missing - take the factory again so that what is here can be named');

  if (fs.existsSync(recordFile)) {
    const record = fs.readFileSync(recordFile, 'utf8');

    check('and it says where the machinery came from', /taken-from\s+VSCodium\s+\S+/.test(record), `factory/FACTORY does not name the VSCodium version it was taken from:\n${record}`);
    check('and which repository the source is fetched from', /vscode-from\s+https?:\/\/\S+/.test(record), 'factory/FACTORY does not name the repository the source comes from');
  }

  // The whole point: nothing in the machinery still reaches for Microsoft's repository.
  const reaching = factorySources().filter(file => /(^|[^a-z])microsoft\/vscode([^a-z]|$)/i.test(fs.readFileSync(file, 'utf8')));
  check(
    'the machinery fetches the source from Sid\u2019s fork and nowhere else',
    reaching.length === 0,
    `these still name Microsoft's repository: ${reaching.map(file => path.relative(root, file)).join(', ')} - run tools/take-the-factory.sh again, or fix the line it prints`
  );

  const forkNamed = factorySources().some(file =>
    /github\.com\/Sir0Sid\//i.test(fs.readFileSync(file, 'utf8'))
  );
  check('and one of them names Sid\u2019s own', forkNamed, 'no file under factory/ names github.com/Sir0Sid/ - is the rewrite still there?');

  // The build has to prefer the factory, and say which path it took.
  const build = source('build.sh');
  check(
    'build.sh uses the factory when it is there',
    /-d "\$\{FACTORY\}\/dev"/.test(build),
    'build.sh has no test for a factory/dev directory - it would fetch a VSCodium checkout instead'
  );
  check('and says which it used', /factory in this repo|the factory in this repo/.test(build), 'build.sh does not say whether it built from the factory or from a fetched checkout');

  // And the factory has to travel: committed, and in the archive.
  const ignore = fs.existsSync(path.join(root, '.gitignore')) ? source('.gitignore') : '';
  check('the factory is not ignored by git', !/^\s*\/?factory\/?\s*$/m.test(ignore), '.gitignore excludes factory/, so the machinery would not be committed');
  const pack = source('tools/pack.sh');
  check('and the archive carries it', !/exclude=['"]\.\/factory/.test(pack), 'tools/pack.sh excludes factory/ from the archive');

  if (failures.length > 0) {
    console.error('the factory is not what it should be:');
    failures.forEach(failure => console.error(`  ${failure}`));
    process.exit(1);
  }

  const record = fs.readFileSync(recordFile, 'utf8').trim().split('\n');
  console.log(`Factory OK - ${notes.length} checks.`);
  console.log('  in this repo, taken from:');
  record.forEach(line => console.log(`    ${line}`));
  console.log('  and the build will use it without fetching the machinery.');
}

main();
