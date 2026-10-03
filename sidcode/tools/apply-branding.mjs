#!/usr/bin/env node

/**
 * Put SidCode's name on the product.json of a prepared VS Code tree.
 *
 * VSCodium's `prepare_vscode.sh` has already done the de-branding by the time this runs, so
 * this only overrides the fields in `branding/product.sidcode.json` - the name, the CLI
 * command, the data folder, the protocol - and leaves everything else (Open VSX as the
 * gallery, the extension lists, the telemetry flags) as VSCodium left it.
 *
 *   node tools/apply-branding.mjs <path to the prepared vscode/product.json>
 *
 * Run without an argument and it prints what it would set, which is the useful half when
 * something looks wrong.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const brandingFile = path.join(here, '..', 'branding', 'product.sidcode.json');
const branding = JSON.parse(fs.readFileSync(brandingFile, 'utf8'));

const target = process.argv[2];

if (!target) {
  console.log(`branding/product.sidcode.json sets ${Object.keys(branding).length} fields:`);
  for (const [key, value] of Object.entries(branding)) {
    console.log(`  ${key}: ${JSON.stringify(value)}`);
  }
  process.exit(0);
}

if (!fs.existsSync(target)) {
  console.error(`no product.json at ${target}`);
  process.exit(1);
}

const product = JSON.parse(fs.readFileSync(target, 'utf8'));
const changed = [];

for (const [key, value] of Object.entries(branding)) {
  if (product[key] !== value) {
    changed.push(`${key}: ${JSON.stringify(product[key])} -> ${JSON.stringify(value)}`);
    product[key] = value;
  }
}

fs.writeFileSync(target, JSON.stringify(product, null, 2) + '\n');

console.log(`branded ${target}`);
changed.forEach(line => console.log(`  ${line}`));
if (!changed.length) {
  console.log('  (already branded)');
}
