#!/usr/bin/env node

/**
 * The name of the remote server artifact, and the URL it is fetched from - both derived from
 * `server/artifact.json`, which is the only place either is written.
 *
 * Three things read this: `build.sh --server` names the tarball it packs, `tools/publish-server.sh`
 * says where that tarball has to be uploaded, and `tools/check-remote.mjs` compares the URL the
 * editor's settings were generated with against the one here. A mismatch between the name in the
 * URL and the name of the artifact is the one failure in this arrangement that nothing else would
 * notice - the editor would simply fail to fetch a server and say so badly.
 *
 *   node tools/artifact-name.mjs name <version> <commit> <arch>
 *   node tools/artifact-name.mjs url  <version> <commit> <arch>
 *
 * `quality` is fixed at `stable`: it is one of the variables the Remote-SSH extension substitutes
 * and this product has no insiders channel.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const file = path.join(here, '..', 'server', 'artifact.json');

export function readArtifact() {
  const artifact = JSON.parse(fs.readFileSync(file, 'utf8'));

  if (!artifact.name || !artifact.urlTemplate) {
    throw new Error(`${path.relative(process.cwd(), file)} needs both a name and a urlTemplate`);
  }

  return artifact;
}

export function fill(template, values) {
  return template.replace(/\$\{(\w+)\}/g, (whole, key) =>
    values[key] === undefined ? whole : String(values[key])
  );
}

export function artifactName(version, commit, arch) {
  return fill(readArtifact().name, { version, commit, arch, quality: 'stable' });
}

export function artifactUrl(version, commit, arch) {
  return fill(readArtifact().urlTemplate, { version, commit, arch, quality: 'stable' });
}

// Called as a script rather than imported: two lines of output, no state.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [what, version, commit, arch] = process.argv.slice(2);

  if (!version) {
    console.error('usage: node tools/artifact-name.mjs name|url <version> <commit> <arch>');
    process.exit(2);
  }

  if (what === 'name') {
    console.log(artifactName(version, commit, arch));
  } else if (what === 'url') {
    console.log(artifactUrl(version, commit, arch));
  } else {
    console.error(`unknown: ${what} - name or url`);
    process.exit(2);
  }
}
