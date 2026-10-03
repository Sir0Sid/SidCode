#!/usr/bin/env node

/**
 * Write the product.json SidCode's build uses.
 *
 * VSCodium brands itself inside `prepare_vscode.sh`: it sets the Microsoft name fields to
 * "VSCodium" and then merges **its own** `product.json` over the upstream one, so whatever
 * that file says wins. That merge is the hook: give it a product.json that is VSCodium's own
 * (gallery, extension lists, all of it) with SidCode's fields on top, and the branding
 * survives every prepare step instead of being overwritten by it.
 *
 *   node tools/merge-product.mjs <path to a VSCodium checkout>
 *
 * It writes branding/product.json, which build.sh copies into the checkout.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const brandingFile = path.join(here, '..', 'branding', 'product.sidcode.json');
const outFile = path.join(here, '..', 'branding', 'product.json');

const checkout = process.argv[2];

if (!checkout) {
  console.error('usage: node tools/merge-product.mjs <path to a VSCodium checkout>');
  process.exit(1);
}

const vscodiumFile = path.join(checkout, 'product.json');
if (!fs.existsSync(vscodiumFile)) {
  console.error(`no product.json in ${checkout} - is that a VSCodium checkout?`);
  process.exit(1);
}

const vscodium = JSON.parse(fs.readFileSync(vscodiumFile, 'utf8'));
const branding = JSON.parse(fs.readFileSync(brandingFile, 'utf8'));

const merged = { ...vscodium, ...branding };
fs.writeFileSync(outFile, JSON.stringify(merged, null, 2) + '\n');

console.log(`wrote branding/product.json from ${vscodiumFile}`);
const overrides = Object.keys(branding).filter(key => key in vscodium);
console.log(`  VSCodium's own keys kept: ${Object.keys(vscodium).length}`);
console.log(`  SidCode overrides:        ${Object.keys(branding).length}${overrides.length ? ` (of which ${overrides.length} existed)` : ''}`);
console.log(`  nameShort:    ${merged.nameShort}`);
console.log(`  command:      ${merged.applicationName}`);
console.log(`  data folder:  ${merged.dataFolderName}`);
