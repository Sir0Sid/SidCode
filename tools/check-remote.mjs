#!/usr/bin/env node

/**
 * Check the remote half before it is built: the one arrangement in this folder that can be wrong in
 * a way nothing else notices.
 *
 * The editor's settings tell every user's Remote-SSH where to fetch the server component from, and
 * `build.sh --server` names the tarball it packs. If those two names disagree, nothing fails here -
 * a user's editor simply fetches nothing, somewhere else, and says so badly. So the URL in the
 * generated settings is compared against the artifact name, the extension that does the fetching is
 * checked to be in the built-in list, and the parts of `build.sh` that do it are checked to exist.
 *
 * Run it after changing anything about the remote half; it runs `make-defaults` itself, so what it
 * reads is the manifest that would be built.
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { artifactName, artifactUrl, fill, readArtifact } from './artifact-name.mjs';

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

function source(relative) {
  return fs.readFileSync(path.join(root, relative), 'utf8');
}

function main() {
  execFileSync(process.execPath, [path.join(here, 'make-defaults.mjs')], { stdio: 'pipe' });

  const artifact = readArtifact();
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'defaults', 'package.json'), 'utf8'));
  const defaults = manifest.contributes.configurationDefaults || {};
  const url = defaults['remote.SSH.serverDownloadUrlTemplate'];

  // A sample build, only for checking that the URL's file name is the artifact's name.
  const sample = { version: '1.135.06055', commit: 'a1b2c3d', arch: 'x64' };
  const expectedName = artifactName(sample.version, sample.commit, sample.arch);
  const expectedUrl = artifactUrl(sample.version, sample.commit, sample.arch);

  check('the settings carry a download URL for the server component', Boolean(url));
  check(
    'and it is the one server/artifact.json defines',
    url === artifact.urlTemplate,
    `the generated settings say ${JSON.stringify(url)}, server/artifact.json says ${JSON.stringify(artifact.urlTemplate)}`
  );
  check(
    'and it is SidCode\u2019s own, not VSCodium\u2019s',
    !/vscodium/i.test(url || ''),
    `the URL still points at someone else's build: ${JSON.stringify(url)}`
  );
  check(
    'the file it names is the artifact build.sh --server packs',
    expectedUrl.split('/').pop() === expectedName,
    `the URL names ${expectedUrl.split('/').pop()}, the artifact is named ${expectedName}`
  );
  check(
    'the client and the server component are pinned to the same build',
    defaults['remote.SSH.serverVersion'] === 'match',
    `remote.SSH.serverVersion is ${JSON.stringify(defaults['remote.SSH.serverVersion'])}, which lets a client and a server be different builds`
  );

  // The extension that does the fetching, and it may only be one that is allowed to ship inside the
  // editor: the list's rule is MIT-only, and this one is MIT with its LICENSE.txt in the VSIX.
  const builtin = source('extensions/builtin.txt');
  const entry = builtin.split('\n').find(line => line.trim().startsWith('jeanp413.open-remote-ssh@'));

  check('the Remote-SSH extension is built in, and pinned to a version', Boolean(entry), `extensions/builtin.txt has no jeanp413.open-remote-ssh@<version> line`);
  check(
    'and it is the one that can be pointed at your own server build',
    /open-remote-ssh/.test(entry || '') && !/ms-vscode-remote/.test(builtin),
    'the built-in list names Microsoft\u2019s Remote-SSH, which is not on the open gallery and may not be shipped'
  );

  // The build half: the flag, the branch, and the two functions that do the work.
  const build = source('build.sh');
  check('build.sh takes --server', /--server\)\s*SERVER_MODE="yes"/.test(build));
  check('and branches into the server build', /build_server_component\n/.test(build));
  check('and looks for what VSCodium left behind rather than assuming it', build.includes('find_reh_dir'));
  check(
    'and refuses to do it quietly when there is no server build',
    /finished without leaving a server build behind/.test(build)
  );
  check(
    'and names the artifact through the one definition',
    build.includes('tools/artifact-name.mjs')
  );

  // The definition itself has to be usable by all of this.
  check('artifact.json has a name with variables in it', /\$\{version\}/.test(artifact.name || ''));
  check(
    'and the name it produces contains no unsubstituted variables',
    !/\$\{/.test(expectedName),
    `the name still has variables in it: ${expectedName}`
  );
  check(
    'and filling an unknown variable leaves it visible rather than making it empty',
    fill('${version}-${nothing}', { version: '1' }) === '1-${nothing}'
  );

  if (failures.length > 0) {
    console.error('the remote half is not what it should be:');
    failures.forEach(failure => console.error(`  ${failure}`));
    process.exit(1);
  }

  console.log(`Remote half OK - ${notes.length} checks.`);
  console.log(`  every user's editor fetches the server component from, for a build like this one:`);
  console.log(`    ${expectedUrl}`);
  console.log(`  and the artifact it will find there is called:`);
  console.log(`    ${expectedName}`);
}

main();
