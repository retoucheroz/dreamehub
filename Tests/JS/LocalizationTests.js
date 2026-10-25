/* Checks the shipped English table against every Turkish source string the app can show. */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const html = fs.readFileSync(path.join(root, 'Sources/DreameHub/Resources/index.html'), 'utf8');
// DREAME_I18N_TABLE points the test at another table, e.g. a fragment under review.
const tablePath = process.env.DREAME_I18N_TABLE || path.join(root, 'Sources/DreameHub/Resources/assets/i18n/en.json');
const table = JSON.parse(fs.readFileSync(tablePath, 'utf8'));
const has = key => Object.prototype.hasOwnProperty.call(table, key);
const turkish = /[çğıİöşüÇĞÖŞÜ]/;
const missingFrom = (keys, where) => {
  const missing = [...new Set(keys)].filter(key => !has(key));
  assert.deepEqual(missing, [], 'Missing from ' + path.basename(tablePath) + ' (' + where + '):\n  ' + missing.join('\n  '));
};

// (b) Every t('…') key in the main script. Keys must be literals so they can be checked here.
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const unescapeJS = text => text.replace(/\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)/g, (_, e) =>
  e[0] === 'u' || e[0] === 'x' ? String.fromCodePoint(parseInt(e.replace(/[ux{}]/g, ''), 16)) : ({ n: '\n', t: '\t', r: '\r' })[e] ?? e);
const calls = [...js.matchAll(/(?<![\w$.])t\(/g)].length;
const scriptKeys = [...js.matchAll(/(?<![\w$.])t\('((?:[^'\\\n]|\\.)*)'/g)].map(match => unescapeJS(match[1]));
assert(scriptKeys.length > 100, 'Script translation keys found');
assert.equal(scriptKeys.length, calls - 1, 't() is always called with a literal Turkish key'); // minus the definition
missingFrom(scriptKeys, 'index.html t() calls');

// (c) Static markup outside <script>/<style>: text nodes and the attributes translateStatic() handles.
const markup = html.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/g, '').replace(/<!--[\s\S]*?-->/g, '');
const decode = text => text.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);/gi, (_, e) =>
  e[0] === '#' ? String.fromCodePoint(e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : Number(e.slice(1)))
    : ({ amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0' })[e.toLowerCase()]);
const staticKeys = [];
for (const piece of markup.split(/(<[^>]*>)/)) {
  if (piece.startsWith('<')) {
    for (const [, , double, single] of piece.matchAll(/\s(placeholder|title|aria-label|alt)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) {
      const value = double ?? single;
      if (turkish.test(value)) staticKeys.push(decode(value).trim());
    }
  } else if (turkish.test(piece)) staticKeys.push(decode(piece).trim());
}
assert(staticKeys.length > 100, 'Static Turkish markup found');
missingFrom(staticKeys, 'index.html markup');

// (d) Placeholders survive translation unchanged.
const placeholders = text => (text.match(/\{\w+\}/g) || []).sort().join(' ');
for (const [key, value] of Object.entries(table)) {
  assert.equal(typeof value, 'string', 'Table value is a string: ' + key);
  assert.equal(placeholders(value), placeholders(key), 'Same {placeholders} in key and value: ' + key);
}

// (e) Swift: every Localization.text("…") literal key.
const swiftFiles = [];
const walk = dir => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full); else if (entry.name.endsWith('.swift')) swiftFiles.push(full);
  }
};
walk(path.join(root, 'Sources'));
const unescapeSwift = text => text.replace(/\\(u\{[0-9a-fA-F]+\}|.)/g, (_, e) =>
  e[0] === 'u' && e.length > 1 ? String.fromCodePoint(parseInt(e.slice(2, -1), 16)) : ({ n: '\n', t: '\t', r: '\r', 0: '\0' })[e] ?? e);
const swiftKeys = [];
for (const file of swiftFiles) {
  for (const [, literal] of fs.readFileSync(file, 'utf8').matchAll(/Localization\.text\(\s*"((?:[^"\\\n]|\\.)*)"/g)) {
    assert(!literal.includes('\\('), 'Use {placeholders}, not interpolation, in ' + path.relative(root, file) + ': ' + literal);
    swiftKeys.push(unescapeSwift(literal));
  }
}
missingFrom(swiftKeys, 'Swift Localization.text calls');

console.log('PASS: ' + Object.keys(table).length + ' English entries cover ' + new Set(scriptKeys).size + ' script keys, '
  + new Set(staticKeys).size + ' static markup strings and ' + new Set(swiftKeys).size + ' Swift keys; placeholders preserved');
